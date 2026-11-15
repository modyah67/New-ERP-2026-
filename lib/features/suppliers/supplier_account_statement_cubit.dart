import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/statement_notes_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import '../../data/models/currency_snapshot.dart';
import '../../data/services/currency_conversion_service.dart';
import 'supplier_account_statement_state.dart';

class _CurrencyResolution {
  final double baseAmount;
  final double exchangeRate;
  final bool isForeign;
  final double foreignAmount;
  final String? foreignCurrency;

  const _CurrencyResolution({
    required this.baseAmount,
    required this.exchangeRate,
    required this.isForeign,
    required this.foreignAmount,
    this.foreignCurrency,
  });
}

class SupplierAccountStatementCubit extends Cubit<SupplierAccountStatementState> {
  final SupplierDao _supplierDao = SupplierDao();
  final StatementNotesDao _notesDao = StatementNotesDao();

  List<StatementRow> _rawRows = [];
  Map<String, double> _rawOpeningBalancesByCurrency = {};
  List<String> _availableCurrencies = ['ALL', 'EGP'];
  Map<String, String> _savedNotes = {};
  late final StreamSubscription<void> _eventBusSub;

  SupplierAccountStatementCubit() : super(const SupplierAccountStatementInitial()) {
    _eventBusSub = DataChangeEventBus.instance.suppliersStream.listen((_) {
      if (!isClosed) {
        _handleSuppliersChanged();
      }
    });
    _init();
  }

  Future<void> _handleSuppliersChanged() async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    try {
      final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
      SupplierModel? updatedSupplier = currentState.selectedSupplier;
      if (updatedSupplier != null) {
        final found = suppliers.where((s) => s.id == updatedSupplier!.id).firstOrNull;
        if (found != null) {
          updatedSupplier = found;
        }
      }
      if (!isClosed) {
        emit(currentState.copyWith(
          suppliers: suppliers,
          selectedSupplier: updatedSupplier,
        ));
        if (updatedSupplier != null) {
          await loadStatement();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error in _handleSuppliersChanged: $e');
    }
  }

  @override
  Future<void> close() {
    _eventBusSub.cancel();
    return super.close();
  }

  Future<void> init({String? initialSupplierId}) => _init(initialSupplierId: initialSupplierId);

  Future<void> _init({String? initialSupplierId}) async {
    try {
      final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
      final now = DateTime.now();
      SupplierModel? selected;
      if (initialSupplierId != null) {
        selected = suppliers.where((s) => s.id == initialSupplierId).firstOrNull;
      }
      if (!isClosed) {
        emit(SupplierAccountStatementLoaded(
          suppliers: suppliers,
          selectedSupplier: selected,
          fromDate: DateTime(now.year, now.month, 1),
          toDate: now,
        ));
        if (selected != null) {
          await selectSupplier(selected);
          await loadStatement();
        }
      }
    } catch (e) {
      if (!isClosed) emit(SupplierAccountStatementError(message: 'فشل تحميل الموردين: $e'));
    }
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      try {
        final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
        emit(currentState.copyWith(suppliers: suppliers));
      } catch (e) {
        emit(SupplierAccountStatementError(message: 'فشل تحميل البيانات: $e'));
      }
    }
  }

