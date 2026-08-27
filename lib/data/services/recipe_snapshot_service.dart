import 'package:flutter/foundation.dart';
import '../dao/packing_order_dao.dart';
import '../dao/packing_recipe_dao.dart';
import '../dao/shipment_recipe_snapshot_dao.dart';
import '../dao/export_shipment_dao.dart';
import '../models/packing_recipe_model.dart';
import '../models/shipment_recipe_snapshot_model.dart';

class RecipeSnapshotService {
  final _packingOrderDao = PackingOrderDao();
  final _recipeDao = PackingRecipeDao();
  final _snapshotDao = ShipmentRecipeSnapshotDao();
  final _shipmentDao = ExportShipmentDao();

  Future<void> createSnapshot(int shipmentId) async {
    final orders = await _packingOrderDao.getByShipmentIdViaItems(shipmentId);
    if (orders.isEmpty) return;

    final firstOrder = orders.first;
    final recipeName = firstOrder.recipeName;
    final grade = firstOrder.grade;

    if (recipeName == null || recipeName.isEmpty) return;

    List<PackingRecipeModel> recipes;
    if (firstOrder.recipeId != null) {
      recipes = await _recipeDao.getByRecipeId(firstOrder.recipeId!);
    } else {
      recipes = await _recipeDao.getByRecipeName(recipeName);
    }
    if (recipes.isEmpty) {
      debugPrint('⚠️ No recipes found for recipeName=$recipeName grade=$grade — skipping snapshot');
      return;
    }

    final recipeId = recipes.first.id;
    final totalCartons = orders.fold<int>(0, (s, o) => s + o.cartonCount);

    // Save packing_recipe_id on shipment
    if (recipeId != null) {
      try {
        await _shipmentDao.updatePackingRecipeId(shipmentId, recipeId);
      } catch (e) {
        debugPrint('⚠️ Could not update packing_recipe_id: $e');
      }
    }

    // Determine next version
    final existing = await _snapshotDao.getByShipment(shipmentId);
    final nextVersion = existing.isNotEmpty
        ? existing.map((e) => e.recipeVersion).reduce((a, b) => a > b ? a : b) + 1
        : 1;

    // Build snapshot rows (cost is calculated dynamically from FIFO during order execution)
    final snapshots = recipes.map((r) {
      final totalQty = r.quantityPerCarton * totalCartons;
      return ShipmentRecipeSnapshotModel(
        shipmentId: shipmentId,
        packingRecipeId: r.id,
        recipeName: recipeName,
        grade: r.grade,
        recipeVersion: nextVersion,
        materialId: r.rawMaterialId,
        materialName: r.rawMaterialName,
        unit: r.unit,
        quantityPerCarton: r.quantityPerCarton,
        unitCost: 0,
        totalQuantity: totalQty,
        totalCost: 0,
      );
    }).toList();

    // Remove old snapshots if any, then insert new
    await _snapshotDao.deleteByShipment(shipmentId);
    await _snapshotDao.insertAll(shipmentId, snapshots);

    debugPrint('✅ Created ${snapshots.length} snapshot rows for shipment $shipmentId');
  }

  Future<void> backfillForShipment(int shipmentId) async {
    final s = await _shipmentDao.getById(shipmentId);
    if (s == null) return;

    final orders = await _packingOrderDao.getByShipmentIdViaItems(shipmentId);
    if (orders.isEmpty) return;

    // Check if snapshot already exists
    final existing = await _snapshotDao.getByShipment(shipmentId);
    if (existing.isNotEmpty) return;

    await createSnapshot(shipmentId);
  }
}
