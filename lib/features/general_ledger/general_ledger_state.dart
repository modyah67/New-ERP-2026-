part of 'general_ledger_cubit.dart';

abstract class GeneralLedgerState extends Equatable {
  const GeneralLedgerState();
  @override
  List<Object?> get props => [];
}

class GeneralLedgerInitial extends GeneralLedgerState {
  const GeneralLedgerInitial();
}

class GeneralLedgerLoading extends GeneralLedgerState {
  const GeneralLedgerLoading();
}

class GeneralLedgerRefreshing extends GeneralLedgerState {
  final GeneralLedgerLoaded current;
  const GeneralLedgerRefreshing(this.current);
  @override
  List<Object?> get props => [current];
}

class GeneralLedgerLoaded extends GeneralLedgerState {
  final LedgerReport report;
  final ReportFilter filter;
  final String? sortColumn;
  final bool sortAscending;
  final bool isFullscreen;
  final String? drillDownAccountCode;
  final String? drillDownAccountName;
  final String searchQuery;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
  final double lastRunningBalance;
  final String? currencyFilter;

  const GeneralLedgerLoaded({
    required this.report,
    required this.filter,
    this.sortColumn,
    this.sortAscending = true,
    this.isFullscreen = false,
    this.drillDownAccountCode,
    this.drillDownAccountName,
    this.searchQuery = '',
    this.nextCursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.lastRunningBalance = 0,
    this.currencyFilter,
  });

  GeneralLedgerLoaded copyWith({
    LedgerReport? report,
    ReportFilter? filter,
    String? sortColumn,
    bool? sortAscending,
    bool? isFullscreen,
    String? drillDownAccountCode,
    String? drillDownAccountName,
    String? searchQuery,
    String? nextCursor,
    bool? hasMore,
    bool? isLoadingMore,
    double? lastRunningBalance,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
  }) {
    return GeneralLedgerLoaded(
      report: report ?? this.report,
      filter: filter ?? this.filter,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      drillDownAccountCode: drillDownAccountCode ?? this.drillDownAccountCode,
      drillDownAccountName: drillDownAccountName ?? this.drillDownAccountName,
      searchQuery: searchQuery ?? this.searchQuery,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      lastRunningBalance: lastRunningBalance ?? this.lastRunningBalance,
      currencyFilter: clearCurrencyFilter ? null : (currencyFilter ?? this.currencyFilter),
    );
  }

  @override
  List<Object?> get props => [
        report,
        filter,
        sortColumn,
        sortAscending,
        isFullscreen,
        drillDownAccountCode,
        drillDownAccountName,
        searchQuery,
        nextCursor,
        hasMore,
        isLoadingMore,
        lastRunningBalance,
        currencyFilter,
      ];
}

class GeneralLedgerError extends GeneralLedgerState {
  final String message;
  const GeneralLedgerError(this.message);
  @override
  List<Object?> get props => [message];
}
