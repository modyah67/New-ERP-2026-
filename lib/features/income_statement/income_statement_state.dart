part of 'income_statement_cubit.dart';

abstract class IncomeStatementState extends Equatable {
  const IncomeStatementState();
  @override
  List<Object?> get props => [];
}

class IncomeStatementInitial extends IncomeStatementState {
  const IncomeStatementInitial();
}

class IncomeStatementLoading extends IncomeStatementState {
  const IncomeStatementLoading();
}

class IncomeStatementRefreshing extends IncomeStatementState {
  final IncomeStatementLoaded current;
  const IncomeStatementRefreshing(this.current);
  @override
  List<Object?> get props => [current];
}

class IncomeStatementLoaded extends IncomeStatementState {
  final IncomeStatementReport report;
  final ReportFilter filter;
  final ValidationResult? validationResult;
  final Set<String> expandedAccountIds;
  final String searchQuery;
  final bool hideZeroBalances;
  final bool isFullscreen;
  final String? currencyFilter;

  const IncomeStatementLoaded({
    required this.report,
    required this.filter,
    this.validationResult,
    this.expandedAccountIds = const {},
    this.searchQuery = '',
    this.hideZeroBalances = false,
    this.isFullscreen = false,
    this.currencyFilter,
  });

  IncomeStatementLoaded copyWith({
    IncomeStatementReport? report,
    ReportFilter? filter,
    ValidationResult? validationResult,
    Set<String>? expandedAccountIds,
    String? searchQuery,
    bool? hideZeroBalances,
    bool? isFullscreen,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
  }) {
    return IncomeStatementLoaded(
      report: report ?? this.report,
      filter: filter ?? this.filter,
      validationResult: validationResult ?? this.validationResult,
      expandedAccountIds: expandedAccountIds ?? this.expandedAccountIds,
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
        validationResult,
        expandedAccountIds,
        searchQuery,
        hideZeroBalances,
        isFullscreen,
        currencyFilter,
      ];
}

class IncomeStatementError extends IncomeStatementState {
  final String message;
  const IncomeStatementError(this.message);
  @override
  List<Object?> get props => [message];
}
