import '../../data/models/shareholder_model.dart';
import '../../data/models/statement_row_model.dart';

class ShareholderStatementState {
  final List<ShareholderModel> shareholders;
  final ShareholderModel? selectedShareholder;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String selectedCurrency;
  final List<StatementRow> rows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final double totalProfitShare;
  final double openingBalance;
  final Map<String, String> rowNotes;
  final bool loading;

  const ShareholderStatementState({
    this.shareholders = const [],
    this.selectedShareholder,
    this.fromDate,
    this.toDate,
    this.selectedCurrency = 'EGP',
    this.rows = const [],
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.finalBalance = 0,
    this.totalProfitShare = 0,
    this.openingBalance = 0,
    this.rowNotes = const {},
    this.loading = false,
  });

  ShareholderStatementState copyWith({
    List<ShareholderModel>? shareholders,
    ShareholderModel? selectedShareholder,
    bool clearSelected = false,
    DateTime? fromDate,
    DateTime? toDate,
    String? selectedCurrency,
    List<StatementRow>? rows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    double? totalProfitShare,
    double? openingBalance,
    Map<String, String>? rowNotes,
    bool? loading,
  }) {
    return ShareholderStatementState(
      shareholders: shareholders ?? this.shareholders,
      selectedShareholder: clearSelected ? null : (selectedShareholder ?? this.selectedShareholder),
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      selectedCurrency: selectedCurrency ?? this.selectedCurrency,
      rows: rows ?? this.rows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      totalProfitShare: totalProfitShare ?? this.totalProfitShare,
      openingBalance: openingBalance ?? this.openingBalance,
      rowNotes: rowNotes ?? this.rowNotes,
      loading: loading ?? this.loading,
    );
  }
}
