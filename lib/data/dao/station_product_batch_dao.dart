import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/station_product_batch.dart';
import '../services/currency_conversion_service.dart';

class FIFODeduction {
  final int batchId;
  final double quantity;
  final double unitCost;
  final String currency;
  final double exchangeRate;
  final String supplierName;
  final int? purchaseInvoiceId;
  final String sourceDate;
  final String originalSourceType;
  final String productCode;
  final String itemType;
  final String? rawMaterialId;
  final int? fruitTypeId;

  const FIFODeduction({
    required this.batchId,
    required this.quantity,
    required this.unitCost,
    this.currency = 'EGP',
    this.exchangeRate = 1.0,
    this.supplierName = '',
    this.purchaseInvoiceId,
    this.sourceDate = '',
    this.originalSourceType = 'purchase',
    this.productCode = '',
    this.itemType = 'material',
    this.rawMaterialId,
    this.fruitTypeId,
  });

  /// Cost in original currency.
  double get totalCost => quantity * unitCost;

  /// Cost in base currency (EGP).
  double get totalCostBase => quantity * unitCost * exchangeRate;
}

class StationProductBatchDao {
  final _client = Supabase.instance.client;
  static const _table = 'station_product_batches';

  Future<List<StationProductBatch>> getBatches({
    required int stationId,
    String? productName,
    String? productCode,
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    var query = _client
        .from(_table)
        .select('*, purchase_invoices(invoice_number)')
        .eq('station_id', stationId);

    if (itemType == 'fruit' || fruitTypeId != null) {
      query = query.inFilter('source_type', ['lot_receipt', 'crop_purchase']);
    } else if (itemType == 'material' || rawMaterialId != null) {
      query = query.neq('source_type', 'lot_receipt');
    }

    if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else if (productName != null && productName.isNotEmpty) {
      query = query.eq('product_name', productName);
    }

    final data = await query
        .gt('remaining_quantity', 0)
        .order('created_at', ascending: true);
    return data.map(StationProductBatch.fromMap).toList();
  }

  Future<List<StationProductBatch>> getAllBatches({required int stationId}) async {
    final data = await _client
        .from(_table)
        .select('*, purchase_invoices(invoice_number)')
        .eq('station_id', stationId)
        .gt('remaining_quantity', 0)
        .order('created_at', ascending: true);
    return data.map(StationProductBatch.fromMap).toList();
  }

  Future<List<StationProductBatch>> getAllBatchesIncludingConsumed({
    required int stationId,
    String? productName,
    String? productCode,
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    var query = _client
        .from(_table)
        .select('*, purchase_invoices(invoice_number)')
        .eq('station_id', stationId);

    if (itemType == 'fruit' || fruitTypeId != null) {
      query = query.inFilter('source_type', ['lot_receipt', 'crop_purchase']);
    } else if (itemType == 'material' || rawMaterialId != null) {
      query = query.neq('source_type', 'lot_receipt');
    }

    if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else if (productName != null && productName.isNotEmpty) {
      query = query.eq('product_name', productName);
    }

    final data = await query.order('created_at', ascending: true);
    return data.map(StationProductBatch.fromMap).toList();
  }

  Future<void> deletePurchaseBatches({
    required int stationId,
    required String productName,
    String? productCode,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    var query = _client
        .from(_table)
        .delete()
        .eq('station_id', stationId)
        .eq('source_type', 'purchase');

    if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else {
      query = query.eq('product_name', productName);
    }

    await query;
  }

  Future<void> deleteNonTransferBatches({
    required int stationId,
    required String productName,
    String? productCode,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    var query = _client
        .from(_table)
        .delete()
        .eq('station_id', stationId)
        .neq('source_type', 'transfer');

    if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else {
      query = query.eq('product_name', productName);
    }

    await query;
  }

  Future<void> insertBatch({
    required int stationId,
    required String productName,
    required String productCode,
    required double quantity,
    required double unitCost,
    String sourceType = 'transfer',
    String supplierName = '',
    String sourceStationName = '',
    String sourceDate = '',
    int? purchaseInvoiceId,
    double exchangeRate = 1.0,
    String currency = 'EGP',
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    final determinedType = itemType ?? (fruitTypeId != null ? 'fruit' : 'material');
    final snapshot = CurrencyConversionService.instance.createSnapshot(
      currency: currency,
      amount: quantity * unitCost,
      exchangeRate: exchangeRate,
    );

    final data = <String, dynamic>{
      'station_id': stationId,
      'product_name': productName,
      'product_code': productCode,
      'quantity': quantity,
      'remaining_quantity': quantity,
      'unit_cost': unitCost,
      'currency': currency,
      'exchange_rate': exchangeRate,
      'source_type': sourceType,
      'source_date': sourceDate.isNotEmpty ? sourceDate : DateTime.now().toIso8601String(),
      'supplier_name': supplierName,
      'source_station_name': sourceStationName,
      'purchase_invoice_id': purchaseInvoiceId,
      'currency_snapshot': snapshot?.toJson(),
      'item_type': determinedType,
    };
    if (rawMaterialId != null) data['raw_material_id'] = rawMaterialId;
    if (fruitTypeId != null) data['fruit_type_id'] = fruitTypeId;

    try {
      await _client.from(_table).insert(data);
    } catch (e) {
      debugPrint('⚠️ insertBatch full insert failed, trying fallback: $e');
      final basic = <String, dynamic>{
        'station_id': stationId,
        'product_name': productName,
        'product_code': productCode,
        'quantity': quantity.toInt(),
        'remaining_quantity': quantity.toInt(),
        'unit_cost': unitCost,
        'source_type': sourceType,
        'source_date': data['source_date'],
        'supplier_name': supplierName,
        'currency': currency,
        'exchange_rate': exchangeRate,
      };
      if (rawMaterialId != null) basic['raw_material_id'] = rawMaterialId;
      if (fruitTypeId != null) basic['fruit_type_id'] = fruitTypeId;

      try {
        await _client.from(_table).insert(basic);
      } catch (e2) {
        debugPrint('⚠️ insertBatch fallback failed: $e2');
        basic.remove('raw_material_id');
        basic.remove('fruit_type_id');
        await _client.from(_table).insert(basic);
      }
    }
  }

  Future<void> restoreFIFO({
    required int stationId,
    required String productName,
    required double quantity,
    String? productCode,
    String? rawMaterialId,
    int? fruitTypeId,
    String? itemType,
  }) async {
    var query = _client
        .from(_table)
        .select()
        .eq('station_id', stationId);

    if (rawMaterialId != null) {
      query = query.eq('raw_material_id', rawMaterialId);
    } else if (fruitTypeId != null) {
      query = query.eq('fruit_type_id', fruitTypeId);
    } else if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else {
      query = query.eq('product_name', productName);
    }

    final data = await query.order('created_at', ascending: false);
    final batches = data.map(StationProductBatch.fromMap).toList();

    double remaining = quantity;

    for (final batch in batches) {
      if (remaining <= 0) break;
      final deducted = batch.quantity - batch.remainingQuantity;
      if (deducted <= 0) continue;
      final restore = remaining < deducted ? remaining : deducted;
      await _client
          .from(_table)
          .update({'remaining_quantity': batch.remainingQuantity + restore})
          .eq('id', batch.id!);
      remaining -= restore;
    }
  }

  Future<(double totalCost, double totalCostBase)> deductFIFO({
    required int stationId,
    required String productName,
    required double quantity,
    String? productCode,
    String? rawMaterialId,
    int? fruitTypeId,
    String? itemType,
  }) async {
    final batches = await getBatches(
      stationId: stationId,
      productName: productName,
      productCode: productCode,
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
      itemType: itemType,
    );

    double remaining = quantity;
    double totalCost = 0;
    double totalCostBase = 0;

    for (final batch in batches) {
      if (remaining <= 0) break;

      final deduct = remaining < batch.remainingQuantity ? remaining : batch.remainingQuantity;
      final newRemaining = batch.remainingQuantity - deduct;

      await _client
          .from(_table)
          .update({'remaining_quantity': newRemaining})
          .eq('id', batch.id!);

      totalCost += deduct * batch.unitCost;
      totalCostBase += deduct * batch.unitCost * batch.exchangeRate;
      remaining -= deduct;
    }

    if (remaining > 0) {
      throw StateError(
        'Insufficient stock for $productName at station $stationId. '
        'Requested: $quantity, Shortfall: $remaining',
      );
    }

    return (totalCost, totalCostBase);
  }

  Future<List<FIFODeduction>> deductFIFODetailed({
    required int stationId,
    required String productName,
    required double quantity,
    String? productCode,
    String? rawMaterialId,
    int? fruitTypeId,
    String? itemType,
  }) async {
    final batches = await getBatches(
      stationId: stationId,
      productName: productName,
      productCode: productCode,
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
      itemType: itemType,
    );

    double remaining = quantity;
    final deductions = <FIFODeduction>[];

    for (final batch in batches) {
      if (remaining <= 0) break;

      final deduct = remaining < batch.remainingQuantity ? remaining : batch.remainingQuantity;
      final newRemaining = batch.remainingQuantity - deduct;

      await _client
          .from(_table)
          .update({'remaining_quantity': newRemaining})
          .eq('id', batch.id!);

      deductions.add(FIFODeduction(
        batchId: batch.id!,
        quantity: deduct,
        unitCost: batch.unitCost,
        currency: batch.currency,
        exchangeRate: batch.exchangeRate,
        supplierName: batch.supplierName,
        purchaseInvoiceId: batch.purchaseInvoiceId,
        sourceDate: batch.sourceDate,
        originalSourceType: batch.sourceType,
        productCode: batch.productCode,
        itemType: batch.itemType,
        rawMaterialId: batch.rawMaterialId,
        fruitTypeId: batch.fruitTypeId,
      ));

      remaining -= deduct;
    }

    return deductions;
  }
}
