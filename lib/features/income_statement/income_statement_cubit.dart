library;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/services/report_calculation_service.dart';
import '../../accounting/reporting/services/report_filter_service.dart';
import '../../accounting/reporting/services/report_validation_service.dart';

part 'income_statement_state.dart';

class IncomeStatementCubit extends Cubit<IncomeStatementState> {
  final ReportCalculationService _calculationService;
  final ReportFilterService _filterService;
  final ReportValidationService _validationService;

  ReportFilter _currentFilter = ReportFilter.defaultFilter();
  String? _currencyFilter = 'EGP';

  IncomeStatementCubit({
    required ReportCalculationService calculationService,
    required ReportFilterService filterService,
    required ReportValidationService validationService,
  })  : _calculationService = calculationService,
        _filterService = filterService,
        _validationService = validationService,
        super(const IncomeStatementInitial());

  Future<void> init() async {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    await loadReport();
  }

  Future<void> loadReport({bool refresh = false}) async {
    if (state is IncomeStatementLoading) return;
    if (refresh && state is IncomeStatementLoaded) {
      emit(IncomeStatementRefreshing(state as IncomeStatementLoaded));
    } else {
      emit(const IncomeStatementLoading());
    }

    try {
      final fromDate = _currentFilter.fromDate ?? DateTime(DateTime.now().year, 1, 1);
      final toDate = _currentFilter.toDate ?? DateTime.now();

      final report = await _calculationService.calculateIncomeStatement(
        fromDate: fromDate,
        toDate: toDate,
        currency: _currencyFilter,
      );

      final expandedIds = <String>{};
      expandedIds.add('revenue');
      expandedIds.add('cogs');
      expandedIds.add('expenses');

      emit(IncomeStatementLoaded(
        report: report,
        filter: _currentFilter,
        expandedAccountIds: expandedIds,
        currencyFilter: _currencyFilter,
      ));
    } catch (e) {
      emit(IncomeStatementError(e.toString()));
    }
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

  void setSearchQuery(String query) {
    if (state is IncomeStatementLoaded) {
      emit((state as IncomeStatementLoaded).copyWith(searchQuery: query));
    }
  }

  Future<void> setCurrencyFilter(String? currency) async {
    _currencyFilter = currency;
    await loadReport(refresh: true);
  }

  void toggleHideZeroBalances() {
    if (state is IncomeStatementLoaded) {
      final loaded = state as IncomeStatementLoaded;
      emit(loaded.copyWith(hideZeroBalances: !loaded.hideZeroBalances));
    }
  }

  void toggleFullscreen() {
    if (state is IncomeStatementLoaded) {
      final loaded = state as IncomeStatementLoaded;
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
