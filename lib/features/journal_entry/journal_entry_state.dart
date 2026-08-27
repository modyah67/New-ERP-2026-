import 'package:equatable/equatable.dart';
import '../../data/models/account_model.dart';

abstract class JournalEntryState extends Equatable {
  const JournalEntryState();

  @override
  List<Object?> get props => [];
}

class JournalEntryInitial extends JournalEntryState {
  const JournalEntryInitial();
}

class JournalEntryLoading extends JournalEntryState {
  const JournalEntryLoading();
}

class JournalEntryLoaded extends JournalEntryState {
  final List<AccountModel> accounts;
  final List<Map<String, dynamic>> journalEntries;
  final AccountModel? selectedDebitAccount;
  final AccountModel? selectedCreditAccount;
  final DateTime transactionDate;
  final double totalBalances;
  final int totalAccountsCount;
  final int totalEntriesCount;
  final bool isSaving;
  final String historySearchQuery;
  final DateTime? historyFromDate;
  final DateTime? historyToDate;
  final List<AccountModel> debitResults;
  final List<AccountModel> creditResults;
  final int debitHighlightIdx;
  final int creditHighlightIdx;
  final bool isSingleEntryLoading;
  final String? singleEntryError;
  final String? singleEntryTitle;

  const JournalEntryLoaded({
    required this.accounts,
    required this.journalEntries,
    this.selectedDebitAccount,
    this.selectedCreditAccount,
    required this.transactionDate,
    required this.totalBalances,
    required this.totalAccountsCount,
    required this.totalEntriesCount,
    this.isSaving = false,
    this.historySearchQuery = '',
    this.historyFromDate,
    this.historyToDate,
    this.debitResults = const [],
    this.creditResults = const [],
    this.debitHighlightIdx = 0,
    this.creditHighlightIdx = 0,
    this.isSingleEntryLoading = false,
    this.singleEntryError,
    this.singleEntryTitle,
  });

  JournalEntryLoaded copyWith({
    List<AccountModel>? accounts,
    List<Map<String, dynamic>>? journalEntries,
    AccountModel? selectedDebitAccount,
    AccountModel? selectedCreditAccount,
    DateTime? transactionDate,
    double? totalBalances,
    int? totalAccountsCount,
    int? totalEntriesCount,
    bool? isSaving,
    String? historySearchQuery,
    DateTime? historyFromDate,
    DateTime? historyToDate,
    List<AccountModel>? debitResults,
    List<AccountModel>? creditResults,
    int? debitHighlightIdx,
    int? creditHighlightIdx,
    bool clearSelectedDebitAccount = false,
    bool clearSelectedCreditAccount = false,
    bool clearHistoryFromDate = false,
    bool clearHistoryToDate = false,
    bool? isSingleEntryLoading,
    String? singleEntryError,
    String? singleEntryTitle,
    bool clearSingleEntryError = false,
    bool clearSingleEntryTitle = false,
  }) {
    return JournalEntryLoaded(
      accounts: accounts ?? this.accounts,
      journalEntries: journalEntries ?? this.journalEntries,
      selectedDebitAccount: clearSelectedDebitAccount
          ? null
          : (selectedDebitAccount ?? this.selectedDebitAccount),
      selectedCreditAccount: clearSelectedCreditAccount
          ? null
          : (selectedCreditAccount ?? this.selectedCreditAccount),
      transactionDate: transactionDate ?? this.transactionDate,
      totalBalances: totalBalances ?? this.totalBalances,
      totalAccountsCount: totalAccountsCount ?? this.totalAccountsCount,
      totalEntriesCount: totalEntriesCount ?? this.totalEntriesCount,
      isSaving: isSaving ?? this.isSaving,
      historySearchQuery: historySearchQuery ?? this.historySearchQuery,
      historyFromDate: clearHistoryFromDate
          ? null
          : (historyFromDate ?? this.historyFromDate),
      historyToDate: clearHistoryToDate
          ? null
          : (historyToDate ?? this.historyToDate),
      debitResults: debitResults ?? this.debitResults,
      creditResults: creditResults ?? this.creditResults,
      debitHighlightIdx: debitHighlightIdx ?? this.debitHighlightIdx,
      creditHighlightIdx: creditHighlightIdx ?? this.creditHighlightIdx,
      isSingleEntryLoading: isSingleEntryLoading ?? this.isSingleEntryLoading,
      singleEntryError: clearSingleEntryError
          ? null
          : (singleEntryError ?? this.singleEntryError),
      singleEntryTitle: clearSingleEntryTitle
          ? null
          : (singleEntryTitle ?? this.singleEntryTitle),
    );
  }

  @override
  List<Object?> get props => [
        accounts,
        journalEntries,
        selectedDebitAccount,
        selectedCreditAccount,
        transactionDate,
        totalBalances,
        totalAccountsCount,
        totalEntriesCount,
        isSaving,
        historySearchQuery,
        historyFromDate,
        historyToDate,
        debitResults,
        creditResults,
        debitHighlightIdx,
        creditHighlightIdx,
        isSingleEntryLoading,
        singleEntryError,
        singleEntryTitle,
      ];
}

class JournalEntryError extends JournalEntryState {
  final String message;

  const JournalEntryError({required this.message});

  @override
  List<Object?> get props => [message];
}
