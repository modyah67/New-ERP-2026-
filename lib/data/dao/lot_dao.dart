import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../models/lot_model.dart';
import '../services/currency_conversion_service.dart';
import '../services/lot_payment_service.dart';
import '../services/product_cost_center_sync_service.dart';
import '../services/crop_purchase_calculation_service.dart';

class LotDao {
  final _client = Supabase.instance.client;

  Future<List<LotReceiptModel>> getAll({String? status}) async {
    try {
      var query = _client.from('lot_receipts').select(
            '*, suppliers(name, code)',
          );

      if (status != null) {
        query = query.eq('status', status);
      }

      final data = await query.order('created_at', ascending: false);
      return data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final supplier = AppUtils.asMap(row.remove('suppliers'));
        return LotReceiptModel.fromMap({
          ...row,
          'supplier_name': supplier?['name'],
        });
      }).toList();
    } catch (e, st) {
      debugPrint('❌ LotDao.getAll error: $e\n$st');
      rethrow;
    }
  }

  Future<LotReceiptModel?> getById(dynamic id) async {
    try {
      final lot = await _client
          .from('lot_receipts')
          .select('*, suppliers(name, code)')
          .eq('id', id.toString())
          .maybeSingle();

      if (lot == null) return null;

      final row = Map<String, dynamic>.from(lot as Map);
      final supplier = AppUtils.asMap(row.remove('suppliers'));

      final result = LotReceiptModel.fromMap({
        ...row,
        'supplier_name': supplier?['name'],
      });

      final grading = await _client
          .from('lot_grading_results')
          .select()
          .eq('lot_id', id);

      debugPrint('LotDao.getById: lot_id=$id, grading rows found=${grading.length}');
      for (final g in grading) {
        debugPrint('  grading row: grade=${g['grade']}, weight_kg=${g['weight_kg']}, id=${g['id']}');
      }

      result.gradingResults = grading
          .map((g) => LotGradingResult.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList();

      debugPrint('LotDao.getById: parsed ${result.gradingResults.length} LotGradingResult objects');
      for (final r in result.gradingResults) {
        debugPrint('  LotGradingResult: grade=${r.grade}, weightKg=${r.weightKg}');
      }

      return result;
    } catch (e, st) {
      debugPrint('❌ LotDao.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> insert(LotReceiptModel lot) async {
    try {
      final countResult = await _client
          .from('lot_receipts')
          .select('id')
          .count(CountOption.exact);
      final nextNum = countResult.count + 1;
      final lotNumber = nextNum.toString();

      final payload = lot.toMap();
      payload['lot_number'] = lotNumber;
      if (lot.productName != null) payload['product_name'] = lot.productName;
      // Store immutable currency snapshot at time of creation
      payload['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
        currency: lot.currency,
        amount: lot.totalProductCost,
        exchangeRate: lot.exchangeRate,
      ).toJson();
      debugPrint('LotDao.insert: payload=$payload');
      final result = await _client
          .from('lot_receipts')
          .insert(payload)
          .select('id')
          .single();
      final insertedId = result['id'];
      debugPrint('LotDao.insert: DONE - inserted id=$insertedId, lot_number=$lotNumber, status=${lot.status}');

      // Automatically sync into cost center transactions
      try {
        final isCarton = lot.purchaseMode == 'carton';
        final double qty = isCarton
            ? (lot.cartonCount?.toDouble() ?? 0.0)
            : (lot.netWeightKg > 0 ? lot.netWeightKg : lot.grossWeightKg);
        final double unitPrice = isCarton
            ? (lot.pricePerCarton ?? 0.0)
            : (lot.fruitCostPerKg > 0 ? lot.fruitCostPerKg : (qty > 0 ? lot.totalProductCost / qty : 0.0));
        final double totalCost = lot.totalFruitCost > 0
            ? lot.totalFruitCost
            : (lot.totalProductCost > 0
                ? lot.totalProductCost
                : CropPurchaseCalculationService.calculateTotalAmount(
                    purchaseMethod: lot.purchaseMode,
                    cartonCount: lot.cartonCount,
                    pricePerCarton: lot.pricePerCarton,
                    grossWeightKg: lot.grossWeightKg,
                    netWeightKg: lot.netWeightKg,
                    pricePerKg: lot.fruitCostPerKg,
                  ));

        final formulaDesc = CropPurchaseCalculationService.buildFormulaDescription(
          purchaseMethod: lot.purchaseMode,
          cartonCount: lot.cartonCount,
          pricePerCarton: lot.pricePerCarton,
          grossWeightKg: lot.grossWeightKg,
          netWeightKg: lot.netWeightKg,
          pricePerKg: lot.fruitCostPerKg,
          totalAmount: totalCost,
          currency: lot.currency,
        );

        ProductCostCenterSyncService.instance.recordCropPurchaseTransaction(
          sourceType: 'lot_receipt',
          sourceId: insertedId.toString(),
          fruitTypeId: lot.fruitTypeId?.toString(),
          cropName: lot.productName,
          supplierName: lot.supplierName,
          purchaseDate: DateTime.tryParse(lot.createdAt?.toIso8601String() ?? '') ?? DateTime.now(),
          quantity: qty,
          unitPrice: unitPrice,
          totalCost: totalCost,
          currency: lot.currency,
          exchangeRate: lot.exchangeRate,
          notes: lot.notes != null ? '${lot.notes} ($formulaDesc)' : formulaDesc,
        ).catchError((e) {
          debugPrint('Cost center sync non-fatal error in LotDao.insert: $e');
        });
      } catch (e) {
        debugPrint('Cost center sync error in LotDao.insert: $e');
      }

      return {'id': insertedId, 'lot_number': lotNumber};
    } catch (e, st) {
      debugPrint('❌ LotDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    debugPrint('LotDao.updateStatus: id=$id, status=$status');
    if (!LotReceiptModel.validStatuses.contains(status)) {
      throw ArgumentError('Invalid lot_receipts status: "$status". '
          'Must be one of: ${LotReceiptModel.validStatuses.join(", ")}');
    }
    try {
      await _client.from('lot_receipts').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      debugPrint('LotDao.updateStatus: DONE - id=$id status=$status');
    } catch (e, st) {
      debugPrint('❌ LotDao.updateStatus error: $e\n$st');
      rethrow;
    }
  }

  Future<void> update(
    dynamic id,
    LotReceiptModel lot, {
    bool skipCostFields = false,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'product_name': lot.productName,
        'supplier_id': lot.supplierId,
        'gross_weight_kg': lot.grossWeightKg,
        'net_weight_kg': lot.netWeightKg,
        'waste_weight_kg': lot.wasteWeightKg,
        'waste_percentage': lot.wastePercentage,
        if (!skipCostFields) 'fruit_cost_per_kg': lot.fruitCostPerKg,
        if (!skipCostFields) 'total_fruit_cost': lot.totalFruitCost,
        if (!skipCostFields)
          'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
            currency: lot.currency,
            amount: lot.totalFruitCost,
            exchangeRate: lot.exchangeRate,
          ).toJson(),
        if (lot.stationId != null) 'station_id': lot.stationId,
        if (lot.purchaseInvoiceItemId != null)
          'purchase_invoice_item_id': lot.purchaseInvoiceItemId,
        if (lot.notes != null) 'notes': lot.notes,
        'purchase_mode': lot.purchaseMode,
        if (lot.cartonCount != null) 'carton_count': lot.cartonCount,
        if (lot.weightPerCartonKg != null)
          'weight_per_carton_kg': lot.weightPerCartonKg,
        if (lot.grossWeightPerCartonKg != null)
          'gross_weight_per_carton_kg': lot.grossWeightPerCartonKg,
        if (lot.pricePerCarton != null) 'price_per_carton': lot.pricePerCarton,
        'currency': lot.currency,
        'exchange_rate': lot.exchangeRate,
        'paid_amount': lot.paidAmount,
        'payment_source_type': lot.paymentSourceType,
        'payment_treasury_id': lot.paymentTreasuryId,
        'payment_bank_account_id': lot.paymentBankAccountId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _client
          .from('lot_receipts')
          .update(updateData)
          .eq('id', id);
    } catch (e, st) {
      debugPrint('❌ LotDao.update error: $e\n$st');
      rethrow;
    }
  }

  Future<void> saveGradingResults(
      String lotId, List<LotGradingResult> results) async {
    try {
      await _client
          .from('lot_grading_results')
          .delete()
          .eq('lot_id', lotId);

      if (results.isEmpty) return;

      await _client.from('lot_grading_results').insert(
            results
                .map((r) => {...r.toMap(), 'lot_id': lotId})
                .toList(),
          );

      if (results.any((r) => r.grade != 'waste')) {
        await updateStatus(lotId, 'sorting');
      }
    } catch (e, st) {
      debugPrint('❌ LotDao.saveGradingResults error: $e\n$st');
      rethrow;
    }
  }

  /// Atomically applies supplier balance, ledger, stock batches, station
  /// inventory, and product price/qty updates via Postgres RPC.
  Future<Map<String, dynamic>> processReceiptSideEffects(
    String lotId, {
    double? unitCostKg,
    String? oldStationId,
    String? oldFruitTypeId,
    String? oldSupplierId,
    bool isEdit = false,
  }) async {
    try {
      debugPrint(
          'LotDao.processReceiptSideEffects: lotId=$lotId, unitCostKg=$unitCostKg, oldStationId=$oldStationId, oldFruitTypeId=$oldFruitTypeId, oldSupplierId=$oldSupplierId, isEdit=$isEdit');

      final bool isReprocess = isEdit ||
          oldStationId != null || oldFruitTypeId != null || oldSupplierId != null;

      final rpcName = isReprocess
          ? 'rpc_reprocess_lot_receipt'
          : 'rpc_process_lot_receipt';

      final params = isReprocess
          ? <String, dynamic>{
              'p_lot_id': lotId,
              if (unitCostKg != null && unitCostKg > 0)
                'p_unit_cost_kg': unitCostKg,
              if (oldStationId != null && oldStationId.isNotEmpty) 'p_old_station_id': oldStationId,
              if (oldFruitTypeId != null && oldFruitTypeId.isNotEmpty) 'p_old_fruit_type_id': oldFruitTypeId,
              if (oldSupplierId != null && oldSupplierId.isNotEmpty) 'p_old_supplier_id': oldSupplierId,
            }
          : <String, dynamic>{
              'p_lot_id': lotId,
              if (unitCostKg != null && unitCostKg > 0)
                'p_unit_cost_kg': unitCostKg,
            };

      final result = await _client.rpc(rpcName, params: params);
      final map = Map<String, dynamic>.from(result as Map);
      debugPrint('LotDao.processReceiptSideEffects: DONE $map');
      if (map.containsKey('success') && map['success'] != true) {
        throw Exception(map['error']?.toString() ?? 'فشل معالجة شراء المحصول');
      }

      // Automatically sync into cost center transactions
      try {
        final lotRow = await _client
            .from('lot_receipts')
            .select('*, suppliers(name), fruit_types(name, cost_center_id)')
            .eq('id', lotId)
            .maybeSingle();
        if (lotRow != null) {
          final sName = lotRow['suppliers']?['name']?.toString();
          final fName = lotRow['fruit_types']?['name']?.toString() ?? lotRow['product_name']?.toString();
          final isCarton = lotRow['purchase_mode'] == 'carton';
          final double qty = isCarton && (lotRow['carton_count'] as num? ?? 0) > 0
              ? (lotRow['carton_count'] as num).toDouble()
              : ((lotRow['net_weight_kg'] as num?)?.toDouble() ??
                  (lotRow['gross_weight_kg'] as num?)?.toDouble() ??
                  0.0);
          final double unitPrice = isCarton && (lotRow['price_per_carton'] as num? ?? 0) > 0
              ? (lotRow['price_per_carton'] as num).toDouble()
              : ((lotRow['fruit_cost_per_kg'] as num?)?.toDouble() ??
                  (lotRow['price_per_carton'] as num?)?.toDouble() ??
                  0.0);
          final double totalCost = (lotRow['total_fruit_cost'] as num?)?.toDouble() ??
              (lotRow['total_product_cost'] as num?)?.toDouble() ??
              (qty * unitPrice);
          final DateTime? pDate = DateTime.tryParse(lotRow['created_at']?.toString() ?? '');

          await ProductCostCenterSyncService.instance.recordCropPurchaseTransaction(
            sourceType: 'lot_receipt',
            sourceId: lotId.toString(),
            fruitTypeId: lotRow['fruit_type_id']?.toString(),
            cropName: fName,
            supplierName: sName,
            purchaseDate: pDate ?? DateTime.now(),
            quantity: qty,
            unitPrice: unitPrice,
            totalCost: totalCost > 0 ? totalCost : (qty * unitPrice),
            currency: lotRow['currency']?.toString() ?? 'EGP',
            exchangeRate: (lotRow['exchange_rate'] as num?)?.toDouble() ?? 1.0,
            notes: lotRow['notes']?.toString(),
          );
        }
      } catch (e) {
        debugPrint('Cost center sync non-fatal error in LotDao.processReceiptSideEffects: $e');
      }

      return map;
    } catch (e, st) {
      debugPrint('❌ LotDao.processReceiptSideEffects error: $e\n$st');
      rethrow;
    }
  }

  /// Syncs a single entry into station_product_batches after the main RPC succeeds.
  /// Called from lot_form_page after processReceiptSideEffects.
    Future<void> syncStationProductBatch({
      required String stationId,
      required String productName,
      required String productCode,
      required double quantity,
      required double unitCost,
      String supplierName = '',
      double exchangeRate = 1.0,
      String currency = 'EGP',
    }) async {
      try {
        final existingBatchRes = await _client
            .from('station_product_batches')
            .select('id, quantity, remaining_quantity')
            .eq('source_type', 'lot_receipt')
            .eq('station_id', stationId)
            .eq('product_code', productCode)
            .eq('product_name', productName)
            .maybeSingle();

        if (existingBatchRes != null) {
          final existingBatch = Map<String, dynamic>.from(existingBatchRes);
          final oldQty = double.tryParse(existingBatch['quantity']?.toString() ?? '0') ?? 0;
          final oldRemaining = double.tryParse(existingBatch['remaining_quantity']?.toString() ?? '0') ?? 0;
          
          final usedQty = oldQty - oldRemaining;
          final newRemaining = quantity - (usedQty > 0 ? usedQty : 0);
          
          await _client.from('station_product_batches').update({
            'quantity': quantity,
            'remaining_quantity': newRemaining > 0 ? newRemaining : 0,
            'unit_cost': unitCost,
            'supplier_name': supplierName,
            'exchange_rate': exchangeRate,
            'currency': currency,
          }).eq('id', existingBatch['id']);
          debugPrint('LotDao.syncStationProductBatch: UPDATED $productCode');
        } else {
          debugPrint('LotDao.syncStationProductBatch: NOT FOUND $productCode');
        }
      } catch (e) {
        debugPrint('LotDao.syncStationProductBatch failed (non-critical): $e');
      }
    }

    /// Cleans up duplicate batches created by a DB mismatch and fixes the original batch
    Future<void> cleanupDuplicateBatches({
      required String stationId,
      required String productName,
      required String lotNumber,
      required String createdAt,
    }) async {
      try {
        // Fix the original batch's product_code (the DB RPC might have inserted NULL or fruit_type_code)
        await _client.from('station_product_batches')
            .update({'product_code': lotNumber})
            .eq('source_type', 'lot_receipt')
            .eq('station_id', stationId)
            .eq('product_name', productName)
            .eq('source_date', createdAt);

        // Delete any duplicates created by the sync script (which have source_date IS NULL)
        await _client.from('station_product_batches')
            .delete()
            .eq('source_type', 'lot_receipt')
            .eq('station_id', stationId)
            .eq('product_name', productName)
            .eq('product_code', lotNumber)
            .isFilter('source_date', null);
      } catch (e) {
        debugPrint('Failed to cleanup batches: $e');
      }
    }

  Future<void> updateLotPrice(String lotId, double newPrice, double exchangeRate, String currency) async {
    try {
      final result = await _client.rpc('rpc_edit_lot_price', params: {
        'p_lot_id': lotId,
        'p_new_price': newPrice,
        'p_exchange_rate': exchangeRate,
        'p_currency': currency,
      });
      final map = Map<String, dynamic>.from(result as Map);
      if (map.containsKey('success') && map['success'] != true) {
        throw Exception(map['error']?.toString() ?? 'فشل تعديل سعر المحصول');
      }
    } catch (e, st) {
      debugPrint('❌ LotDao.updateLotPrice error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      await _client
          .from('lot_grading_results')
          .delete()
          .eq('lot_id', id);
      await _client.from('lot_receipts').delete().eq('id', id);
    } catch (e, st) {
      debugPrint('❌ LotDao.delete error: $e\n$st');
      rethrow;
    }
  }

  /// Confirms a draft lot receipt: marks it as confirmed and runs all side
  /// effects (inventory, supplier balance, ledger entries, stock batches).
  /// Returns the RPC result map on success.
  Future<Map<String, dynamic>> confirmLot(String lotId) async {
    try {
      debugPrint('LotDao.confirmLot: lotId=$lotId');

      // 1. Fetch the lot to get unit cost info
      final lot = await getById(lotId);
      if (lot == null) {
        throw Exception('المحصول غير موجود');
      }
      if (lot.isConfirmed) {
        throw Exception('المحصول مؤكد بالفعل');
      }

      // 2. Determine unit cost
      final double unitCostKg;
      if (lot.purchaseMode == 'carton') {
        final netWeightKg = lot.netWeightKg > 0 ? lot.netWeightKg : lot.grossWeightKg;
        unitCostKg = netWeightKg > 0
            ? ((lot.cartonCount ?? 0) * (lot.pricePerCarton ?? 0)) / netWeightKg
            : 0;
      } else {
        unitCostKg = lot.productCostPerKg;
      }

      // 3. Run side effects via RPC (station_product_batches, station_products)
      final rpcResult = await processReceiptSideEffects(
        lotId,
        unitCostKg: unitCostKg,
      );

      if (lot.purchaseMode == 'carton' && rpcResult['station_id'] != null) {
        final supplierName = await _resolveSupplierName(lot.supplierId);
        double netCartons = 0;
        if ((lot.weightPerCartonKg ?? 0) > 0) {
          netCartons = (lot.netWeightKg / lot.weightPerCartonKg!).roundToDouble();
        } else {
          netCartons = (lot.cartonCount ?? 0).toDouble();
        }
        if (netCartons < 0) netCartons = 0;
        
        final cartonUnitCost = netCartons > 0 ? lot.totalProductCost / netCartons : 0.0;
        
        await syncStationProductBatch(
          stationId: rpcResult['station_id'].toString(),
          productName: rpcResult['product_name']?.toString() ?? lot.productName ?? '',
          productCode: lot.lotNumber,
          quantity: netCartons,
          unitCost: cartonUnitCost,
          supplierName: supplierName,
          exchangeRate: lot.exchangeRate,
          currency: lot.currency,
        );
      }

      // 4. Mark as confirmed — triggers fn_on_harvest_receipt_saved which:
      //    - creates supplier credit ledger entry (sync_supplier_ledger_for_lot)
      //    - creates stock_batches (sync_inventory_stock_for_lot)
      await _client.from('lot_receipts').update({
        'is_confirmed': true,
        'confirmed_at': DateTime.now().toIso8601String(),
      }).eq('id', lotId);

      // Ensure enterprise journal entry is posted/linked
      await _ensureJournalEntryForLot(lot);

      // 5. Process treasury/bank payment
      //    NOTE: For purchases made via purchase_invoices, rpc_confirm_purchase handles
      //    the payment. But most users create lot receipts directly without purchase
      //    invoices, so we need LotPaymentService here too.
      if (lot.paidAmount > 0) {
        final supplierName = await _resolveSupplierName(lot.supplierId);
        await LotPaymentService().processPayment(
          lot: lot,
          supplierName: supplierName,
        );
        debugPrint('LotPayment: processed ${lot.paidAmount} ${lot.currency} for lot ${lot.lotNumber}');
      }
      
      DataChangeEventBus.instance.notifySuppliersChanged();

      debugPrint('LotDao.confirmLot: DONE');
      return rpcResult;
    } catch (e, st) {
      debugPrint('❌ LotDao.confirmLot error: $e\n$st');
      rethrow;
    }
  }

  Future<void> _ensureJournalEntryForLot(LotReceiptModel lot) async {
    try {
      if (lot.id == null || (lot.totalProductCost <= 0)) return;

      // 1. Check if lot already has a journal entry linked in the database
      final existingLot = await _client
          .from('lot_receipts')
          .select('journal_entry_id')
          .eq('id', lot.id!)
          .maybeSingle();

      if (existingLot != null && existingLot['journal_entry_id'] != null) {
        return;
      }

      // 2. Check if journal entry exists for this source_type + source_id
      final existingJe = await _client
          .from('journal_entries')
          .select('id')
          .eq('source_type', 'lot_receipt')
          .eq('source_id', lot.id!.toString())
          .isFilter('deleted_at', null)
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();

      if (existingJe != null && existingJe['id'] != null) {
        final jeId = existingJe['id'];
        await _client.from('lot_receipts').update({
          'journal_entry_id': jeId,
        }).eq('id', lot.id!);
        debugPrint('✅ _ensureJournalEntryForLot: Linked existing JE $jeId to lot ${lot.lotNumber}');
        return;
      }

      // 3. PostgreSQL trigger/function is the single source of truth.
      // If the trigger was not executed automatically, call sync_supplier_ledger_for_lot RPC.
      try {
        await _client.rpc('sync_supplier_ledger_for_lot', params: {
          'p_lot_id': lot.id!,
          'p_action': 'INSERT',
        });
      } catch (rpcErr) {
        debugPrint('⚠️ LotDao._ensureJournalEntryForLot: sync_supplier_ledger_for_lot RPC fallback: $rpcErr');
      }

      // 4. Check again if JE was created and link it to the lot
      final jeAfterSync = await _client
          .from('journal_entries')
          .select('id')
          .eq('source_type', 'lot_receipt')
          .eq('source_id', lot.id!.toString())
          .isFilter('deleted_at', null)
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();

      if (jeAfterSync != null && jeAfterSync['id'] != null) {
        final jeId = jeAfterSync['id'];
        await _client.from('lot_receipts').update({
          'journal_entry_id': jeId,
        }).eq('id', lot.id!);
        debugPrint('✅ _ensureJournalEntryForLot: Linked generated JE $jeId to lot ${lot.lotNumber}');
      }
    } catch (e, st) {
      debugPrint('❌ LotDao._ensureJournalEntryForLot error: $e\n$st');
    }
  }

  Future<String> _resolveSupplierName(String? supplierId) async {
    if (supplierId == null || supplierId.isEmpty) return '';
    try {
      final result = await _client
          .from('suppliers')
          .select('name')
          .eq('id', supplierId)
          .maybeSingle();
      return result?['name']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> getJournalEntriesForLot(String lotId) async {
    if (lotId.trim().isEmpty) return [];
    try {
      try {
        final result = await _client.rpc('rpc_get_lot_journal_entries', params: {
          'p_lot_id': lotId,
        });
        if (result is List && result.isNotEmpty) {
          return result.cast<Map<String, dynamic>>();
        }
      } catch (rpcError) {
        debugPrint('⚠️ LotDao.getJournalEntriesForLot RPC warning (falling back to direct query): $rpcError');
      }

      // Fallback 1: Query journal_entries directly by linked journal_entry_id or source_id
      final lotRow = await _client
          .from('lot_receipts')
          .select('id, lot_number, is_confirmed, journal_entry_id, total_fruit_cost')
          .eq('id', lotId)
          .maybeSingle();

      if (lotRow != null) {
        final jeId = lotRow['journal_entry_id'];
        if (jeId != null) {
          final directJe = await _client
              .from('journal_entries')
              .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
              .eq('id', jeId)
              .maybeSingle();
          if (directJe != null) {
            final lines = await _client
                .from('account_ledger_entries')
                .select('debit, credit, currency')
                .eq('journal_entry_id', jeId);
            double totalDebit = 0;
            double totalCredit = 0;
            String cur = 'EGP';
            for (final line in (lines as List)) {
              totalDebit += (line['debit'] as num?)?.toDouble() ?? 0;
              totalCredit += (line['credit'] as num?)?.toDouble() ?? 0;
              if (line['currency'] != null) cur = line['currency'].toString();
            }
            return [
              {
                'journal_entry_id': directJe['id'],
                'entry_number': directJe['entry_number'] ?? 'LOT-$jeId',
                'entry_date': directJe['entry_date'],
                'description': directJe['description'],
                'source_type': directJe['source_type'] ?? 'lot_receipt',
                'source_id': directJe['source_id'] ?? lotId,
                'total_debit': totalDebit > 0 ? totalDebit : (lotRow['total_fruit_cost'] ?? 0),
                'total_credit': totalCredit > 0 ? totalCredit : (lotRow['total_fruit_cost'] ?? 0),
                'currency': cur,
                'created_at': directJe['created_at'],
              }
            ];
          }
        }

        // Fallback 2: Self-healing. If lot is confirmed but has no JE, generate it on the fly!
        if (lotRow['is_confirmed'] == true && ((lotRow['total_fruit_cost'] as num?)?.toDouble() ?? 0) > 0) {
          final lotObj = await getById(lotId);
          if (lotObj != null) {
            await _ensureJournalEntryForLot(lotObj);
            // Re-fetch after healing: first try RPC safely
            try {
              final healed = await _client.rpc('rpc_get_lot_journal_entries', params: {
                'p_lot_id': lotId,
              });
              if (healed is List && healed.isNotEmpty) {
                return healed.cast<Map<String, dynamic>>();
              }
            } catch (_) {}
            // If still empty from RPC, check lot_receipts.journal_entry_id directly
            final reLot = await _client
                .from('lot_receipts')
                .select('journal_entry_id')
                .eq('id', lotId)
                .maybeSingle();
            final newJeId = reLot?['journal_entry_id'];
            if (newJeId != null) {
              final directJe = await _client
                  .from('journal_entries')
                  .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
                  .eq('id', newJeId)
                  .maybeSingle();
              if (directJe != null) {
                return [
                  {
                    'journal_entry_id': directJe['id'],
                    'entry_number': directJe['entry_number'] ?? 'LOT-$newJeId',
                    'entry_date': directJe['entry_date'],
                    'description': directJe['description'],
                    'source_type': directJe['source_type'] ?? 'lot_receipt',
                    'source_id': directJe['source_id'] ?? lotId,
                    'total_debit': (lotRow['total_fruit_cost'] ?? 0),
                    'total_credit': (lotRow['total_fruit_cost'] ?? 0),
                    'currency': lotObj.currency.isNotEmpty ? lotObj.currency : 'EGP',
                    'created_at': directJe['created_at'],
                  }
                ];
              }
            }
          }
        }
      }

      return [];
    } catch (e) {
      debugPrint('LotDao.getJournalEntriesForLot error: $e');
      return [];
    }
  }
}
