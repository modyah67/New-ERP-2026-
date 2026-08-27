part of 'balance_sheet_cubit.dart';

abstract class BalanceSheetState extends Equatable {
  const BalanceSheetState();
  @override
  List<Object?> get props => [];
}

class BalanceSheetInitial extends BalanceSheetState {
  const BalanceSheetInitial();
}

class BalanceSheetLoading extends BalanceSheetState {
  const BalanceSheetLoading();
}

class BalanceSheetRefreshing extends BalanceSheetState {
  final BalanceSheetLoaded current;
  const BalanceSheetRefreshing(this.current);
  @override
  List<Object?> get props => [current];
}

class BalanceSheetLoaded extends BalanceSheetState {
  final BalanceSheetReport report;
  final List<AccountHierarchy> hierarchy;
  final ReportFilter filter;
  final ValidationResult? validationResult;
  final Set<String> expandedAccountIds;
  final String? sortColumn;
  final bool sortAscending;
  final String searchQuery;
  final bool hideZeroBalances;
  final bool isFullscreen;
  final String? currencyFilter;

  const BalanceSheetLoaded({
    required this.report,
    required this.hierarchy,
    required this.filter,
    this.validationResult,
    this.expandedAccountIds = const {},
    this.sortColumn,
    this.sortAscending = true,
    this.searchQuery = '',
    this.hideZeroBalances = false,
    this.isFullscreen = false,
    this.currencyFilter,
  });

  BalanceSheetLoaded copyWith({
    BalanceSheetReport? report,
    List<AccountHierarchy>? hierarchy,
    ReportFilter? filter,
    ValidationResult? validationResult,
    Set<String>? expandedAccountIds,
    String? sortColumn,
    bool? sortAscending,
    String? searchQuery,
    bool? hideZeroBalances,
    bool? isFullscreen,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
  }) {
    return BalanceSheetLoaded(
      report: report ?? this.report,
      hierarchy: hierarchy ?? this.hierarchy,
      filter: filter ?? this.filter,
      validationResult: validationResult ?? this.validationResult,
      expandedAccountIds: expandedAccountIds ?? this.expandedAccountIds,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      searchQuery: searchQuery ?? this.searchQuery,
      hideZeroBalances: hideZeroBalances ?? this.hideZeroBalances,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      currencyFilter: clearCurrencyFilter ? null : (currencyFilter ?? this.currencyFilter),
    );
  }

  @override
  List<Object?> get props => [
        report,
        hierarchy,
        filter,
        validationResult,
        expandedAccountIds,
        sortColumn,
        sortAscending,
        searchQuery,
        hideZeroBalances,
        isFullscreen,
        currencyFilter,
      ];
}

class BalanceSheetError extends BalanceSheetState {
  final String message;
  const BalanceSheetError(this.message);
  @override
  List<Object?> get props => [message];
}
