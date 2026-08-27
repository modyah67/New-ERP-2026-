import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/invoice_dao.dart';
import '../../data/dao/purchase_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/transaction_model.dart';
import '../../core/utils.dart';
import '../../data/models/statement_row_model.dart';
import 'brief_statement_state.dart';

class BriefStatementCubit extends Cubit<BriefStatementState> {
  final CustomerDao _customerDao = CustomerDao();
  final SupplierDao _supplierDao = SupplierDao();
  final InvoiceDao _invoiceDao = InvoiceDao();
  final PurchaseDao _purchaseDao = PurchaseDao();
  final TransactionDao _transactionDao = TransactionDao();

  BriefStatementCubit() : super(const BriefStatementInitial()) {
    _init();
  }

  void init() {}

  Future<void> _init() async {
    final customers = await _customerDao.getAll(limit: 2000, offset: 0);
    final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
    final now = DateTime.now();
    emit(BriefStatementLoaded(
      isCustomerMode: true,
      customers: customers,
      suppliers: suppliers,
      statementRows: const [],
      totalDebit: 0,
      totalCredit: 0,
      finalBalance: 0,
      totalMeters: 0,
      statementNumber: 0,
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    ));
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is BriefStatementLoaded) {
      try {
        final customers = await _customerDao.getAll(limit: 2000, offset: 0);
        final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
        emit(currentState.copyWith(
          customers: customers,
          suppliers: suppliers,
        ));
      } catch (e) {
        emit(BriefStatementError(message: 'فشل تحميل البيانات: $e'));
      }
    }
  }

  void setCustomerMode(bool isCustomer) {
    toggleMode(isCustomer);
  }

  void toggleMode(bool isCustomer) {
    final currentState = state;
    if (currentState is BriefStatementLoaded) {
      if (currentState.isCustomerMode == isCustomer) return;
      reset();
      emit(currentState.copyWith(
        isCustomerMode: isCustomer,
        clearSelectedCustomer: true,
        clearSelectedSupplier: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        totalMeters: 0,
      ));
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! BriefStatementLoaded) return;

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
    if (currentState is! BriefStatementLoaded) return;

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
    if (currentState is BriefStatementLoaded) {
      emit(currentState.copyWith(
        selectedCustomer: customer,
        clearSelectedCustomer: customer == null,
      ));
    }
  }

  void selectSupplier(SupplierModel? supplier) {
    final currentState = state;
    if (currentState is BriefStatementLoaded) {
      emit(currentState.copyWith(
        selectedSupplier: supplier,
        clearSelectedSupplier: supplier == null,
      ));
    }
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! BriefStatementLoaded) return;

    if (currentState.isCustomerMode && currentState.selectedCustomer == null) {
      return;
    }
    if (!currentState.isCustomerMode && currentState.selectedSupplier == null) {
      return;
    }

    try {
      final from = currentState.fromDate != null
          ? AppUtils.formatDateForDb(currentState.fromDate!)
          : null;
      final to = currentState.toDate != null
          ? AppUtils.formatDateForDb(currentState.toDate!)
          : null;

      if (currentState.isCustomerMode) {
        await _loadCustomerBriefStatement(currentState, from, to);
      } else {
        await _loadSupplierBriefStatement(currentState, from, to);
      }
    } catch (e) {
      if (!isClosed) {
        emit(BriefStatementError(message: 'فشل تحميل كشف الحساب: $e'));
      }
    }
  }

  Future<void> _loadCustomerBriefStatement(
    BriefStatementLoaded currentState,
    String? from,
    String? to,
  ) async {
    final customerId = currentState.selectedCustomer!.id!;

    // 1. Calculate Opening Balance from invoices before the date
    double openingBalance = currentState.selectedCustomer!.initialBalance;
    List<InvoiceModel> priorInvoices = [];
    List<TransactionModel> priorTransactions = [];
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
      // Cheques before date
      final priorCheques = await _fetchCustomerCheques(customerId, null, from);
      for (final ch in priorCheques) {
        final amt = (ch['amount'] as num?)?.toDouble() ?? 0;
        final isIncoming = ch['type']?.toString() == 'incoming';
        openingBalance += isIncoming ? -amt : amt;
      }
    }

    // 2. Load Invoices
    final invoices = await _invoiceDao.getByCustomer(
      customerId,
      fromDate: from,
      toDate: to,
    );

    // 3. Load Independent Transactions
    final transactions = await _transactionDao.getAll(
      fromDate: from,
      toDate: to,
    );

    // 4. Build summarized rows
    final rows = <StatementRow>[];

    for (final inv in invoices) {
      final invNum = inv.invoiceNumber.toString().padLeft(6, '0');
      final invDate = inv.invoiceDate;
      final isReturn = inv.type == 'return';

      rows.add(StatementRow(
        transactionNumber: invNum,
        date: invDate,
        accountName: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
        description: isReturn
            ? 'فاتورة مرتجع مبيعات رقم $invNum'
            : 'فاتورة مبيعات رقم $invNum',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: isReturn ? 0 : inv.netAmount,
        credit: isReturn ? inv.netAmount : 0,
        balance: 0,
        type: 'invoice',
        createdAt: inv.createdAt,
      ));

      if (inv.paidAmount > 0) {
        rows.add(StatementRow(
          transactionNumber: invNum,
          date: invDate,
          accountName: 'سداد',
          description:
              'سداد ${isReturn ? 'مرتجع' : 'فاتورة'} رقم $invNum',
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

    // Add cheques
    final cheques = await _fetchCustomerCheques(customerId, from, to);
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
        piecesCount: 0, quantity: 0, unitPrice: 0,
        debit: isIncoming ? 0 : amt,
        credit: isIncoming ? amt : 0,
        balance: 0,
        type: 'cheque',
        createdAt: (dateRaw ?? '').toString(),
      ));
    }

    // Sort rows
    rows.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return a.createdAt.compareTo(b.createdAt);
    });

    // 5. Add Opening Balance Row
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

    // 6. Apply Running Balance
    double running = 0;
    final withBalance = rows.map((row) {
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

    final totalDebit =
        withBalance.fold(0.0, (s, r) => s + r.debit);
    final totalCredit =
        withBalance.fold(0.0, (s, r) => s + r.credit);
    final finalBalance =
        withBalance.isNotEmpty ? withBalance.last.balance : 0.0;

    // Calculate total meters
    double meters = 0.0;
    for (final inv in invoices) {
      final items = await _invoiceDao.getItemsForInvoice(inv.id!);
      final sumQty = items.fold<double>(0.0, (s, it) => s + it.quantity);
      if (inv.type == 'return') {
        meters -= sumQty;
      } else {
        meters += sumQty;
      }
    }

    final statementNumber =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;

    emit(currentState.copyWith(
      statementRows: withBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      totalMeters: meters,
      statementNumber: statementNumber,
    ));
  }

  Future<void> _loadSupplierBriefStatement(
    BriefStatementLoaded currentState,
    String? from,
    String? to,
  ) async {
    final supplierId = currentState.selectedSupplier!.id ?? currentState.selectedSupplier!.supplierCode;

    // 1. Calculate Opening Balance from purchases before the date
    double openingBalance = currentState.selectedSupplier!.initialBalance;
    List<dynamic> priorPurchases = [];
    List<TransactionModel> priorTransactions = [];
    if (from != null) {
      final fromDt = DateTime.tryParse(from);
      final dayBefore = fromDt != null
          ? AppUtils.formatDateForDb(fromDt.subtract(const Duration(days: 1)))
          : null;
      priorPurchases = await _purchaseDao.getBySupplier(
        supplierId,
        toDate: dayBefore,
      );
      for (final pur in priorPurchases) {
        openingBalance += (pur.netAmount - pur.paidAmount);
      }
      priorTransactions = await _transactionDao.getAll(
        fromDate: null,
        toDate: dayBefore,
      );
      for (final tx in priorTransactions) {
        if (tx.purchaseId != null) continue;
        if (tx.supplierId != supplierId) continue;
        if (tx.type == 'debit') {
          openingBalance -= tx.amount;
        } else {
          openingBalance += tx.amount;
        }
      }
      // Cheques before date
      final priorCheques = await _fetchSupplierCheques(supplierId, null, dayBefore);
      for (final ch in priorCheques) {
        final amt = (ch['amount'] as num?)?.toDouble() ?? 0;
        final isIncoming = ch['type']?.toString() == 'incoming';
        openingBalance += isIncoming ? -amt : amt;
      }
    }

    // 2. Load Purchases
    final purchases = await _purchaseDao.getBySupplier(
      supplierId,
      fromDate: from,
      toDate: to,
    );

    // 3. Load Independent Transactions
    final allTransactions = await _transactionDao.getAll(
      fromDate: from,
      toDate: to,
    );
    final transactions = allTransactions.where((tx) => tx.supplierId == supplierId).toList();

    // 4. Build summarized rows
    final rows = <StatementRow>[];

    for (final pur in purchases) {
      final purNum = pur.purchaseNumber.toString().padLeft(6, '0');
      final purDate = pur.purchaseDate;

      rows.add(StatementRow(
        transactionNumber: purNum,
        date: purDate,
        createdAt: pur.createdAt,
        accountName: 'فاتورة مشتريات',
        description: 'فاتورة مشتريات رقم $purNum',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 0,
        credit: pur.netAmount,
        balance: 0,
        type: 'purchase',
      ));

      if (pur.paidAmount > 0) {
        rows.add(StatementRow(
          transactionNumber: purNum,
          date: purDate,
          createdAt: pur.createdAt,
          accountName: 'سداد',
          description: 'سداد فاتورة مشتريات رقم $purNum',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: pur.paidAmount,
          credit: 0,
          balance: 0,
          type: 'payment',
        ));
      }
    }

    // Independent transactions
    for (final tx in transactions) {
      if (tx.purchaseId != null) continue;

      if (tx.description.startsWith('مشتريات رقم') ||
          tx.description.startsWith('دفعة نقدية لمشتريات رقم')) {
        continue;
      }

      final txNum = tx.id?.toString().padLeft(6, '0') ?? '—';

      if (tx.type == 'debit') {
        rows.add(StatementRow(
          transactionNumber: txNum,
          date: tx.transactionDate,
          createdAt: tx.createdAt,
          accountName: 'سداد / قيد مدين',
          description: tx.description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: tx.amount,
          credit: 0,
          balance: 0,
          type: 'payment',
        ));
      } else {
        rows.add(StatementRow(
          transactionNumber: txNum,
          date: tx.transactionDate,
          createdAt: tx.createdAt,
          accountName: 'قيد دائن',
          description: tx.description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: tx.amount,
          balance: 0,
          type: 'other',
        ));
      }
    }

    // Add cheques
    final cheques = await _fetchSupplierCheques(supplierId, from, to);
    for (final cheque in cheques) {
      final amt = (cheque['amount'] as num?)?.toDouble() ?? 0;
      final dateRaw = cheque['cleared_at'] ?? cheque['created_at'];
      final date = _toLocalDate(dateRaw);
      final chequeNum = cheque['cheque_number']?.toString() ?? '';
      final isIncoming = cheque['type']?.toString() == 'incoming';

      rows.add(StatementRow(
        transactionNumber: cheque['id']?.toString() ?? '-',
        date: date,
        createdAt: (dateRaw ?? '').toString(),
        accountName: isIncoming ? 'شيك وارد' : 'شيك صادر',
        description: isIncoming ? 'تحصيل شيك رقم $chequeNum' : 'صرف شيك رقم $chequeNum',
        piecesCount: 0, quantity: 0, unitPrice: 0,
        debit: isIncoming ? 0 : amt,
        credit: isIncoming ? amt : 0,
        balance: 0,
        type: 'cheque',
      ));
    }

    // Sort rows
    rows.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return a.createdAt.compareTo(b.createdAt);
    });

    // 5. Add Opening Balance Row
    if (from != null && (rows.isNotEmpty || openingBalance != 0)) {
      final obRow = StatementRow(
        transactionNumber: '—',
        date: from,
        createdAt: '',
        accountName: 'رصيد سابق',
        description: 'رصيد سابق',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: openingBalance < 0 ? openingBalance.abs() : 0,
        credit: openingBalance > 0 ? openingBalance : 0,
        balance: openingBalance,
        type: 'opening',
      );
      rows.insert(0, obRow);
    }

    // 6. Apply Running Balance
    double running = 0;
    final withBalance = rows.map((row) {
      if (row.type == 'opening') {
        running = row.balance;
        return row;
      }
      running += row.credit - row.debit;
      return StatementRow(
        transactionNumber: row.transactionNumber,
        date: row.date,
        createdAt: row.createdAt,
        accountName: row.accountName,
        description: row.description,
        piecesCount: row.piecesCount,
        quantity: row.quantity,
        unitPrice: row.unitPrice,
        debit: row.debit,
        credit: row.credit,
        balance: running,
        type: row.type,
      );
    }).toList();

    final totalDebit =
        withBalance.fold(0.0, (s, r) => s + r.debit);
    final totalCredit =
        withBalance.fold(0.0, (s, r) => s + r.credit);
    final finalBalance =
        withBalance.isNotEmpty ? withBalance.last.balance : 0.0;

    // Calculate total meters
    double meters = 0.0;
    for (final pur in purchases) {
      final items = await _purchaseDao.getItemsForPurchase(int.parse(pur.id!));
      meters += items.fold<double>(0.0, (s, it) => s + it.quantity);
    }

    final statementNumber =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;

    emit(currentState.copyWith(
      statementRows: withBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      totalMeters: meters,
      statementNumber: statementNumber,
    ));
  }

  void reset() {
    final currentState = state;
    if (currentState is BriefStatementLoaded) {
      final now = DateTime.now();
      emit(currentState.copyWith(
        clearSelectedCustomer: true,
        clearSelectedSupplier: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        totalMeters: 0,
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    }
    refreshData();
  }

  @override
  void onChange(Change<BriefStatementState> change) {
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

  Future<List<Map<String, dynamic>>> _fetchCustomerCheques(
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
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSupplierCheques(
      dynamic supplierId, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('cheques')
          .select('*')
          .eq('counterparty_type', 'supplier')
          .eq('supplier_id', supplierId.toString())
          .eq('status', 'cleared');
      if (fromDate != null) query = query.gte('cleared_at', fromDate);
      if (toDate != null) query = query.lte('cleared_at', '${toDate}T23:59:59');
      final data = await query.order('cleared_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}
