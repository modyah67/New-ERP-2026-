import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/utils.dart';
import '../models/crop_purchase_model.dart';
import '../services/currency_conversion_service.dart';

class CropPurchaseDao {
  final _client = Supabase.instance.client;
  static const _table = 'crop_purchases';

  static const _selectWithJoins = '''
    *,
    suppliers!crop_purchases_supplier_id_fkey(name),
    fruit_types!crop_purchases_fruit_type_id_fkey(name, code),
    stations!crop_purchases_warehouse_id_fkey(name)
  ''';

  CropPurchaseModel _fromRow(Map<String, dynamic> row) {
    final flat = Map<String, dynamic>.from(row);
    flat['supplier_name'] = AppUtils.nestedString(flat, 'suppliers', 'name');
    flat['fruit_type_name'] = AppUtils.nestedString(flat, 'fruit_types', 'name');
    flat['warehouse_name'] = AppUtils.nestedString(flat, 'stations', 'name');
    flat.remove('suppliers');
    flat.remove('fruit_types');
    flat.remove('stations');
    return CropPurchaseModel.fromMap(flat);
  }

  Future<List<CropPurchaseModel>> getAll({
    String? supplierId,
    String? fruitTypeId,
    int? year,
    int? month,
  }) async {
    var query = _client.from(_table).select(_selectWithJoins);
    if (supplierId != null) {
      query = query.eq('supplier_id', supplierId);
    }
    if (fruitTypeId != null) {
      query = query.eq('fruit_type_id', fruitTypeId);
    }
    if (year != null) {
      final prefix = '$year-';
      query = query.like('purchase_date', '$prefix%');
      if (month != null) {
        final m = month.toString().padLeft(2, '0');
        query = query.like('purchase_date', '$prefix$m-%');
      }
    }
    final data = await query.order('purchase_date', ascending: false);
    return data.map(_fromRow).toList();
  }

  Future<CropPurchaseModel?> getById(String id) async {
    final data = await _client
        .from(_table)
        .select(_selectWithJoins)
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<String> insert(CropPurchaseModel item) async {
    final data = item.toMap();
    data['created_by'] = _client.auth.currentUser?.id;
    data['user_id'] = _client.auth.currentUser?.id;
    data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: 'EGP',
      amount: item.totalCost,
      exchangeRate: 1.0,
    ).toJson();
    final result = await _client.from(_table).insert(data).select().single();
    DataChangeEventBus.instance.notifyCropPurchasesChanged();
    return result['id']?.toString() ?? '';
  }

  Future<void> update(CropPurchaseModel item) async {
    final data = item.toMap();
    data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: 'EGP',
      amount: item.totalCost,
      exchangeRate: 1.0,
    ).toJson();
    await _client.from(_table).update(data).eq('id', int.tryParse(item.id!) ?? item.id!);
    DataChangeEventBus.instance.notifyCropPurchasesChanged();
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', int.tryParse(id) ?? id);
    DataChangeEventBus.instance.notifyCropPurchasesChanged();
  }

  Future<String> generateReceiptNumber() async {
    try {
      final data = await _client.rpc('generate_crop_receipt_number');
      return data?.toString() ?? 'CR001';
    } catch (e) {
      return 'CR001';
    }
  }

  Future<double?> getLatestPriceForFruit(String fruitTypeId) async {
    try {
      final data = await _client
          .from(_table)
          .select('purchase_price_per_kg')
          .eq('fruit_type_id', fruitTypeId)
          .order('purchase_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return (data['purchase_price_per_kg'] as num?)?.toDouble();
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final all = await _client.from(_table).select('total_cost, net_cost, quantity');
      int count = all.length;
      double totalCost = 0, totalNetCost = 0, totalQuantity = 0;
      for (final row in all) {
        totalCost += (row['total_cost'] as num?)?.toDouble() ?? 0;
        totalNetCost += (row['net_cost'] as num?)?.toDouble() ?? 0;
        totalQuantity += (row['quantity'] as num?)?.toDouble() ?? 0;
      }
      return {
        'count': count,
        'total_cost': AppUtils.roundDouble(totalCost),
        'total_net_cost': AppUtils.roundDouble(totalNetCost),
        'total_quantity': AppUtils.roundDouble(totalQuantity),
      };
    } catch (e) {
      return {
        'count': 0,
        'total_cost': 0.0,
        'total_net_cost': 0.0,
        'total_quantity': 0.0,
      };
    }
  }
}
