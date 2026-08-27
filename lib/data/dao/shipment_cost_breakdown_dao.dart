import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipment_cost_breakdown_model.dart';
import '../services/currency_conversion_service.dart';

class ShipmentCostBreakdownDao {
  final _client = Supabase.instance.client;

  Future<List<ShipmentCostBreakdownModel>> getForShipment(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('shipment_cost_breakdown')
        .select()
        .eq('shipment_id', parsedId)
        .order('sort_order')
        .order('created_at');
    return data.map((e) => ShipmentCostBreakdownModel.fromMap(e)).toList();
  }

  Future<double> getTotalByType(String shipmentId, String costType) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('shipment_cost_breakdown')
        .select('total_cost')
        .eq('shipment_id', parsedId)
        .eq('cost_type', costType);
    return data.fold<double>(
        0.0, (s, r) => s + ((r['total_cost'] as num?)?.toDouble() ?? 0));
  }

  Future<double> getGrandTotal(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('shipment_cost_breakdown')
        .select('total_cost')
        .eq('shipment_id', parsedId);
    return data.fold<double>(
        0.0, (s, r) => s + ((r['total_cost'] as num?)?.toDouble() ?? 0));
  }

  Future<void> updateSupplier(String id, String supplier) async {
    await _client
        .from('shipment_cost_breakdown')
        .update({'supplier': supplier})
        .eq('id', id);
  }

  Future<void> deleteForShipment(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    await _client
        .from('shipment_cost_breakdown')
        .delete()
        .eq('shipment_id', parsedId);
  }

  Future<void> insertAll(
      int shipmentId, List<ShipmentCostBreakdownModel> rows) async {
    if (rows.isEmpty) return;
    final futures = rows.asMap().entries.map((e) async {
      final snapshot = await CurrencyConversionService.instance.createSnapshotFromDb(
        currency: e.value.currency,
        amount: e.value.totalCost,
      );
      return <String, dynamic>{
        ...e.value.toMap(),
        'shipment_id': shipmentId,
        'sort_order': e.key,
        'currency_snapshot': snapshot.toJson(),
      };
    }).toList();
    final mappedRows = await Future.wait(futures);
    await _client.from('shipment_cost_breakdown').insert(mappedRows);
  }
}
