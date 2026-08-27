import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prep_center_cost_item_model.dart';
import '../services/currency_conversion_service.dart';

class PrepCenterCostItemDao {
  final _client = Supabase.instance.client;

  Future<List<PrepCenterCostItemModel>> getByShipment(String shipmentId) async {
    try {
      final parsedId = int.tryParse(shipmentId) ?? shipmentId;
      final data = await _client
          .from('prep_center_cost_items')
          .select()
          .eq('shipment_id', parsedId)
          .order('created_at');
      return data.map((e) => PrepCenterCostItemModel.fromMap(e)).toList();
    } catch (e, st) {
      debugPrint('❌ PrepCenterCostItemDao.getByShipment error: $e\n$st');
      rethrow;
    }
  }

  Future<void> saveAll(String shipmentId, List<PrepCenterCostItemModel> items) async {
    try {
      final parsedId = int.tryParse(shipmentId) ?? shipmentId;
      await _client.from('prep_center_cost_items').delete().eq('shipment_id', parsedId);
      if (items.isEmpty) return;
      await _client.from('prep_center_cost_items').insert(
        items.map((r) {
          final map = r.toMap();
          map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
            currency: 'EGP',
            amount: r.totalCost,
            exchangeRate: 1.0,
          ).toJson();
          return map;
        }).toList(),
      );
    } catch (e, st) {
      debugPrint('❌ PrepCenterCostItemDao.saveAll error: $e\n$st');
      rethrow;
    }
  }

  Future<double> getTotalForShipment(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('prep_center_cost_items')
        .select('total_cost')
        .eq('shipment_id', parsedId);
    return data.fold<double>(
        0.0, (sum, row) => sum + ((row['total_cost'] as num?)?.toDouble() ?? 0));
  }

  Future<Map<String, double>> getTotalsByType(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('prep_center_cost_items')
        .select('cost_type, total_cost')
        .eq('shipment_id', parsedId);
    final map = <String, double>{};
    for (final row in data) {
      final type = row['cost_type'] as String? ?? 'OTHER';
      final cost = (row['total_cost'] as num?)?.toDouble() ?? 0;
      map[type] = (map[type] ?? 0) + cost;
    }
    return map;
  }

  Future<String> insert(PrepCenterCostItemModel item) async {
    try {
      final map = item.toMap();
      map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
        currency: 'EGP',
        amount: item.totalCost,
        exchangeRate: 1.0,
      ).toJson();
      final result = await _client
          .from('prep_center_cost_items')
          .insert(map)
          .select('id')
          .single();
      return result['id'] as String;
    } catch (e, st) {
      debugPrint('❌ PrepCenterCostItemDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('prep_center_cost_items').delete().eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PrepCenterCostItemDao.delete error: $e\n$st');
      rethrow;
    }
  }
}