  Future<void> selectSupplier(SupplierModel? supplier) async {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      final Set<String> currencies = {'ALL', 'EGP'};
      if (supplier != null) {
        if (supplier.isMultiCurrency || supplier.currency == 'MULTI') {
          currencies.addAll(supplier.supportedCurrencies);
          currencies.addAll(supplier.initialBalancesByCurrency.keys);
          if (supplier.cropCurrency.isNotEmpty) currencies.add(supplier.cropCurrency);
          if (supplier.packagingCurrency.isNotEmpty) currencies.add(supplier.packagingCurrency);
        } else if (supplier.currency.isNotEmpty && supplier.currency != 'MULTI') {
          currencies.add(supplier.currency);
        }
      }
      _availableCurrencies = currencies.toList();
      _rawRows = [];
      _rawOpeningBalancesByCurrency = {};

      emit(currentState.copyWith(
        selectedSupplier: supplier,
        clearSelectedSupplier: supplier == null,
        selectedCurrency: 'ALL',
        availableCurrencies: _availableCurrencies,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
      ));
      if (supplier != null) await loadStatement();
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) emit(currentState.copyWith(fromDate: picked));
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) emit(currentState.copyWith(toDate: picked));
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    if (currentState.selectedSupplier == null) return;

    emit(currentState.copyWith(statementRows: [], totalDebit: 0, totalCredit: 0, finalBalance: 0));

    try {
      final supplierId = currentState.selectedSupplier!.id;
      final supplierCode = currentState.selectedSupplier!.supplierCode;
      final from = currentState.fromDate != null ? AppUtils.formatDateForDb(currentState.fromDate!) : null;
      final to = currentState.toDate != null ? AppUtils.formatDateForDb(currentState.toDate!) : null;

      // 1. Fetch purchases, payments, and treasury txs in parallel
      final currentResults = await Future.wait([
        _fetchPurchases(supplierId.toString(), from, to),
        _fetchPayments(supplierCode, supplierId, from, to),
        _fetchTreasuryTx(supplierId.toString(), from, to),
        _fetchCheques(supplierId.toString(), from, to),
        _fetchBankTx(supplierId.toString(), supplierCode, from, to),
        _fetchLots(supplierId.toString(), from, to),
        _fetchSettlementCostItems(supplierId.toString(), supplierCode),
      ]);
      final purchases = currentResults[0];
      final payments = currentResults[1];
      final treasuryTxs = currentResults[2];
      final cheques = currentResults[3];
      final bankTxs = currentResults[4];
      final lots = currentResults[5];
      final settlementCostItems = List<Map<String, dynamic>>.from(currentResults[6]);

      // Also fetch cost items for any settlement or packing cost rows whose order ID wasn't fetched yet
      final existingCostItemIds = settlementCostItems.map((c) => c['id']?.toString()).toSet();
      final missingOrderIds = <String>{};
      for (final p in payments) {
        final rType = p['reference_type']?.toString().toLowerCase() ?? '';
        if (rType == 'cost_settlement' ||
            rType == 'packing_cost_settlement' ||
            rType == 'packing_cost' ||
            rType == 'packing_cost_item' ||
            rType == 'packing_order_costs') {
          final rId = p['reference_id']?.toString();
          if (rId != null &&
              rId.isNotEmpty &&
              !settlementCostItems.any((c) => c['packing_order_id']?.toString() == rId || c['id']?.toString() == rId)) {
            missingOrderIds.add(rId);
          }
        }
      }
      if (missingOrderIds.isNotEmpty) {
        try {
          final extraData = await Supabase.instance.client
              .from('packing_order_cost_items')
              .select('id, packing_order_id, name, cost_type, cost_status, expected_amount, base_amount, actual_amount, variance_amount, reconciled_at, variance_journal_entry_id, actual_quantity, actual_unit_price, detailed_notes, settlement_notes, invoice_ref, original_currency, supplier_id, currency_snapshot, deleted_at, created_at')
              .inFilter('packing_order_id', missingOrderIds.toList())
              .isFilter('deleted_at', null);
          for (final row in extraData) {
            final m = Map<String, dynamic>.from(row as Map);
            if (m['deleted_at'] != null) continue;
            if (!existingCostItemIds.contains(m['id']?.toString())) {
              settlementCostItems.add(m);
              existingCostItemIds.add(m['id']?.toString());
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching extra settlement cost items: $e');
        }
      }

      // Build lookup maps for cost items to enrich settlement statement rows
      final costItemsById = <String, Map<String, dynamic>>{};
      final costItemsByOrderAndName = <String, Map<String, dynamic>>{};
      final costItemsByOrder = <String, List<Map<String, dynamic>>>{};
      for (final c in settlementCostItems) {
        if (c['deleted_at'] != null) continue;
        final cId = c['id']?.toString();
        final poId = c['packing_order_id']?.toString();
        final cName = c['name']?.toString() ?? '';
        if (cId != null) costItemsById[cId] = c;
        if (poId != null) {
          costItemsByOrder.putIfAbsent(poId, () => []).add(c);
          if (cName.isNotEmpty) {
            costItemsByOrderAndName['${poId}_$cName'] = c;
          }
        }
      }

      final supplier = currentState.selectedSupplier!;
      final isDualCostSupplier = supplier.isStationSupplier || supplier.isDeductionSupplier;
      final emittedDualCostItemIds = <String>{};

      // Build lot currency lookup map from lots
      final lotCurrencyMap = <String, String>{};
      for (final lot in lots) {
        final lId = lot['id']?.toString();
        final lNum = lot['lot_number']?.toString();
        final lCur = lot['currency']?.toString();
        if (lCur != null && lCur.isNotEmpty && lCur != 'MULTI') {
          if (lId != null) lotCurrencyMap[lId] = lCur;
          if (lNum != null) lotCurrencyMap[lNum] = lCur;
        }
      }

      // Fetch lot_returns for this supplier to map returnId -> native currency
      final lotReturnCurrencyMap = <String, String>{};
      try {
        final returnRows = await Supabase.instance.client
            .from('lot_returns')
            .select('id, lot_receipt_id, lot_receipts(currency)')
            .eq('supplier_id', supplierId.toString());
        for (final r in returnRows) {
          final rId = r['id']?.toString();
          final lr = r['lot_receipts'] as Map<String, dynamic>?;
          final c = lr?['currency']?.toString();
          if (rId != null && c != null && c.isNotEmpty && c != 'MULTI') {
            lotReturnCurrencyMap[rId] = c;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error mapping lot_returns currency: $e');
      }

      // 2. Build rows
      final rows = <StatementRow>[];

      // 3. Calculate opening balances per currency stream
      final isSupplierMulti = supplier.isMultiCurrency || supplier.currency == 'MULTI';
      final Map<String, double> openingBalancesByCurrency = {};

      if (isSupplierMulti && supplier.initialBalancesByCurrency.isNotEmpty) {
        for (final entry in supplier.initialBalancesByCurrency.entries) {
          final amt = entry.value.amount;
          final dir = entry.value.direction.toUpperCase();
          if (amt > 0) {
            openingBalancesByCurrency[entry.key] = (dir == 'DEBIT') ? -amt : amt;
          }
        }
      } else if (supplier.initialBalance != 0) {
        final cur = (supplier.currency.isNotEmpty && supplier.currency != 'MULTI') ? supplier.currency : 'EGP';
        final isDebit = supplier.initialBalanceDirection.toUpperCase() == 'DEBIT';
        openingBalancesByCurrency[cur] = isDebit ? -supplier.initialBalance.abs() : supplier.initialBalance.abs();
      }

      if (from != null) {
        final priorDateStr = AppUtils.formatDateForDb(currentState.fromDate!.subtract(const Duration(days: 1)));
        final priorResults = await Future.wait([
          _fetchPurchases(supplierId.toString(), null, priorDateStr),
          _fetchPayments(supplierCode, supplierId, null, priorDateStr),
          _fetchTreasuryTx(supplierId.toString(), null, priorDateStr),
          _fetchCheques(supplierId.toString(), null, priorDateStr),
          _fetchBankTx(supplierId.toString(), supplierCode, null, priorDateStr),
          _fetchLots(supplierId.toString(), null, priorDateStr),
        ]);
        final priorPurchases = priorResults[0];
        final rawPriorPayments = priorResults[1];
        final priorTreasuryTxs = priorResults[2];
        final priorCheques = priorResults[3];
        final priorBankTxs = priorResults[4];
        final priorLots = priorResults[5];

        final priorPayments = normalizeDualCostSupplierLedgerEntries(
          rawEntries: rawPriorPayments,
          costItemsById: costItemsById,
          costItemsByOrderAndName: costItemsByOrderAndName,
          costItemsByOrder: costItemsByOrder,
          isDualCostSupplier: isDualCostSupplier,
          emittedCostItemIds: emittedDualCostItemIds,
        );

        for (final l in priorLots) {
          final lId = l['id']?.toString();
          final lNum = l['lot_number']?.toString();
          final lCur = l['currency']?.toString();
          if (lCur != null && lCur.isNotEmpty && lCur != 'MULTI') {
            if (lId != null) lotCurrencyMap[lId] = lCur;
            if (lNum != null) lotCurrencyMap[lNum] = lCur;
          }
        }

        // Deduplicate: skip ledger entries that reference treasury transactions
        final priorTreasuryIds = priorTreasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

        for (final p in priorPurchases) {
          final cur = p['currency']?.toString() ?? 'EGP';
          final amt = (p['total_amount'] as num?)?.toDouble() ?? 0;
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + amt;
        }
        for (final l in priorLots) {
          final cur = l['currency']?.toString() ?? (supplier.cropCurrency.isNotEmpty ? supplier.cropCurrency : 'USD');
          final amt = (l['total_fruit_cost'] as num?)?.toDouble() ?? 0;
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + amt;
        }
        for (final p in priorPayments) {
          final refId = p['reference_id']?.toString() ?? '';
          if (refId.isNotEmpty && priorTreasuryIds.contains(refId)) continue;
          final refType = p['reference_type']?.toString() ?? '';
          if (refType == 'lot_receipt') continue; // Skip legacy lot_receipts from ledger_entries
          
          final rawCur = p['currency']?.toString() ?? '';
          String cur = rawCur;
          if (refType == 'lot_return') {
            final refText = p['reference_text']?.toString() ?? '';
            if (lotReturnCurrencyMap.containsKey(refText)) {
              cur = lotReturnCurrencyMap[refText]!;
            } else if (lotReturnCurrencyMap.containsKey(refId)) {
              cur = lotReturnCurrencyMap[refId]!;
            } else if (lotCurrencyMap.containsKey(refId)) {
              cur = lotCurrencyMap[refId]!;
            } else if (rawCur.isNotEmpty && rawCur != 'EGP') {
              cur = rawCur;
            } else if (supplier.cropCurrency.isNotEmpty && supplier.cropCurrency != 'EGP') {
              cur = supplier.cropCurrency;
            } else if (supplier.currency.isNotEmpty && supplier.currency != 'MULTI' && supplier.currency != 'EGP') {
              cur = supplier.currency;
            } else {
              cur = 'EGP';
            }
          } else if (cur.isEmpty) {
            cur = (supplier.isForeignCurrency && !supplier.isMultiCurrency) ? supplier.currency : 'EGP';
          }

          final amt = (p['amount'] as num?)?.toDouble() ?? 0;
          final isCredit = p['entry_type']?.toString() == 'credit' ||
              refType == 'supplier_deposit' ||
              refType == 'export_return_expense' ||
              refType == 'packing_cost' ||
              refType == 'packing_order_costs';
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + (isCredit ? amt : -amt);
        }
        for (final tx in priorTreasuryTxs) {
          final cur = tx['currency']?.toString() ?? 'EGP';
          final type = tx['type']?.toString().toLowerCase() ?? '';
          final isCredit = type == 'deposit' || type == 'receive' || type == 'income' || type == 'supplier_refund';
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + (isCredit ? amt : -amt);
        }
        for (final ch in priorCheques) {
          final cur = ch['currency']?.toString() ?? 'EGP';
          final amt = (ch['amount'] as num?)?.toDouble() ?? 0;
          final isCredit = ch['type']?.toString() == 'incoming';
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + (isCredit ? amt : -amt);
        }
        for (final tx in priorBankTxs) {
          final cur = tx['currency']?.toString() ?? 'EGP';
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          final type = tx['type']?.toString() ?? '';
          final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
          openingBalancesByCurrency[cur] = (openingBalancesByCurrency[cur] ?? 0.0) + (isCredit ? amt : -amt);
        }
      }

      // Collect treasury transaction IDs to avoid duplicating ledger entries
      final treasuryTxIds = treasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

      // Add purchases as credit rows (buying materials increases supplier liability)
      for (final purchase in purchases) {
        final amount = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
        final purchaseDate = (purchase['invoice_date'] ?? '').toString().substring(0, 10);
        final invoiceNo = purchase['invoice_number']?.toString() ?? purchase['id']?.toString() ?? '—';
        final cur = purchase['currency']?.toString() ?? 'EGP';
        final description = _buildMaterialPurchaseDescription(purchase);

        // Aggregate units and quantities from invoice items
        double totalQty = 0;
        double totalPieces = 0;
        num? itemRate;
        final items = purchase['purchase_invoice_items'] as List<dynamic>?;
        if (items != null) {
          for (final item in items) {
            final rawItem = item as Map<String, dynamic>;
            final qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0;
            totalQty += qty;
            final rm = rawItem['raw_materials'] as Map<String, dynamic>?;
            final unit = (rm?['unit'] ?? '').toString();
            if (unit.contains('كرتون') || unit.contains('حبة') || unit.contains('قطعة')) {
              totalPieces += qty;
            }
            final r = rawItem['exchange_rate'] as num?;
            if (r != null && r > 0 && r != 1.0) {
              itemRate = r;
            }
          }
        }

        final res = await _resolveCurrencyConversion(
          amount: amount,
          currency: cur,
          currencySnapshot: purchase['currency_snapshot'],
          explicitRate: (purchase['exchange_rate'] as num?) ?? itemRate,
          amountInBaseCurrency: purchase['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: invoiceNo,
          date: purchaseDate,
          accountName: 'مشتريات خامات',
          description: description,
          piecesCount: totalPieces,
          quantity: totalQty,
          unitPrice: totalQty > 0 ? (res.baseAmount / totalQty) : 0,
          debit: 0,
          credit: res.baseAmount,
          balance: 0,
          type: 'purchase',
          createdAt: (purchase['created_at'] ?? '').toString(),
          currency: 'EGP',
          foreignDebit: null,
          foreignCredit: res.isForeign ? amount : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
        ));
      }

      // Add lots as credit rows (buying crop increases supplier liability)
      for (final lot in lots) {
        final amount = (lot['total_fruit_cost'] as num?)?.toDouble() ?? 0;
        final lotDate = (lot['receipt_date'] ?? '').toString().substring(0, 10);
        final lotNo = lot['lot_number']?.toString() ?? lot['id']?.toString() ?? '—';
        final cur = lot['currency']?.toString() ?? (supplier.cropCurrency.isNotEmpty ? supplier.cropCurrency : 'USD');
        final description = _buildCropPurchaseDescription(lot);

        final cartonCount = (lot['carton_count'] as num?)?.toDouble() ?? 0;
        final grossWeight = (lot['gross_weight_kg'] as num?)?.toDouble() ?? 0;
        final netWeight = (lot['net_weight_kg'] as num?)?.toDouble() ?? 0;
        final effectiveWeight = netWeight > 0 ? netWeight : grossWeight;
        final pricePerKg = (lot['price_per_kg'] as num?)?.toDouble() ?? 0;
        final pricePerCarton = (lot['price_per_carton'] as num?)?.toDouble() ?? 0;
        final isCarton = (lot['purchase_mode'] ?? 'weight') == 'carton';

        final res = await _resolveCurrencyConversion(
          amount: amount,
          currency: cur,
          currencySnapshot: lot['currency_snapshot'],
          explicitRate: lot['exchange_rate'] as num?,
          amountInBaseCurrency: lot['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: lotNo,
          date: lotDate,
          accountName: 'شراء محصول',
          description: description,
          piecesCount: cartonCount,
          quantity: effectiveWeight,
          unitPrice: isCarton
              ? (res.isForeign ? pricePerCarton * res.exchangeRate : pricePerCarton)
              : (pricePerKg > 0
                  ? (res.isForeign ? pricePerKg * res.exchangeRate : pricePerKg)
                  : (effectiveWeight > 0 ? res.baseAmount / effectiveWeight : 0)),
          debit: 0,
          credit: res.baseAmount,
          balance: 0,
          type: 'lot_receipt',
          createdAt: (lot['created_at'] ?? '').toString(),
          currency: 'EGP',
          foreignDebit: null,
          foreignCredit: res.isForeign ? amount : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
        ));
      }

      // Add ledger entries (payments/expenses/receive)
      // Skip entries whose reference_id matches a treasury transaction (already shown)
      final normalizedPayments = normalizeDualCostSupplierLedgerEntries(
        rawEntries: payments,
        costItemsById: costItemsById,
        costItemsByOrderAndName: costItemsByOrderAndName,
        costItemsByOrder: costItemsByOrder,
        isDualCostSupplier: isDualCostSupplier,
        emittedCostItemIds: emittedDualCostItemIds,
      );

      for (final payment in normalizedPayments) {
        final refType = payment['reference_type']?.toString() ?? '';
        if (refType == 'lot_receipt') continue; // Skip legacy lot_receipts from ledger_entries

        final refId = payment['reference_id']?.toString() ?? '';
        if (refId.isNotEmpty && treasuryTxIds.contains(refId)) continue;

        final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
        final paymentDate = _toLocalDate(payment['created_at']);
        final entryType = payment['entry_type']?.toString() ?? 'debit';
        final isCredit = entryType == 'credit' ||
            refType == 'supplier_deposit' ||
            refType == 'export_return_expense' ||
            refType == 'packing_cost' ||
            refType == 'packing_order_costs';
        final accountName = refType == 'lot_receipt' ? 'شراء محصول' :
            refType == 'lot_return' ? 'مرتجع شراء محصول' :
            refType == 'packing_order_debit_note' ? 'إشعار خصم أمر تعبئة' :
            refType == 'cheque_cleared_outgoing' ? 'شيك صادر' :
            refType == 'cheque_cleared_incoming' ? 'شيك وارد' :
            refType == 'supplier_deposit' ? 'إيداع نقدي / استلام من مورد' :
            refType == 'export_return_expense' ? 'مصروفات رجوع شحنة (نولون/تفريغ)' :
            (refType == 'packing_cost' || refType == 'packing_order_costs') ? 'استحقاق تكلفة أمر تعبئة' :
            (refType == 'cost_settlement' || refType == 'packing_cost_settlement')
                ? (isDualCostSupplier
                    ? 'اعتماد تكلفة فعلية'
                    : (isCredit ? 'تسوية تكلفة فعلية (استحقاق دائن)' : 'تسوية تكلفة فعلية (وفر تكلفة)')) :
            isCredit ? 'سند قبض من مورد' : 'سند صرف للمورد';

        final rawDesc = payment['description']?.toString() ?? '';
        final fallbackDesc = rawDesc.isNotEmpty
            ? rawDesc
            : (refType == 'lot_return'
                ? 'مرتجع محصول للمورد - تسوية'
                : refType == 'export_return_expense'
                    ? 'استحقاق مصروفات رجوع شحنة من المطار'
                : refType == 'packing_order_debit_note'
                    ? 'إشعار خصم وتسوية أمر تعبئة'
                : (refType == 'packing_cost' || refType == 'packing_order_costs')
                    ? 'استحقاق تكلفة ومصروفات أمر تعبئة'
                : (refType == 'cost_settlement' || refType == 'packing_cost_settlement')
                    ? (isDualCostSupplier
                        ? 'اعتماد تكلفة فعلية للمورد'
                        : (isCredit ? 'تسوية تكلفة فعلية - زيادة استحقاق للمورد' : 'تسوية تكلفة فعلية - وفر وتخفيض تكلفة'))
                : refType == 'cheque_cleared_incoming'
                    ? 'سند قبض شيك'
                : refType == 'supplier_deposit'
                    ? 'إيداع نقدي / استلام من المورد'
                : isCredit
                    ? 'سند قبض من مورد'
                    : 'سند صرف للمورد');

        final isCostSettlement = refType == 'cost_settlement' || refType == 'packing_cost_settlement';
        String description = fallbackDesc;
        double itemQty = 0.0;
        double itemUnitPrice = 0.0;

        if (isCostSettlement) {
          final matchedCostItem = matchCostItemForSettlement(
            payment: payment,
            costItemsById: costItemsById,
            costItemsByOrderAndName: costItemsByOrderAndName,
            costItemsByOrder: costItemsByOrder,
          );
          final enriched = enrichSettlementStatementDetails(
            rawDesc: rawDesc,
            fallbackDesc: fallbackDesc,
            refId: refId,
            isCredit: isCredit,
            amount: amount,
            matchedCostItem: matchedCostItem,
          );
          description = enriched.description;
          itemQty = enriched.quantity;
          itemUnitPrice = enriched.unitPrice;
        }

        final rawCur = payment['currency']?.toString() ?? '';
        String cur = rawCur;
        if (refType == 'lot_return') {
          final refText = payment['reference_text']?.toString() ?? '';
          if (lotReturnCurrencyMap.containsKey(refText)) {
            cur = lotReturnCurrencyMap[refText]!;
          } else if (lotReturnCurrencyMap.containsKey(refId)) {
            cur = lotReturnCurrencyMap[refId]!;
          } else if (lotCurrencyMap.containsKey(refId)) {
            cur = lotCurrencyMap[refId]!;
          } else if (rawCur.isNotEmpty && rawCur != 'EGP') {
            cur = rawCur;
          } else if (supplier.cropCurrency.isNotEmpty && supplier.cropCurrency != 'EGP') {
            cur = supplier.cropCurrency;
          } else if (supplier.currency.isNotEmpty && supplier.currency != 'MULTI' && supplier.currency != 'EGP') {
            cur = supplier.currency;
          } else {
            cur = 'EGP';
          }
        } else if (cur.isEmpty) {
          cur = (supplier.isForeignCurrency && !supplier.isMultiCurrency) ? supplier.currency : 'EGP';
        }

        final res = await _resolveCurrencyConversion(
          amount: amount,
          currency: cur,
          currencySnapshot: payment['currency_snapshot'],
          explicitRate: payment['exchange_rate'] as num?,
          amountInBaseCurrency: payment['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: payment['id']?.toString() ?? '—',
          date: paymentDate,
          accountName: accountName,
          description: description,
          piecesCount: 0,
          quantity: itemQty,
          unitPrice: itemUnitPrice > 0
              ? (res.isForeign ? itemUnitPrice * res.exchangeRate : itemUnitPrice)
              : 0,
          debit: isCredit ? 0 : res.baseAmount,
          credit: isCredit ? res.baseAmount : 0,
          balance: 0,
          type: refType == 'lot_return'
              ? 'lot_return'
              : refType == 'lot_receipt'
                  ? 'lot_receipt'
                  : isCostSettlement
                      ? 'cost_settlement'
                      : 'payment',
          createdAt: (payment['created_at'] ?? '').toString(),
          currency: 'EGP',
          foreignDebit: res.isForeign && !isCredit ? amount : null,
          foreignCredit: res.isForeign && isCredit ? amount : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
          id: payment['id']?.toString(),
          referenceType: refType,
          referenceId: refId,
        ));
      }

      // Add treasury transactions with enriched descriptions
      for (final tx in treasuryTxs) {
        final rawType = tx['type']?.toString().toLowerCase() ?? '';
        final isDeposit = rawType == 'deposit' || rawType == 'receive' || rawType == 'income' || rawType == 'supplier_refund';
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = tx['created_at'];
        final date = _toLocalDate(dateRaw);
        final description = _buildTreasuryDescription(tx);

        final res = await _resolveCurrencyConversion(
          amount: amt,
          currency: tx['currency']?.toString() ?? 'EGP',
          currencySnapshot: tx['currency_snapshot'],
          explicitRate: tx['exchange_rate'] as num?,
          amountInBaseCurrency: tx['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: tx['transaction_number']?.toString() ?? tx['id']?.toString() ?? '-',
          date: date,
          createdAt: dateRaw?.toString() ?? '',
          accountName: isDeposit ? 'إيداع نقدي / استلام من مورد' : 'سداد نقدي للمورد',
          description: description,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isDeposit ? 0 : res.baseAmount,
          credit: isDeposit ? res.baseAmount : 0,
          balance: 0,
          type: 'treasury',
          currency: 'EGP',
          foreignDebit: res.isForeign && !isDeposit ? amt : null,
          foreignCredit: res.isForeign && isDeposit ? amt : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
        ));
      }

      // Add cheques with enriched descriptions
      for (final cheque in cheques) {
        final amt = (cheque['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = cheque['cleared_at'] ?? cheque['created_at'];
        final date = _toLocalDate(dateRaw);
        final isCredit = cheque['type']?.toString() == 'incoming';
        final description = _buildChequeDescription(cheque);

        final res = await _resolveCurrencyConversion(
          amount: amt,
          currency: cheque['currency']?.toString() ?? 'EGP',
          currencySnapshot: cheque['currency_snapshot'],
          explicitRate: cheque['exchange_rate'] as num?,
          amountInBaseCurrency: cheque['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: cheque['cheque_number']?.toString() ?? cheque['id']?.toString() ?? '-',
          date: date,
          createdAt: dateRaw?.toString() ?? '',
          accountName: isCredit ? 'شيك وارد' : 'شيك صادر',
          description: description,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isCredit ? 0 : res.baseAmount,
          credit: isCredit ? res.baseAmount : 0,
          balance: 0,
          type: 'cheque',
          currency: 'EGP',
          foreignDebit: res.isForeign && !isCredit ? amt : null,
          foreignCredit: res.isForeign && isCredit ? amt : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
        ));
      }

      // Add bank transactions with enriched descriptions
      for (final tx in bankTxs) {
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
        final type = tx['type']?.toString().toLowerCase() ?? '';
        final isDeposit = type == 'deposit' || type == 'receive' || type == 'income';
        final dateRaw = tx['transaction_date'] ?? tx['created_at'];
        final date = _toLocalDate(dateRaw);
        final description = _buildBankDescription(tx);

        final res = await _resolveCurrencyConversion(
          amount: amt,
          currency: tx['currency']?.toString() ?? 'EGP',
          currencySnapshot: tx['currency_snapshot'],
          explicitRate: tx['exchange_rate'] as num?,
          amountInBaseCurrency: tx['amount_in_base_currency'] as num?,
        );

        rows.add(StatementRow(
          transactionNumber: tx['id']?.toString() ?? '-',
          date: date,
          createdAt: (tx['created_at'] ?? '').toString(),
          accountName: isDeposit ? 'إيداع بنكي / استلام من مورد' : 'سداد بنكي للمورد',
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isDeposit ? 0 : res.baseAmount,
          credit: isDeposit ? res.baseAmount : 0,
          balance: 0,
          type: 'bank',
          currency: 'EGP',
          foreignDebit: res.isForeign && !isDeposit ? amt : null,
          foreignCredit: res.isForeign && isDeposit ? amt : null,
          foreignCurrency: res.foreignCurrency,
          exchangeRate: res.isForeign ? res.exchangeRate : null,
        ));
      }

      // Insert opening balance rows per currency with clear narratives
      if (from == null) {
        if (openingBalancesByCurrency.isNotEmpty) {
          for (final entry in openingBalancesByCurrency.entries) {
            final cur = entry.key;
            final bal = entry.value;
            if (bal.abs() > 0.001) {
              final res = await _resolveCurrencyConversion(
                amount: bal.abs(),
                currency: cur,
              );
              final baseBal = bal >= 0 ? res.baseAmount : -res.baseAmount;

              rows.add(StatementRow(
                transactionNumber: '-',
                date: '',
                accountName: 'رصيد افتتاحي',
                description: _buildInitialBalanceDescription(cur, bal, isSupplierMulti),
                piecesCount: 0,
                quantity: 0,
                unitPrice: 0,
                debit: baseBal < 0 ? baseBal.abs() : 0,
                credit: baseBal > 0 ? baseBal : 0,
                balance: baseBal,
                type: 'initial',
                createdAt: '',
                currency: 'EGP',
                foreignDebit: res.isForeign && bal < 0 ? bal.abs() : null,
                foreignCredit: res.isForeign && bal > 0 ? bal : null,
                foreignCurrency: res.foreignCurrency,
                exchangeRate: res.isForeign ? res.exchangeRate : null,
              ));
            }
          }
        }
      } else {
        // Date filter active
        if (openingBalancesByCurrency.isNotEmpty) {
          for (final entry in openingBalancesByCurrency.entries) {
            final cur = entry.key;
            final bal = entry.value;
            if (bal.abs() > 0.001) {
              final res = await _resolveCurrencyConversion(
                amount: bal.abs(),
                currency: cur,
              );
              final baseBal = bal >= 0 ? res.baseAmount : -res.baseAmount;

              rows.add(StatementRow(
                transactionNumber: '—',
                date: from,
                createdAt: '',
                accountName: 'رصيد سابق',
                description: _buildOpeningBalanceDescription(cur, bal, from, isSupplierMulti),
                piecesCount: 0,
                quantity: 0,
                unitPrice: 0,
                debit: baseBal < 0 ? baseBal.abs() : 0,
                credit: baseBal > 0 ? baseBal : 0,
                balance: baseBal,
                type: 'opening',
                currency: 'EGP',
                foreignDebit: res.isForeign && bal < 0 ? bal.abs() : null,
                foreignCredit: res.isForeign && bal > 0 ? bal : null,
                foreignCurrency: res.foreignCurrency,
                exchangeRate: res.isForeign ? res.exchangeRate : null,
              ));
            }
          }
        }
      }

      // Sort by date with opening/initial rows pinned to top
      rows.sort((a, b) {
        if (a.type == 'opening' || a.type == 'initial') {
          if (b.type == 'opening' || b.type == 'initial') {
            return (a.currency ?? '').compareTo(b.currency ?? '');
          }
          return -1;
        }
        if (b.type == 'opening' || b.type == 'initial') return 1;
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

      // Collect available currencies across supplier profile and actual transactions
      final Set<String> currencies = {'ALL', 'EGP'};
      if (supplier.isMultiCurrency || supplier.currency == 'MULTI') {
        currencies.addAll(supplier.supportedCurrencies);
        currencies.addAll(supplier.initialBalancesByCurrency.keys);
        if (supplier.cropCurrency.isNotEmpty) currencies.add(supplier.cropCurrency);
        if (supplier.packagingCurrency.isNotEmpty) currencies.add(supplier.packagingCurrency);
      } else if (supplier.currency.isNotEmpty && supplier.currency != 'MULTI') {
        currencies.add(supplier.currency);
      }
      for (final r in rows) {
        if (r.currency != null && r.currency!.isNotEmpty && r.currency != 'MULTI') {
          currencies.add(r.currency!);
        }
      }
      _availableCurrencies = currencies.toList();
      _rawRows = rows;
      _rawOpeningBalancesByCurrency = Map<String, double>.from(openingBalancesByCurrency);

      _savedNotes = await _notesDao.getNotes(
        entityType: 'supplier',
        entityId: currentState.selectedSupplier!.id!.toString(),
      );

      final targetCurrency = _availableCurrencies.contains(currentState.selectedCurrency)
          ? currentState.selectedCurrency!
          : 'ALL';

      await _applyCurrencyFilter(targetCurrency);
    } catch (e, st) {
      debugPrint('SupplierAccountStatement error: $e\n$st');
      if (!isClosed) {
        emit(SupplierAccountStatementError(message: 'فشل تحميل كشف الحساب: $e'));
      }
    }
  }

  Future<void> selectCurrency(String? currency) async {
    final targetCurrency = currency ?? 'ALL';
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    if (currentState.selectedCurrency == targetCurrency) return;

    await _applyCurrencyFilter(targetCurrency);
  }

  static Future<_CurrencyResolution> _resolveCurrencyConversion({
    required double amount,
    required String currency,
    dynamic currencySnapshot,
    num? explicitRate,
    num? amountInBaseCurrency,
  }) async {
    final cur = (currency.isNotEmpty && currency != 'MULTI') ? currency.toUpperCase().trim() : 'EGP';
    if (cur == 'EGP' || cur == 'ج.م') {
      return _CurrencyResolution(
        baseAmount: amount,
        exchangeRate: 1.0,
        isForeign: false,
        foreignAmount: 0.0,
        foreignCurrency: null,
      );
    }

    // 1. Try currency snapshot
    final snapshot = CurrencySnapshot.fromJsonNullable(currencySnapshot);
    if (snapshot != null && snapshot.isValid) {
      final baseAmt = snapshot.baseAmount > 0 ? snapshot.baseAmount : amount * snapshot.exchangeRate;
      return _CurrencyResolution(
        baseAmount: baseAmt,
        exchangeRate: snapshot.exchangeRate,
        isForeign: true,
        foreignAmount: amount,
        foreignCurrency: cur,
      );
    }

    // 2. Try explicit amount_in_base_currency
    if (amountInBaseCurrency != null && amountInBaseCurrency > 0) {
      final baseAmt = amountInBaseCurrency.toDouble();
      final rate = amount > 0 ? (baseAmt / amount) : 1.0;
      return _CurrencyResolution(
        baseAmount: baseAmt,
        exchangeRate: rate,
        isForeign: true,
        foreignAmount: amount,
        foreignCurrency: cur,
      );
    }

    // 3. Try explicit exchange rate
    if (explicitRate != null && explicitRate > 0) {
      final rate = explicitRate.toDouble();
      return _CurrencyResolution(
        baseAmount: amount * rate,
        exchangeRate: rate,
        isForeign: true,
        foreignAmount: amount,
        foreignCurrency: cur,
      );
    }

    // 4. Fallback to live/cached rate from CurrencyConversionService
    final rate = await CurrencyConversionService.instance.getRate(cur);
    return _CurrencyResolution(
      baseAmount: amount * rate,
      exchangeRate: rate,
      isForeign: true,
      foreignAmount: amount,
      foreignCurrency: cur,
    );
  }

  Future<void> _applyCurrencyFilter(String curFilter) async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;

    final isAll = curFilter == 'ALL';

    List<StatementRow> filteredRows;
    Map<String, double> finalBalancesByCurrency = {};
    Map<String, double> openingBalancesByCurrency = {};
    Map<String, double> totalDebitsByCurrency = {};
    Map<String, double> totalCreditsByCurrency = {};

    if (isAll) {
      filteredRows = List<StatementRow>.from(_rawRows);
      openingBalancesByCurrency = Map<String, double>.from(_rawOpeningBalancesByCurrency);
    } else {
      // SPECIFIC CURRENCY filter
      filteredRows = _rawRows.where((row) {
        if (row.type == 'opening' || row.type == 'initial') {
          return row.foreignCurrency == curFilter || (curFilter == 'EGP' && !row.isForeignCurrency);
        }
        return row.foreignCurrency == curFilter || (curFilter == 'EGP' && !row.isForeignCurrency);
      }).toList();

      final openingBal = _rawOpeningBalancesByCurrency[curFilter] ?? 0.0;
      openingBalancesByCurrency = {curFilter: openingBal};
    }

    // Compute running balance in EGP strictly across all filtered rows
    double running = 0.0;
    double totalDebitEgp = 0.0;
    double totalCreditEgp = 0.0;
    double openingBalanceEgp = 0.0;
    final updatedRows = <StatementRow>[];

    for (final row in filteredRows) {
      if (row.type == 'opening' || row.type == 'initial') {
        running += row.balance; // balance is already in EGP
        openingBalanceEgp += row.balance;
        updatedRows.add(row);
      } else {
        running += (row.credit - row.debit); // debit and credit are strictly in EGP
        totalDebitEgp += row.debit;
        totalCreditEgp += row.credit;
        updatedRows.add(row.copyWith(balance: running));

        // Track native currency totals for multi-currency profile breakdowns
        final cur = row.foreignCurrency ?? 'EGP';
        final fDebit = row.foreignDebit ?? (row.foreignCurrency == null ? row.debit : 0.0);
        final fCredit = row.foreignCredit ?? (row.foreignCurrency == null ? row.credit : 0.0);
        totalDebitsByCurrency[cur] = (totalDebitsByCurrency[cur] ?? 0.0) + fDebit;
        totalCreditsByCurrency[cur] = (totalCreditsByCurrency[cur] ?? 0.0) + fCredit;
      }
    }

    final double finalBalanceEgp = running;
    finalBalancesByCurrency = Map<String, double>.from(_rawOpeningBalancesByCurrency);
    for (final entry in totalCreditsByCurrency.entries) {
      final cur = entry.key;
      final cr = entry.value;
      final dr = totalDebitsByCurrency[cur] ?? 0.0;
      final prev = finalBalancesByCurrency[cur] ?? 0.0;
      finalBalancesByCurrency[cur] = prev + (cr - dr);
    }

    final statementNumber = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    emit(currentState.copyWith(
      statementRows: updatedRows,
      selectedCurrency: curFilter,
      availableCurrencies: _availableCurrencies,
      totalDebit: totalDebitEgp,
      totalCredit: totalCreditEgp,
      finalBalance: finalBalanceEgp,
      statementNumber: statementNumber,
      openingBalance: openingBalanceEgp,
      openingBalancesByCurrency: openingBalancesByCurrency,
      finalBalancesByCurrency: finalBalancesByCurrency,
      totalDebitsByCurrency: totalDebitsByCurrency,
      totalCreditsByCurrency: totalCreditsByCurrency,
      rowNotes: _savedNotes,
    ));
  }

  Future<List<Map<String, dynamic>>> _fetchPurchases(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('purchase_invoices')
        .select('*, purchase_invoice_items(*)')
        .eq('supplier_id', supplierId)
        .eq('status', 'confirmed');
    if (fromDate != null) query = query.gte('invoice_date', fromDate);
    if (toDate != null) query = query.lte('invoice_date', toDate);
    final data = await query.order('invoice_date', ascending: true);
    final purchases = List<Map<String, dynamic>>.from(data);

    // Collect all raw_material_ids from items
    final Set<String> materialIds = {};
    for (final p in purchases) {
      final items = p['purchase_invoice_items'] as List<dynamic>?;
      if (items != null) {
        for (final item in items) {
          final mId = item['raw_material_id']?.toString();
          if (mId != null && mId.isNotEmpty) {
            materialIds.add(mId);
          }
        }
      }
    }

    // Fetch raw materials map to avoid ambiguous postgrest joins
    Map<String, Map<String, dynamic>> materialMap = {};
    if (materialIds.isNotEmpty) {
      try {
        final rawMatData = await client
            .from('raw_materials')
            .select('id, name, code, unit')
            .inFilter('id', materialIds.toList());
        for (final rm in rawMatData) {
          materialMap[rm['id'].toString()] = Map<String, dynamic>.from(rm as Map);
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching raw materials for statement: $e');
      }
    }

    // Attach raw_material object to each item
    for (final p in purchases) {
      final items = p['purchase_invoice_items'] as List<dynamic>?;
      if (items != null) {
        final newItems = <Map<String, dynamic>>[];
        for (final item in items) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          final mId = itemMap['raw_material_id']?.toString();
          if (mId != null && materialMap.containsKey(mId)) {
            itemMap['raw_materials'] = materialMap[mId];
          }
          newItems.add(itemMap);
        }
        p['purchase_invoice_items'] = newItems;
      }
    }

    return purchases;
  }

  Future<List<Map<String, dynamic>>> _fetchLots(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client.from('lot_receipts').select('*').eq('supplier_id', supplierId).eq('is_confirmed', true);
    if (fromDate != null) query = query.gte('receipt_date', fromDate);
    if (toDate != null) query = query.lte('receipt_date', toDate);
    final data = await query.order('receipt_date', ascending: true);
    final lots = List<Map<String, dynamic>>.from(data);

    final Set<String> fruitTypeIds = {};
    for (final lot in lots) {
      final fId = lot['fruit_type_id']?.toString();
      if (fId != null && fId.isNotEmpty) fruitTypeIds.add(fId);
    }
    if (fruitTypeIds.isNotEmpty) {
      try {
        final fData = await client
            .from('fruit_types')
            .select('id, name')
            .inFilter('id', fruitTypeIds.toList());
        final fMap = {for (final f in fData) f['id'].toString(): f['name']?.toString() ?? ''};
        for (final lot in lots) {
          final fId = lot['fruit_type_id']?.toString();
          if (fId != null && fMap.containsKey(fId)) {
            lot['crop_name'] = fMap[fId];
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching fruit_types for statement: $e');
      }
    }
    return lots;
  }

  Future<List<Map<String, dynamic>>> _fetchSettlementCostItems(
      String supplierId, String? supplierCode) async {
    final client = Supabase.instance.client;
    try {
      String orFilter = 'supplier_id.eq.$supplierId,currency_snapshot->>supplier_id.eq.$supplierId';
      if (supplierCode != null && supplierCode.isNotEmpty && supplierCode != supplierId) {
        orFilter += ',supplier_id.eq.$supplierCode,currency_snapshot->>supplier_id.eq.$supplierCode';
      }
      final data = await client
          .from('packing_order_cost_items')
          .select('id, packing_order_id, name, cost_type, cost_status, expected_amount, base_amount, actual_amount, variance_amount, reconciled_at, variance_journal_entry_id, actual_quantity, actual_unit_price, detailed_notes, settlement_notes, invoice_ref, original_currency, supplier_id, currency_snapshot, deleted_at, created_at')
          .or(orFilter)
          .isFilter('deleted_at', null);
      return List<Map<String, dynamic>>.from(data)
          .where((row) => row['deleted_at'] == null)
          .toList();
    } catch (e) {
      debugPrint('⚠️ Error fetching settlement cost items for statement: $e');
      return [];
    }
  }

  static const Set<String> _packingCostLedgerRefTypes = {
    'packing_cost',
    'packing_cost_item',
    'packing_order_costs',
    'cost_settlement',
    'packing_cost_settlement',
  };

  /// Determines whether a packing_order_cost_items row represents a genuinely approved
  /// actual cost (vs an unsettled estimate or legacy false Stage-3 auto-lock).
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

  /// Normalizes ledger entries for dual-cost suppliers (station / deduction) so:
  /// 1. Unsettled / estimated packing_cost rows are excluded from financial credits & balances.
  /// 2. Any mixed estimated + variance rows for the same cost item collapse into ONE clean
  ///    credit entry equal strictly to the approved `actual_amount`.
  /// 3. Variance (saving/overrun) rows never inflate or reduce the supplier's closing balance.
  static List<Map<String, dynamic>> normalizeDualCostSupplierLedgerEntries({
    required List<Map<String, dynamic>> rawEntries,
    required Map<String, Map<String, dynamic>> costItemsById,
    required Map<String, Map<String, dynamic>> costItemsByOrderAndName,
    required Map<String, List<Map<String, dynamic>>> costItemsByOrder,
    required bool isDualCostSupplier,
    bool includeOnlyActualSettled = true,
    Set<String>? emittedCostItemIds,
  }) {
    if (!isDualCostSupplier) {
      return List<Map<String, dynamic>>.from(rawEntries);
    }

    final seenIds = emittedCostItemIds ?? <String>{};
    final normalized = <Map<String, dynamic>>[];

    // Index preferred settled metadata (e.g. cost_settlement row has actual_date_time / invoice_ref)
    final bestSettlementRowByKey = <String, Map<String, dynamic>>{};
    for (final entry in rawEntries) {
      final refType = entry['reference_type']?.toString().toLowerCase() ?? '';
      if (!_packingCostLedgerRefTypes.contains(refType)) continue;
      final matched = matchCostItemForSettlement(
        payment: entry,
        costItemsById: costItemsById,
        costItemsByOrderAndName: costItemsByOrderAndName,
        costItemsByOrder: costItemsByOrder,
      );
      if (matched == null || !isApprovedSettledCostItem(matched)) continue;
      final dedupKey = matched['id']?.toString() ??
          '${matched['packing_order_id'] ?? entry['reference_id']}_${matched['name'] ?? ''}';
      final isCanonical = refType == 'cost_settlement' || refType == 'packing_cost_settlement';
      if (isCanonical || !bestSettlementRowByKey.containsKey(dedupKey)) {
        bestSettlementRowByKey[dedupKey] = entry;
      }
    }

    for (final entry in rawEntries) {
      final refType = entry['reference_type']?.toString().toLowerCase() ?? '';
      if (!_packingCostLedgerRefTypes.contains(refType)) {
        normalized.add(entry);
        continue;
      }

      final matched = matchCostItemForSettlement(
        payment: entry,
        costItemsById: costItemsById,
        costItemsByOrderAndName: costItemsByOrderAndName,
        costItemsByOrder: costItemsByOrder,
      );

      if (matched != null) {
        if (includeOnlyActualSettled && !isApprovedSettledCostItem(matched)) {
          continue;
        }
        final actualAmt = (matched['actual_amount'] as num?)?.toDouble() ?? 0.0;
        if (actualAmt <= 0) continue;

        final dedupKey = matched['id']?.toString() ??
            '${matched['packing_order_id'] ?? entry['reference_id']}_${matched['name'] ?? ''}';
        if (seenIds.contains(dedupKey)) {
          continue;
        }
        seenIds.add(dedupKey);

        final sourceRow = bestSettlementRowByKey[dedupKey] ?? entry;
        final copy = Map<String, dynamic>.from(sourceRow);
        final rawDesc = sourceRow['description']?.toString() ?? '';
        final itemName = matched['name']?.toString().trim() ?? '';
        final poId = (matched['packing_order_id'] ?? sourceRow['reference_id'])?.toString() ?? '';
        final hasVarianceWording = rawDesc.contains('(وفر)') ||
            rawDesc.contains('وفر تكلفة') ||
            rawDesc.contains('وفر وتخفيض') ||
            rawDesc.contains('(زيادة)') ||
            rawDesc.contains('زيادة استحقاق') ||
            rawDesc.startsWith('بند تكلفة');

        copy['entry_type'] = 'credit';
        copy['reference_type'] = 'cost_settlement';
        copy['amount'] = actualAmt;
        if (rawDesc.isEmpty || hasVarianceWording) {
          copy['description'] =
              'اعتماد تكلفة فعلية بند: ${itemName.isNotEmpty ? itemName : 'تكلفة'}${poId.isNotEmpty ? ' (أمر #$poId)' : ''}';
        }
        normalized.add(copy);
        continue;
      }

      // Unmatched entry on a dual-cost supplier: exclude estimated packing_cost and variance adjustments
      final entryType = entry['entry_type']?.toString().toLowerCase() ?? '';
      final rawDesc = entry['description']?.toString() ?? '';
      if (refType == 'packing_cost' ||
          refType == 'packing_cost_item' ||
          refType == 'packing_order_costs') {
        if (includeOnlyActualSettled) continue;
      }
      final isVarianceOrDebit = entryType == 'debit' ||
          rawDesc.contains('(وفر)') ||
          rawDesc.contains('وفر') ||
          rawDesc.contains('تخفيض تكلفة') ||
          rawDesc.contains('(زيادة)') ||
          rawDesc.contains('زيادة استحقاق');
      if (isVarianceOrDebit) {
        continue;
      }
      normalized.add(entry);
    }

    return normalized;
  }

  /// Matches a settlement ledger payment entry against fetched packing_order_cost_items
  static Map<String, dynamic>? matchCostItemForSettlement({
    required Map<String, dynamic> payment,
    required Map<String, Map<String, dynamic>> costItemsById,
    required Map<String, Map<String, dynamic>> costItemsByOrderAndName,
    required Map<String, List<Map<String, dynamic>>> costItemsByOrder,
  }) {
    final snap = payment['currency_snapshot'];
    if (snap is Map) {
      final snapCostItemId = snap['cost_item_id']?.toString();
      if (snapCostItemId != null && snapCostItemId.isNotEmpty && costItemsById.containsKey(snapCostItemId)) {
        return costItemsById[snapCostItemId];
      }
    }

    final refId = payment['reference_id']?.toString() ?? '';
    final refText = payment['reference_text']?.toString() ?? '';
    final rawDesc = payment['description']?.toString() ?? '';

    if (costItemsById.containsKey(refId)) {
      return costItemsById[refId];
    }
    if (refText.isNotEmpty && costItemsByOrderAndName.containsKey('${refId}_$refText')) {
      return costItemsByOrderAndName['${refId}_$refText'];
    }
    if (costItemsByOrder.containsKey(refId)) {
      final candidates = costItemsByOrder[refId]!;
      return candidates.where((c) {
        final name = c['name']?.toString() ?? '';
        final inv = c['invoice_ref']?.toString() ?? '';
        return (name.isNotEmpty && rawDesc.contains(name)) ||
            (inv.isNotEmpty && (rawDesc.contains(inv) || refText == inv));
      }).firstOrNull ?? (candidates.length == 1 ? candidates.first : null);
    }
    return null;
  }

  /// Enriches description, quantity, and unitPrice for a cost settlement statement row
  static ({String description, double quantity, double unitPrice}) enrichSettlementStatementDetails({
    required String rawDesc,
    required String fallbackDesc,
    required String refId,
    required bool isCredit,
    required double amount,
    Map<String, dynamic>? matchedCostItem,
  }) {
    String enrichedDesc = fallbackDesc;
    double itemQty = 0.0;
    double itemUnitPrice = 0.0;

    if (matchedCostItem != null) {
      final notes = (matchedCostItem['detailed_notes'] ??
              matchedCostItem['settlement_notes'] ??
              matchedCostItem['notes'])
          ?.toString()
          .trim();
      final invRef = matchedCostItem['invoice_ref']?.toString().trim();
      final itemName = matchedCostItem['name']?.toString() ?? '';
      itemQty = (matchedCostItem['actual_quantity'] as num?)?.toDouble() ?? 0.0;
      itemUnitPrice = (matchedCostItem['actual_unit_price'] as num?)?.toDouble() ?? 0.0;

      if (rawDesc.isEmpty ||
          rawDesc == 'سند صرف للمورد' ||
          rawDesc == 'سند قبض من مورد' ||
          rawDesc == 'تسوية تكلفة فعلية - زيادة استحقاق للمورد' ||
          rawDesc == 'تسوية تكلفة فعلية - وفر وتخفيض تكلفة') {
        enrichedDesc = isCredit
            ? 'تسوية تكلفة فعلية (زيادة) بند: $itemName${refId.isNotEmpty ? ' (أمر #$refId)' : ''}'
            : 'تسوية تكلفة فعلية (وفر) بند: $itemName${refId.isNotEmpty ? ' (أمر #$refId)' : ''}';
      }

      if (notes != null && notes.isNotEmpty && !enrichedDesc.contains(notes)) {
        enrichedDesc = '$enrichedDesc - $notes';
      }
      if (invRef != null && invRef.isNotEmpty && !enrichedDesc.contains(invRef)) {
        enrichedDesc = '$enrichedDesc - مستند: $invRef';
      }
    }

    final resolvedPrice = itemUnitPrice > 0
        ? itemUnitPrice
        : (itemQty > 0 && amount > 0 ? (amount / itemQty) : 0.0);

    return (
      description: enrichedDesc,
      quantity: itemQty > 0 ? itemQty : 0.0,
      unitPrice: resolvedPrice,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(
      String supplierCode, String? supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    
    // We search by either supplierCode or supplierId
    String orFilter = 'entity_id.eq.$supplierCode';
    if (supplierId != null && supplierId.isNotEmpty) {
      orFilter += ',entity_id.eq.$supplierId';
    }

    var query = client
        .from('ledger_entries')
        .select('*')
        .eq('entity_type', 'supplier')
        .or(orFilter);
        
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchTreasuryTx(String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('treasury_transactions')
        .select('*')
        .eq('supplier_id', supplierId)
        .neq('status', 'draft');
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    final txs = List<Map<String, dynamic>>.from(data);

    final Set<String> treasuryIds = {};
    for (final tx in txs) {
      final tId = tx['treasury_id']?.toString();
      if (tId != null && tId.isNotEmpty) treasuryIds.add(tId);
    }
    if (treasuryIds.isNotEmpty) {
      try {
        final tData = await client
            .from('treasuries')
            .select('id, name')
            .inFilter('id', treasuryIds.toList());
        final tMap = {for (final t in tData) t['id'].toString(): t['name']?.toString() ?? ''};
        for (final tx in txs) {
          final tId = tx['treasury_id']?.toString();
          if (tId != null && tMap.containsKey(tId)) {
            tx['treasury_name'] = tMap[tId];
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching treasuries for statement: $e');
      }
    }
    return txs;
  }

  Future<List<Map<String, dynamic>>> _fetchCheques(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('cheques')
        .select('*')
        .eq('counterparty_type', 'supplier')
        .eq('supplier_id', supplierId)
        .inFilter('status', ['cleared', 'collected']);
    if (fromDate != null) query = query.gte('cleared_at', fromDate);
    if (toDate != null) query = query.lte('cleared_at', '${toDate}T23:59:59');
    final data = await query.order('cleared_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchBankTx(
      String supplierId, String? supplierCode, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('bank_account_transactions')
          .select('*, bank_accounts(id, name, name_en, currency)')
          .eq('entity_type', 'supplier');

      if (supplierCode != null && supplierCode.isNotEmpty && supplierCode != supplierId) {
        query = query.or('entity_id.eq.$supplierId,entity_id.eq.$supplierCode');
      } else {
        query = query.eq('entity_id', supplierId);
      }

      query = query
          .neq('status', 'draft')
          .neq('status', 'cancelled');
          
      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', '${toDate}T23:59:59');
      }
      final data = await query.order('created_at', ascending: true);
      final txs = List<Map<String, dynamic>>.from(data);

      for (final tx in txs) {
        final ba = tx['bank_accounts'] as Map<String, dynamic>?;
        if (ba != null) {
          tx['bank_name'] = (ba['name'] ?? ba['name_en'] ?? '').toString();
          final cur = ba['currency']?.toString();
          if (cur != null && cur.isNotEmpty) {
            tx['currency'] = cur.toUpperCase();
          }
        }
      }

      final Set<String> bankIds = {};
      for (final tx in txs) {
        if (tx['currency'] == null || tx['currency'].toString().isEmpty || tx['bank_name'] == null) {
          final bId = tx['bank_account_id']?.toString();
          if (bId != null && bId.isNotEmpty) bankIds.add(bId);
        }
      }
      if (bankIds.isNotEmpty) {
        try {
          final bData = await client
              .from('bank_accounts')
              .select('id, name, name_en, currency')
              .inFilter('id', bankIds.toList());
          final bMap = {
            for (final b in bData)
              b['id'].toString(): {
                'name': (b['name'] ?? b['name_en'] ?? '').toString(),
                'currency': (b['currency'] ?? 'EGP').toString().toUpperCase(),
              }
          };
          for (final tx in txs) {
            final bId = tx['bank_account_id']?.toString();
            if (bId != null && bMap.containsKey(bId)) {
              tx['bank_name'] ??= bMap[bId]!['name'];
              tx['currency'] ??= bMap[bId]!['currency'];
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching bank accounts for statement: $e');
        }
      }
      return txs;
    } catch (e, st) {
      debugPrint('⚠️ _fetchBankTx error: $e\n$st');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NARRATIVE BUILDERS FOR ENRICHED STATEMENT ROWS (البيان)
  // ─────────────────────────────────────────────────────────────────────────

  String _formatNumber(num value, [int maxDecimals = 2]) {
    final str = value.toStringAsFixed(maxDecimals);
    final parts = str.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    if (parts.length > 1) {
      final dec = parts[1].replaceAll(RegExp(r'0+$'), '');
      if (dec.isNotEmpty) {
        return '$intPart.$dec';
      }
    }
    return intPart;
  }

  String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'EGP':
        return 'ج.م';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      case 'GBP':
        return '£';
      default:
        return currency;
    }
  }

  String _buildMaterialPurchaseDescription(Map<String, dynamic> purchase) {
    final invoiceNo = purchase['invoice_number']?.toString() ?? purchase['id']?.toString() ?? '';
    final cur = purchase['currency']?.toString() ?? 'EGP';
    final curSymbol = _getCurrencySymbol(cur);
    final items = purchase['purchase_invoice_items'] as List<dynamic>?;

    if (items != null && items.isNotEmpty) {
      final allItemDescriptions = <String>[];
      for (final it in items) {
        final item = it as Map<String, dynamic>;
        final rm = item['raw_materials'] as Map<String, dynamic>?;
        final name = rm?['name']?.toString() ?? item['item_name']?.toString() ?? 'صنف خامات';
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final unit = (rm?['unit'] ?? item['unit'] ?? '').toString();
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? (item['unit_cost'] as num?)?.toDouble() ?? 0;
        final unitStr = unit.isNotEmpty ? ' $unit' : '';

        allItemDescriptions.add(
          '$name (${_formatNumber(qty)}$unitStr بسعر ${_formatNumber(unitPrice)} $curSymbol)',
        );
      }

      String itemSummary;
      if (allItemDescriptions.length <= 3) {
        itemSummary = allItemDescriptions.join(' + ');
      } else {
        itemSummary = '${allItemDescriptions.take(3).join(' + ')} (+ ${allItemDescriptions.length - 3} أصناف أخرى)';
      }

      final notes = purchase['notes']?.toString();
      final notesPart = (notes != null && notes.trim().isNotEmpty && notes.trim() != 'مشتريات')
          ? ' - ${notes.trim()}'
          : '';

      return 'فاتورة مشتريات خامات #$invoiceNo: $itemSummary$notesPart';
    }

    final totalAmt = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
    final notes = purchase['notes']?.toString();
    if (notes != null && notes.trim().isNotEmpty) {
      return 'فاتورة مشتريات #$invoiceNo (${notes.trim()})';
    }
    return 'فاتورة مشتريات خامات #$invoiceNo بمبلغ ${_formatNumber(totalAmt)} $curSymbol';
  }

  String _buildCropPurchaseDescription(Map<String, dynamic> lot) {
    final lotNo = lot['lot_number']?.toString() ?? lot['id']?.toString() ?? '';
    final cur = lot['currency']?.toString() ?? 'USD';
    final curSymbol = _getCurrencySymbol(cur);
    final cropName = lot['crop_name']?.toString() ??
        lot['product_name']?.toString() ??
        lot['crop_type']?.toString() ??
        'محصول';
    final isCarton = (lot['purchase_mode'] ?? 'weight') == 'carton';

    String desc;
    if (isCarton) {
      final cartons = (lot['carton_count'] as num?)?.toDouble() ?? 0;
      final pricePerCarton = (lot['price_per_carton'] as num?)?.toDouble() ?? 0;
      final gross = (lot['gross_weight_kg'] as num?)?.toDouble() ?? 0;
      final net = (lot['net_weight_kg'] as num?)?.toDouble() ?? 0;

      String weightSub = '';
      if (gross > 0 || net > 0) {
        weightSub = ' [إجمالي: ${_formatNumber(gross)} كجم، صافي: ${_formatNumber(net)} كجم]';
      }

      desc = 'شراء محصول $cropName - ${_formatNumber(cartons)} كرتونة بسعر ${_formatNumber(pricePerCarton)} $curSymbol$weightSub (لوط: $lotNo)';
    } else {
      final gross = (lot['gross_weight_kg'] as num?)?.toDouble() ?? 0;
      final net = (lot['net_weight_kg'] as num?)?.toDouble() ?? 0;
      final pricePerKg = (lot['price_per_kg'] as num?)?.toDouble() ??
          (lot['product_cost_per_kg'] as num?)?.toDouble() ??
          (lot['fruit_cost_per_kg'] as num?)?.toDouble() ??
          0;

      if (gross > 0 && net > 0 && (gross - net).abs() > 0.01) {
        desc = 'شراء محصول $cropName - ${_formatNumber(gross)} كجم (إجمالي مالي) بسعر ${_formatNumber(pricePerKg)} $curSymbol [صافي المخزن: ${_formatNumber(net)} كجم] (لوط: $lotNo)';
      } else {
        final weight = gross > 0 ? gross : net;
        desc = 'شراء محصول $cropName - ${_formatNumber(weight)} كجم بسعر ${_formatNumber(pricePerKg)} $curSymbol (لوط: $lotNo)';
      }
    }

    final notes = lot['notes']?.toString().trim();
    if (notes != null && notes.isNotEmpty) {
      desc += ' - $notes';
    }

    return desc;
  }

  String _buildTreasuryDescription(Map<String, dynamic> tx) {
    final isCredit = tx['type']?.toString() == 'deposit' ||
        tx['type']?.toString() == 'receive' ||
        tx['type']?.toString() == 'income';
    final rawDesc = (tx['description'] ?? tx['notes'] ?? '').toString().trim();
    final treasuryName = (tx['treasury_name'] ?? '').toString().trim();
    final receiptNo = (tx['receipt_number'] ?? '').toString().trim();

    final treasurySuffix = treasuryName.isNotEmpty ? ' (خزينة: $treasuryName)' : '';
    final receiptSuffix = receiptNo.isNotEmpty ? ' [إيصال: $receiptNo]' : '';

    if (rawDesc.isNotEmpty && rawDesc != 'سداد مورد' && rawDesc != 'صرف لمورد' && rawDesc != 'توريد مورد' && rawDesc != 'إيداع مورد') {
      return '$rawDesc$treasurySuffix$receiptSuffix';
    }

    if (isCredit) {
      return 'إيداع نقدي / دفعة مقدمة من المورد$treasurySuffix$receiptSuffix';
    } else {
      return 'سداد نقدي للمورد$treasurySuffix$receiptSuffix';
    }
  }

  String _buildChequeDescription(Map<String, dynamic> cheque) {
    final isIncoming = cheque['type']?.toString() == 'incoming';
    final chequeNo = (cheque['cheque_number'] ?? cheque['id'] ?? '').toString().trim();
    final bank = (cheque['bank_name'] ?? cheque['bank'] ?? '').toString().trim();
    final dueDateRaw = cheque['due_date'];
    final dueDate = dueDateRaw != null ? _toLocalDate(dueDateRaw) : '';
    final bankSuffix = bank.isNotEmpty ? ' مسحوب على بنك $bank' : '';
    final dueSuffix = dueDate.isNotEmpty ? ' استحقاق $dueDate' : '';
    final notes = (cheque['notes'] ?? '').toString().trim();
    final notesSuffix = notes.isNotEmpty ? ' ($notes)' : '';

    if (isIncoming) {
      return 'شيك وارد من المورد رقم $chequeNo$bankSuffix$dueSuffix$notesSuffix';
    } else {
      return 'شيك صادر للمورد رقم $chequeNo$bankSuffix$dueSuffix$notesSuffix';
    }
  }

  String _buildBankDescription(Map<String, dynamic> tx) {
    final type = tx['type']?.toString() ?? '';
    final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
    final bankName = (tx['bank_name'] ?? '').toString().trim();
    final refNo = (tx['reference_number'] ?? tx['cheque_number'] ?? tx['id'] ?? '').toString().trim();
    final rawDesc = (tx['description'] ?? tx['notes'] ?? '').toString().trim();
    final bankSuffix = bankName.isNotEmpty ? ' عبر بنك: $bankName' : '';
    final refSuffix = refNo.isNotEmpty && refNo != '-' ? ' [مرجع: $refNo]' : '';

    if (rawDesc.isNotEmpty && rawDesc != 'تحويل بنكي' && rawDesc != 'سداد بنكي') {
      return '$rawDesc$bankSuffix$refSuffix';
    }

    if (isCredit) {
      return 'إيداع / تحويل بنكي من المورد$bankSuffix$refSuffix';
    } else {
      return 'سداد / تحويل بنكي للمورد$bankSuffix$refSuffix';
    }
  }

  String _buildInitialBalanceDescription(String cur, double bal, bool isMulti) {
    final curSymbol = _getCurrencySymbol(cur);
    final absBal = _formatNumber(bal.abs());
    final multiLabel = isMulti ? ' ($cur)' : '';
    if (bal > 0) {
      return 'رصيد افتتاحي مستحق للمورد (دائن) بـ $absBal $curSymbol$multiLabel';
    } else if (bal < 0) {
      return 'رصيد افتتاحي مستحق على المورد (مدين) بـ $absBal $curSymbol$multiLabel';
    } else {
      return 'رصيد افتتاحي متوازن$multiLabel';
    }
  }

  String _buildOpeningBalanceDescription(String cur, double bal, String fromDate, bool isMulti) {
    final curSymbol = _getCurrencySymbol(cur);
    final absBal = _formatNumber(bal.abs());
    final multiLabel = isMulti ? ' ($cur)' : '';
    if (bal > 0) {
      return 'رصيد سابق مستحق للمورد حتى $fromDate (دائن) بـ $absBal $curSymbol$multiLabel';
    } else if (bal < 0) {
      return 'رصيد سابق مستحق على المورد حتى $fromDate (مدين) بـ $absBal $curSymbol$multiLabel';
    } else {
      return 'رصيد سابق حتى $fromDate متوازن$multiLabel';
    }
  }

  void setRowNote(String transactionNumber, String note) {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      final newNotes = Map<String, String>.from(currentState.rowNotes);
      if (note.isEmpty) {
        newNotes.remove(transactionNumber);
      } else {
        newNotes[transactionNumber] = note;
      }
      emit(currentState.copyWith(rowNotes: newNotes));

      if (currentState.selectedSupplier?.id != null) {
        _notesDao.upsertNote(
          entityType: 'supplier',
          entityId: currentState.selectedSupplier!.id!.toString(),
          referenceId: transactionNumber,
          note: note,
        );
      }
    }
  }

  void reset() {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      final now = DateTime.now();
      _rawRows = [];
      _rawOpeningBalancesByCurrency = {};
      _availableCurrencies = ['ALL', 'EGP'];
      _savedNotes = {};
      emit(currentState.copyWith(
        clearSelectedSupplier: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        openingBalance: 0,
        selectedCurrency: 'ALL',
        availableCurrencies: const ['ALL', 'EGP'],
        openingBalancesByCurrency: const {},
        finalBalancesByCurrency: const {},
        totalDebitsByCurrency: const {},
        totalCreditsByCurrency: const {},
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    }
    refreshData();
  }

  String _toLocalDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString().substring(0, raw.toString().length >= 10 ? 10 : raw.toString().length);
    }
  }
}