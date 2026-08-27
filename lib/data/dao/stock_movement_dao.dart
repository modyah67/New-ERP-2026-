import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/stock_movement_model.dart';
import '../services/currency_conversion_service.dart';

class StockMovementDao {
  final _client = Supabase.instance.client;

  StockMovementModel _fromRow(Map<String, dynamic> row) {
    final flat = Map<String, dynamic>.from(row);
    final fruit = AppUtils.asMap(flat['fruit_types']);
    final raw = AppUtils.asMap(flat['raw_materials']);
    flat['product_name'] = fruit?['name'] ?? raw?['name'] ?? '';
    flat.remove('fruit_types');
    flat.remove('raw_materials');
    flat['batch_number'] = AppUtils.nestedString(flat, 'stock_batches', 'batch_number');
    flat.remove('stock_batches');
    flat.remove('batches');
    return StockMovementModel.fromMap(flat);
  }

  Future<List<StockMovementModel>> getAll({
    int? productId,
    String? movementType,
    int page = 0,
    int limit = 50,
  }) async {
    var query = _client.from('stock_movements').select('*, fruit_types!left(name), stock_batches(batch_number)');
    if (productId != null) {
      query = query.eq('product_id', productId.toString());
    }
    if (movementType != null) {
      query = query.eq('movement_type', movementType);
    }
    final offset = page * limit;
    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<StockMovementModel>> getByProductId(int productId) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .eq('product_id', productId.toString())
        .order('created_at', ascending: false);
    return data.map(_fromRow).toList();
  }

  Future<int> insert(StockMovementModel movement) async {
    final data = movement.toMap();
    data['user_id'] = _client.auth.currentUser?.id;
    data.remove('product_name');
    data.remove('batch_number');
    data.remove('user_name');
    data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: 'EGP',
      amount: movement.totalCost,
      exchangeRate: 1.0,
    ).toJson();
    final result = await _client.from('stock_movements').insert(data).select().single();
    return result['id'] as int;
  }

  Future<List<StockMovementModel>> getRecentMovements(int limit) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .order('created_at', ascending: false)
        .limit(limit);
    return data.map(_fromRow).toList();
  }

  Future<List<StockMovementModel>> getForShipment(int shipmentId) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .eq('shipment_id', shipmentId.toString())
        .order('created_at', ascending: false);
    return data.map(_fromRow).toList();
  }
}
