import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../models/supplier_model.dart';
import '../services/currency_conversion_service.dart';

class LotReturnModel {
  final String? id;
  final String lotReceiptId;
  final String? supplierId;
  final String? stationId;
  final double returnedQuantity;
  final double returnValue;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;
  final int? journalEntryId;

  LotReturnModel({
    this.id,
    required this.lotReceiptId,
    this.supplierId,
    this.stationId,
    required this.returnedQuantity,
    required this.returnValue,
    this.notes,
    this.createdAt,
    this.createdBy,
    this.journalEntryId,
  });

  factory LotReturnModel.fromMap(Map<String, dynamic> map) {
    return LotReturnModel(
      id: map['id']?.toString(),
      lotReceiptId: map['lot_receipt_id'].toString(),
      supplierId: map['supplier_id']?.toString(),
      stationId: map['station_id']?.toString(),
      returnedQuantity: (map['returned_quantity'] as num?)?.toDouble() ?? 0.0,
      returnValue: (map['return_value'] as num?)?.toDouble() ?? 0.0,
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      createdBy: map['created_by']?.toString(),
      journalEntryId: map['journal_entry_id'] as int?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'lot_receipt_id': lotReceiptId,
      'supplier_id': supplierId,
      'station_id': stationId,
      'returned_quantity': returnedQuantity,
      'return_value': returnValue,
      'notes': notes,
    };
  }
}

class LotReturnDao {
  final _client = Supabase.instance.client;

  /// Fetches lots available for return along with canonical purchased and remaining quantities.
  /// First calls backend RPC `rpc_get_lot_return_available_quantities`.
  /// If the RPC is not yet deployed or errors, falls back to direct query calculation.
  Future<List<Map<String, dynamic>>> getAvailableLotsForReturn({String? lotId}) async {
    try {
      final parsedLotId = lotId != null ? int.tryParse(lotId) : null;
      final params = parsedLotId != null
          ? {'p_lot_id': parsedLotId}
          : (lotId != null ? {'p_lot_id': lotId} : <String, dynamic>{});
      final response = await _client.rpc('rpc_get_lot_return_available_quantities', params: params);
      if (response is List && response.isNotEmpty) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('⚠️ RPC rpc_get_lot_return_available_quantities fallback: $e');
    }

    try {
      var query = _client.from('lot_receipts').select('''
        id,
        lot_number,
        product_name,
        fruit_type_id,
        supplier_id,
        station_id,
        receipt_date,
        purchase_mode,
        currency,
        exchange_rate,
        carton_count,
        weight_per_carton_kg,
        gross_weight_kg,
        net_weight_kg,
        fruit_cost_per_kg,
        price_per_carton,
        total_fruit_cost,
        is_confirmed,
        suppliers (name),
        stations (name),
        lot_returns (returned_quantity)
      ''').eq('is_confirmed', true);

      if (lotId != null) {
        query = query.eq('id', lotId);
      }

      final data = await query.order('receipt_date', ascending: false);
      final results = <Map<String, dynamic>>[];

      for (final row in data) {
        final mode = row['purchase_mode']?.toString() ?? 'weight';
        final cartonCount = (row['carton_count'] as num?)?.toDouble() ?? 0.0;
        final netWeight = (row['net_weight_kg'] as num?)?.toDouble() ?? 0.0;
        final grossWeight = (row['gross_weight_kg'] as num?)?.toDouble() ?? 0.0;

        final weightPerCarton = (row['weight_per_carton_kg'] as num?)?.toDouble() ?? 0.0;

        double purchasedGrossQty;
        double netWarehouseQty;
        if (mode == 'carton') {
          if (cartonCount > 0) {
            purchasedGrossQty = cartonCount;
            netWarehouseQty = cartonCount;
          } else if (weightPerCarton > 0 && netWeight > 0) {
            purchasedGrossQty = (netWeight / weightPerCarton).roundToDouble();
            netWarehouseQty = purchasedGrossQty;
          } else {
            purchasedGrossQty = cartonCount;
            netWarehouseQty = cartonCount;
          }
        } else {
          purchasedGrossQty = grossWeight > 0 ? grossWeight : netWeight;
          netWarehouseQty = netWeight > 0 ? netWeight : grossWeight;
        }

        final returnsList = (row['lot_returns'] as List?) ?? [];
        double alreadyReturned = 0.0;
        for (final r in returnsList) {
          alreadyReturned += (r['returned_quantity'] as num?)?.toDouble() ?? 0.0;
        }

        final availableQty = (netWarehouseQty - alreadyReturned).clamp(0.0, double.infinity);
        if (availableQty <= 0) continue;

        final pricePerCarton = (row['price_per_carton'] as num?)?.toDouble() ?? 0.0;
        final fruitCostPerKg = (row['fruit_cost_per_kg'] as num?)?.toDouble() ?? 0.0;
        final totalFruitCost = (row['total_fruit_cost'] as num?)?.toDouble() ?? 0.0;
        final unitPrice = (mode == 'carton')
            ? (pricePerCarton > 0 ? pricePerCarton : (netWarehouseQty > 0 ? totalFruitCost / netWarehouseQty : 0.0))
            : (fruitCostPerKg > 0 ? fruitCostPerKg : (netWarehouseQty > 0 ? totalFruitCost / netWarehouseQty : 0.0));

        results.add({
          'lot_id': row['id'],
          'lot_number': row['lot_number'] ?? row['id']?.toString(),
          'product_name': row['product_name'] ?? 'محصول',
          'fruit_type_id': row['fruit_type_id'],
          'supplier_id': row['supplier_id'],
          'supplier_name': (row['suppliers'] as Map?)?['name'] ?? 'بدون مورد',
          'station_id': row['station_id'],
          'station_name': (row['stations'] as Map?)?['name'] ?? 'المحطة الرئيسية',
          'receipt_date': row['receipt_date'],
          'purchase_mode': mode,
          'currency': row['currency'] ?? 'EGP',
          'exchange_rate': (row['exchange_rate'] as num?)?.toDouble() ?? 1.0,
          'unit_price': unitPrice,
          'total_fruit_cost': totalFruitCost,
          'purchased_quantity': purchasedGrossQty,
          'net_quantity': netWarehouseQty,
          'already_returned_quantity': alreadyReturned,
          'available_quantity': availableQty,
          'unit_label': mode == 'carton' ? 'كرتونة' : 'كجم',
        });
      }
      return results;
    } catch (e) {
      debugPrint('⚠️ Fallback query error for available return lots: $e');
      return [];
    }
  }

