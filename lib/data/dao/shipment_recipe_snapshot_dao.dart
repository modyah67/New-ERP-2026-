import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipment_recipe_snapshot_model.dart';

class ShipmentRecipeSnapshotDao {
  final _client = Supabase.instance.client;

  Future<List<ShipmentRecipeSnapshotModel>> getByShipment(int shipmentId) async {
    try {
      final data = await _client
          .from('shipment_recipe_snapshots')
          .select()
          .eq('shipment_id', shipmentId)
          .order('material_id');
      return data.map((e) => ShipmentRecipeSnapshotModel.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (e, st) {
      debugPrint('❌ ShipmentRecipeSnapshotDao.getByShipment error: $e\n$st');
      rethrow;
    }
  }

  Future<void> insertAll(int shipmentId, List<ShipmentRecipeSnapshotModel> items) async {
    try {
      if (items.isEmpty) return;
      await _client.from('shipment_recipe_snapshots').insert(items.map((r) => r.toMap()).toList());
    } catch (e, st) {
      debugPrint('❌ ShipmentRecipeSnapshotDao.insertAll error: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteByShipment(int shipmentId) async {
    try {
      await _client.from('shipment_recipe_snapshots').delete().eq('shipment_id', shipmentId);
    } catch (e, st) {
      debugPrint('❌ ShipmentRecipeSnapshotDao.deleteByShipment error: $e\n$st');
      rethrow;
    }
  }
}
