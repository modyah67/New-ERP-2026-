part of 'trial_balance_cubit.dart';

abstract class TrialBalanceState extends Equatable {
  const TrialBalanceState();
  @override
  List<Object?> get props => [];
}

class TrialBalanceInitial extends TrialBalanceState {
  const TrialBalanceInitial();
}

class TrialBalanceLoading extends TrialBalanceState {
  const TrialBalanceLoading();
}

class TrialBalanceRefreshing extends TrialBalanceState {
  final TrialBalanceLoaded current;
  const TrialBalanceRefreshing(this.current);
  @override
  List<Object?> get props => [current];
}

class TrialBalanceLoaded extends TrialBalanceState {
  final TrialBalanceReport report;
  final List<AccountHierarchy> hierarchy;
  final ReportFilter filter;
  final ValidationResult? validationResult;
  final Set<String> expandedAccountIds;
  final String? sortColumn;
  final bool sortAscending;
  final String searchQuery;
  final bool hideZeroBalances;
  final bool showParentAccounts;
  final bool isFullscreen;
  final String? currencyFilter;

  const TrialBalanceLoaded({
    required this.report,
    required this.hierarchy,
    required this.filter,
    this.validationResult,
    this.expandedAccountIds = const {},
    this.sortColumn,
    this.sortAscending = true,
    this.searchQuery = '',
    this.hideZeroBalances = false,
    this.showParentAccounts = true,
    this.isFullscreen = false,
    this.currencyFilter,
  });

  TrialBalanceLoaded copyWith({
    TrialBalanceReport? report,
    List<AccountHierarchy>? hierarchy,
    ReportFilter? filter,
    ValidationResult? validationResult,
    Set<String>? expandedAccountIds,
    String? sortColumn,
    bool? sortAscending,
    String? searchQuery,
    bool? hideZeroBalances,
    bool? showParentAccounts,
    bool? isFullscreen,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
  }) {
    return TrialBalanceLoaded(
      report: report ?? this.report,
      hierarchy: hierarchy ?? this.hierarchy,
      filter: filter ?? this.filter,
      validationResult: validationResult ?? this.validationResult,
      expandedAccountIds: expandedAccountIds ?? this.expandedAccountIds,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      searchQuery: searchQuery ?? this.searchQuery,
      hideZeroBalances: hideZeroBalances ?? this.hideZeroBalances,
      showParentAccounts: showParentAccounts ?? this.showParentAccounts,
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
        showParentAccounts,
        isFullscreen,
        currencyFilter,
      ];
}

class TrialBalanceError extends TrialBalanceState {
  final String message;
  const TrialBalanceError(this.message);
  @override
  List<Object?> get props => [message];
}
