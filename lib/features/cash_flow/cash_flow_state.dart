part of 'cash_flow_cubit.dart';

abstract class CashFlowState extends Equatable {
  const CashFlowState();
  @override
  List<Object?> get props => [];
}

class CashFlowInitial extends CashFlowState {
  const CashFlowInitial();
}

class CashFlowLoading extends CashFlowState {
  const CashFlowLoading();
}

class CashFlowRefreshing extends CashFlowState {
  final CashFlowLoaded current;
  const CashFlowRefreshing(this.current);
  @override
  List<Object?> get props => [current];
}

class CashFlowLoaded extends CashFlowState {
  final CashFlowReport report;
  final ReportFilter filter;
  final String searchQuery;
  final bool hideZeroBalances;
  final bool isFullscreen;
  final String? currencyFilter;

  const CashFlowLoaded({
    required this.report,
    required this.filter,
    this.searchQuery = '',
    this.hideZeroBalances = false,
    this.isFullscreen = false,
    this.currencyFilter,
  });

  CashFlowLoaded copyWith({
    CashFlowReport? report,
    ReportFilter? filter,
    String? searchQuery,
    bool? hideZeroBalances,
    bool? isFullscreen,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
  }) {
    return CashFlowLoaded(
      report: report ?? this.report,
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      hideZeroBalances: hideZeroBalances ?? this.hideZeroBalances,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      currencyFilter: clearCurrencyFilter ? null : (currencyFilter ?? this.currencyFilter),
    );
  }

  @override
  List<Object?> get props => [
        report,
        filter,
        searchQuery,
        hideZeroBalances,
        isFullscreen,
        currencyFilter,
      ];
}

class CashFlowError extends CashFlowState {
  final String message;
  const CashFlowError(this.message);
  @override
  List<Object?> get props => [message];
}
