import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/stock_movement_model.dart';
import '../models/batch_model.dart';

class InventoryRepository {
  final _client = Supabase.instance.client;

  StockMovementModel _mapMovementRow(dynamic e) {
    final row = Map<String, dynamic>.from(e as Map);
    final fruit = AppUtils.asMap(row.remove('fruit_types'));
    final raw = AppUtils.asMap(row.remove('raw_materials'));
    final batch = AppUtils.asMap(row.remove('stock_batches'));
    
    return StockMovementModel.fromMap({
      'id': row['id']?.toString(),
      'movement_type': row['movement_type'],
      'product_id': row['product_id']?.toString(),
      'product_name': fruit?['name'] ?? raw?['name'] ?? '',
      'batch_id': row['batch_id']?.toString(),
      'batch_number': batch?['batch_number'],
      'from_warehouse_id': row['from_warehouse_id'],
      'to_warehouse_id': row['to_warehouse_id'],
      'quantity': row['quantity'],
      'before_quantity': row['before_quantity'],
      'after_quantity': row['after_quantity'],
      'unit_cost': row['unit_cost'],
      'total_cost': row['total_cost'],
      'reference_type': row['reference_type'],
      'reference_id': row['reference_id']?.toString(),
      'description': row['description'],
      'created_at': row['created_at'],
    });
  }

  Future<List<StockMovementModel>> getAllMovements({
    String? productId,
    String? movementType,
    int page = 0,
    int limit = 50,
  }) async {
    var query = _client.from('stock_movements').select('*, fruit_types!left(name), stock_batches(batch_number)');
    if (productId != null && productId.isNotEmpty) {
      query = query.eq('product_id', productId);
    }
    if (movementType != null && movementType.isNotEmpty) {
      query = query.eq('movement_type', movementType);
    }
    final offset = page * limit;
    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return data.map(_mapMovementRow).toList();
  }

  Future<List<StockMovementModel>> getMovementsByProductId(String productId) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return data.map(_mapMovementRow).toList();
  }

  Future<String> insertMovement(StockMovementModel movement) async {
    final data = movement.toMap();
    data['user_id'] = _client.auth.currentUser?.id;
    data.remove('product_name');
    data.remove('batch_number');
    data.remove('user_name');
    final result = await _client.from('stock_movements').insert(data).select().single();
    return result['id'].toString();
  }

  Future<List<StockMovementModel>> getRecentMovements(int limit) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .order('created_at', ascending: false)
        .limit(limit);
    return data.map(_mapMovementRow).toList();
  }

  Future<List<StockMovementModel>> getForShipment(String shipmentId) async {
    final data = await _client
        .from('stock_movements')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .eq('reference_id', shipmentId)
        .order('created_at', ascending: false);
    return data.map(_mapMovementRow).toList();
  }

  // ── InventoryService Functionality ──

  Future<String> createBatchFromPurchase({
    required String productId,
    String? supplierId,
    String? warehouseId,
    String? purchaseInvoiceId,
    required double quantity,
    required double purchaseCost,
    DateTime? productionDate,
    DateTime? expiryDate,
    String? qualityGrade,
    String? category,
    String? notes,
  }) async {
    try {
      final result = await _client.rpc('create_batch_from_purchase', params: {
        'p_product_id': productId,
        'p_supplier_id': supplierId,
        'p_warehouse_id': warehouseId,
        'p_purchase_invoice_id': purchaseInvoiceId,
        'p_quantity': quantity,
        'p_purchase_cost': purchaseCost,
        'p_production_date': productionDate?.toIso8601String(),
        'p_expiry_date': expiryDate?.toIso8601String(),
        'p_fruit_category': category,
        'p_notes': notes,
      });
      return result.toString();
    } catch (e) {
      debugPrint('Error in createBatchFromPurchase: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deductStockFIFO({
    required String productId,
    required double quantity,
    String reason = 'sale',
    String? referenceId,
  }) async {
    try {
      final result = await _client.rpc('deduct_stock_fifo', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_reason': reason,
        'p_reference_id': referenceId,
      });
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('Error in deductStockFIFO: $e');
      rethrow;
    }
  }

  Future<void> returnStock({
    required String productId,
    required double quantity,
    String? batchId,
    String? referenceType,
    String? referenceId,
    String? description,
  }) async {
    try {
      await _client.rpc('return_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_batch_id': batchId,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
        'p_description': description,
      });
    } catch (e) {
      debugPrint('Error in returnStock: $e');
      rethrow;
    }
  }

  Future<void> damageStock({
    required String productId,
    required double quantity,
    required String batchId,
    required String warehouseId,
    String? description,
  }) async {
    try {
      await _client.rpc('damage_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_batch_id': batchId,
        'p_warehouse_id': warehouseId,
        'p_description': description,
      });
    } catch (e) {
      debugPrint('Error in damageStock: $e');
      rethrow;
    }
  }

  Future<void> adjustStock({
    required String productId,
    required double quantity,
    required String batchId,
    required String warehouseId,
    String? description,
  }) async {
    try {
      await _client.rpc('adjust_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_batch_id': batchId,
        'p_warehouse_id': warehouseId,
        'p_description': description,
      });
    } catch (e) {
      debugPrint('Error in adjustStock: $e');
      rethrow;
    }
  }

  Future<void> transferStock({
    required String productId,
    required double quantity,
    required String batchId,
    required String fromWarehouseId,
    required String toWarehouseId,
    String? description,
  }) async {
    try {
      await _client.rpc('transfer_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_batch_id': batchId,
        'p_from_warehouse_id': fromWarehouseId,
        'p_to_warehouse_id': toWarehouseId,
        'p_description': description,
      });
    } catch (e) {
      debugPrint('Error in transferStock: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getExpiringItems({int thresholdDays = 30}) async {
    try {
      final result = await _client.rpc('get_expiring_items', params: {
        'threshold_days': thresholdDays,
      });
      return result as List<dynamic>;
    } catch (e) {
      debugPrint('Error in getExpiringItems: $e');
      return [];
    }
  }

  Future<List<dynamic>> getLowStockProducts() async {
    try {
      final result = await _client.rpc('get_low_stock_products');
      return result as List<dynamic>;
    } catch (e) {
      debugPrint('Error in getLowStockProducts: $e');
      return [];
    }
  }
}
