import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/batch_model.dart';
import '../services/currency_conversion_service.dart';

class BatchDao {
  final _client = Supabase.instance.client;
  static const _table = 'stock_batches';

  BatchModel _fromRow(Map<String, dynamic> row) {
    final flat = Map<String, dynamic>.from(row);
    final fruit = AppUtils.asMap(flat['fruit_types']);
    flat['product_name'] = fruit?['name'] ?? '';
    if (flat['supplier_name'] == null || flat['supplier_name'].toString().isEmpty) {
      flat['supplier_name'] = AppUtils.nestedString(flat, 'suppliers', 'name');
    }
    flat.remove('fruit_types');
    flat.remove('suppliers');
    return BatchModel.fromMap(flat);
  }

  Future<List<BatchModel>> getAll({
    dynamic productId,
    String? status,
    int page = 0,
    int limit = 50,
  }) async {
    var query = _client.from(_table).select('*, fruit_types!left(name), suppliers(name)');
    if (productId != null) {
      query = query.eq('product_id', productId.toString());
    }
    if (status != null) {
      query = query.eq('status', status);
    }
    final offset = page * limit;
    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<BatchModel>> getByProductId(dynamic productId) async {
    final data = await _client
        .from(_table)
        .select('*, fruit_types!left(name), suppliers(name)')
        .eq('product_id', productId.toString())
        .order('created_at');
    return data.map(_fromRow).toList();
  }

  Future<List<BatchModel>> getActiveBatches(dynamic productId) async {
    final data = await _client
        .from(_table)
        .select('*, fruit_types!left(name), suppliers(name)')
        .eq('product_id', productId.toString())
        .eq('status', 'active')
        .gt('remaining_quantity', 0)
        .order('created_at');
    return data.map(_fromRow).toList();
  }

  Future<BatchModel?> getById(dynamic id) async {
    final data = await _client
        .from(_table)
        .select('*, fruit_types!left(name), suppliers(name)')
        .eq('id', id.toString())
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<dynamic> insert(BatchModel batch) async {
    debugPrint('BatchDao.insert: batch_number=${batch.batchNumber}, product_id=${batch.productId}, qty=${batch.quantity}, cost=${batch.purchaseCost}');
    final data = batch.toMap();
    data['user_id'] = _client.auth.currentUser?.id;
    data.remove('product_name');
    data.remove('product_sku');
    data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: 'EGP',
      amount: batch.purchaseCost,
      exchangeRate: 1.0,
    ).toJson();
    debugPrint('BatchDao.insert: payload=$data');
    final result = await _client.from(_table).insert(data).select().single();
    final id = result['id']?.toString();
    debugPrint('BatchDao.insert: DONE - id=$id');
    return id;
  }

  Future<void> update(BatchModel batch) async {
    final data = batch.toMap();
    data.remove('product_name');
    data.remove('product_sku');
    data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: 'EGP',
      amount: batch.purchaseCost,
      exchangeRate: 1.0,
    ).toJson();
    await _client.from(_table).update(data).eq('id', batch.id!.toString());
  }

  Future<void> updateStatus(dynamic batchId, String status) async {
    await _client.from(_table).update({'status': status}).eq('id', batchId.toString());
  }

  Future<void> deductStock(dynamic batchId, double quantity) async {
    final row = await _client
        .from(_table)
        .select('remaining_quantity')
        .eq('id', batchId.toString())
        .single();
    final current = (row['remaining_quantity'] as num).toDouble();
    final newRemaining = current - quantity;
    final updates = <String, dynamic>{
      'remaining_quantity': newRemaining,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newRemaining <= 0) {
      updates['status'] = 'depleted';
    }
    await _client.from(_table).update(updates).eq('id', batchId.toString());
  }

  Future<List<BatchModel>> getExpiringBatches(int daysThreshold) async {
    final thresholdDate = DateTime.now().add(Duration(days: daysThreshold)).toIso8601String();
    final data = await _client
        .from(_table)
        .select('*, fruit_types!left(name)')
        .not('expiry_date', 'is', null)
        .lte('expiry_date', thresholdDate)
        .gt('remaining_quantity', 0)
        .order('expiry_date');
    return data.map(_fromRow).toList();
  }

  Future<int> getBatchCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
