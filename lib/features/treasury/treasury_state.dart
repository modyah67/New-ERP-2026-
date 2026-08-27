import 'package:equatable/equatable.dart';
import '../../data/models/treasury_model.dart';
import '../../data/models/expense_category_model.dart';
import '../../data/models/treasury_stats_model.dart';

abstract class TreasuryState extends Equatable {
  const TreasuryState();

  @override
  List<Object?> get props => [];
}

class TreasuryInitial extends TreasuryState {}

class TreasuryLoading extends TreasuryState {}

class TreasuryLoaded extends TreasuryState {
  final List<TreasuryModel> treasuries;
  final TreasuryModel? mainTreasury;
  final List<TreasuryModel> employeeTreasuries;
  final bool isAdmin;
  final bool hasOwnerSafe;
  final List<TreasuryTransactionModel> transactions;
  final TreasuryModel? selectedTreasury;
  final bool hasMore;
  final bool isFetchingMore;
  final bool isSaving;
  final String? errorMessage;
  final List<ExpenseCategoryModel> categories;
  final List<Map<String, dynamic>> expenseAccounts;
  final List<CurrencyTotal> currencyTotals;
  final double totalEmployeeCustody;
  final TreasuryStatsModel? stats;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? selectedCurrencyFilter;
  final String? searchQuery;
  final String? selectedFromAccountId;
  final String? selectedToAccountId;

  const TreasuryLoaded({
    required this.treasuries,
    this.mainTreasury,
    this.employeeTreasuries = const [],
    this.isAdmin = false,
    this.hasOwnerSafe = false,
    this.transactions = const [],
    this.selectedTreasury,
    this.hasMore = true,
    this.isFetchingMore = false,
    this.isSaving = false,
    this.errorMessage,
    this.categories = const [],
    this.expenseAccounts = const [],
    this.currencyTotals = const [],
    this.totalEmployeeCustody = 0.0,
    this.stats,
    this.startDate,
    this.endDate,
    this.selectedCurrencyFilter,
    this.searchQuery,
    this.selectedFromAccountId,
    this.selectedToAccountId,
  });

  TreasuryModel? get treasuryForCurrentUser {
    if (isAdmin && mainTreasury != null) return mainTreasury;
    if (hasOwnerSafe && mainTreasury != null) return mainTreasury;
    if (!isAdmin && treasuries.isNotEmpty) return treasuries.first;
    return null;
  }