  Future<List<LotReturnModel>> getAll({int limit = 50, int offset = 0}) async {
    final response = await _client
        .from('lot_returns')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    
    return response.map((e) => LotReturnModel.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getHistoryWithDetails({int limit = 100}) async {
    final response = await _client
        .from('lot_returns')
        .select('''
          id,
          lot_receipt_id,
          supplier_id,
          station_id,
          returned_quantity,
          return_value,
          notes,
          created_at,
          created_by,
          journal_entry_id,
          lot_receipts (
            lot_number,
            product_name,
            purchase_mode,
            currency
          ),
          suppliers (
            name
          ),
          stations (
            name
          ),
          journal_entries:journal_entry_id (
            entry_number
          )
        ''')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> processReturn({
    required String lotId,
    required double returnQuantity,
    String? notes,
    String? stationId,
    int? batchId,
    String? costCenterId,
  }) async {
    final params = <String, dynamic>{
      'p_lot_id': int.parse(lotId),
      'p_return_quantity': returnQuantity,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
      if (stationId != null) 'p_station_id': int.parse(stationId),
      if (batchId != null) 'p_batch_id': batchId,
      if (costCenterId != null && costCenterId.isNotEmpty) 'p_cost_center_id': costCenterId,
    };

    dynamic response;
    try {
      response = await _client
          .rpc('rpc_process_lot_return', params: params)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('انتهت مهلة الاتصال - حاول مرة أخرى');
      });
    } on PostgrestException catch (e) {
      // If the backend function in PostgreSQL lacks p_station_id, retry without it
      if (e.code == 'PGRST202' && params.containsKey('p_station_id')) {
        final fallbackParams = Map<String, dynamic>.from(params)..remove('p_station_id');
        response = await _client
            .rpc('rpc_process_lot_return', params: fallbackParams)
            .timeout(const Duration(seconds: 30), onTimeout: () {
          throw Exception('انتهت مهلة الاتصال - حاول مرة أخرى');
        });
      } else {
        rethrow;
      }
    }

    final result = Map<String, dynamic>.from(response as Map);
    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'فشل تسجيل المرتجع');
    }

    // Note: Deductions from station_product_batches and station_products
    // are handled atomically inside rpc_process_lot_return (FIFO cascade & dual quantity reduction).


