library;

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/dao/report_dao.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/services/report_calculation_service.dart';
import '../../accounting/reporting/export/report_export_service.dart';
import '../../accounting/reporting/services/report_filter_service.dart';
import '../../accounting/reporting/services/report_validation_service.dart';

part 'trial_balance_state.dart';

class TrialBalanceCubit extends Cubit<TrialBalanceState> {
  final ReportCalculationService _calculationService;
  final ReportValidationService _validationService;
  final ReportDao _dao = ReportDao();

  ReportFilter _currentFilter = ReportFilter.defaultFilter();

  TrialBalanceCubit({
    required ReportCalculationService calculationService,
    required ReportFilterService filterService,
    required ReportValidationService validationService,
  })  : _calculationService = calculationService,
        _validationService = validationService,
        super(const TrialBalanceInitial());

  Future<void> init() async {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    await loadReport();
  }

  Future<void> loadReport({bool refresh = false}) async {
    if (state is TrialBalanceLoading) return;
    if (refresh && state is TrialBalanceLoaded) {
      emit(TrialBalanceRefreshing(state as TrialBalanceLoaded));
    } else {
      emit(const TrialBalanceLoading());
    }

    try {
      final fromDate = _currentFilter.fromDate ?? DateTime(DateTime.now().year, 1, 1);
      final toDate = _currentFilter.toDate ?? DateTime.now();

      final results = await Future.wait([
        _calculationService.calculateTrialBalance(
          fromDate: fromDate,
          asOfDate: toDate,
          accountType: _currentFilter.accountType,
          currency: null,
        ),
        _dao.getAccountHierarchy(),
      ]);

      final report = results[0] as TrialBalanceReport;
      final hierarchy = results[1] as List<AccountHierarchy>;

      final validationResult = _validationService.validateTrialBalance(report);

      final expandedIds = <String>{};
      for (final account in hierarchy) {
        if (account.hasChildren) {
          expandedIds.add(account.id);
        }
      }

      emit(TrialBalanceLoaded(
        report: report,
        hierarchy: hierarchy,
        filter: _currentFilter,
        validationResult: validationResult,
        expandedAccountIds: expandedIds,
        currencyFilter: null,
      ));
    } catch (e) {
      emit(TrialBalanceError(e.toString()));
    }
  }

  Future<void> applyFilter(ReportFilter filter) async {
    _currentFilter = filter;
    await loadReport(refresh: true);
  }

  Future<void> setDateRange(DateTime from, DateTime to) async {
    _currentFilter = _currentFilter.copyWith(fromDate: from, toDate: to);
    await loadReport(refresh: true);
  }

  Future<void> setFinancialYear(int year) async {
    _currentFilter = _currentFilter.copyWith(
      fromDate: DateTime(year, 1, 1),
      toDate: DateTime(year, 12, 31),
    );
    await loadReport(refresh: true);
  }

  Future<void> setAccountType(AccountClassification? type) async {
    _currentFilter = _currentFilter.copyWith(accountType: type);
    await loadReport(refresh: true);
  }

  void setSearchQuery(String query) {
    if (state is TrialBalanceLoaded) {
      emit((state as TrialBalanceLoaded).copyWith(searchQuery: query));
    }
  }

  void toggleHideZeroBalances() {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      emit(loaded.copyWith(hideZeroBalances: !loaded.hideZeroBalances));
    }
  }

  void toggleShowParentAccounts() {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      emit(loaded.copyWith(showParentAccounts: !loaded.showParentAccounts));
    }
  }

  void toggleAccountExpand(String accountId) {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      final newExpanded = Set<String>.from(loaded.expandedAccountIds);
      if (newExpanded.contains(accountId)) {
        newExpanded.remove(accountId);
      } else {
        newExpanded.add(accountId);
      }
      emit(loaded.copyWith(expandedAccountIds: newExpanded));
    }
  }

  void expandAll() {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      final allIds = loaded.hierarchy.expand((a) => _collectIds(a)).toSet();
      emit(loaded.copyWith(expandedAccountIds: allIds));
    }
  }

  void collapseAll() {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      emit(loaded.copyWith(expandedAccountIds: {}));
    }
  }

  Set<String> _collectIds(AccountHierarchy account) {
    final ids = <String>{};
    if (account.hasChildren) {
      ids.add(account.id);
      for (final child in account.children) {
        ids.addAll(_collectIds(child));
      }
    }
    return ids;
  }

  void sort(String column) {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      final ascending = loaded.sortColumn == column
          ? !loaded.sortAscending
          : true;
      emit(loaded.copyWith(sortColumn: column, sortAscending: ascending));
    }
  }

  void toggleFullscreen() {
    if (state is TrialBalanceLoaded) {
      final loaded = state as TrialBalanceLoaded;
      emit(loaded.copyWith(isFullscreen: !loaded.isFullscreen));
    }
  }

  void resetFilters() {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    loadReport(refresh: true);
  }

  // ── Export actions ──

  String exportToCsv() {
    if (state is TrialBalanceLoaded) {
      final report = (state as TrialBalanceLoaded).report;
      return ReportExportService.exportTrialBalanceToCsv(report);
    }
    return '';
  }

  // ── Drill Down ──

  void drillDown(String accountId) {
    // Navigation handled by TrialBalancePage via GoRouter
  }
}
