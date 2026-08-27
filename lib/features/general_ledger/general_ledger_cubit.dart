library;

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/dao/report_dao.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/services/report_filter_service.dart';
import '../../accounting/reporting/utils/balance_calculator.dart';

part 'general_ledger_state.dart';

class GeneralLedgerCubit extends Cubit<GeneralLedgerState> {
  final ReportDao _dao;
  ReportFilter _currentFilter = ReportFilter.defaultFilter();
  String? _drillDownAccountCode;
  String? _drillDownAccountName;
  String _searchQuery = '';
  String? _currencyFilter = 'EGP';

  GeneralLedgerCubit({
    required ReportFilterService filterService,
  })  : _dao = ReportDao(),
        super(const GeneralLedgerInitial());

  Future<void> init({
    String? accountId,
    String? accountCode,
    String? accountName,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: fromDate ?? DateTime(now.year, now.month, 1),
      toDate: toDate ?? now,
      accountId: accountId,
    );
    _drillDownAccountCode = accountCode;
    _drillDownAccountName = accountName;
    await loadReport();
  }

  Future<void> loadReport({bool refresh = false}) async {
    if (isClosed) return;
    if (state is GeneralLedgerLoading) return;
    if (refresh && state is GeneralLedgerLoaded) {
      emit(GeneralLedgerRefreshing(state as GeneralLedgerLoaded));
    } else {
      emit(const GeneralLedgerLoading());
    }

    try {
      final fromDate = _currentFilter.fromDate ?? DateTime(DateTime.now().year, 1, 1);
      final toDate = _currentFilter.toDate ?? DateTime.now();

      final page = await _dao.getLedgerPage(
        accountId: _currentFilter.accountId,
        fromDate: fromDate,
        toDate: toDate,
        limit: 50,
        currency: _currencyFilter,
      );

      if (isClosed) return;

      final rows = <LedgerRow>[];
      for (final raw in page.rows) {
        final (debit, credit) = BalanceCalculator.normalizeRow(raw);
        final dateStr = raw['date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr) ?? DateTime.now();

        rows.add(LedgerRow(
          id: raw['id']?.toString(),
          date: date,
          entryNumber: raw['entry_number']?.toString(),
          accountCode: (raw['account_code'] as String?) ?? '',
          accountName: (raw['account_name'] as String?) ?? '',
          description: raw['description']?.toString(),
          debit: debit,
          credit: credit,
          referenceType: raw['reference_type']?.toString(),
          referenceId: raw['reference_id']?.toString(),
        ));
      }

      final obDebit = page.openingDebit;
      final obCredit = page.openingCredit;

      final isCreditNormal = _drillDownAccountCode != null &&
          (_drillDownAccountCode!.startsWith('2') ||
           _drillDownAccountCode!.startsWith('3') ||
           _drillDownAccountCode!.startsWith('4'));

      double runningBalance = isCreditNormal ? obCredit - obDebit : obDebit - obCredit;
      final ledgerRows = <LedgerRow>[];
      for (final row in rows) {
        final effect = isCreditNormal ? (row.credit - row.debit) : (row.debit - row.credit);
        runningBalance += effect;
        ledgerRows.add(LedgerRow(
          id: row.id,
          date: row.date,
          entryNumber: row.entryNumber,
          accountCode: row.accountCode,
          accountName: row.accountName,
          description: row.description,
          debit: row.debit,
          credit: row.credit,
          balance: runningBalance,
          referenceType: row.referenceType,
          referenceId: row.referenceId,
        ));
      }

      final totalDebit = ledgerRows.fold(0.0, (s, r) => s + r.debit);
      final totalCredit = ledgerRows.fold(0.0, (s, r) => s + r.credit);

      final report = LedgerReport(
        fromDate: fromDate,
        toDate: toDate,
        accountId: _currentFilter.accountId,
        rows: ledgerRows,
        openingBalance: isCreditNormal ? obCredit - obDebit : obDebit - obCredit,
        closingBalance: runningBalance,
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        transactionCount: ledgerRows.length,
        generatedAt: DateTime.now(),
        currencyFilter: _currencyFilter,
      );

      if (isClosed) return;

      emit(GeneralLedgerLoaded(
        report: report,
        filter: _currentFilter,
        drillDownAccountCode: _drillDownAccountCode,
        drillDownAccountName: _drillDownAccountName,
        searchQuery: _searchQuery,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        lastRunningBalance: runningBalance,
        currencyFilter: _currencyFilter,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(GeneralLedgerError(e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (isClosed) return;
    final loaded = state as GeneralLedgerLoaded?;
    if (loaded == null || !loaded.hasMore || loaded.isLoadingMore) return;

    emit(loaded.copyWith(isLoadingMore: true));

    try {
      final fromDate = _currentFilter.fromDate ?? DateTime(DateTime.now().year, 1, 1);
      final toDate = _currentFilter.toDate ?? DateTime.now();

      final page = await _dao.getLedgerPage(
        accountId: _currentFilter.accountId,
        fromDate: fromDate,
        toDate: toDate,
        cursor: loaded.nextCursor,
        limit: 50,
        currency: _currencyFilter,
      );

      if (isClosed) return;

      final newRows = <LedgerRow>[];
      for (final raw in page.rows) {
        final (debit, credit) = BalanceCalculator.normalizeRow(raw);
        final dateStr = raw['date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr) ?? DateTime.now();

        newRows.add(LedgerRow(
          id: raw['id']?.toString(),
          date: date,
          entryNumber: raw['entry_number']?.toString(),
          accountCode: (raw['account_code'] as String?) ?? '',
          accountName: (raw['account_name'] as String?) ?? '',
          description: raw['description']?.toString(),
          debit: debit,
          credit: credit,
          referenceType: raw['reference_type']?.toString(),
          referenceId: raw['reference_id']?.toString(),
        ));
      }

      final isCreditNormal = _drillDownAccountCode != null &&
          (_drillDownAccountCode!.startsWith('2') ||
           _drillDownAccountCode!.startsWith('3') ||
           _drillDownAccountCode!.startsWith('4'));

      // Compute running balance for new rows using previous closing balance
      var runningBalance = loaded.lastRunningBalance;
      final newLedgerRows = <LedgerRow>[];
      for (final row in newRows) {
        final effect = isCreditNormal ? (row.credit - row.debit) : (row.debit - row.credit);
        runningBalance += effect;
        newLedgerRows.add(LedgerRow(
          id: row.id,
          date: row.date,
          entryNumber: row.entryNumber,
          accountCode: row.accountCode,
          accountName: row.accountName,
          description: row.description,
          debit: row.debit,
          credit: row.credit,
          balance: runningBalance,
          referenceType: row.referenceType,
          referenceId: row.referenceId,
        ));
      }

      final allRows = [...loaded.report.rows, ...newLedgerRows];
      final totalDebit = allRows.fold(0.0, (s, r) => s + r.debit);
      final totalCredit = allRows.fold(0.0, (s, r) => s + r.credit);

      final updatedReport = LedgerReport(
        fromDate: loaded.report.fromDate,
        toDate: loaded.report.toDate,
        accountId: loaded.report.accountId,
        rows: allRows,
        openingBalance: loaded.report.openingBalance,
        closingBalance: runningBalance,
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        transactionCount: allRows.length,
        generatedAt: loaded.report.generatedAt,
        currencyFilter: _currencyFilter,
      );

      if (isClosed) return;

      emit(loaded.copyWith(
        report: updatedReport,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
        lastRunningBalance: runningBalance,
      ));
    } catch (e) {
      if (isClosed) return;
      final loaded = state as GeneralLedgerLoaded?;
      if (loaded != null) {
        emit(loaded.copyWith(isLoadingMore: false));
      }
    }
  }

  Future<void> setDateRange(DateTime from, DateTime to) async {
    _currentFilter = _currentFilter.copyWith(fromDate: from, toDate: to);
    await loadReport(refresh: true);
  }

  Future<void> setAccountId(String? accountId) async {
    if (accountId == null) {
      _currentFilter = _currentFilter.copyWith(clearAccountId: true);
      _drillDownAccountCode = null;
      _drillDownAccountName = null;
    } else {
      _currentFilter = _currentFilter.copyWith(accountId: accountId);
      _drillDownAccountCode = accountId;
      _drillDownAccountName = null;
    }
    await loadReport(refresh: true);
  }

  Future<void> setAccountType(AccountClassification? type) async {
    if (type == null) {
      _currentFilter = _currentFilter.copyWith(clearAccountType: true);
    } else {
      _currentFilter = _currentFilter.copyWith(accountType: type);
    }
    await loadReport(refresh: true);
  }

  void sort(String column) {
    if (state is GeneralLedgerLoaded) {
      final loaded = state as GeneralLedgerLoaded;
      final ascending = loaded.sortColumn == column
          ? !loaded.sortAscending
          : true;
      emit(loaded.copyWith(sortColumn: column, sortAscending: ascending));
    }
  }

  void toggleFullscreen() {
    if (state is GeneralLedgerLoaded) {
      final loaded = state as GeneralLedgerLoaded;
      emit(loaded.copyWith(isFullscreen: !loaded.isFullscreen));
    }
  }

  void resetFilters() {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    );
    _searchQuery = '';
    _currencyFilter = 'EGP';
    _drillDownAccountCode = null;
    _drillDownAccountName = null;
    loadReport(refresh: true);
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    if (state is GeneralLedgerLoaded) {
      emit((state as GeneralLedgerLoaded).copyWith(searchQuery: query));
    }
  }

  Future<void> setCurrencyFilter(String? currency) async {
    _currencyFilter = currency;
    
    // Auto-update the account filter for multi-currency accounts (Treasury/Banks)
    final accId = _currentFilter.accountId;
    if (accId != null && (accId.length == 4 || accId.length == 5)) {
      if (accId.startsWith('1110')) {
        String newAcc = '1110'; // All / Parent
        if (currency == 'EGP') newAcc = '11101';
        if (currency == 'USD') newAcc = '11102';
        if (currency == 'EUR') newAcc = '11103';
        if (currency == 'GBP') newAcc = '11104';
        _currentFilter = _currentFilter.copyWith(accountId: newAcc);
        _drillDownAccountCode = newAcc;
      } else if (accId.startsWith('1120')) {
        String newAcc = '1120'; // All / Parent
        if (currency == 'EGP') newAcc = '11201';
        if (currency == 'USD') newAcc = '11202';
        if (currency == 'EUR') newAcc = '11203';
        if (currency == 'GBP') newAcc = '11204';
        _currentFilter = _currentFilter.copyWith(accountId: newAcc);
        _drillDownAccountCode = newAcc;
      }
    }

    await loadReport(refresh: true);
  }
}
