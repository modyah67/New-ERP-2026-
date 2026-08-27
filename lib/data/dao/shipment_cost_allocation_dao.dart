import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipment_cost_allocation_model.dart';
import '../services/currency_conversion_service.dart';

class ShipmentCostAllocationDao {
  final _client = Supabase.instance.client;
  static const _table = 'shipment_cost_allocations';

  Future<List<ShipmentCostAllocationModel>> getForShipment(int shipmentId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('shipment_id', shipmentId)
        .order('finished_product_id');
    return data.map((e) => ShipmentCostAllocationModel.fromMap(e)).toList();
  }

  Future<List<ShipmentCostAllocationModel>> getForShipmentAndProduct(
      int shipmentId, int productId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('shipment_id', shipmentId)
        .eq('finished_product_id', productId);
    return data.map((e) => ShipmentCostAllocationModel.fromMap(e)).toList();
  }

  Future<void> deleteForShipment(int shipmentId) async {
    await _client.from(_table).delete().eq('shipment_id', shipmentId);
  }

  Future<void> insertAll(
      int shipmentId, List<ShipmentCostAllocationModel> items) async {
    if (items.isEmpty) return;
    final rows = items.map((e) {
      final map = e.toMap()..remove('id');
      map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
        currency: 'EGP',
        amount: e.allocatedAmount,
        exchangeRate: 1.0,
      ).toJson();
      return map;
    }).toList();
    await _client.from(_table).insert(rows);
  }
}
