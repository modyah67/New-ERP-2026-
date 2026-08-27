import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../data/services/account_ledger_service.dart';
import '../../core/utils.dart';
import 'supplier_statement_state.dart';

class SupplierStatementCubit extends Cubit<SupplierStatementState> {
  final SupplierDao _supplierDao = SupplierDao();
  final AccountLedgerService _ledgerService = AccountLedgerService();

  SupplierStatementCubit() : super(const SupplierStatementInitial()) {
    _init();
  }

  void init() {}

  Future<void> _init() async {
    final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
    final now = DateTime.now();
    emit(SupplierStatementLoaded(
      suppliers: suppliers,
      statementRows: const [],
      totalDebit: 0,
      totalCredit: 0,
      finalBalance: 0,
      statementNumber: 0,
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    ));
  }

  Future<void> refreshSuppliers() async {
    final currentState = state;
    if (currentState is SupplierStatementLoaded) {
      final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
      emit(currentState.copyWith(suppliers: suppliers));
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! SupplierStatementLoaded) return;

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
    if (currentState is! SupplierStatementLoaded) return;

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

  void selectSupplier(SupplierModel? supplier) {
    final currentState = state;
    if (currentState is SupplierStatementLoaded) {
      emit(currentState.copyWith(
        selectedSupplier: supplier,
        clearSelectedSupplier: supplier == null,
      ));
    }
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! SupplierStatementLoaded) return;

    if (currentState.selectedSupplier == null) {
      return;
    }

    emit(currentState.copyWith(
      statementRows: [],
      totalDebit: 0,
      totalCredit: 0,
      finalBalance: 0,
    ));

    try {
      final supplierId = currentState.selectedSupplier!.id;
      if (supplierId == null) throw Exception('Supplier ID is null');

      // 1. Get the account_id for this supplier
      final client = Supabase.instance.client;
      final supplierData = await client
          .from('suppliers')
          .select('account_id')
          .eq('id', supplierId)
          .maybeSingle();

      final accountId = supplierData?['account_id']?.toString();
      if (accountId == null) {
        throw Exception('هذا المورد غير مرتبط بحساب في شجرة الحسابات (Account ID is missing)');
      }

      // 2. Fetch the Unified General Ledger for this account
      final ledgerResult = await _ledgerService.getAccountLedger(
        accountIds: [accountId],
        accountType: 'liability',
        fromDate: currentState.fromDate,
        toDate: currentState.toDate,
        currency: currentState.selectedSupplier!.currency,
      );

      // 3. Map to StatementRows for the legacy UI
      final rows = <StatementRow>[];

      // Add opening balance row if there is a date filter
      if (currentState.fromDate != null) {
        rows.add(StatementRow(
          transactionNumber: '—',
          date: AppUtils.formatDateForDb(currentState.fromDate!),
          createdAt: '',
          accountName: 'رصيد سابق',
          description: 'رصيد مرحل قبل الفترة المحددة',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: ledgerResult.openingBalance < 0 ? ledgerResult.openingBalance.abs() : 0,
          credit: ledgerResult.openingBalance > 0 ? ledgerResult.openingBalance : 0,
          balance: ledgerResult.openingBalance,
          type: 'opening',
          currency: currentState.selectedSupplier!.currency,
        ));
      }

      // Add the ledger entries
      for (final entry in ledgerResult.entries) {
        rows.add(StatementRow(
          id: entry.id,
          transactionNumber: entry.entryNumber ?? entry.id,
          date: AppUtils.formatDateForDb(entry.date),
          createdAt: entry.createdAt,
          accountName: entry.accountName,
          accountCode: entry.accountCode,
          description: entry.description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: entry.debit,
          credit: entry.credit,
          balance: entry.runningBalance,
          type: _mapReferenceToType(entry.referenceType),
          referenceType: entry.referenceType,
          referenceId: entry.referenceId,
          currency: entry.currency,
        ));
      }

      final statementNumber = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Debug Verification Logs as requested
      debugPrint('--- SupplierStatement Debug ---');
      debugPrint('accountId: $accountId');
      debugPrint('fromDate: ${currentState.fromDate}');
      debugPrint('toDate: ${currentState.toDate}');
      debugPrint('entryCount: ${rows.length}');
      debugPrint('openingBalance: ${ledgerResult.openingBalance}');
      debugPrint('totalDebit: ${ledgerResult.totalDebit}');
      debugPrint('totalCredit: ${ledgerResult.totalCredit}');
      debugPrint('closingBalance: ${ledgerResult.closingBalance}');
      debugPrint('-------------------------------');

      emit(currentState.copyWith(
        statementRows: rows,
        totalDebit: ledgerResult.totalDebit,
        totalCredit: ledgerResult.totalCredit,
        finalBalance: ledgerResult.closingBalance,
        statementNumber: statementNumber,
      ));
    } catch (e, st) {
      debugPrint('⚠️ loadStatement error: $e\n$st');
      if (!isClosed) {
        emit(SupplierStatementError(message: 'حدث خطأ أثناء تحميل كشف الحساب: $e'));
      }
    }
  }

  String _mapReferenceToType(String? refType) {
    switch (refType?.toLowerCase()) {
      case 'purchase_invoice':
      case 'purchase':
        return 'purchase';
      case 'supplier_payment':
      case 'cash_payment':
      case 'treasury_transfer':
      case 'bank_transfer':
        return 'payment';
      default:
        return 'other';
    }
  }

  void reset() {
    final currentState = state;
    if (currentState is SupplierStatementLoaded) {
      final now = DateTime.now();
      emit(currentState.copyWith(
        clearSelectedSupplier: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    }
    refreshSuppliers();
  }

  @override
  void onChange(Change<SupplierStatementState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    return super.close();
  }
}
