import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier_model.dart';
import '../models/supplier_expected_cost_item_model.dart';
import '../models/stock_distribution_model.dart';
import '../services/currency_conversion_service.dart';
import '../../core/services/tenant_service.dart';
import '../../core/extensions/company_injection.dart';
import '../services/opening_balance_gl_sync_service.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/widgets/order_range_filter_field.dart';

class SupplierDao {
  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  SupplierDao([this._clientOverride]);

  // ── Code Generation ──

  Future<String> generateNextCode({String? supplierType}) async {
    try {
      final type = supplierType ?? 'crop';
      final int minRange;
      final int maxRange;
      final String tableName;

      if (type == 'shared') {
        minRange = 75000;
        maxRange = 80000; // 75000 to 79999 (Capacity: 5,000)
        tableName = 'suppliers';
      } else if (type == 'packaging' || type == 'sticker') {
        minRange = 70000;
        maxRange = 75000; // 70000 to 74999 (Capacity: 5,000)
        tableName = 'suppliers';
      } else if (type == 'transport') {
        minRange = 60000;
        maxRange = 70000; // 60000 to 69999 (Capacity: 10,000)
        tableName = 'transport_suppliers';
      } else if (type == 'deduction' || type == 'deductions') {
        minRange = 40000;
        maxRange = 50000; // 40000 to 49999 (Capacity: 10,000)
        tableName = 'suppliers';
      } else if (type == 'station') {
        minRange = 85000;
        maxRange = 90000; // 85000 to 89999 (Capacity: 5,000)
        tableName = 'suppliers';
      } else if (type == 'shipping') {
        minRange = 90000;
        maxRange = 100000; // 90000 to 99999 (Capacity: 10,000)
        tableName = 'shipping_companies';
      } else {
        // crop
        minRange = 50000;
        maxRange = 60000; // 50000 to 59999 (Capacity: 10,000)
        tableName = 'suppliers';
      }

      final response =
          await _client.from(tableName).select('code');
      int maxCode = minRange - 1;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num =
            int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num >= minRange && num < maxRange && num > maxCode) {
          maxCode = num;
        }
      }

