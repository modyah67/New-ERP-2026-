import 'package:flutter/foundation.dart';
import '../dao/packing_order_dao.dart';
import '../dao/shipment_recipe_snapshot_dao.dart';
import '../dao/prep_center_cost_item_dao.dart';
import '../models/prep_center_cost_item_model.dart';

class PrepCenterAutoPopulateService {
  final _packingDao = PackingOrderDao();
  final _snapshotDao = ShipmentRecipeSnapshotDao();
  final _costItemDao = PrepCenterCostItemDao();

  static const Map<String, String> _materialToCostType = {
    'carton': 'PACKAGING',
    'label': 'LABELS',
    'sticker': 'STICKERS',
    'bag': 'PACKAGING',
    'pallet': 'PACKAGING',
    'corner': 'PACKAGING',
    'stretch_film': 'PACKAGING',
    'staple': 'PACKAGING',
    'other_material': 'PACKAGING',
  };

  Future<void> autoGenerate(String shipmentId) async {
    try {
      final shipmentIdInt = int.parse(shipmentId);
      final orders = await _packingDao.getByShipmentIdViaItems(shipmentIdInt);
      if (orders.isEmpty) return;

      final existing = await _costItemDao.getByShipment(shipmentId);
      final snapshots = await _snapshotDao.getByShipment(shipmentIdInt);

      final generated = <PrepCenterCostItemModel>[];

      if (snapshots.isNotEmpty) {
        for (final snapshot in snapshots) {
          final costType = _materialToCostType[snapshot.materialName?.toLowerCase()] ?? 'PACKAGING';
          final description = '${snapshot.materialName ?? 'مواد تعبئة'} - ${snapshot.recipeName ?? ''} (${snapshot.grade ?? ''})';
          final existingMatch = existing.any((e) =>
              e.description == description && e.costType == costType);

          if (!existingMatch) {
            generated.add(PrepCenterCostItemModel(
              shipmentId: shipmentIdInt,
              costType: costType,
              description: description,
              qty: snapshot.totalQuantity,
              unitPrice: snapshot.unitCost,
              notes: 'تلقائي من snapshot الوصفة',
            ));
          }
        }
      } else {
        for (final order in orders) {
          final orderSnapshots = snapshots.where((s) =>
              (order.fruitTypeId != null && s.productId == order.fruitTypeId) && s.grade == order.grade).toList();

          for (final snapshot in orderSnapshots) {
            final costType = _materialToCostType[snapshot.materialName?.toLowerCase()] ?? 'PACKAGING';
            final description = '${snapshot.materialName ?? 'مواد تعبئة'} - ${order.productName ?? ''} (${order.grade})';
            final existingMatch = existing.any((e) =>
                e.description == description && e.costType == costType);

            if (!existingMatch) {
              generated.add(PrepCenterCostItemModel(
                shipmentId: shipmentIdInt,
                costType: costType,
                description: description,
                qty: snapshot.quantityPerCarton * order.cartonCount,
                unitPrice: snapshot.unitCost,
                notes: 'تلقائي من snapshot الوصفة',
              ));
            }
          }
        }
      }

      if (generated.isNotEmpty) {
        for (final item in generated) {
          await _costItemDao.insert(item);
        }
        debugPrint('✅ PrepCenterAutoPopulate: ${generated.length} items created from snapshots');
      }
    } catch (e, st) {
      debugPrint('❌ PrepCenterAutoPopulateService error: $e\n$st');
    }
  }
}
