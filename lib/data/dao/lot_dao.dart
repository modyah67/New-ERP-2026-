import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../models/lot_model.dart';
import '../services/currency_conversion_service.dart';
import '../services/lot_payment_service.dart';


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
        
        final cartonUnitCost = netCartons > 0 ? (lot.totalProductCost ?? 0.0) / netCartons : 0.0;
        
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

      // 1. Check if lot already has a journal entry
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
          .eq('source_id', lot.id!)
          .maybeSingle();

      if (existingJe != null && existingJe['id'] != null) {
        await _client.from('lot_receipts').update({
          'journal_entry_id': existingJe['id'],
        }).eq('id', lot.id!);
        return;
      }

      // 3. Post journal entry via RPC
      final companyRes = await _client.from('sys_companies').select('id').limit(1).maybeSingle();
      final companyId = companyRes?['id']?.toString();
      if (companyId == null) return;

      final invAcc = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '1030')
          .limit(1)
          .maybeSingle();
      final invAccId = invAcc?['id'];

      dynamic supplierAccId;
      if (lot.supplierId != null) {
        final suppRes = await _client
            .from('suppliers')
            .select('account_id')
            .eq('id', lot.supplierId!)
            .maybeSingle();
        supplierAccId = suppRes?['account_id'];
      }
      if (supplierAccId == null) {
        final defaultSuppAcc = await _client
            .from('accounts')
            .select('id')
            .eq('account_code', '2000')
            .limit(1)
            .maybeSingle();
        supplierAccId = defaultSuppAcc?['id'];
      }

      if (invAccId != null && supplierAccId != null) {
        final totalEgp = lot.totalProductCost * (lot.exchangeRate > 0 ? lot.exchangeRate : 1.0);
        final desc = 'شراء محصول خام ${lot.productName ?? "محصول"} - لوط رقم: ${lot.lotNumber}';

        final jeId = await _client.rpc('post_journal_entry', params: {
          'p_source_type': 'lot_receipt',
          'p_description': desc,
          'p_entry_date': AppUtils.formatDateForDb(lot.receiptDate),
          'p_company_id': companyId,
          'p_created_by': _client.auth.currentUser?.id,
          'p_lines': [
            {
              'account_id': invAccId,
              'debit': totalEgp,
              'credit': 0,
              'currency': lot.currency,
              'description': 'شراء محصول رقم ${lot.lotNumber}',
            },
            {
              'account_id': supplierAccId,
              'debit': 0,
              'credit': totalEgp,
              'currency': lot.currency,
              'description': 'مستحقات مورد عن شراء محصول رقم ${lot.lotNumber}',
            }
          ]
        });

        if (jeId != null) {
          await _client.from('journal_entries').update({
            'source_id': lot.id!,
          }).eq('id', jeId);

          await _client.from('lot_receipts').update({
            'journal_entry_id': jeId,
          }).eq('id', lot.id!);
        }
      }
    } catch (e) {
      debugPrint('Note: LotDao._ensureJournalEntryForLot (non-fatal): $e');
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
    try {
      final result = await _client.rpc('rpc_get_lot_journal_entries', params: {
        'p_lot_id': lotId,
      });
      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('LotDao.getJournalEntriesForLot error: $e');
      return [];
    }
  }
}