      if (maxCode < minRange) {
        return minRange.toString();
      }
      return (maxCode + 1).toString();
    } catch (e) {
      final range = SupplierModel.getCategoryRange(supplierType ?? 'crop');
      return range.minCode.toString();
    }
  }

  /// Check if a supplier code already exists in the database to prevent collisions
  Future<bool> checkCodeExists(String code, {String? excludeId}) async {
    try {
      final clean = code.trim();
      var query = _client.from('suppliers').select('id').or('code.eq.$clean,supplier_code.eq.$clean');
      if (excludeId != null && excludeId.isNotEmpty) {
        query = query.neq('id', excludeId);
      }
      final res = await query.limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Row mapping ──

  SupplierModel _fromRow(Map<String, dynamic> row) {
    return SupplierModel.fromMap(row);
  }

  // ── CRUD ──

  Future<List<SupplierModel>> getAll({
    int limit = 2000,
    int offset = 0,
    List<String>? supplierTypes,
  }) async {
    var query = _client.from('suppliers').select();
    if (supplierTypes != null && supplierTypes.isNotEmpty) {
      query = query.inFilter('supplier_type', supplierTypes);
    }
    final rows = await query
        .order('name')
        .range(offset, offset + limit - 1);

    final results = await Future.wait([
      _calculateLiveBalances(),
      fetchPendingExpectedCosts(),
    ]);
    final liveBalances = results[0] as _LiveBalancesResult;
    final pendingCosts = results[1] as Map<String, double>;
    final packingCosts =
        !liveBalances.isSuccess ? await _fetchPackingCosts() : <String, double>{};

    return rows
        .map((row) => _enrichSupplierRow(row, liveBalances, packingCosts, pendingCosts))
        .toList();
  }

  static const Set<String> _packingCostLedgerRefTypes = {
    'packing_cost',
    'packing_cost_item',
    'packing_order_costs',
    'cost_settlement',
    'packing_cost_settlement',
  };

  /// Determines whether a `packing_order_cost_items` row represents an approved
  /// actual cost (excluding unsettled estimates or legacy Stage-3 false auto-locks).
  static bool isApprovedSettledCostItem(Map<String, dynamic> costItem) {
    if (costItem['deleted_at'] != null) return false;
    final actualAmt = (costItem['actual_amount'] as num?)?.toDouble();
    if (actualAmt == null || actualAmt <= 0) return false;

    final status = costItem['cost_status']?.toString().toLowerCase() ?? '';
    if (status == 'expected') return false;

    final hasReconcileMetadata = costItem.containsKey('reconciled_at') &&
        costItem.containsKey('variance_journal_entry_id') &&
        costItem.containsKey('cost_status');
    if (hasReconcileMetadata) {
      final hasEvidence = costItem['reconciled_at'] != null ||
          costItem['variance_journal_entry_id'] != null ||
          (costItem['invoice_ref']?.toString().trim().isNotEmpty ?? false) ||
          (costItem['settlement_notes']?.toString().trim().isNotEmpty ?? false) ||
          (costItem['detailed_notes']?.toString().trim().isNotEmpty ?? false);
      if (!hasEvidence) return false;
    }
    return true;
  }

  /// Applies sub-ledger entries and settled dual-cost items into `perCurrency`.
  /// For station & deduction suppliers (`dualCostSupplierKeys`), mixed estimated/variance
  /// rows (`packing_cost`, `cost_settlement`) in `ledgerTxs` are skipped so the balance
  /// reflects strictly approved `actual_amount` from `costItems` (never variance/estimates).
  static void applyLedgerEntriesToCurrencyBalances({
    required List<Map<String, dynamic>> ledgerTxs,
    required Map<String, Map<String, double>> perCurrency,
    required Set<String> treasuryTxIds,
    required Set<String> bankTxIds,
    Set<String> dualCostSupplierKeys = const {},
    Map<String, String> aliasToCanonicalId = const {},
    List<Map<String, dynamic>> costItems = const [],
    Set<int> cancelledOrderIds = const {},
  }) {
    for (final le in ledgerTxs) {
      final sid = le['entity_id']?.toString();
      if (sid == null || sid.isEmpty) continue;

      final refType = le['reference_type']?.toString().toLowerCase() ?? '';
      // Skip lot receipts and lot returns (already aggregated from primary lot tables)
      if (refType == 'lot_receipt' ||
          refType == 'lot_adjustment' ||
          refType == 'lot_price_adjustment' ||
          refType == 'lot_return') {
        continue;
      }

      final refId = le['reference_id']?.toString() ?? '';
      // Skip duplicate treasury and bank entries
      if (refId.isNotEmpty &&
          (treasuryTxIds.contains(refId) || bankTxIds.contains(refId))) {
        continue;
      }

      // Station & deduction suppliers get their packing obligations exclusively from
      // approved settled actual_amount on packing_order_cost_items below.
      if (dualCostSupplierKeys.contains(sid) &&
          _packingCostLedgerRefTypes.contains(refType)) {
        continue;
      }

      final cur = (le['currency']?.toString() ?? 'EGP').toUpperCase();
      final amt = (le['amount'] as num?)?.toDouble() ?? 0.0;
      final entryType = le['entry_type']?.toString().toLowerCase() ?? 'credit';
      final isCredit = entryType == 'credit' ||
          refType == 'supplier_deposit' ||
          refType == 'export_return_expense' ||
          refType == 'export_shipment_return_expense';
      final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
      map[cur] = (map[cur] ?? 0.0) + (isCredit ? amt : -amt);
    }

    // Add strictly approved actual costs for station & deduction suppliers
    final seenCostItemIds = <String>{};
    for (final ci in costItems) {
      if (!isApprovedSettledCostItem(ci)) continue;

      final poRaw = ci['packing_order_id'];
      final int? poId = poRaw is int
          ? poRaw
          : (poRaw is num ? poRaw.toInt() : int.tryParse('${poRaw ?? ''}'));
      if (poId != null && cancelledOrderIds.contains(poId)) continue;

      String? rawSid = ci['supplier_id']?.toString();
      if (rawSid == null || rawSid.isEmpty || rawSid == 'null') {
        final snap = ci['currency_snapshot'];
        if (snap is Map) {
          rawSid = snap['supplier_id']?.toString() ??
              snap['supplier_code']?.toString();
        }
      }
      if (rawSid == null || rawSid.isEmpty || rawSid == 'null') continue;
      if (!dualCostSupplierKeys.contains(rawSid)) continue;

      final cid = ci['id']?.toString();
      if (cid != null && cid.isNotEmpty && !seenCostItemIds.add(cid)) continue;

      final targetSid = aliasToCanonicalId[rawSid] ?? rawSid;
      final origCur = ci['original_currency']?.toString().trim() ?? '';
      final cur = origCur.isNotEmpty ? origCur.toUpperCase() : 'EGP';
      final actualAmt = (ci['actual_amount'] as num?)?.toDouble() ?? 0.0;
      if (actualAmt <= 0) continue;

      final map = perCurrency.putIfAbsent(targetSid, () => <String, double>{});
      map[cur] = (map[cur] ?? 0.0) + actualAmt;
    }
  }

  /// Calculates live net balances per currency and total in EGP for all suppliers
  /// strictly matching the accounting logic of the Supplier Account Statement.
  Future<_LiveBalancesResult> _calculateLiveBalances() async {
    final perCurrency = <String, Map<String, double>>{};
    final rates = <String, double>{'EGP': 1.0, 'USD': 50.0, 'EUR': 55.0, 'GBP': 65.0};

    try {
      final results = await Future.wait([
        _client.from('purchase_invoices').select('supplier_id, currency, total_amount').eq('status', 'confirmed'),
        _client.from('lot_receipts').select('supplier_id, currency, total_fruit_cost').eq('is_confirmed', true),
        _client.from('treasury_transactions').select('id, supplier_id, currency, amount, type').not('supplier_id', 'is', null).neq('status', 'draft'),
        _client.from('bank_account_transactions').select('id, entity_id, amount, type, bank_accounts(currency)').eq('entity_type', 'supplier').neq('status', 'cancelled'),
        _client.from('cheques').select('supplier_id, currency, amount, type').eq('counterparty_type', 'supplier').inFilter('status', ['cleared', 'collected']),
        _client.from('lot_returns').select('supplier_id, return_value, lot_receipts(currency)'),
        _client.from('exchange_rates').select('currency_code, rate_to_egp'),
        _client.from('ledger_entries').select('id, entity_id, amount, currency, entry_type, reference_type, reference_id, reference_text, description, currency_snapshot').eq('entity_type', 'supplier'),
        _client.from('suppliers').select('id, code, supplier_code, supplier_type'),
        _client.from('packing_order_cost_items').select('id, packing_order_id, supplier_id, cost_status, actual_amount, reconciled_at, variance_journal_entry_id, invoice_ref, settlement_notes, detailed_notes, original_currency, currency_snapshot, deleted_at').isFilter('deleted_at', null),
        _client.from('packing_orders').select('id').eq('status', 'cancelled'),
      ]);

      final purchases = results[0] as List;
      final lots = results[1] as List;
      final treasuryTxs = results[2] as List;
      final bankTxs = results[3] as List;
      final cheques = results[4] as List;
      final lotReturns = results[5] as List;
      final ratesData = results[6] as List;
      final ledgerTxs = List<Map<String, dynamic>>.from(
        (results[7] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final suppliersMeta = results[8] as List;
      final costItems = List<Map<String, dynamic>>.from(
        (results[9] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final cancelledOrders = results[10] as List;

      final cancelledOrderIds = cancelledOrders
          .map((o) => (o['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();

      final dualCostSupplierKeys = <String>{};
      final aliasToCanonicalId = <String, String>{};
      for (final s in suppliersMeta) {
        final sid = s['id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final sType = s['supplier_type']?.toString();
        final sCode = s['supplier_code']?.toString() ?? s['code']?.toString() ?? '';
        final altCode = s['code']?.toString() ?? '';

        aliasToCanonicalId[sid] = sid;
        if (sCode.isNotEmpty) aliasToCanonicalId[sCode] = sid;
        if (altCode.isNotEmpty) aliasToCanonicalId[altCode] = sid;

        if (SupplierModel.isEgpOnlyCategoryOrCode(sType, sCode) ||
            SupplierModel.isEgpOnlyCategoryOrCode(sType, altCode)) {
          dualCostSupplierKeys.add(sid);
          if (sCode.isNotEmpty) dualCostSupplierKeys.add(sCode);
          if (altCode.isNotEmpty) dualCostSupplierKeys.add(altCode);
        }
      }

      for (final r in ratesData) {
        final cur = r['currency_code']?.toString().toUpperCase() ?? '';
        final rate = (r['rate_to_egp'] as num?)?.toDouble() ?? 1.0;
        if (cur.isNotEmpty && rate > 0) rates[cur] = rate;
      }

      // 1. Purchases (+credit increases supplier liability)
      for (final p in purchases) {
        final sid = p['supplier_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final cur = (p['currency']?.toString() ?? 'EGP').toUpperCase();
        final amt = (p['total_amount'] as num?)?.toDouble() ?? 0.0;
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) + amt;
      }

      // 2. Lots (+credit increases supplier liability)
      for (final l in lots) {
        final sid = l['supplier_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final cur = (l['currency']?.toString() ?? 'USD').toUpperCase();
        final amt = (l['total_fruit_cost'] as num?)?.toDouble() ?? 0.0;
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) + amt;
      }

      // 3. Treasury transactions (+credit for cash receipts/deposits from supplier, -debit for payments to supplier)
      for (final t in treasuryTxs) {
        final sid = t['supplier_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final cur = (t['currency']?.toString() ?? 'EGP').toUpperCase();
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        final type = t['type']?.toString().toLowerCase() ?? '';
        final isCredit = type == 'deposit' || type == 'receive' || type == 'income' || type == 'supplier_refund';
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) + (isCredit ? amt : -amt);
      }

      // 4. Bank transactions (-debit for payments to supplier, +credit for receipts)
      for (final b in bankTxs) {
        final sid = b['entity_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final ba = b['bank_accounts'] as Map?;
        final cur = (ba?['currency']?.toString() ?? 'EGP').toUpperCase();
        final amt = (b['amount'] as num?)?.toDouble() ?? 0.0;
        final type = b['type']?.toString().toLowerCase() ?? '';
        final isCredit = type == 'deposit' || type == 'income' || type == 'receive' || type == 'supplier_refund';
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) + (isCredit ? amt : -amt);
      }

      // 5. Cheques (-debit for outgoing cheques, +credit for incoming cheques)
      for (final ch in cheques) {
        final sid = ch['supplier_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final cur = (ch['currency']?.toString() ?? 'EGP').toUpperCase();
        final amt = (ch['amount'] as num?)?.toDouble() ?? 0.0;
        final isCredit = ch['type']?.toString().toLowerCase() == 'incoming';
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) + (isCredit ? amt : -amt);
      }

      // 6. Lot returns (-debit reduces supplier liability)
      for (final lr in lotReturns) {
        final sid = lr['supplier_id']?.toString();
        if (sid == null || sid.isEmpty) continue;
        final rec = lr['lot_receipts'] as Map?;
        final cur = (rec?['currency']?.toString() ?? 'USD').toUpperCase();
        final amt = (lr['return_value'] as num?)?.toDouble() ?? 0.0;
        final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
        map[cur] = (map[cur] ?? 0.0) - amt;
      }

      // 7. General & sub-ledger entries + Approved Station/Deduction Actual Costs
      // Exactly deduplicate against treasury/bank/lots to match SupplierAccountStatementCubit 100%
      final treasuryTxIds = treasuryTxs.map((t) => t['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      final bankTxIds = bankTxs.map((b) => b['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();

      applyLedgerEntriesToCurrencyBalances(
        ledgerTxs: ledgerTxs,
        perCurrency: perCurrency,
        treasuryTxIds: treasuryTxIds,
        bankTxIds: bankTxIds,
        dualCostSupplierKeys: dualCostSupplierKeys,
        aliasToCanonicalId: aliasToCanonicalId,
        costItems: costItems,
        cancelledOrderIds: cancelledOrderIds,
      );

      return _LiveBalancesResult(
        movementsByCurrency: perCurrency,
        rates: rates,
        isSuccess: true,
      );
    } catch (e) {
      debugPrint('SupplierDao._calculateLiveBalances error: $e');
      return _LiveBalancesResult(
        movementsByCurrency: {},
        rates: rates,
        isSuccess: false,
      );
    }
  }

  SupplierModel _enrichSupplierRow(
    Map<String, dynamic> row,
    _LiveBalancesResult liveBalances,
    Map<String, double> packingCosts, [
    Map<String, double>? pendingExpectedCosts,
  ]) {
    final id = row['id']?.toString() ?? '';
    final code = row['supplier_code']?.toString() ?? row['code']?.toString() ?? '';
    final isMulti = row['is_multi_currency'] == true || row['currency'] == 'MULTI';
    final curMap = <String, double>{};

    // 1. Initial balances per configured currency
    if (isMulti && row['initial_balances_by_currency'] is Map) {
      final initMap = row['initial_balances_by_currency'] as Map;
      initMap.forEach((k, v) {
        final curKey = k.toString().toUpperCase();
        double amt = 0.0;
        if (v is Map) {
          final a = (v['amount'] as num?)?.toDouble() ?? 0.0;
          final dir = v['direction']?.toString().toUpperCase() ?? 'CREDIT';
          amt = dir == 'DEBIT' ? -a : a;
        } else if (v is num) {
          amt = v.toDouble();
        }
        curMap[curKey] = amt;
      });
    } else if (row['initial_balance'] != null) {
      final cur = (row['currency']?.toString() ?? 'EGP').toUpperCase();
      final a = (row['initial_balance'] as num).toDouble();
      final dir = row['initial_balance_direction']?.toString().toUpperCase() ?? 'CREDIT';
      final amt = dir == 'DEBIT' ? -a : a;
      curMap[cur] = amt;
    }

    if (liveBalances.isSuccess) {
      // 2. Add movements from live calculation (matching statement 100%)
      // Seamlessly combine movements tracked under UUID and/or supplier code
      void applyMovements(Map<String, double>? movements) {
        if (movements == null) return;
        for (final entry in movements.entries) {
          final cur = entry.key.toUpperCase();
          curMap[cur] = (curMap[cur] ?? 0.0) + entry.value;
        }
      }

      applyMovements(liveBalances.movementsByCurrency[id]);
      if (code.isNotEmpty && code != id) {
        applyMovements(liveBalances.movementsByCurrency[code]);
      }

      // 3. Compute total in EGP using current conversion rates
      double totalEgp = 0.0;
      curMap.forEach((c, b) {
        final rate = liveBalances.rates[c] ?? 1.0;
        totalEgp += b * rate;
      });

      row['current_balances_by_currency'] = curMap;
      row['outstanding_balance'] = totalEgp;
      row['computed_balance'] = totalEgp;

      _syncSupplierRowInDb(id, curMap, totalEgp, row);
    } else {
      // Fallback if live balance query failed: use stored row values
      final rawCur = row['current_balances_by_currency'];
      if (rawCur is Map) {
        rawCur.forEach((k, v) {
          final amt = (v as num?)?.toDouble();
          if (amt != null) curMap[k.toString().toUpperCase()] = amt;
        });
      }
      row['current_balances_by_currency'] = curMap;
      final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
      final outstandingBal =
          (row['outstanding_balance'] as num?)?.toDouble() ?? initialBal;
      final packingCost = packingCosts[id] ?? 0.0;
      row['computed_balance'] = outstandingBal + packingCost;
    }

    final pending = (pendingExpectedCosts != null)
        ? ((pendingExpectedCosts[id] ?? 0.0) +
            (code.isNotEmpty && code != id ? (pendingExpectedCosts[code] ?? 0.0) : 0.0))
        : ((row['pending_expected_balance'] as num?)?.toDouble() ?? 0.0);
    row['pending_expected_balance'] = pending;

    return _fromRow(row);
  }

  void _syncSupplierRowInDb(
    String id,
    Map<String, double> curMap,
    double totalEgp,
    Map<String, dynamic> originalRow,
  ) {
    if (id.isEmpty) return;
    final storedOutstanding = (originalRow['outstanding_balance'] as num?)?.toDouble();
    final storedMap = originalRow['current_balances_by_currency'];

    bool needsUpdate = false;
    if (storedOutstanding == null || (storedOutstanding - totalEgp).abs() > 0.01) {
      needsUpdate = true;
    } else if (storedMap is! Map) {
      needsUpdate = true;
    } else {
      for (final entry in curMap.entries) {
        final storedVal = (storedMap[entry.key] as num?)?.toDouble() ??
            (storedMap[entry.key.toLowerCase()] as num?)?.toDouble();
        if (storedVal == null || (storedVal - entry.value).abs() > 0.01) {
          needsUpdate = true;
          break;
        }
      }
    }

    if (needsUpdate) {
      _client.from('suppliers').update({
        'current_balances_by_currency': curMap,
        'outstanding_balance': totalEgp,
      }).eq('id', id).then((_) {}, onError: (e) {
        debugPrint('SupplierDao._syncSupplierRowInDb error: $e');
      });
    }
  }

  // ── CRUD ──

  Future<List<StockDistributionEntry>> getStockDistribution(
      String productId) async {
    try {
      // 1. Fetch from purchase_invoice_items (standard purchases)
      final invoiceRows =
          await _client.from('purchase_invoice_items').select('''
            quantity,
            remaining_quantity,
            unit_cost,
            purchase_invoices!inner (
              suppliers!inner (
                supplier_code,
                name
              )
            )
          ''').eq('raw_material_id', productId.toString());

      // 2. Fetch from stock_batches (crop purchases)
      final batchRows = await _client
          .from('stock_batches')
          .select('''
            quantity,
            remaining_quantity,
            purchase_cost,
            suppliers!inner (
              supplier_code,
              name
            )
          ''')
          .eq('product_id', productId.toString())
          .like('batch_number', 'G-%');

      final Map<String, _AggSupplier> grouped = {};

      // Process invoice items
      for (final row in invoiceRows) {
        final inv = row['purchase_invoices'] as Map<String, dynamic>?;
        final supp = inv?['suppliers'] as Map<String, dynamic>?;
        final code = supp?['supplier_code']?.toString() ?? '';
        final name = supp?['name']?.toString() ?? code;
        final qty = (row['remaining_quantity'] as num?)?.toDouble() ??
            (row['quantity'] as num?)?.toDouble() ??
            0.0;
        final cost = (row['unit_cost'] as num?)?.toDouble() ?? 0.0;

        grouped.putIfAbsent(code, () => _AggSupplier(name: name));
        grouped[code]!.add(qty, cost);
      }

      // Process crop purchase batches (starting with G-)
      for (final row in batchRows) {
        final supp = row['suppliers'] as Map<String, dynamic>?;
        final code = supp?['supplier_code']?.toString() ?? '';
        final name = supp?['name']?.toString() ?? code;
        final qty = (row['remaining_quantity'] as num?)?.toDouble() ??
            (row['quantity'] as num?)?.toDouble() ??
            0.0;
        final originalQty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
        final totalCost = (row['purchase_cost'] as num?)?.toDouble() ?? 0.0;
        final unitCost = originalQty > 0 ? totalCost / originalQty : 0.0;

        grouped.putIfAbsent(code, () => _AggSupplier(name: name));
        grouped[code]!.add(qty, unitCost);
      }

      return grouped.entries.map((e) {
        final agg = e.value;
        return StockDistributionEntry(
          supplierCode: e.key,
          supplierName: agg.name,
          totalQuantity: agg.totalQty,
          totalCost: agg.totalCost,
          unitCost: agg.totalQty > 0 ? agg.totalCost / agg.totalQty : 0.0,
        );
      }).toList();
    } catch (e) {
      debugPrint('SupplierDao.getStockDistribution error: $e');
      return [];
    }
  }

  Future<List<SupplierModel>> search(
    String query, {
    int limit = 50,
    int offset = 0,
    List<String>? supplierTypes,
    bool includeTransportSuppliers = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // Semantic mapping for Arabic classification keywords to supplier_type
    final mappedTypes = <String>[];
    final lower = trimmed.toLowerCase();
    if (lower.contains('مشترك') || lower.contains('مشتركين')) {
      mappedTypes.add('shared');
    }
    if (lower.contains('محصول') || lower.contains('محاصيل')) {
      mappedTypes.add('crop');
    }
    if (lower.contains('تعبئ') || lower.contains('تعبئة') || lower.contains('تعبئه') || lower.contains('تغليف')) {
      mappedTypes.add('packaging');
    }
    if (lower.contains('نقل') || lower.contains('شحن')) {
      mappedTypes.add('transport');
    }

    // Build or clause for suppliers table
    var orClause = 'name.ilike.%$trimmed%,code.ilike.%$trimmed%,supplier_code.ilike.%$trimmed%,phone.ilike.%$trimmed%,supplier_type.ilike.%$trimmed%';
    for (final mt in mappedTypes) {
      orClause += ',supplier_type.eq.$mt';
    }

    // Also support search by "مورد" if user typed plural "موردين"
    if (trimmed == 'موردين' || trimmed == 'الموردين') {
      orClause += ',name.ilike.%مورد%';
    }

    var q = _client.from('suppliers').select().or(orClause);
    if (supplierTypes != null && supplierTypes.isNotEmpty) {
      q = q.inFilter('supplier_type', supplierTypes);
    }
    final rows = await q
        .order('name')
        .range(offset, offset + limit - 1);

    final results = await Future.wait([
      _calculateLiveBalances(),
      fetchPendingExpectedCosts(),
    ]);
    final liveBalances = results[0] as _LiveBalancesResult;
    final pendingCosts = results[1] as Map<String, double>;
    final packingCosts =
        !liveBalances.isSuccess ? await _fetchPackingCosts() : <String, double>{};

    return rows
        .map((row) => _enrichSupplierRow(row, liveBalances, packingCosts, pendingCosts))
        .toList();
  }

  Future<SupplierModel?> getByCode(String code) async {
    final row =
        await _client.from('suppliers').select().eq('code', code).maybeSingle();
    if (row == null) return null;

    final results = await Future.wait([
      _calculateLiveBalances(),
      fetchPendingExpectedCosts(),
    ]);
    final liveBalances = results[0] as _LiveBalancesResult;
    final pendingCosts = results[1] as Map<String, double>;
    final packingCosts =
        !liveBalances.isSuccess ? await _fetchPackingCosts() : <String, double>{};
    return _enrichSupplierRow(row, liveBalances, packingCosts, pendingCosts);
  }

  Future<SupplierModel?> getById(String id) async {
    final row =
        await _client.from('suppliers').select().eq('id', id).maybeSingle();
    if (row == null) return null;

    final results = await Future.wait([
      _calculateLiveBalances(),
      fetchPendingExpectedCosts(),
    ]);
    final liveBalances = results[0] as _LiveBalancesResult;
    final pendingCosts = results[1] as Map<String, double>;
    final packingCosts =
        !liveBalances.isSuccess ? await _fetchPackingCosts() : <String, double>{};
    return _enrichSupplierRow(row, liveBalances, packingCosts, pendingCosts);
  }

  /// Retrieves live native balances for each currency (EGP, USD, EUR, GBP) for a specific supplier.
  /// Queries the authoritative PostgreSQL function `get_supplier_true_balances_by_currency()`.
  /// Falls back to `getById()` enriched live ledger movements if RPC is unavailable.
  Future<Map<String, double>> getSupplierBalancesByCurrency(String supplierId) async {
    final map = <String, double>{};
    try {
      final rpcRes = await _client.rpc('get_supplier_true_balances_by_currency');
      if (rpcRes is List) {
        for (final r in rpcRes) {
          final sId = r['supplier_id']?.toString() ?? '';
          if (sId.toLowerCase() == supplierId.toLowerCase()) {
            final cur = r['currency']?.toString().toUpperCase() ?? '';
            final bal = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
            if (cur.isNotEmpty) {
              map[cur] = bal;
            }
          }
        }
      }
      if (map.isNotEmpty) return map;
    } catch (e) {
      debugPrint('SupplierDao.getSupplierBalancesByCurrency RPC error: $e');
    }

    try {
      final s = await getById(supplierId);
      if (s != null && s.currentBalancesByCurrency.isNotEmpty) {
        return Map<String, double>.from(s.currentBalancesByCurrency);
      } else if (s != null) {
        final c = (s.currency.isNotEmpty && s.currency != 'MULTI') ? s.currency : 'EGP';
        return {c: s.outstandingBalance};
      }
    } catch (e) {
      debugPrint('SupplierDao.getSupplierBalancesByCurrency fallback error: $e');
    }
    return map;
  }


  /// Resolves the master Level-5 summary account ID directly:
  /// - Crop purchases ('crop' / default) -> 21113 ("موردي مشتريات محاصيل")
  /// - Packaging materials ('packaging') -> 21112 ("موردي مواد التعبئة")
  /// - Transport ('transport') -> 21111 ("موردي النقل والسيارات")
  /// - Shipping ('shipping') -> 21115 ("شركات الشحن")
  /// - Clearing agents ('clearing' / 'customs') -> 21116 ("مخلصي الجمارك")
  /// - Station suppliers ('station') -> 21117 ("موردي المحطات")
  /// - Deductions suppliers ('deduction' / 'deductions') -> 21118 ("موردي التخصيمات")
  /// Resolves the master Level-5 summary account Code directly (21111..21118)
  static String resolveMasterAccountCode(
    String supplierType, {
    String? code,
    String? category,
  }) {
    final cleanType = supplierType.trim().toLowerCase();
    final cleanCat = (category ?? '').trim().toLowerCase();
    final cleanCode = (code ?? '').trim();

    if (cleanType == 'station' || cleanCat.contains('محطة') || cleanCat.contains('محطات') || cleanCode.startsWith('85') || cleanCode.startsWith('86') || cleanCode.startsWith('87') || cleanCode.startsWith('88') || cleanCode.startsWith('89')) {
      return '21117';
    } else if (cleanType == 'deduction' || cleanType == 'deductions' || cleanCat.contains('تخصيم') || cleanCat.contains('تخصيمات') || cleanCode.startsWith('4')) {
      return '21118';
    } else if (cleanType == 'transport' || cleanType.contains('نقل') || cleanCode.startsWith('6')) {
      return '21111';
    } else if (cleanType == 'packaging' ||
        cleanType == 'sticker' ||
        cleanType.contains('تعبئة') ||
        cleanCat.contains('تعبئة') ||
        cleanCode.startsWith('70') ||
        cleanCode.startsWith('71') ||
        cleanCode.startsWith('72') ||
        cleanCode.startsWith('73') ||
        cleanCode.startsWith('74')) {
      return '21112';
    } else if (cleanType == 'shared' ||
        cleanType.contains('مشترك') ||
        cleanCat.contains('مشترك') ||
        cleanCode.startsWith('75') ||
        cleanCode.startsWith('76') ||
        cleanCode.startsWith('77') ||
        cleanCode.startsWith('78') ||
        cleanCode.startsWith('79')) {
      return '21114';
    } else if (cleanType == 'shipping' || cleanType.contains('شحن') || cleanCode.startsWith('9')) {
      return '21115';
    } else if (cleanType == 'clearing' ||
        cleanType == 'customs' ||
        cleanType.contains('تخليص') ||
        cleanType.contains('مخلص')) {
      return '21116';
    } else {
      return '21113';
    }
  }

  /// Instance forwarder for resolveMasterAccountCode
  String resolveAccountCode(
    String supplierType, {
    String? code,
    String? category,
  }) => resolveMasterAccountCode(supplierType, code: code, category: category);

  Future<int?> resolveMasterAccountId(
    String supplierType, {
    String? code,
    String? category,
  }) async {
    final targetCode = resolveMasterAccountCode(supplierType, code: code, category: category);

    final tenantId = TenantService().tenantId;
    try {
      var query = _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetCode);

      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.or('company_id.eq.$tenantId,company_id.is.null,company_id.eq.a0000000-0000-0000-0000-000000000001');
      }

      final res = await query.limit(1).maybeSingle();
      if (res != null && res['id'] != null) {
        return (res['id'] as num).toInt();
      }
      final fallback = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetCode)
          .limit(1)
          .maybeSingle();
      return (fallback?['id'] as num?)?.toInt();
    } catch (e) {
      return null;
    }
  }

  Future<void> insert(SupplierModel supplier) async {
    final data = supplier.toInsertMap();
    data.remove('pending_expected_balance');

    // Direct Master Account Binding (similar to CustomerDao)
    if (data['account_id'] == null) {
      final masterId = await resolveMasterAccountId(
        supplier.supplierType,
        code: supplier.supplierCode,
        category: supplier.category,
      );
      if (masterId != null) {
        data['account_id'] = masterId;
      }
    }

    if (supplier.isMultiCurrency) {
      data['initial_balance_snapshot'] = {
        'currency': supplier.primaryCurrency,
        'amount': supplier.totalInitialBalanceInEgp.abs(),
        'direction': supplier.totalInitialBalanceInEgp >= 0 ? 'CREDIT' : 'DEBIT',
        'rate_to_base': 1.0,
        'base_currency': 'EGP',
        'rate_source': 'multi_currency_setup',
        'rate_date': DateTime.now().toIso8601String(),
        'multi_currency': true,
        'currency_balances': supplier.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.toMap())),
      };
    } else {
      data['initial_balance_snapshot'] =
          (await CurrencyConversionService.instance.createSnapshotFromDb(
        currency: supplier.currency,
        amount: supplier.initialBalance,
      ))
              .toJson();
    }

    dynamic insertedId = supplier.id;
    if (supplier.supplierType == 'transport') {
      final masterId = data['account_id'] ?? await resolveMasterAccountId('transport');
      final res = await _client.from('transport_suppliers').insert({
        'code': supplier.supplierCode,
        'name': supplier.name,
        'phone': supplier.phone,
        'initial_balance': supplier.initialBalance,
        'initial_balance_direction': supplier.initialBalanceDirection,
        'company_id': TenantService().tenantId,
        if (masterId != null) 'account_id': masterId,
      }).select('id').maybeSingle();
      if (res != null) insertedId = res['id'];
    } else if (supplier.supplierType == 'shipping') {
      final masterId = data['account_id'] ?? await resolveMasterAccountId('shipping');
      final res = await _client.from('shipping_companies').insert({
        'code': supplier.supplierCode,
        'name': supplier.name,
        'phone': supplier.phone,
        'company_id': TenantService().tenantId,
        if (masterId != null) 'account_id': masterId,
      }).select('id').maybeSingle();
      if (res != null) insertedId = res['id'];
    } else {
      try {
        final res = await _client.from('suppliers').insert(data.withCompanyId()).select('id').maybeSingle();
        if (res != null) insertedId = res['id'];
      } on PostgrestException catch (e) {
        if (e.code == '23505' || e.message.contains('unique') || e.message.contains('duplicate')) {
          throw Exception('كود المورد (${supplier.supplierCode}) مسجل مسبقاً في النظام.');
        }
        if (e.toString().contains('categories')) {
          data.remove('categories');
          final res = await _client.from('suppliers').insert(data.withCompanyId()).select('id').maybeSingle();
          if (res != null) insertedId = res['id'];
        } else {
          rethrow;
        }
      } catch (e) {
        if (e.toString().contains('23505')) {
          throw Exception('كود المورد (${supplier.supplierCode}) مسجل مسبقاً في النظام.');
        }
        if (e.toString().contains('categories')) {
          data.remove('categories');
          final res = await _client.from('suppliers').insert(data.withCompanyId()).select('id').maybeSingle();
          if (res != null) insertedId = res['id'];
        } else {
          rethrow;
        }
      }
    }

    // Direct Dual-Posting into General Ledger (mirroring opening balance to COA)
    try {
      if (insertedId != null) {
        await OpeningBalanceGlSyncService.instance.syncSupplierOpeningBalance(
          supplierId: insertedId,
          supplierName: supplier.name,
          supplierCode: supplier.supplierCode,
          supplierType: supplier.supplierType,
          category: supplier.category,
          accountId: data['account_id'] as int?,
          isMultiCurrency: supplier.isMultiCurrency,
          initialBalance: supplier.initialBalance,
          currency: supplier.currency,
          direction: supplier.initialBalanceDirection,
          initialBalancesByCurrency: supplier.isMultiCurrency
              ? supplier.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.toMap()))
              : null,
          companyId: TenantService().tenantId,
        );
      }
    } catch (e) {
      debugPrint('SupplierDao.insert GL sync warning: $e');
    }
  }

  Future<void> update(SupplierModel supplier) async {
    final data = supplier.toInsertMap();
    data.remove('pending_expected_balance');

    // Fallback: Ensure account_id is resolved if missing
    if (data['account_id'] == null) {
      final masterId = await resolveMasterAccountId(
        supplier.supplierType,
        code: supplier.supplierCode,
        category: supplier.category,
      );
      if (masterId != null) {
        data['account_id'] = masterId;
      }
    }

    if (supplier.isMultiCurrency) {
      data['initial_balance_snapshot'] = {
        'currency': supplier.primaryCurrency,
        'amount': supplier.totalInitialBalanceInEgp.abs(),
        'direction': supplier.totalInitialBalanceInEgp >= 0 ? 'CREDIT' : 'DEBIT',
        'rate_to_base': 1.0,
        'base_currency': 'EGP',
        'rate_source': 'multi_currency_setup',
        'rate_date': DateTime.now().toIso8601String(),
        'multi_currency': true,
        'currency_balances': supplier.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.toMap())),
      };
    } else {
      data['initial_balance_snapshot'] =
          (await CurrencyConversionService.instance.createSnapshotFromDb(
        currency: supplier.currency,
        amount: supplier.outstandingBalance,
      ))
              .toJson();
    }
    try {
      await _client
          .from('suppliers')
          .update(data)
          .eq('id', supplier.id!)
          .eq('company_id', TenantService().tenantId!);
    } catch (e) {
      if (e.toString().contains('categories')) {
        data.remove('categories');
        await _client
            .from('suppliers')
            .update(data)
            .eq('id', supplier.id!)
            .eq('company_id', TenantService().tenantId!);
      } else {
        rethrow;
      }
    }

    // Mirror updated opening balances to General Ledger
    try {
      await OpeningBalanceGlSyncService.instance.syncSupplierOpeningBalance(
        supplierId: supplier.id!,
        supplierName: supplier.name,
        supplierCode: supplier.supplierCode,
        supplierType: supplier.supplierType,
        category: supplier.category,
        accountId: data['account_id'] as int?,
        isMultiCurrency: supplier.isMultiCurrency,
        initialBalance: supplier.initialBalance,
        currency: supplier.currency,
        direction: supplier.initialBalanceDirection,
        initialBalancesByCurrency: supplier.isMultiCurrency
            ? supplier.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.toMap()))
            : null,
        companyId: TenantService().tenantId,
      );
    } catch (e) {
      debugPrint('SupplierDao.update GL sync warning: $e');
    }
  }

  Future<void> delete(String supplierCode) async {
    try {
      final existing = await _client.from('suppliers').select('id').eq('code', supplierCode).maybeSingle();
      if (existing != null && existing['id'] != null) {
        await OpeningBalanceGlSyncService.instance.deleteEntityOpeningBalance(
          'suppliers_${existing['id']}',
          TenantService().tenantId,
        );
      }
    } catch (_) {}

    await _client
        .from('suppliers')
        .delete()
        .eq('code', supplierCode); // ✅ FIX: was 'supplier_code'
  }

  Future<int> getCount() async {
    final response =
        await _client.from('suppliers').select().count(CountOption.exact);
    return response.count;
  }

  /// Fallback packing costs aggregation when `_calculateLiveBalances()` fails.
  /// For station & deduction suppliers, sums strictly approved `actual_amount` from
  /// settled `packing_order_cost_items` (never unsettled estimates or variance).
  Future<Map<String, double>> _fetchPackingCosts() async {
    try {
      Set<int> cancelledOrderIds = {};
      try {
        final cancelledOrders = await _client
            .from('packing_orders')
            .select('id')
            .eq('status', 'cancelled');
        cancelledOrderIds = (cancelledOrders as List)
            .map((e) => (e['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
      } catch (_) {}

      final results = await Future.wait([
        _client.from('suppliers').select('id, code, supplier_code, supplier_type'),
        _client
            .from('packing_order_cost_items')
            .select('id, packing_order_id, supplier_id, cost_status, actual_amount, reconciled_at, variance_journal_entry_id, invoice_ref, settlement_notes, detailed_notes, currency_snapshot, deleted_at')
            .eq('cost_status', 'actual')
            .not('actual_amount', 'is', null)
            .isFilter('deleted_at', null)
            .limit(5000),
        _client
            .from('ledger_entries')
            .select('entity_id, amount, entry_type, reference_type')
            .eq('entity_type', 'supplier')
            .inFilter('reference_type', ['packing_cost', 'packing_cost_item'])
            .limit(5000),
      ]);

      final suppliersMeta = results[0] as List;
      final settledItems = results[1] as List;
      final ledgerRows = results[2] as List;

      final dualCostSupplierKeys = <String>{};
      final aliasToCanonicalId = <String, String>{};
      for (final s in suppliersMeta) {
        final sid = s['id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        final sType = s['supplier_type']?.toString();
        final sCode = s['supplier_code']?.toString() ?? s['code']?.toString() ?? '';
        final altCode = s['code']?.toString() ?? '';
        aliasToCanonicalId[sid] = sid;
        if (sCode.isNotEmpty) aliasToCanonicalId[sCode] = sid;
        if (altCode.isNotEmpty) aliasToCanonicalId[altCode] = sid;

        if (SupplierModel.isEgpOnlyCategoryOrCode(sType, sCode) ||
            SupplierModel.isEgpOnlyCategoryOrCode(sType, altCode)) {
          dualCostSupplierKeys.add(sid);
          if (sCode.isNotEmpty) dualCostSupplierKeys.add(sCode);
          if (altCode.isNotEmpty) dualCostSupplierKeys.add(altCode);
        }
      }

      final map = <String, double>{};
      final seenCostItemIds = <String>{};

      for (final raw in settledItems) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (!isApprovedSettledCostItem(row)) continue;

        final poRaw = row['packing_order_id'];
        final int? poId = poRaw is int
            ? poRaw
            : (poRaw is num ? poRaw.toInt() : int.tryParse('${poRaw ?? ''}'));
        if (poId != null && cancelledOrderIds.contains(poId)) continue;

        String? rawSid = row['supplier_id']?.toString();
        if (rawSid == null || rawSid.isEmpty || rawSid == 'null') {
          final snap = row['currency_snapshot'];
          if (snap is Map) {
            rawSid = snap['supplier_id']?.toString() ?? snap['supplier_code']?.toString();
          }
        }
        if (rawSid == null || rawSid.isEmpty || rawSid == 'null') continue;
        if (!dualCostSupplierKeys.contains(rawSid)) continue;

        final cid = row['id']?.toString();
        if (cid != null && cid.isNotEmpty && !seenCostItemIds.add(cid)) continue;

        final targetSid = aliasToCanonicalId[rawSid] ?? rawSid;
        final amt = (row['actual_amount'] as num?)?.toDouble() ?? 0.0;
        if (amt > 0) {
          map[targetSid] = (map[targetSid] ?? 0.0) + amt;
        }
      }

      for (final raw in ledgerRows) {
        final sid = raw['entity_id']?.toString() ?? '';
        if (sid.isEmpty || dualCostSupplierKeys.contains(sid)) continue;
        final amt = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        final isCredit = (raw['entry_type']?.toString().toLowerCase() ?? 'credit') == 'credit';
        if (amt > 0) {
          final targetSid = aliasToCanonicalId[sid] ?? sid;
          map[targetSid] = (map[targetSid] ?? 0.0) + (isCredit ? amt : -amt);
        }
      }
      return map;
    } catch (e) {
      debugPrint('SupplierDao._fetchPackingCosts error: $e');
      return {};
    }
  }

  /// Fetch pending expected costs from packing_order_cost_items awaiting actual settlement.
  /// Sums pending amounts grouped by supplier_id (and supplier code).
  Future<Map<String, double>> fetchPendingExpectedCosts() async {
    try {
      Set<int> cancelledOrderIds = {};
      try {
        final cancelledOrders = await _client
            .from('packing_orders')
            .select('id')
            .eq('status', 'cancelled');
        cancelledOrderIds = (cancelledOrders as List)
            .map((e) => (e['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
      } catch (_) {}

      final rows = await _client
          .from('packing_order_cost_items')
          .select('packing_order_id, supplier_id, expected_amount, base_amount, original_amount, currency_snapshot, cost_status, actual_amount')
          .or('cost_status.is.null,cost_status.neq.actual,actual_amount.is.null')
          .limit(5000);

      final map = <String, double>{};
      final seenPackingOrderIds = <int>{};

      for (final row in rows) {
        final costStatus = row['cost_status']?.toString();
        final actualAmt = row['actual_amount'];
        // Ignore settled items if any were caught by filter
        if (costStatus == 'actual' && actualAmt != null) continue;

        final pOrderId = row['packing_order_id'];
        final int? intPOrderId = (pOrderId is int)
            ? pOrderId
            : (pOrderId is num ? pOrderId.toInt() : int.tryParse('$pOrderId'));
        if (intPOrderId != null) {
          if (cancelledOrderIds.contains(intPOrderId)) continue;
          seenPackingOrderIds.add(intPOrderId);
        }

        String? sid = row['supplier_id']?.toString();
        if (sid == null || sid.isEmpty || sid == 'null') {
          final snap = row['currency_snapshot'];
          if (snap is Map) {
            sid = snap['supplier_id']?.toString() ?? snap['supplier_code']?.toString();
          }
        }
        if (sid == null || sid.isEmpty || sid == 'null') continue;

        double expectedAmt = (row['expected_amount'] as num?)?.toDouble() ?? 0.0;
        if (expectedAmt <= 0) {
          final snap = row['currency_snapshot'];
          if (snap is Map && snap['settlement'] is Map) {
            expectedAmt = ((snap['settlement'] as Map)['expected_amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        if (expectedAmt <= 0) {
          expectedAmt = (row['base_amount'] as num?)?.toDouble() ?? 0.0;
        }
        if (expectedAmt <= 0) {
          final snap = row['currency_snapshot'];
          if (snap is Map) {
            expectedAmt = (snap['total_egp'] as num?)?.toDouble() ??
                (snap['total'] as num?)?.toDouble() ?? 0.0;
          }
        }
        if (expectedAmt <= 0) {
          expectedAmt = (row['original_amount'] as num?)?.toDouble() ?? 0.0;
        }

        if (expectedAmt > 0) {
          map[sid] = (map[sid] ?? 0.0) + expectedAmt;
        }
      }

      // Fallback: Also check active packing orders where cost items are stored in notes JSON
      // but not yet persisted into packing_order_cost_items
      try {
        final activeOrders = await _client
            .from('packing_orders')
            .select('id, notes, status')
            .not('status', 'in', '("completed","cancelled")')
            .limit(200);

        for (final order in activeOrders) {
          final oid = order['id'];
          final int? intOid = (oid is int) ? oid : (oid is num ? oid.toInt() : int.tryParse('$oid'));
          if (intOid != null && seenPackingOrderIds.contains(intOid)) continue;

          final notesRaw = order['notes'];
          if (notesRaw is String && notesRaw.contains('cost_items')) {
            try {
              final decoded = jsonDecode(notesRaw);
              if (decoded is Map && decoded['cost_items'] is List) {
                for (final item in decoded['cost_items']) {
                  if (item is! Map) continue;
                  final status = item['cost_status']?.toString();
                  final actual = item['actual_amount'];
                  if (status == 'actual' && actual != null) continue;

                  final sid = item['supplier_id']?.toString() ?? item['supplier_code']?.toString();
                  if (sid == null || sid.isEmpty || sid == 'null') continue;

                  final exp = (item['expected_amount'] as num?)?.toDouble() ??
                      (item['total_egp'] as num?)?.toDouble() ??
                      (item['total'] as num?)?.toDouble() ?? 0.0;
                  if (exp > 0) {
                    map[sid] = (map[sid] ?? 0.0) + exp;
                  }
                }
              }
            } catch (_) {}
          }
        }
      } catch (notesErr) {
        debugPrint('SupplierDao.fetchPendingExpectedCosts notes fallback: $notesErr');
      }

      return map;
    } catch (e) {
      debugPrint('SupplierDao.fetchPendingExpectedCosts error: $e');
      return {};
    }
  }

  Future<List<SupplierModel>> getAllSuppliers({List<String>? supplierTypes}) async {
    var query = _client.from('suppliers').select();
    if (supplierTypes != null && supplierTypes.isNotEmpty) {
      query = query.inFilter('supplier_type', supplierTypes);
    }
    final data = await query.order('name').limit(500);

    final results = await Future.wait([
      _calculateLiveBalances(),
      fetchPendingExpectedCosts(),
    ]);
    final liveBalances = results[0] as _LiveBalancesResult;
    final pendingCosts = results[1] as Map<String, double>;
    final packingCosts =
        !liveBalances.isSuccess ? await _fetchPackingCosts() : <String, double>{};

    return data
        .map((row) => _enrichSupplierRow(row, liveBalances, packingCosts, pendingCosts))
        .toList();
  }

  Future<Map<String, dynamic>> multiInvoicePayment({
    required String sourceType,
    required int sourceId,
    required double amount,
    required String currency,
    required String supplierId,
    required String description,
    required String notes,
    int? expenseAccountId,
  }) async {
    try {
      final response = await _client.rpc('rpc_supplier_multi_payment', params: {
        'p_source_type': sourceType,
        'p_source_id': sourceId,
        'p_currency': currency,
        'p_amount': amount,
        'p_supplier_id': supplierId,
        'p_description': description,
        'p_notes': notes,
        'p_expense_account_id': expenseAccountId,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('Error in multiInvoicePayment: $e');
      rethrow;
    }
  }

  /// Fetch expected vs actual cost items for station and deduction suppliers
  Future<List<SupplierExpectedCostItemModel>> getExpectedCostItems({
    String? supplierType,
    String? supplierId,
    String? status,
    String? search,
    int? fromOrderId,
    int? toOrderId,
    int limit = 200,
    int offset = 0,
  }) async {
    bool matchesRange(SupplierExpectedCostItemModel item) =>
        OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: item.orderNumber,
          packingOrderId: item.packingOrderId,
          fromOrderId: fromOrderId,
          toOrderId: toOrderId,
        );

    final baseParams = <String, dynamic>{
      'p_supplier_type': supplierType,
      'p_supplier_id': supplierId,
      'p_status': status,
      'p_search': search,
      'p_limit': limit,
      'p_offset': offset,
    };

    try {
      dynamic res;
      if (fromOrderId != null || toOrderId != null) {
        try {
          res = await _client.rpc(
            'rpc_get_supplier_expected_cost_items',
            params: {
              ...baseParams,
              if (fromOrderId != null) 'p_from_order_id': fromOrderId,
              if (toOrderId != null) 'p_to_order_id': toOrderId,
            },
          );
        } catch (rangeRpcError) {
          // Graceful backwards-compatibility if DB migration has not been applied yet
          debugPrint('RPC order-range fallback retry: $rangeRpcError');
          res = await _client.rpc(
            'rpc_get_supplier_expected_cost_items',
            params: baseParams,
          );
        }
      } else {
        res = await _client.rpc(
          'rpc_get_supplier_expected_cost_items',
          params: baseParams,
        );
      }

      if (res is List) {
        final items = res
            .map((item) => SupplierExpectedCostItemModel.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .where(matchesRange)
            .toList();
        return items;
      }
      return [];
    } catch (e) {
      debugPrint('Error in getExpectedCostItems RPC: $e');
      // Fallback query if RPC isn't deployed yet
      try {
        var builder = _client
            .from('packing_order_cost_items')
            .select('*, packing_orders!inner(order_number, status, packed_at, packing_cost_per_carton), cost_report_categories(name)')
            .isFilter('deleted_at', null);

        PostgrestFilterBuilder<List<Map<String, dynamic>>> filterBuilder = builder;
        if (status != null && status != 'all') {
          filterBuilder = filterBuilder.eq('cost_status', status);
        }

        final data = await filterBuilder.order('id', ascending: false).limit(limit);
        return (data as List)
            .map((row) {
              final m = Map<String, dynamic>.from(row as Map);
              final po = m['packing_orders'] as Map? ?? {};
              final rc = m['cost_report_categories'] as Map? ?? {};
              m['order_number'] = (po['order_number'] ?? m['packing_order_id']).toString();
              m['order_status'] = (po['status'] ?? 'pending').toString();
              m['packing_cost_per_carton'] = po['packing_cost_per_carton'];
              m['report_category_name'] = rc['name'] ?? m['category'];
              return SupplierExpectedCostItemModel.fromJson(m);
            })
            .where(matchesRange)
            .toList();
      } catch (fallbackError) {
        debugPrint('Fallback error in getExpectedCostItems: $fallbackError');
        return [];
      }
    }
  }

  /// Settle actual cost for a packing order cost item
  Future<Map<String, dynamic>> settleCostItem({
    required int costItemId,
    required double actualAmount,
    String? invoiceRef,
    String? notes,
  }) async {
    try {
      final res = await _client.rpc('rpc_settle_packing_cost_item', params: {
        'p_cost_item_id': costItemId,
        'p_actual_amount': actualAmount,
        'p_invoice_ref': invoiceRef,
        'p_notes': notes,
      });
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyPackingOrdersChanged();
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      debugPrint('Error in settleCostItem: $e');
      rethrow;
    }
  }

  /// يتحقق مما إذا كان بند التكلفة ما زال في حالته التقديرية البحتة وقابلاً للحذف:
  /// يُحظر الحذف تماماً لأي بند أخذ قيمة فعلية أو اعتُمدت تسويته أو أُثبت في القيود أو أُقفل.
  static bool canDeleteEstimatedCostItem({
    required dynamic costStatus,
    required dynamic actualAmount,
    required dynamic reconciledAt,
    required dynamic varianceJournalEntryId,
    required dynamic isLocked,
    dynamic deletedAt,
  }) {
    final deletedStr = deletedAt?.toString().trim().toLowerCase() ?? '';
    if (deletedStr.isNotEmpty && deletedStr != 'null') return false;

    if (isLocked == true) return false;

    final status = (costStatus?.toString() ?? '').trim().toLowerCase();
    if (status == 'actual' || status == 'settled' || status == 'locked') {
      return false;
    }

    final num? parsedActual = actualAmount is num
        ? actualAmount
        : num.tryParse(actualAmount?.toString().trim() ?? '');
    if (parsedActual != null && parsedActual > 0) {
      return false;
    }

    final recStr = reconciledAt?.toString().trim().toLowerCase() ?? '';
    if (recStr.isNotEmpty && recStr != 'null') return false;

    final jeStr = varianceJournalEntryId?.toString().trim().toLowerCase() ?? '';
    if (jeStr.isNotEmpty && jeStr != 'null' && jeStr != '0') return false;

    return true;
  }

  static bool canDeleteExpectedCostItemModel(
      SupplierExpectedCostItemModel item) {
    return item.costItemId > 0 &&
        canDeleteEstimatedCostItem(
          costStatus: item.costStatus,
          actualAmount: item.actualAmount,
          reconciledAt: item.reconciledAt,
          varianceJournalEntryId: item.varianceJournalEntryId,
          isLocked: item.isLocked,
        );
  }

  static bool canDeleteEstimatedCostItemMap(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt() ??
        (row['cost_item_id'] as num?)?.toInt();
    if (id == null || id <= 0) return false;
    return canDeleteEstimatedCostItem(
      costStatus: row['cost_status'],
      actualAmount: row['actual_amount'],
      reconciledAt: row['reconciled_at'],
      varianceJournalEntryId: row['variance_journal_entry_id'],
      isLocked: row['is_locked'] == true,
      deletedAt: row['deleted_at'],
    );
  }

  /// إزالة البند التقديري المحذوف من قائمة `cost_items` داخل `packing_orders.notes`
  /// حتى لا يُعاد إنشاؤه عند تعديل أمر التعبئة مستقبلاً، دون لمس أي بيانات أخرى.
  static String? removeDeletedCostItemFromOrderNotes(
    dynamic rawNotes, {
    required int costItemId,
    String? itemUuid,
  }) {
    if (rawNotes == null) return null;
    Map<String, dynamic>? notesMap;
    if (rawNotes is Map) {
      notesMap = Map<String, dynamic>.from(rawNotes);
    } else if (rawNotes is String && rawNotes.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNotes);
        if (decoded is Map) {
          notesMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    if (notesMap == null || notesMap['cost_items'] is! List) return null;

    final rawList = notesMap['cost_items'] as List;
    final updatedList = <dynamic>[];
    bool removed = false;
    for (final entry in rawList) {
      if (entry is Map) {
        final entryId = (entry['id'] as num?)?.toInt();
        final entryUuid = entry['item_uuid']?.toString();
        final matchesId = entryId != null && entryId == costItemId;
        final matchesUuid =
            itemUuid != null && itemUuid.isNotEmpty && entryUuid == itemUuid;
        if (matchesId || matchesUuid) {
          removed = true;
          continue;
        }
      }
      updatedList.add(entry);
    }

    if (!removed) return null;
    notesMap['cost_items'] = updatedList;
    return jsonEncode(notesMap);
  }

  /// حذف بند تكلفة تقديري غير مسوّى وغير مقيد في القيود
  /// دون أي تعديل على الحسابات أو القيود المحاسبية أو أرصدة الموردين.
  Future<void> deleteEstimatedCostItem({
    required int costItemId,
    int? packingOrderId,
  }) async {
    final fresh = await _client
        .from('packing_order_cost_items')
        .select(
            'id, packing_order_id, cost_status, actual_amount, reconciled_at, variance_journal_entry_id, is_locked, deleted_at, currency_snapshot')
        .eq('id', costItemId)
        .maybeSingle();

    final int? resolvedOrderId =
        packingOrderId ?? (fresh?['packing_order_id'] as num?)?.toInt();
    String? itemUuid;
    final snap = fresh?['currency_snapshot'];
    if (snap is Map) {
      itemUuid = snap['item_uuid']?.toString();
    } else if (snap is String && snap.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(snap);
        if (decoded is Map) {
          itemUuid = decoded['item_uuid']?.toString();
        }
      } catch (_) {}
    }

    if (fresh != null) {
      final deletedStr =
          fresh['deleted_at']?.toString().trim().toLowerCase() ?? '';
      final alreadyDeleted =
          deletedStr.isNotEmpty && deletedStr != 'null';

      if (!alreadyDeleted) {
        if (!canDeleteEstimatedCostItemMap(fresh)) {
          throw StateError(
            'لا يمكن حذف هذا البند لأن له قيمة فعلية أو تم اعتماد تسويته في القيود.',
          );
        }

        // محاولة الحذف النهائي أولاً بشرط عدم التسوية أو القفل
        try {
          await _client
              .from('packing_order_cost_items')
              .delete()
              .eq('id', costItemId)
              .isFilter('reconciled_at', null)
              .isFilter('variance_journal_entry_id', null);
        } catch (_) {}

        // إذا بقي السجل بسبب قيود أو سياسات، يتم الحذف المنطقي الآمن مع تصفير التقديري فقط
        final stillPresent = await _client
            .from('packing_order_cost_items')
            .select('id')
            .eq('id', costItemId)
            .isFilter('deleted_at', null)
            .maybeSingle();

        if (stillPresent != null) {
          await _client
              .from('packing_order_cost_items')
              .update({
                'deleted_at': DateTime.now().toIso8601String(),
                'base_amount': 0,
                'original_amount': 0,
                'expected_amount': 0,
                'variance_amount': 0,
              })
              .eq('id', costItemId)
              .isFilter('reconciled_at', null)
              .isFilter('variance_journal_entry_id', null);
        }
      }
    }

    // مزامنة قائمة البنود داخل ملاحظات أمر التعبئة فقط دون المساس بالحسابات أو الموردين
    if (resolvedOrderId != null) {
      try {
        final poRow = await _client
            .from('packing_orders')
            .select('notes')
            .eq('id', resolvedOrderId)
            .maybeSingle();
        final updatedNotes = removeDeletedCostItemFromOrderNotes(
          poRow?['notes'],
          costItemId: costItemId,
          itemUuid: itemUuid,
        );
        if (updatedNotes != null) {
          await _client
              .from('packing_orders')
              .update({'notes': updatedNotes})
              .eq('id', resolvedOrderId);
        }
      } catch (_) {}
    }
  }
}

/// Result container for synchronized live supplier balances
class _LiveBalancesResult {
  final Map<String, Map<String, double>> movementsByCurrency;
  final Map<String, double> rates;
  final bool isSuccess;

  const _LiveBalancesResult({
    required this.movementsByCurrency,
    required this.rates,
    required this.isSuccess,
  });
}

/// Helper for in-memory supplier aggregation in getStockDistribution.
class _AggSupplier {
  final String name;
  double totalQty = 0.0;
  double totalCost = 0.0;
  _AggSupplier({required this.name});
  void add(double qty, double cost) {
    totalQty += qty;
    totalCost += qty * cost;
  }
}
