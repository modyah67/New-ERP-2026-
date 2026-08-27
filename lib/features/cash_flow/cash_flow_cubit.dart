library;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounting/reporting/models/report_models.dart';
import '../../accounting/reporting/services/report_calculation_service.dart';
import '../../accounting/reporting/services/report_filter_service.dart';

part 'cash_flow_state.dart';

class CashFlowCubit extends Cubit<CashFlowState> {
  final ReportCalculationService _calculationService;
  final ReportFilterService _filterService;

  ReportFilter _currentFilter = ReportFilter.defaultFilter();
  String? _currencyFilter = 'EGP';

  CashFlowCubit({
    required ReportCalculationService calculationService,
    required ReportFilterService filterService,
  })  : _calculationService = calculationService,
        _filterService = filterService,
        super(const CashFlowInitial());

  Future<void> init() async {
    final now = DateTime.now();
    _currentFilter = ReportFilter(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
    await loadReport();
  }

  Future<void> loadReport({bool refresh = false}) async {
    if (state is CashFlowLoading) return;
    if (refresh && state is CashFlowLoaded) {
      emit(CashFlowRefreshing(state as CashFlowLoaded));
    } else {
      emit(const CashFlowLoading());
    }

    try {
      final fromDate = _currentFilter.fromDate ?? DateTime(DateTime.now().year, 1, 1);
      final toDate = _currentFilter.toDate ?? DateTime.now();

      final report = await _calculationService.calculateCashFlowStatement(
        fromDate: fromDate,
        toDate: toDate,
        currency: _currencyFilter,
      );

      emit(CashFlowLoaded(
        report: report,
        filter: _currentFilter,
        currencyFilter: _currencyFilter,
      ));
    } catch (e) {
      emit(CashFlowError(e.toString()));
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
    if (state is CashFlowLoaded) {
      emit((state as CashFlowLoaded).copyWith(searchQuery: query));
    }
  }

  Future<void> setCurrencyFilter(String? currency) async {
    _currencyFilter = currency;
    await loadReport(refresh: true);
  }

  void toggleHideZeroBalances() {
    if (state is CashFlowLoaded) {
      final loaded = state as CashFlowLoaded;
      emit(loaded.copyWith(hideZeroBalances: !loaded.hideZeroBalances));
    }
  }

  void toggleFullscreen() {
    if (state is CashFlowLoaded) {
      final loaded = state as CashFlowLoaded;
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
