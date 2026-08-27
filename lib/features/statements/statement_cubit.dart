import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/invoice_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/transaction_model.dart';
import '../../core/utils.dart';
import '../../data/models/statement_row_model.dart';
import 'statement_state.dart';

class StatementCubit extends Cubit<StatementState> {
  final CustomerDao _customerDao = CustomerDao();
  final InvoiceDao _invoiceDao = InvoiceDao();
  final TransactionDao _transactionDao = TransactionDao();

  StatementCubit() : super(const StatementInitial()) {
    _init();
  }

  void init() => _init();

  Future<void> _init() async {
    final customers = await _customerDao.getAll(limit: 2000, offset: 0);
    final now = DateTime.now();
    emit(StatementLoaded(
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

  Future<void> refreshCustomers() async {
    final currentState = state;
    if (currentState is StatementLoaded) {
      final customers = await _customerDao.getAll(limit: 2000, offset: 0);
      emit(currentState.copyWith(customers: customers));
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! StatementLoaded) return;

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
    if (currentState is! StatementLoaded) return;

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

  void selectCustomer(CustomerModel? customer) {
    final currentState = state;
    debugPrint('🔍 selectCustomer: ${customer?.name ?? "null"}, state=${currentState.runtimeType}');
    if (currentState is StatementLoaded) {
      emit(currentState.copyWith(
        selectedCustomer: customer,
        clearSelectedCustomer: customer == null,
      ));
      if (customer != null) loadStatement();
    }
  }

  Future<void> loadStatement() async {
    final currentState = state;
    debugPrint('📊 loadStatement called, state=${currentState.runtimeType}');
    if (currentState is! StatementLoaded) return;

    if (currentState.selectedCustomer == null) {
      debugPrint('⚠️ loadStatement: selectedCustomer is null, returning');
      return;
    }

    emit(currentState.copyWith(
      statementRows: [],
      totalDebit: 0,
      totalCredit: 0,
      finalBalance: 0,
    ));

    try {
      final customerId = currentState.selectedCustomer!.id!;
      final from = currentState.fromDate != null
          ? AppUtils.formatDateForDb(currentState.fromDate!)
          : null;
      final to = currentState.toDate != null
          ? AppUtils.formatDateForDb(currentState.toDate!)
          : null;

      // 1. Calculate Opening Balance from invoices before the date
      double openingBalance = currentState.selectedCustomer!.initialBalance;
      List<InvoiceModel> priorInvoices = [];
      List<TransactionModel> priorTransactions = [];
      List<Map<String, dynamic>> priorLedger = [];
      if (from != null) {
        priorInvoices = await _invoiceDao.getByCustomer(
          customerId,
          toDate: from,
        );
        for (final inv in priorInvoices) {
          if (inv.type == 'return') {
            openingBalance -= (inv.netAmount - inv.paidAmount);
          } else {
            openingBalance += (inv.netAmount - inv.paidAmount);
          }
        }
        priorTransactions = await _transactionDao.getAll(
          customerId: customerId,
          fromDate: null,
          toDate: from,
        );
        for (final tx in priorTransactions) {
          if (tx.invoiceId != null) continue;
          if (tx.type == 'credit') {
            openingBalance -= tx.amount;
          } else {
            openingBalance += tx.amount;
          }
        }
        // Ledger entries before date
        priorLedger = await _fetchLedgerEntries(customerId, null, from);
        for (final entry in priorLedger) {
          final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
          if (entry['entry_type'] == 'credit') {
            openingBalance -= amt;
          } else {
            openingBalance += amt;
          }
        }
        // Cheques before date
        final priorCheques = await _fetchCheques(customerId, null, from);
        for (final ch in priorCheques) {
          final amt = (ch['amount'] as num?)?.toDouble() ?? 0;
          final isIncoming = ch['type']?.toString() == 'incoming';
          // incoming cheque = customer paid us = credit
          openingBalance += isIncoming ? -amt : amt;
        }
      }

      // 2. Load data for the period
      final invoices = await _invoiceDao.getByCustomer(
        customerId,
        fromDate: from,
        toDate: to,
      );

      debugPrint('📊 Statement: customerId=$customerId, from=$from, to=$to');
      debugPrint('📊 Invoices found: ${invoices.length}');

      final invoicesWithItems = <InvoiceModel>[];
      for (final inv in invoices) {
        final items = await _invoiceDao.getItemsForInvoice(inv.id!);
        invoicesWithItems.add(inv.copyWith(items: items));
      }

      final transactions = await _transactionDao.getAll(
        customerId: customerId,
        fromDate: from,
        toDate: to,
      );

      final ledgerEntries = await _fetchLedgerEntries(customerId, from, to);

      debugPrint('📊 Transactions found: ${transactions.length}');
      debugPrint('📊 Ledger entries found: ${ledgerEntries.length}');

      final rows = _buildRows(invoicesWithItems, transactions);

      debugPrint('📊 Rows built: ${rows.length}');

      // Add ledger entries as statement rows
      for (final entry in ledgerEntries) {
        final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
        final entryDate = _toLocalDate(entry['created_at']);
        final refType = entry['reference_type']?.toString() ?? '';
        final entryType = entry['entry_type']?.toString() ?? '';
        final description = entry['description']?.toString() ??
            (refType == 'receive' ? 'استلام' : refType == 'expense' ? 'مصروف' : 'قيد');

        final isCredit = entryType == 'credit';
        rows.add(StatementRow(
          transactionNumber: entry['id']?.toString() ?? '—',
          date: entryDate,
          accountName: isCredit ? 'سند قبض' : 'مصروف',
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amt,
          credit: isCredit ? amt : 0,
          balance: 0,
          type: 'payment',
          createdAt: (entry['created_at'] ?? '').toString(),
        ));
      }

      // Add cheques
      final cheques = await _fetchCheques(customerId, from, to);
      for (final cheque in cheques) {
        final amt = (cheque['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = cheque['cleared_at'] ?? cheque['created_at'];
        final date = _toLocalDate(dateRaw);
        final chequeNum = cheque['cheque_number']?.toString() ?? '';
        final isIncoming = cheque['type']?.toString() == 'incoming';

        rows.add(StatementRow(
          transactionNumber: cheque['id']?.toString() ?? '-',
          date: date,
          accountName: isIncoming ? 'شيك وارد' : 'شيك صادر',
          description: isIncoming ? 'تحصيل شيك رقم $chequeNum' : 'صرف شيك رقم $chequeNum',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isIncoming ? 0 : amt,
          credit: isIncoming ? amt : 0,
          balance: 0,
          type: 'cheque',
          createdAt: (dateRaw ?? '').toString(),
        ));
      }

      rows.sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

      // 3. Add Opening Balance Row
      if (from != null && (rows.isNotEmpty || openingBalance != 0)) {
        final obRow = StatementRow(
          transactionNumber: '—',
          date: from,
          accountName: 'رصيد سابق',
          description: 'رصيد سابق',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: openingBalance > 0 ? openingBalance : 0,
          credit: openingBalance < 0 ? openingBalance.abs() : 0,
          balance: openingBalance,
          type: 'opening',
          createdAt: '',
        );
        rows.insert(0, obRow);
      }

      final withBalance = _applyRunningBalance(rows);

      final totalDebit =
          withBalance.fold(0.0, (s, r) => s + r.debit);
      final totalCredit =
          withBalance.fold(0.0, (s, r) => s + r.credit);
      final finalBalance =
          withBalance.isNotEmpty ? withBalance.last.balance : 0.0;
      final statementNumber =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;

      debugPrint('📊 Final: rows=${withBalance.length}, debit=$totalDebit, credit=$totalCredit, balance=$finalBalance');

      emit(currentState.copyWith(
        statementRows: withBalance,
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        finalBalance: finalBalance,
        statementNumber: statementNumber,
      ));
    } catch (e, stackTrace) {
      debugPrint('❌ loadStatement error: $e');
      debugPrint('❌ stackTrace: $stackTrace');
      if (!isClosed) {
        emit(StatementError(message: 'حدث خطأ: $e'));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLedgerEntries(
      String customerId, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('ledger_entries')
          .select('*')
          .eq('entity_type', 'customer')
          .eq('entity_id', customerId.toString())
          .inFilter('reference_type', ['receive', 'expense', 'payment']);
      if (fromDate != null) query = query.gte('created_at', fromDate);
      if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
      final data = await query.order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCheques(
      String customerId, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('cheques')
          .select('*')
          .eq('counterparty_type', 'customer')
          .eq('counterparty_id', customerId)
          .eq('status', 'cleared');
      if (fromDate != null) query = query.gte('cleared_at', fromDate);
      if (toDate != null) query = query.lte('cleared_at', '${toDate}T23:59:59');
      final data = await query.order('cleared_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchCheques error: $e');
      return [];
    }
  }

  List<StatementRow> _buildRows(
    List<InvoiceModel> invoices,
    List<TransactionModel> transactions,
  ) {
    final rows = <StatementRow>[];

    for (final inv in invoices) {
      final invNum = inv.invoiceNumber.toString().padLeft(6, '0');
      final invDate = inv.invoiceDate;
      final isReturn = inv.type == 'return';

      if (inv.items.isNotEmpty) {
        for (final item in inv.items) {
          rows.add(StatementRow(
            transactionNumber: invNum,
            date: invDate,
            accountName: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
            description: item.itemName ?? '—',
            piecesCount: 1,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            debit: isReturn ? 0 : item.totalPrice,
            credit: isReturn ? item.totalPrice : 0,
            balance: 0,
            type: 'invoice',
            createdAt: inv.createdAt,
          ));
        }
      } else {
        rows.add(StatementRow(
          transactionNumber: invNum,
          date: invDate,
          accountName: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
          description: 'فاتورة ${isReturn ? 'مرتجع' : 'بيع'}',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isReturn ? 0 : inv.netAmount,
          credit: isReturn ? inv.netAmount : 0,
          balance: 0,
          type: 'invoice',
          createdAt: inv.createdAt,
        ));
      }

      // Payment row
      if (inv.paidAmount > 0) {
        rows.add(StatementRow(
          transactionNumber: invNum,
          date: invDate,
          accountName: 'سداد',
          description: 'سداد ${isReturn ? 'مرتجع' : 'فاتورة'} رقم $invNum',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isReturn ? inv.paidAmount : 0,
          credit: isReturn ? 0 : inv.paidAmount,
          balance: 0,
          type: 'payment',
          createdAt: inv.createdAt,
        ));
      }
    }

    // Independent transactions
    for (final tx in transactions) {
      if (tx.invoiceId != null) continue;

      final txNum = tx.id?.toString().padLeft(6, '0') ?? '—';

      if (tx.type == 'credit') {
        rows.add(StatementRow(
          transactionNumber: txNum,
          date: tx.transactionDate,
          accountName: 'سداد',
          description: tx.description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: tx.amount,
          balance: 0,
          type: 'payment',
          createdAt: tx.createdAt,
        ));
      } else {
        rows.add(StatementRow(
          transactionNumber: txNum,
          date: tx.transactionDate,
          accountName: 'قيد محاسبي',
          description: tx.description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: tx.amount,
          credit: 0,
          balance: 0,
          type: 'other',
          createdAt: tx.createdAt,
        ));
      }
    }

    return rows;
  }

  List<StatementRow> _applyRunningBalance(List<StatementRow> rows) {
    double running = 0;
    return rows.map((row) {
      if (row.type == 'opening') {
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
  }

  void reset() {
    final currentState = state;
    if (currentState is StatementLoaded) {
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
    refreshCustomers();
  }

  @override
  void onChange(Change<StatementState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    return super.close();
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
