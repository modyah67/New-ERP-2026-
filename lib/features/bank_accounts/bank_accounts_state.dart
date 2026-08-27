import 'package:equatable/equatable.dart';
import '../../data/models/bank_account_model.dart';
import '../../data/models/bank_account_transaction_model.dart';

abstract class BankAccountsState extends Equatable {
  const BankAccountsState();
  @override
  List<Object?> get props => [];
}

class BankAccountsInitial extends BankAccountsState {
  const BankAccountsInitial();
}

class BankAccountsLoading extends BankAccountsState {
  const BankAccountsLoading();
}

class BankAccountsLoaded extends BankAccountsState {
  final List<BankAccountModel> accounts;
  final List<BankAccountTransactionModel> transactions;
  final int? selectedAccountId;
  final bool isSaving;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? currencyFilter;
  final int? accountFilter;
  final String searchQuery;
  final Map<String, String> userNamesCache;

  const BankAccountsLoaded({
    required this.accounts,
    this.transactions = const [],
    this.selectedAccountId,
    this.isSaving = false,
    this.startDate,
    this.endDate,
    this.currencyFilter,
    this.accountFilter,
    this.searchQuery = '',
    this.userNamesCache = const {},
  });

  BankAccountModel? getByCurrency(String currency) {
    try {
      return accounts.firstWhere((a) => a.currency == currency);
    } catch (_) {
      return null;
    }
  }

  BankAccountsLoaded copyWith({
    List<BankAccountModel>? accounts,
    List<BankAccountTransactionModel>? transactions,
    int? selectedAccountId,
    bool? isSaving,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDates = false,
    String? currencyFilter,
    bool clearCurrencyFilter = false,
    int? accountFilter,
    bool clearAccountFilter = false,
    String? searchQuery,
    Map<String, String>? userNamesCache,
  }) {
    return BankAccountsLoaded(
      accounts: accounts ?? this.accounts,
      transactions: transactions ?? this.transactions,
      selectedAccountId: selectedAccountId ?? this.selectedAccountId,
      isSaving: isSaving ?? this.isSaving,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      currencyFilter: clearCurrencyFilter ? null : (currencyFilter ?? this.currencyFilter),
      accountFilter: clearAccountFilter ? null : (accountFilter ?? this.accountFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      userNamesCache: userNamesCache ?? this.userNamesCache,
    );
  }

  List<BankAccountTransactionModel> get filteredTransactions {
    return transactions.where((tx) {
      if (startDate != null) {
        final startBoundary = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (tx.createdAt.isBefore(startBoundary)) return false;
      }
      if (endDate != null) {
        final endBoundary = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
        if (tx.createdAt.isAfter(endBoundary)) return false;
      }
      if (currencyFilter != null && currencyFilter!.isNotEmpty) {
        final txAccount = accounts.where((a) => a.id == tx.bankAccountId).toList();
        if (txAccount.isNotEmpty && txAccount.first.currency != currencyFilter) return false;
      }
      if (accountFilter != null) {
        if (tx.bankAccountId != accountFilter) return false;
      }
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        final cleanIdQuery = q.replaceAll('#', '').trim();
        final idMatch = tx.journalEntryId?.toLowerCase().contains(q) ?? false;
        final idNumMatch = cleanIdQuery.isNotEmpty &&
            (tx.journalEntryId?.contains(cleanIdQuery) ?? false);
        final descMatch = tx.description?.toLowerCase().contains(q) ?? false;
        final createdByNameMatch = tx.createdByName?.toLowerCase().contains(q) ?? false;
        final partyMatch = tx.relatedPartyName?.toLowerCase().contains(q) ?? false;
        if (!idMatch && !idNumMatch && !descMatch && !createdByNameMatch && !partyMatch) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  List<Object?> get props => [
        accounts,
        transactions,
        selectedAccountId,
        isSaving,
        startDate,
        endDate,
        currencyFilter,
        accountFilter,
        searchQuery,
        userNamesCache,
      ];
}

class BankAccountsError extends BankAccountsState {
  final String message;
  const BankAccountsError(this.message);
  @override
  List<Object?> get props => [message];
}
