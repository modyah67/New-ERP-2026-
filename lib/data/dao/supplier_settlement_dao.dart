import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/supplier_settlement_model.dart';
import '../services/currency_conversion_service.dart';

class SupplierSettlementDao {
  final _client = Supabase.instance.client;

  Future<List<SupplierSettlementModel>> getByShipment(String shipmentId) async {
    try {
      final parsedId = int.tryParse(shipmentId) ?? shipmentId;
      final data = await _client
          .from('supplier_settlements')
          .select('*, suppliers(name), fruit_types!left(name)')
          .eq('shipment_id', parsedId)
          .order('created_at');
      return data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final supplier = AppUtils.asMap(row.remove('suppliers'));
        final fruit = AppUtils.asMap(row.remove('fruit_types'));
        final raw = AppUtils.asMap(row.remove('raw_materials'));
        return SupplierSettlementModel.fromMap({
          ...row,
          'supplier_name': supplier?['name'],
          'product_name': fruit?['name'] ?? raw?['name'] ?? '',
        });
      }).toList();
    } catch (e, st) {
      debugPrint('❌ SupplierSettlementDao.getByShipment error: $e\n$st');
      rethrow;
    }
  }

  Future<void> saveAll(String shipmentId, List<SupplierSettlementModel> items) async {
    try {
      final parsedId = int.tryParse(shipmentId) ?? shipmentId;
      await _client.from('supplier_settlements').delete().eq('shipment_id', parsedId);
      if (items.isEmpty) return;
      await _client.from('supplier_settlements').insert(
        items.map((r) {
          final map = r.toMap();
          map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
            currency: 'EGP',
            amount: r.totalAmount,
            exchangeRate: 1.0,
          ).toJson();
          return map;
        }).toList(),
      );
    } catch (e, st) {
      debugPrint('❌ SupplierSettlementDao.saveAll error: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteForShipment(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    await _client
        .from('supplier_settlements')
        .delete()
        .eq('shipment_id', parsedId);
  }

  Future<double> getTotalForShipment(String shipmentId) async {
    final parsedId = int.tryParse(shipmentId) ?? shipmentId;
    final data = await _client
        .from('supplier_settlements')
        .select('total_amount')
        .eq('shipment_id', parsedId);
    return data.fold<double>(
        0.0, (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0));
  }

  Future<String> insert(SupplierSettlementModel item) async {
    try {
      final map = item.toMap();
      map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
        currency: 'EGP',
        amount: item.totalAmount,
        exchangeRate: 1.0,
      ).toJson();
      final result = await _client
          .from('supplier_settlements')
          .insert(map)
          .select('id')
          .single();
      return result['id'] as String;
    } catch (e, st) {
      debugPrint('❌ SupplierSettlementDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('supplier_settlements').delete().eq('id', id);
    } catch (e, st) {
      debugPrint('❌ SupplierSettlementDao.delete error: $e\n$st');
      rethrow;
    }
  }
}
