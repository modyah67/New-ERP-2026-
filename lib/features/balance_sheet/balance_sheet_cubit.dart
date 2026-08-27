library;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/dao/report_dao.dart';
import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/services/report_calculation_service.dart';
import '../../accounting/reporting/services/report_filter_service.dart';
import '../../accounting/reporting/services/report_validation_service.dart';

part 'balance_sheet_state.dart';

class BalanceSheetCubit extends Cubit<BalanceSheetState> {
  final ReportCalculationService _calculationService;
  final ReportFilterService _filterService;
  final ReportValidationService _validationService;
  final ReportDao _dao;

  ReportFilter _currentFilter = ReportFilter.defaultFilter();
  String? _currencyFilter;

  BalanceSheetCubit({
    required ReportCalculationService calculationService,
    required ReportFilterService filterService,
    required ReportValidationService validationService,
    ReportDao? dao,
  })  : _calculationService = calculationService,
        _filterService = filterService,
        _validationService = validationService,
        _dao = dao ?? ReportDao(),
        super(const BalanceSheetInitial());

  Future<void> init() async {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    await loadReport();
  }

  Future<void> loadReport({bool refresh = false}) async {
    if (state is BalanceSheetLoading) return;
    if (refresh && state is BalanceSheetLoaded) {
      emit(BalanceSheetRefreshing(state as BalanceSheetLoaded));
    } else {
      emit(const BalanceSheetLoading());
    }

    try {
      final asOfDate = _currentFilter.toDate ?? DateTime.now();

      final results = await Future.wait([
        _calculationService.calculateBalanceSheet(
          asOfDate: asOfDate,
          currency: _currencyFilter,
        ),
        _dao.getAccountHierarchy(),
      ]);

      final report = results[0] as BalanceSheetReport;
      final hierarchy = results[1] as List<AccountHierarchy>;

      final validationResult = _validationService.validateBalanceSheet(report);

      final expandedIds = <String>{};
      for (final account in hierarchy) {
        if (account.hasChildren) {
          expandedIds.add(account.id);
        }
      }

      emit(BalanceSheetLoaded(
        report: report,
        hierarchy: hierarchy,
        filter: _currentFilter,
        validationResult: validationResult,
        expandedAccountIds: expandedIds,
        currencyFilter: _currencyFilter,
      ));
    } catch (e) {
      emit(BalanceSheetError(e.toString()));
    }
  }

  Future<void> setDateRange(DateTime from, DateTime to) async {
    _currentFilter = _currentFilter.copyWith(fromDate: from, toDate: to);
    await loadReport(refresh: true);
  }

  Future<void> setAsOfDate(DateTime date) async {
    _currentFilter = _currentFilter.copyWith(toDate: date);
    await loadReport(refresh: true);
  }

  void setSearchQuery(String query) {
    if (state is BalanceSheetLoaded) {
      emit((state as BalanceSheetLoaded).copyWith(searchQuery: query));
    }
  }

  Future<void> setCurrencyFilter(String? currency) async {
    _currencyFilter = currency;
    await loadReport(refresh: true);
  }

  void toggleHideZeroBalances() {
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
      emit(loaded.copyWith(hideZeroBalances: !loaded.hideZeroBalances));
    }
  }

  void toggleAccountExpand(String accountId) {
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
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
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
      final allIds = loaded.hierarchy.expand((a) => _collectIds(a)).toSet();
      emit(loaded.copyWith(expandedAccountIds: allIds));
    }
  }

  void collapseAll() {
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
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
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
      final ascending = loaded.sortColumn == column ? !loaded.sortAscending : true;
      emit(loaded.copyWith(sortColumn: column, sortAscending: ascending));
    }
  }

  void toggleFullscreen() {
    if (state is BalanceSheetLoaded) {
      final loaded = state as BalanceSheetLoaded;
      emit(loaded.copyWith(isFullscreen: !loaded.isFullscreen));
    }
  }

  void resetFilters() {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    _currencyFilter = 'EGP';
    loadReport(refresh: true);
  }
}
