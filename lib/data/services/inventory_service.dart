import 'package:supabase_flutter/supabase_flutter.dart';

/// Enterprise inventory engine — thin Dart service layer.
/// ALL inventory logic lives in PostgreSQL RPC functions (migration 010).
/// This class handles: validation, RPC calls, error mapping, UI communication.
class InventoryService {
  final _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser?.id ?? '';

  /// ──────────────────────────────────────────────
  /// BATCH CREATION (from purchase)
  /// Single RPC call: creates batch, updates product, records movement, recalculates WAC.
  /// ──────────────────────────────────────────────
  Future<BatchPurchaseResult> createBatchFromPurchase({
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
        'p_category': category,
        'p_notes': notes,
      });
      return BatchPurchaseResult(
        batchId: result.toString(),
        productId: productId,
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// FIFO STOCK DEDUCTION
  /// Single RPC call: locks product, skips expired batches, deducts FIFO,
  /// records accurate movements, recalculates WAC.
  /// ──────────────────────────────────────────────
  Future<FifoDeductionResult> deductStockFIFO({
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
      final data = Map<String, dynamic>.from(result as Map);
      return FifoDeductionResult(
        productId: productId.toString(),
        deducted: (data['deducted'] as num).toDouble(),
        beforeStock: (data['before_stock'] as num).toDouble(),
        afterStock: (data['after_stock'] as num).toDouble(),
      );
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// RETURN STOCK
  /// Single RPC call: returns to original batch or creates return batch,
  /// locks product, records movement, recalculates WAC.
  /// ──────────────────────────────────────────────
  Future<ReturnStockResult> returnStock({
    required String productId,
    required double quantity,
    String? batchId,
    String? referenceType,
    String? referenceId,
    String? description,
  }) async {
    if (quantity <= 0) throw ArgumentError('Quantity must be positive');

    try {
      final result = await _client.rpc('return_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_batch_id': batchId,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
        'p_description': description,
        'p_user_id': _userId,
      });

      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Return failed');
      }
      return ReturnStockResult.fromMap(data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// DAMAGE STOCK
  /// Single RPC call: partial damage support, locks batch+product,
  /// only marks batch 'damaged' when fully depleted.
  /// ──────────────────────────────────────────────
  Future<DamageStockResult> damageStock({
    required String productId,
    required String batchId,
    required double quantity,
    String? description,
  }) async {
    if (quantity <= 0) throw ArgumentError('Quantity must be positive');

    try {
      final result = await _client.rpc('damage_stock', params: {
        'p_product_id': productId,
        'p_batch_id': batchId,
        'p_quantity': quantity,
        'p_description': description,
        'p_user_id': _userId,
      });

      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Damage failed');
      }
      return DamageStockResult.fromMap(data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// ADJUST STOCK
  /// Single RPC call: manual adjustment with locking and movement record.
  /// ──────────────────────────────────────────────
  Future<AdjustStockResult> adjustStock({
    required String productId,
    required double newQuantity,
    String? description,
  }) async {
    if (newQuantity < 0) throw ArgumentError('Quantity cannot be negative');

    try {
      final result = await _client.rpc('adjust_stock', params: {
        'p_product_id': productId,
        'p_new_quantity': newQuantity,
        'p_description': description,
        'p_user_id': _userId,
      });

      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Adjustment failed');
      }
      return AdjustStockResult.fromMap(data);
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// TRANSFER STOCK (between warehouses)
  /// Single RPC call: deducts from source, creates in target, records movement.
  /// ──────────────────────────────────────────────
  Future<void> transferStock({
    required String productId,
    required String batchId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required double quantity,
    String? description,
  }) async {
    if (quantity <= 0) throw ArgumentError('Quantity must be positive');

    try {
      final result = await _client.rpc('transfer_stock', params: {
        'p_product_id': productId,
        'p_batch_id': batchId,
        'p_from_warehouse_id': fromWarehouseId,
        'p_to_warehouse_id': toWarehouseId,
        'p_quantity': quantity,
        'p_description': description,
        'p_user_id': _userId,
      });

      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Transfer failed');
      }
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// GET EXPIRING ITEMS
  /// RPC call: returns items expiring within threshold days.
  /// ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getExpiringItems({
    int daysThreshold = 7,
  }) async {
    try {
      final result = await _client.rpc('get_expiring_items', params: {
        'p_days_threshold': daysThreshold,
      });
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// GET LOW STOCK PRODUCTS
  /// RPC call: returns products below minimum stock.
  /// ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    try {
      final result = await _client.rpc('get_low_stock_products');
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// GET DASHBOARD STATS
  /// RPC call: returns aggregated dashboard statistics.
  /// ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final result = await _client.rpc('get_dashboard_stats');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      throw _mapError(e);
    }
  }

  /// ──────────────────────────────────────────────
  /// HELPER: Map PostgreSQL errors to user-friendly messages
  /// ──────────────────────────────────────────────
  Exception _mapError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('Insufficient stock')) {
      return Exception('Stock insufficient: $msg');
    }
    if (msg.contains('not found')) {
      return Exception('Record not found: $msg');
    }
    if (msg.contains('expired')) {
      return Exception('Expired stock: $msg');
    }
    if (msg.contains('race') || msg.contains('deadlock')) {
      return Exception('Concurrent modification. Please retry.');
    }
    return Exception('Inventory error: $msg');
  }
}

/// ──────────────────────────────────────────────
/// RESULT MODELS (immutable, typed)
/// ──────────────────────────────────────────────

class BatchPurchaseResult {
  final String batchId;
  final String productId;
  const BatchPurchaseResult({required this.batchId, required this.productId});
}

class FifoDeductionResult {
  final String productId;
  final double deducted;
  final double beforeStock;
  final double afterStock;
  const FifoDeductionResult({
    required this.productId,
    required this.deducted,
    required this.beforeStock,
    required this.afterStock,
  });
}

class ReturnStockResult {
  final String productId;
  final double quantityReturned;
  final String batchId;
  final String batchNumber;
  final double productBefore;
  final double productAfter;

  ReturnStockResult({
    required this.productId,
    required this.quantityReturned,
    required this.batchId,
    required this.batchNumber,
    required this.productBefore,
    required this.productAfter,
  });

  factory ReturnStockResult.fromMap(Map<String, dynamic> m) {
    return ReturnStockResult(
      productId: m['product_id'] as String,
      quantityReturned: (m['quantity_returned'] as num).toDouble(),
      batchId: m['batch_id'] as String,
      batchNumber: m['batch_number'] as String? ?? '',
      productBefore: (m['product_before'] as num?)?.toDouble() ?? 0,
      productAfter: (m['product_after'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DamageStockResult {
  final String productId;
  final String batchId;
  final double damagedQuantity;
  final double batchRemaining;
  final String batchStatus;
  final double productBefore;
  final double productAfter;

  DamageStockResult({
    required this.productId,
    required this.batchId,
    required this.damagedQuantity,
    required this.batchRemaining,
    required this.batchStatus,
    required this.productBefore,
    required this.productAfter,
  });

  factory DamageStockResult.fromMap(Map<String, dynamic> m) {
    return DamageStockResult(
      productId: m['product_id'] as String,
      batchId: m['batch_id'] as String,
      damagedQuantity: (m['damaged_quantity'] as num).toDouble(),
      batchRemaining: (m['batch_remaining'] as num).toDouble(),
      batchStatus: m['batch_status'] as String,
      productBefore: (m['product_before'] as num?)?.toDouble() ?? 0,
      productAfter: (m['product_after'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AdjustStockResult {
  final String productId;
  final double oldQuantity;
  final double newQuantity;
  final double difference;

  AdjustStockResult({
    required this.productId,
    required this.oldQuantity,
    required this.newQuantity,
    required this.difference,
  });

  factory AdjustStockResult.fromMap(Map<String, dynamic> m) {
    return AdjustStockResult(
      productId: m['product_id'] as String,
      oldQuantity: (m['old_quantity'] as num).toDouble(),
      newQuantity: (m['new_quantity'] as num).toDouble(),
      difference: (m['difference'] as num).toDouble(),
    );
  }
}