  /// Calculates filtered transactions based on searchQuery, txId, date range, currency, and from/to accounts (AND logic)
  List<TreasuryTransactionModel> get filteredTransactions {
    return transactions.where((tx) {
      // 1. Currency filter
      if (selectedCurrencyFilter != null &&
          selectedCurrencyFilter!.isNotEmpty &&
          selectedCurrencyFilter != 'ALL') {
        if (tx.currency.toUpperCase() != selectedCurrencyFilter!.toUpperCase()) {
          return false;
        }
      }

      // 2. Date Range filter
      if (startDate != null || endDate != null) {
        final txDate = DateTime.tryParse(tx.createdAt);
        if (txDate != null) {
          if (startDate != null) {
            final startBoundary = DateTime(startDate!.year, startDate!.month, startDate!.day);
            if (txDate.isBefore(startBoundary)) return false;
          }
          if (endDate != null) {
            final endBoundary = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
            if (txDate.isAfter(endBoundary)) return false;
          }
        }
      }

      // 3. From Account / Treasury filter
      if (selectedFromAccountId != null && selectedFromAccountId!.isNotEmpty) {
        final fromMatch = tx.treasuryId == selectedFromAccountId ||
            tx.treasuryName.toLowerCase().contains(selectedFromAccountId!.toLowerCase());
        if (!fromMatch) return false;
      }

      // 4. To Account / Counterparty filter (supports composite keys like "type:id")
      if (selectedToAccountId != null && selectedToAccountId!.isNotEmpty) {
        final parts = selectedToAccountId!.split(':');
        final filterType = parts.length > 1 ? parts[0] : null;
        final filterId = parts.length > 1 ? parts.sublist(1).join(':') : selectedToAccountId!;

        bool toMatch = false;
        if (filterType == 'customer') {
          toMatch = tx.customerId == filterId;
        } else if (filterType == 'supplier') {
          toMatch = tx.supplierId == filterId;
        } else if (filterType == 'clearing_agent') {
          toMatch = tx.clearingAgentId == filterId;
        } else if (filterType == 'shipping_company') {
          toMatch = tx.shippingCompanyId == filterId;
        } else if (filterType == 'shareholder') {
          toMatch = tx.shareholderId == filterId;
        } else if (filterType == 'treasury') {
          toMatch = tx.relatedTreasuryId == filterId;
        } else {
          toMatch = tx.relatedTreasuryId == selectedToAccountId ||
              (tx.relatedTreasuryName != null &&
                  tx.relatedTreasuryName!.toLowerCase().contains(selectedToAccountId!.toLowerCase())) ||
              (tx.supplierId != null && tx.supplierId == selectedToAccountId) ||
              (tx.customerId != null && tx.customerId == selectedToAccountId) ||
              (tx.clearingAgentId != null && tx.clearingAgentId == selectedToAccountId) ||
              (tx.shippingCompanyId != null && tx.shippingCompanyId == selectedToAccountId) ||
              (tx.shareholderId != null && tx.shareholderId == selectedToAccountId) ||
              (tx.description != null &&
                  tx.description!.toLowerCase().contains(selectedToAccountId!.toLowerCase()));
        }
        if (!toMatch) return false;
      }

      // 5. Search Query / Transaction ID filter (Instant & Partial Match)
      if (searchQuery != null && searchQuery!.trim().isNotEmpty) {
        final q = searchQuery!.trim().toLowerCase();

        // Check if user entered a transaction ID (e.g. "#3" or "3")
        final cleanIdQuery = q.replaceAll('#', '').trim();
        final isNumeric = int.tryParse(cleanIdQuery) != null;

        if (isNumeric &&
            (tx.id == cleanIdQuery ||
                tx.id == q ||
                (tx.id != null && tx.id!.endsWith(cleanIdQuery)))) {
          return true;
        }

        // Match description, treasury names, category, type label, or supplier/customer
        final descMatch = tx.description?.toLowerCase().contains(q) ?? false;
        final treasuryMatch = tx.treasuryName.toLowerCase().contains(q);
        final relatedTreasuryMatch =
            tx.relatedTreasuryName?.toLowerCase().contains(q) ?? false;
        final catMatch = tx.categoryName?.toLowerCase().contains(q) ?? false;
        final typeMatch = tx.typeLabel.toLowerCase().contains(q);
        final idMatch = tx.id?.toLowerCase().contains(q) ?? false;
        final supplierMatch = tx.supplierName?.toLowerCase().contains(q) ?? false;
        final customerMatch = tx.customerName?.toLowerCase().contains(q) ?? false;

        if (!descMatch &&
            !treasuryMatch &&
            !relatedTreasuryMatch &&
            !catMatch &&
            !typeMatch &&
            !idMatch &&
            !supplierMatch &&
            !customerMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  List<Object?> get props => [
        treasuries,
        mainTreasury,
        employeeTreasuries,
        isAdmin,
        hasOwnerSafe,
        transactions,
        selectedTreasury,
        hasMore,
        isFetchingMore,
        isSaving,
        errorMessage,
        categories,
        expenseAccounts,
        currencyTotals,
        totalEmployeeCustody,
        stats,
        startDate,
        endDate,
        selectedCurrencyFilter,
        searchQuery,
        selectedFromAccountId,
        selectedToAccountId,
      ];

  TreasuryLoaded copyWith({
    List<TreasuryModel>? treasuries,
    TreasuryModel? mainTreasury,
    List<TreasuryModel>? employeeTreasuries,
    bool? isAdmin,
    bool? hasOwnerSafe,
    List<TreasuryTransactionModel>? transactions,
    TreasuryModel? selectedTreasury,
    bool? hasMore,
    bool? isFetchingMore,
    bool? isSaving,
    bool clearMain = false,
    bool clearSelected = false,
    String? errorMessage,
    bool clearError = false,
    List<ExpenseCategoryModel>? categories,
    List<Map<String, dynamic>>? expenseAccounts,
    List<CurrencyTotal>? currencyTotals,
    double? totalEmployeeCustody,
    TreasuryStatsModel? stats,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDateRange = false,
    String? selectedCurrencyFilter,
    bool clearCurrencyFilter = false,
    String? searchQuery,
    bool clearSearchQuery = false,
    String? selectedFromAccountId,
    bool clearFromAccount = false,
    String? selectedToAccountId,
    bool clearToAccount = false,
  }) {
    return TreasuryLoaded(
      treasuries: treasuries ?? this.treasuries,
      mainTreasury: clearMain ? null : mainTreasury ?? this.mainTreasury,
      employeeTreasuries: employeeTreasuries ?? this.employeeTreasuries,
      isAdmin: isAdmin ?? this.isAdmin,
      hasOwnerSafe: hasOwnerSafe ?? this.hasOwnerSafe,
      transactions: transactions ?? this.transactions,
      selectedTreasury:
          clearSelected ? null : selectedTreasury ?? this.selectedTreasury,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      isSaving: isSaving ?? this.isSaving,
      errorMessage:
          clearError ? null : errorMessage ?? this.errorMessage,
      categories: categories ?? this.categories,
      expenseAccounts: expenseAccounts ?? this.expenseAccounts,
      currencyTotals: currencyTotals ?? this.currencyTotals,
      totalEmployeeCustody: totalEmployeeCustody ?? this.totalEmployeeCustody,
      stats: stats ?? this.stats,
      startDate: clearDateRange ? null : startDate ?? this.startDate,
      endDate: clearDateRange ? null : endDate ?? this.endDate,
      selectedCurrencyFilter: clearCurrencyFilter ? null : selectedCurrencyFilter ?? this.selectedCurrencyFilter,
      searchQuery: clearSearchQuery ? null : searchQuery ?? this.searchQuery,
      selectedFromAccountId: clearFromAccount ? null : selectedFromAccountId ?? this.selectedFromAccountId,
      selectedToAccountId: clearToAccount ? null : selectedToAccountId ?? this.selectedToAccountId,
    );
  }
}

class TreasuryError extends TreasuryState {
  final String message;
  const TreasuryError({required this.message});

  @override
  List<Object?> get props => [message];
}