    // Deduct native amount from currentBalancesByCurrency and converted equivalent from outstanding_balance
    try {
      final lotData = await _client
          .from('lot_receipts')
          .select('id, lot_number, supplier_id, currency, exchange_rate, fruit_cost_per_kg, price_per_kg, total_fruit_cost, gross_weight_kg')
          .eq('id', lotId)
          .maybeSingle();

      if (lotData != null && lotData['supplier_id'] != null) {
        final supplierId = lotData['supplier_id'].toString();
        await deductSupplierBalanceOnReturn(
          supplierId: supplierId,
          lotData: lotData,
          returnQuantity: returnQuantity,
          returnValue: (result['return_value'] as num?)?.toDouble(),
          returnId: result['return_id']?.toString() ?? result['id']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error in supplier balance deduction during return: $e');
    }

    DataChangeEventBus.instance.notifyStationsChanged();
    DataChangeEventBus.instance.notifyItemsChanged();
    DataChangeEventBus.instance.notifyCropPurchasesChanged();
    DataChangeEventBus.instance.notifySuppliersChanged();
    DataChangeEventBus.instance.notifyCostCentersChanged();

    return result;
  }

  /// Deducts the returned purchase amount from the supplier's balances:
  /// 1. Subtracts native amount from [currentBalancesByCurrency].
  /// 2. Subtracts converted equivalent from [outstanding_balance] in the database.
  /// 3. Ensures [ledger_entries] for the return is stamped with the native currency.
  Future<void> deductSupplierBalanceOnReturn({
    required String supplierId,
    required Map<String, dynamic> lotData,
    required double returnQuantity,
    double? returnValue,
    String? returnId,
  }) async {
    final supRes = await _client
        .from('suppliers')
        .select('*')
        .eq('id', supplierId)
        .maybeSingle();
    if (supRes == null) return;
    final supplier = SupplierModel.fromMap(supRes);

    // 1. Resolve native currency
    final rawCur = lotData['currency']?.toString();
    final currency = (rawCur != null && rawCur.isNotEmpty && rawCur != 'MULTI')
        ? rawCur
        : (supplier.cropCurrency.isNotEmpty
            ? supplier.cropCurrency
            : (supplier.currency.isNotEmpty && supplier.currency != 'MULTI'
                ? supplier.currency
                : 'EGP'));

    // 2. Compute native return value
    final effectiveReturnValue = returnValue ??
        (returnQuantity *
            ((lotData['fruit_cost_per_kg'] as num?)?.toDouble() ??
                ((lotData['price_per_kg'] as num?)?.toDouble() ?? 0.0)));
    if (effectiveReturnValue <= 0) return;

    // 3. Resolve exchange rate to base EGP
    double exchangeRate = (lotData['exchange_rate'] as num?)?.toDouble() ?? 0.0;
    if (exchangeRate <= 0 && currency != 'EGP') {
      try {
        exchangeRate = await CurrencyConversionService.instance
            .getRate(currency);
      } catch (_) {
        exchangeRate = 1.0;
      }
    }
    if (exchangeRate <= 0) exchangeRate = 1.0;

    final returnValueEgp = (currency == 'EGP')
        ? effectiveReturnValue
        : (effectiveReturnValue * exchangeRate);

    // 4. Deduct native amount from currentBalancesByCurrency
    final curBalances = Map<String, double>.from(supplier.currentBalancesByCurrency);
    final currentNativeBal = curBalances[currency] ??
        (supplier.currency == currency ? supplier.outstandingBalance : 0.0);
    curBalances[currency] = currentNativeBal - effectiveReturnValue;

    // 5. Deduct converted equivalent from outstanding_balance in database
    // Note: rpc_process_lot_return subtracted v_return_value (native amount).
    // For foreign suppliers, the full converted deduction in EGP is returnValueEgp.
    // We adjust outstanding_balance so the net deduction is exactly returnValueEgp.
    final currentOutstanding =
        (supRes['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
    final newOutstanding = (currency == 'EGP')
        ? currentOutstanding
        : (currentOutstanding - (returnValueEgp - effectiveReturnValue));

    // 6. Update database record
    await _client.from('suppliers').update({
      'current_balances_by_currency': curBalances,
      'outstanding_balance': newOutstanding,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', supplierId);

    // 7. Ensure ledger_entries record reflects the native currency and amount
    if (returnId != null && returnId.isNotEmpty) {
      await _client.from('ledger_entries').update({
        'currency': currency,
        'amount': effectiveReturnValue,
      }).eq('reference_type', 'lot_return').eq('reference_text', returnId);
    }
  }
}
