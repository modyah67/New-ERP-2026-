import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/invoice_dao.dart';
import '../../data/dao/statement_notes_dao.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import 'export_customer_statement_state.dart';

class ExportCustomerStatementCubit
    extends Cubit<ExportCustomerStatementState> {
  final CustomerDao _customerDao = CustomerDao();
  final InvoiceDao _invoiceDao = InvoiceDao();
  final StatementNotesDao _notesDao = StatementNotesDao();

  ExportCustomerStatementCubit()
      : super(const ExportCustomerStatementInitial()) {
    _init();
  }

  Future<void> init() => _init();

  Future<void> _init() async {
    try {
      final customers = await _customerDao.getAll(limit: 2000, offset: 0);
      final now = DateTime.now();
      if (!isClosed) {
        emit(ExportCustomerStatementLoaded(
          customers: customers,
          statementRows: const [],
          totalDebit: 0,
          totalCredit: 0,
          finalBalance: 0,
          statementNumber: 0,
          fromDate: DateTime(now.year, now.month, 1),
          toDate: now,
        ));
      }
    } catch (e) {
      if (!isClosed) emit(ExportCustomerStatementError(message: 'فشل تحميل العملاء: $e'));
    }
  }

  void setCustomerTypeFilter(String filter) {
    final currentState = state;
    if (currentState is! ExportCustomerStatementLoaded) return;
    if (currentState.customerTypeFilter == filter) return;

    bool clearSelected = false;
    if (currentState.selectedCustomer != null) {
      final isLocal = currentState.selectedCustomer!.customerType == 'local';
      if (filter == 'local' && !isLocal) clearSelected = true;
      if (filter == 'export' && isLocal) clearSelected = true;
    }

    emit(currentState.copyWith(
      customerTypeFilter: filter,
      clearSelectedCustomer: clearSelected,
      statementRows: clearSelected ? [] : null,
      totalDebit: clearSelected ? 0 : null,
      totalCredit: clearSelected ? 0 : null,
      finalBalance: clearSelected ? 0 : null,
    ));
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is ExportCustomerStatementLoaded) {
      try {
        final customers = await _customerDao.getAll(limit: 2000, offset: 0);
        emit(currentState.copyWith(customers: customers));
      } catch (e) {
        emit(ExportCustomerStatementError(message: 'فشل تحميل البيانات: $e'));
      }
    }
  }

  Future<void> selectCustomer(CustomerModel? customer) async {
    final currentState = state;
    if (currentState is ExportCustomerStatementLoaded) {
      emit(currentState.copyWith(
        selectedCustomer: customer,
        clearSelectedCustomer: customer == null,
      ));
      if (customer != null) await loadStatement();
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! ExportCustomerStatementLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      emit(currentState.copyWith(fromDate: picked));
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! ExportCustomerStatementLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      emit(currentState.copyWith(toDate: picked));
    }
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! ExportCustomerStatementLoaded) return;
    if (currentState.selectedCustomer == null) return;

    // Emit loading state with current data preserved
    emit(currentState.copyWith(statementRows: [], totalDebit: 0, totalCredit: 0, finalBalance: 0));

    try {
      final customerId = currentState.selectedCustomer!.id!;
      final customerCurrency =
          currentState.selectedCustomer!.currency.isNotEmpty
              ? currentState.selectedCustomer!.currency
              : 'EGP';
      final from = currentState.fromDate != null
          ? AppUtils.formatDateForDb(currentState.fromDate!)
          : null;
      final to = currentState.toDate != null
          ? AppUtils.formatDateForDb(currentState.toDate!)
          : null;

      debugPrint('🔍 ExportStatement: Loading for customer $customerId, currency=$customerCurrency, from=$from, to=$to');

      // 1. Fetch export shipments for this customer
      final shipments = await _fetchShipments(customerId, from, to);
      debugPrint('📦 ExportStatement: Found ${shipments.length} shipments');

      // 1.5. Fetch local invoices for this customer
      final invoices = await _fetchInvoices(customerId, from, to);
      debugPrint('🧾 ExportStatement: Found ${invoices.length} invoices');

      // 2. Fetch payments from ledger_entries for this customer
      final payments = await _fetchPayments(customerId, from, to);
      debugPrint('💰 ExportStatement: Found ${payments.length} payments');

      // 3. Fetch cheques for this customer (incoming = customer paid us)
      final cheques = await _fetchCheques(customerId, from, to);
      debugPrint('🧾 ExportStatement: Found ${cheques.length} cheques');

      // 4. Fetch treasury transactions (expense/receive)
      final treasuryTxs = await _fetchTreasuryTx(customerId, from, to);
      debugPrint('🏦 ExportStatement: Found ${treasuryTxs.length} treasury txs');

      // 4.5. Fetch bank transactions
      final bankTxs = await _fetchBankTx(customerId, from, to);
      debugPrint('💳 ExportStatement: Found ${bankTxs.length} bank txs');

      // 4.8. Fetch general ledger journal entries (cash receipts, payments, sorting sales, settlements)
      final glEntries = await _fetchGlEntries(customerId, currentState.selectedCustomer!.accountId, from, to);
      debugPrint('📑 ExportStatement: Found ${glEntries.length} gl entries');

      // 5. Build statement rows
      final rows = <StatementRow>[];

      // 6. Calculate opening balance
      double openingBalance = currentState.selectedCustomer!.initialBalance;

      if (from != null) {
        final beforeDate = currentState.fromDate!.subtract(const Duration(days: 1));
        final beforeStr = AppUtils.formatDateForDb(beforeDate);
        final results = await Future.wait([
          _fetchShipments(customerId, null, beforeStr),
          _fetchPayments(customerId, null, beforeStr),
          _fetchCheques(customerId, null, beforeStr),
          _fetchTreasuryTx(customerId, null, beforeStr),
          _fetchBankTx(customerId, null, beforeStr),
          _fetchInvoices(customerId, null, beforeStr),
          _fetchGlEntries(customerId, currentState.selectedCustomer!.accountId, null, beforeStr),
        ]);
        final priorShipments = results[0] as List<ExportShipmentModel>;
        final priorPayments = results[1] as List<Map<String, dynamic>>;
        final priorCheques = results[2] as List<Map<String, dynamic>>;
        final priorTreasuryTxs = results[3] as List<Map<String, dynamic>>;
        final priorBankTxs = results[4] as List<Map<String, dynamic>>;
        final priorInvoices = results[5] as List<InvoiceModel>;
        final priorGlEntries = results[6] as List<Map<String, dynamic>>;

        final priorTreasuryIds = priorTreasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();
        final priorBankTxIds = priorBankTxs.map((tx) => tx['id']?.toString() ?? '').toSet();
        final priorGlJeIds = priorGlEntries
            .map((gl) => (gl['journal_entry_id'] ?? gl['entry_id'])?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();

        for (final s in priorShipments) {
          openingBalance += await _getShipmentAmountFromItems(s.id, s, customerCurrency);
          if (s.discountAmount > 0) {
            openingBalance -= s.discountAmount;
          }
        }
        for (final inv in priorInvoices) {
          if (inv.type == 'return') {
            openingBalance -= inv.netAmount;
          } else {
            openingBalance += inv.netAmount;
          }
        }
        for (final p in priorPayments) {
          final refId = p['reference_id']?.toString() ?? '';
          if (refId.isNotEmpty && (priorTreasuryIds.contains(refId) || priorBankTxIds.contains(refId))) continue;
          final isCredit = p['entry_type']?.toString() == 'credit';
          final amt = _getPaymentAmount(p);
          openingBalance += isCredit ? -amt : amt;
        }
        for (final ch in priorCheques) {
          openingBalance -= _getChequeAmount(ch);
        }
        for (final tx in priorTreasuryTxs) {
          final jeId = tx['journal_entry_id']?.toString() ?? '';
          if (jeId.isNotEmpty && priorGlJeIds.contains(jeId)) continue;
          final isCredit = tx['type']?.toString() == 'deposit' || tx['type']?.toString() == 'receive' || tx['type']?.toString() == 'income';
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          openingBalance += isCredit ? -amt : amt;
        }
        for (final tx in priorBankTxs) {
          final isCredit = tx['type']?.toString() == 'deposit';
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          openingBalance += isCredit ? -amt : amt;
        }
        for (final gl in priorGlEntries) {
          final sType = gl['source_type']?.toString() ?? '';
          if (sType == 'opening_balance' ||
              sType == 'export_shipment' ||
              sType == 'shipment' ||
              sType == 'invoice' ||
              sType == 'sales_invoice' ||
              sType == 'invoice_return' ||
              sType == 'cheque' ||
              sType == 'cheque_clearance' ||
              sType == 'treasury_tx' ||
              sType == 'bank_tx') {
            continue;
          }
          final debit = (gl['debit'] as num?)?.toDouble() ?? 0.0;
          final credit = (gl['credit'] as num?)?.toDouble() ?? 0.0;
          final isCredit = credit > 0;
          final amt = isCredit ? credit : debit;
          openingBalance += isCredit ? -amt : amt;
        }
      }

      // Add initial balance row only when no date filter
      if (from == null && currentState.selectedCustomer!.initialBalance != 0) {
        final initRow = StatementRow(
          transactionNumber: '-',
          date: '',
          accountName: 'رصيد افتتاحي',
          description: 'رصيد افتتاحي',
          debit: currentState.selectedCustomer!.initialBalance > 0 ? currentState.selectedCustomer!.initialBalance : 0,
          credit: currentState.selectedCustomer!.initialBalance < 0 ? currentState.selectedCustomer!.initialBalance.abs() : 0,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          balance: currentState.selectedCustomer!.initialBalance,
          type: 'initial',
          createdAt: '',
        );
        rows.insert(0, initRow);
      }

      // Add export shipments as debit rows
      for (final shipment in shipments) {
        final amount = await _getShipmentAmountFromItems(shipment.id, shipment, customerCurrency);
        final products = await _getShipmentProducts(shipment.id);
        final productNames = products.isNotEmpty ? products.join('، ') : '—';
        final dateToUse = shipment.shipmentDate ?? shipment.createdAt ?? DateTime.now();
        final shipDate = AppUtils.formatDate(dateToUse);

        rows.add(StatementRow(
          transactionNumber: AppUtils.cleanShipmentNo(shipment.shipmentNo, shipment.id),
          date: shipDate,
          accountName: 'شحنة تصدير',
          description: productNames,
          piecesCount: shipment.cartonsCount.toDouble(),
          quantity: 0,
          unitPrice: 0,
          debit: amount,
          credit: 0,
          balance: 0,
          type: 'shipment',
          createdAt: shipment.createdAt?.toIso8601String() ?? '',
        ));

        if (shipment.discountAmount > 0) {
          final discountReason = shipment.discountReason?.isNotEmpty == true ? ' (${shipment.discountReason})' : '';
          rows.add(StatementRow(
            transactionNumber: AppUtils.cleanShipmentNo(shipment.shipmentNo, shipment.id),
            date: shipDate,
            accountName: 'خصم مسموح به',
            description: 'خصم على شحنة تصدير$discountReason',
            piecesCount: 0,
            quantity: 0,
            unitPrice: 0,
            debit: 0,
            credit: shipment.discountAmount,
            balance: 0,
            type: 'discount',
            createdAt: shipment.createdAt?.toIso8601String() ?? '',
          ));
        }
      }

      // Add local invoices as debit/credit rows
      for (final inv in invoices) {
        final isReturn = inv.type == 'return';
        final invDate = inv.invoiceDate;
        rows.add(StatementRow(
          transactionNumber: 'فاتورة #${inv.invoiceNumber}',
          date: invDate,
          accountName: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
          description: inv.notes?.isNotEmpty == true ? inv.notes! : (isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات محلي'),
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isReturn ? 0 : inv.netAmount,
          credit: isReturn ? inv.netAmount : 0,
          balance: 0,
          type: isReturn ? 'invoice_return' : 'invoice',
          createdAt: inv.createdAt,
        ));
      }

      // Add payments as credit/debit rows
      // Fetch treasury txs first for dedup
      final currentTreasuryIds = treasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();
      final currentBankTxIds = bankTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

      for (final payment in payments) {
        final refId = payment['reference_id']?.toString() ?? '';
        if (refId.isNotEmpty && (currentTreasuryIds.contains(refId) || currentBankTxIds.contains(refId))) continue;
        final amount = _getPaymentAmount(payment);
        final paymentDate = _toLocalDate(payment['created_at']);
        final refType = payment['reference_type']?.toString() ?? '';
        final entryType = payment['entry_type']?.toString() ?? 'credit';
        final isCredit = entryType == 'credit';
        final description = payment['description']?.toString() ?? 
            (refType == 'cheque_cleared_incoming' ? 'سند قبض شيك' :
             refType == 'receive' ? 'استلام' :
             refType == 'expense' ? 'مصروف' : 'سند قبض');

        rows.add(StatementRow(
          transactionNumber: (payment['reference_text']?.toString().isNotEmpty == true)
              ? payment['reference_text'].toString()
              : (payment['id']?.toString() ?? '—'),
          date: paymentDate,
          accountName: isCredit ? 'سند قبض' : 'مصروف',
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: 'payment',
          createdAt: (payment['created_at'] ?? '').toString(),
        ));
      }

      // Add cheques (incoming = credit, outgoing = debit)
      for (final cheque in cheques) {
        final amount = _getChequeAmount(cheque);
        final chequeNum = cheque['cheque_number']?.toString() ?? '';
        final issueDate = (cheque['issue_date'] ?? '').toString();
        final chequeType = cheque['type']?.toString() ?? 'incoming';
        final isIncoming = chequeType == 'incoming';

        rows.add(StatementRow(
          transactionNumber: chequeNum,
          date: issueDate,
          accountName: isIncoming ? 'شيك وارد' : 'شيك صادر',
          description: isIncoming ? 'شيك وارد رقم $chequeNum' : 'شيك صادر رقم $chequeNum',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isIncoming ? 0 : amount,
          credit: isIncoming ? amount : 0,
          balance: 0,
          type: 'cheque',
          createdAt: (cheque['created_at'] ?? '').toString(),
        ));
      }

      final currentGlJeIds = glEntries
          .map((gl) => (gl['journal_entry_id'] ?? gl['entry_id'])?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // Add general ledger journal entries (cash receipts, payments, sorting sales, settlements)
      for (final gl in glEntries) {
        final sType = gl['source_type']?.toString() ?? '';
        if (sType == 'opening_balance' ||
            sType == 'export_shipment' ||
            sType == 'shipment' ||
            sType == 'invoice' ||
            sType == 'sales_invoice' ||
            sType == 'invoice_return' ||
            sType == 'cheque' ||
            sType == 'cheque_clearance' ||
            sType == 'treasury_tx' ||
            sType == 'bank_tx') {
          continue;
        }

        final debit = (gl['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (gl['credit'] as num?)?.toDouble() ?? 0.0;
        final isCredit = credit > 0;
        final amount = isCredit ? credit : debit;
        if (amount == 0) continue;

        final entryNumber = gl['entry_number']?.toString() ?? gl['id']?.toString() ?? '—';
        final txDate = gl['transaction_date'] != null
            ? gl['transaction_date'].toString()
            : _toLocalDate(gl['created_at']);
        final desc = gl['description']?.toString() ?? '';

        String accountName;
        if (sType == 'cash_receipt' || sType == 'receipt') {
          accountName = 'سند قبض';
        } else if (sType == 'cash_payment' || sType == 'payment') {
          accountName = 'سند صرف';
        } else if (sType == 'sale_sorting' || sType == 'sorting_sale') {
          accountName = isCredit ? 'سداد بيع فرز' : 'مديونية بيع فرز';
        } else {
          accountName = isCredit ? 'سند قبض / قيد تسوية' : 'سند صرف / قيد تسوية';
        }

        rows.add(StatementRow(
          transactionNumber: entryNumber,
          date: txDate,
          accountName: accountName,
          description: desc.isNotEmpty ? desc : accountName,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: isCredit ? 'cash_receipt' : 'cash_payment',
          createdAt: (gl['created_at'] ?? '').toString(),
        ));
      }

      // Add treasury transactions (skipping any that were already represented in GL entries)
      for (final tx in treasuryTxs) {
        final jeId = tx['journal_entry_id']?.toString() ?? '';
        if (jeId.isNotEmpty && currentGlJeIds.contains(jeId)) continue;

        final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
        final txDate = _toLocalDate(tx['created_at']);
        final typeStr = tx['type']?.toString() ?? 'deposit';
        final isCredit = typeStr == 'deposit' || typeStr == 'receive' || typeStr == 'income';
        final description = tx['description']?.toString() ?? (isCredit ? 'استلام نقدي' : 'صرف مصروف');
        
        rows.add(StatementRow(
          transactionNumber: tx['id']?.toString() ?? '—',
          date: txDate,
          accountName: isCredit ? 'سند قبض' : 'مصروف',
          description: description.isNotEmpty ? description : (isCredit ? 'استلام نقدي' : 'صرف مصروف'),
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: 'treasury_tx',
          createdAt: (tx['created_at'] ?? '').toString(),
        ));
      }

      // Add bank account transactions
      for (final tx in bankTxs) {
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
        final txDate = _toLocalDate(tx['created_at']);
        final typeStr = tx['type']?.toString() ?? 'deposit';
        final isCredit = typeStr == 'deposit';
        final description = tx['description']?.toString() ?? (isCredit ? 'إيداع بنكي' : 'سحب بنكي');
        
        rows.add(StatementRow(
          transactionNumber: tx['id']?.toString() ?? '—',
          date: txDate,
          accountName: isCredit ? 'إيداع بنكي' : 'سحب بنكي',
          description: description.isNotEmpty ? description : (isCredit ? 'إيداع بنكي' : 'سحب بنكي'),
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: 'bank_tx',
          createdAt: (tx['created_at'] ?? '').toString(),
        ));
      }

      // Sort rows by date then createdAt
      rows.sort((a, b) {
        if (a.type == 'initial') return -1;
        if (b.type == 'initial') return 1;
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

      if (from != null) {
        final obRow = StatementRow(
          transactionNumber: '—',
          date: from,
          createdAt: '',
          accountName: 'رصيد سابق',
          description: 'رصيد سابق',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: openingBalance > 0 ? openingBalance : 0,
          credit: openingBalance < 0 ? openingBalance.abs() : 0,
          balance: openingBalance,
          type: 'opening',
        );
        rows.insert(0, obRow);
      }

      // Apply running balance
      double running = openingBalance;
      final withBalance = rows.map((row) {
        if (row.type == 'opening' || row.type == 'initial') {
          running = row.balance;
          return row;
        }
        running += row.debit - row.credit;
        return StatementRow(
          transactionNumber: row.transactionNumber,
          date: row.date,
          accountName: row.accountName,
          description: row.description,
          piecesCount: row.piecesCount,
          quantity: row.quantity,
          unitPrice: row.unitPrice,
          debit: row.debit,
          credit: row.credit,
          balance: running,
          type: row.type,
          createdAt: row.createdAt,
        );
      }).toList();

      final totalDebit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial').fold(0.0, (s, r) => s + r.debit);
      final totalCredit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial').fold(0.0, (s, r) => s + r.credit);
      final finalBalance =
          withBalance.isNotEmpty ? withBalance.last.balance : 0.0;

      final statementNumber =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;

      debugPrint('✅ ExportStatement: ${withBalance.length} rows, debit=$totalDebit, credit=$totalCredit, balance=$finalBalance');

      final savedNotes = await _notesDao.getNotes(
        entityType: 'customer',
        entityId: currentState.selectedCustomer!.id!.toString(),
      );

      emit(currentState.copyWith(
        statementRows: withBalance,
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        finalBalance: finalBalance,
        statementNumber: statementNumber,
        openingBalance: openingBalance,
        rowNotes: savedNotes,
      ));
    } catch (e, st) {
      debugPrint('❌ ExportStatement error: $e\n$st');
      if (!isClosed) {
        emit(ExportCustomerStatementError(message: 'فشل تحميل كشف الحساب: $e'));
      }
    }
  }

  Future<List<ExportShipmentModel>> _fetchShipments(
    dynamic customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      final query = client
          .from('export_shipments')
          .select()
          .eq('customer_id', customerId)
          .eq('is_confirmed', true)
          .neq('status', 'cancelled');

      final data = await query.order('created_at', ascending: true);
      final allShipments = data.map((row) => ExportShipmentModel.fromMap(row)).toList();
      
      final from = fromDate != null ? DateTime.tryParse(fromDate) : null;
      final to = toDate != null ? DateTime.tryParse(toDate) : null;
      
      return allShipments.where((s) {
        final date = s.shipmentDate ?? s.createdAt ?? DateTime.now();
        if (from != null && date.isBefore(from)) return false;
        if (to != null && date.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59))) return false;
        return true;
      }).toList();
    } catch (e) {
      debugPrint('⚠️ _fetchShipments error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(
    dynamic customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('ledger_entries')
          .select('*')
          .eq('entity_type', 'customer')
          .eq('entity_id', customerId.toString())
          .neq('reference_type', 'cheque_cleared_incoming')
          .neq('reference_type', 'cheque_cleared_outgoing')
          .neq('reference_type', 'export_shipment')
          .neq('reference_type', 'expense')
          .neq('reference_type', 'receive');

      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', '${toDate}T23:59:59');
      }

      final data = await query.order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchPayments error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCheques(
    dynamic customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('cheques')
          .select('*')
          .eq('counterparty_type', 'customer')
          .eq('counterparty_id', customerId)
          .eq('status', 'cleared');

      if (fromDate != null) {
        query = query.gte('issue_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('issue_date', toDate);
      }

      final data = await query.order('issue_date', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchCheques error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTreasuryTx(
    dynamic customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('treasury_transactions')
          .select('*')
          .eq('customer_id', customerId)
          .neq('status', 'draft');

      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', '${toDate}T23:59:59');
      }

      final data = await query.order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchTreasuryTx error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBankTx(
    dynamic customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('bank_account_transactions')
          .select('*')
          .eq('entity_type', 'customer')
          .eq('entity_id', customerId.toString())
          .neq('status', 'draft');

      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', '${toDate}T23:59:59');
      }

      final data = await query.order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchBankTx error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGlEntries(
    dynamic customerId,
    int? customerAccountId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      final client = Supabase.instance.client;
      final orConditions = <String>[
        'entity_id.eq.$customerId',
        'source_id.eq.customers_$customerId',
      ];
      if (customerAccountId != null && customerAccountId > 0) {
        orConditions.add('account_id.eq.$customerAccountId');
      }

      var query = client
          .from('v_journal_entry_lines')
          .select('*')
          .or(orConditions.join(','));

      if (fromDate != null) {
        query = query.gte('transaction_date', fromDate);
      }
      if (toDate != null) {
        query = query.lte('transaction_date', toDate);
      }

      final data = await query.order('transaction_date', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchGlEntries error: $e');
      return [];
    }
  }

  Future<List<String>> _getShipmentProducts(dynamic shipmentId) async {
    try {
      final client = Supabase.instance.client;
      final parsedId = shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId;
      final data = await client
          .from('export_shipment_items')
          .select('product_name, invoice_product_name')
          .eq('shipment_id', parsedId);
      return data
          .map((row) {
            final invoiceName = (row['invoice_product_name'] ?? '').toString();
            final productName = (row['product_name'] ?? '').toString();
            return invoiceName.isNotEmpty ? invoiceName : productName;
          })
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  double _getShipmentAmount(
      ExportShipmentModel shipment, String customerCurrency) {
    if (customerCurrency == 'EGP') {
      return shipment.totalRevenueEgp;
    } else {
      return shipment.totalRevenueForeign;
    }
  }

  Future<double> _getShipmentAmountFromItems(
      dynamic shipmentId, ExportShipmentModel shipment, String customerCurrency) async {
    try {
      final client = Supabase.instance.client;
      final parsedId = shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId;
      final data = await client
          .from('export_shipment_items')
          .select('quantity, export_price_per_carton')
          .eq('shipment_id', parsedId);
      double total = 0;
      for (final row in data) {
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        final price = (row['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        total += qty * price;
      }
      if (total > 0) return total;
    } catch (e) {
      // fall through
    }
    return _getShipmentAmount(shipment, customerCurrency);
  }

  double _getPaymentAmount(Map<String, dynamic> payment) {
    return (payment['amount'] as num?)?.toDouble() ?? 0.0;
  }

  double _getChequeAmount(Map<String, dynamic> cheque) {
    return (cheque['amount'] as num?)?.toDouble() ?? 0.0;
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

  void setRowNote(String transactionNumber, String note) {
    final currentState = state;
    if (currentState is ExportCustomerStatementLoaded) {
      final newNotes = Map<String, String>.from(currentState.rowNotes);
      if (note.isEmpty) {
        newNotes.remove(transactionNumber);
      } else {
        newNotes[transactionNumber] = note;
      }
      emit(currentState.copyWith(rowNotes: newNotes));

      if (currentState.selectedCustomer?.id != null) {
        _notesDao.upsertNote(
          entityType: 'customer',
          entityId: currentState.selectedCustomer!.id!.toString(),
          referenceId: transactionNumber,
          note: note,
        );
      }
    }
  }

  Future<List<InvoiceModel>> _fetchInvoices(
    String customerId,
    String? fromDate,
    String? toDate,
  ) async {
    try {
      return await _invoiceDao.getByCustomer(customerId, fromDate: fromDate, toDate: toDate);
    } catch (e) {
      debugPrint('⚠️ Error fetching invoices in customer statement: $e');
      return [];
    }
  }

  void reset() {
    final currentState = state;
    if (currentState is ExportCustomerStatementLoaded) {
      final now = DateTime.now();
      emit(currentState.copyWith(
        clearSelectedCustomer: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    }
    refreshData();
  }
}
