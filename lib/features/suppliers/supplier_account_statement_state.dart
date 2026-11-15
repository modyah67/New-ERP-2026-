import 'package:equatable/equatable.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class SupplierAccountStatementState extends Equatable {
  const SupplierAccountStatementState();
  @override
  List<Object?> get props => [];
}

class SupplierAccountStatementInitial extends SupplierAccountStatementState {
  const SupplierAccountStatementInitial();
}

class SupplierAccountStatementLoading extends SupplierAccountStatementState {
  const SupplierAccountStatementLoading();
}

class SupplierAccountStatementLoaded extends SupplierAccountStatementState {
  final List<SupplierModel> suppliers;
  final SupplierModel? selectedSupplier;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Map<String, String> rowNotes;
  final double openingBalance;
  final Map<String, double> openingBalancesByCurrency;
  final Map<String, double> finalBalancesByCurrency;
  final Map<String, double> totalDebitsByCurrency;
  final Map<String, double> totalCreditsByCurrency;
  final String? selectedCurrency;
  final List<String> availableCurrencies;

  const SupplierAccountStatementLoaded({
    this.suppliers = const [],
    this.selectedSupplier,
    this.statementRows = const [],
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.finalBalance = 0,
    this.statementNumber = 0,
    this.fromDate,
    this.toDate,
    this.rowNotes = const {},
    this.openingBalance = 0,
    this.openingBalancesByCurrency = const {},
    this.finalBalancesByCurrency = const {},
    this.totalDebitsByCurrency = const {},
    this.totalCreditsByCurrency = const {},
    this.selectedCurrency = 'ALL',
    this.availableCurrencies = const ['ALL', 'EGP'],
  });

  String get formattedFinalBalances {
    if (selectedCurrency != null && selectedCurrency != 'ALL') {
      final amt = finalBalancesByCurrency[selectedCurrency] ?? 0.0;
      final sign = amt < 0 ? '-' : '';
      final sym = SupplierModel.getCurrencySymbol(selectedCurrency!);
      final amtFormatted = amt.abs().toStringAsFixed(
          amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
      return '$sign$amtFormatted $sym';
    }
    if (finalBalancesByCurrency.isEmpty) {
      return '';
    }
    final active = finalBalancesByCurrency.entries
        .where((e) => e.value.abs() > 0.001)
        .toList();
    if (active.isEmpty) return '0.00 ج.م';
    return active.map((e) {
      final amt = e.value;
      final sign = amt < 0 ? '-' : '';
      final sym = SupplierModel.getCurrencySymbol(e.key);
      final amtFormatted = amt.abs().toStringAsFixed(
          amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
      return '$sign$amtFormatted $sym';
    }).join(' + ');
  }

  String get formattedOpeningBalances {
    if (selectedCurrency != null && selectedCurrency != 'ALL') {
      final amt = openingBalancesByCurrency[selectedCurrency] ?? 0.0;
      final sign = amt < 0 ? '-' : '';
      final sym = SupplierModel.getCurrencySymbol(selectedCurrency!);
      final amtFormatted = amt.abs().toStringAsFixed(
          amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
      return '$sign$amtFormatted $sym';
    }
    if (openingBalancesByCurrency.isEmpty) {
      return '';
    }
    final active = openingBalancesByCurrency.entries
        .where((e) => e.value.abs() > 0.001)
        .toList();
    if (active.isEmpty) return '0.00 ج.م';
    return active.map((e) {
      final amt = e.value;
      final sign = amt < 0 ? '-' : '';
      final sym = SupplierModel.getCurrencySymbol(e.key);
      final amtFormatted = amt.abs().toStringAsFixed(
          amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
      return '$sign$amtFormatted $sym';
    }).join(' + ');
  }

  SupplierAccountStatementLoaded copyWith({
    List<SupplierModel>? suppliers,
    SupplierModel? selectedSupplier,
    bool clearSelectedSupplier = false,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    Map<String, String>? rowNotes,
    double? openingBalance,
    Map<String, double>? openingBalancesByCurrency,
    Map<String, double>? finalBalancesByCurrency,
    Map<String, double>? totalDebitsByCurrency,
    Map<String, double>? totalCreditsByCurrency,
    String? selectedCurrency,
    bool clearSelectedCurrency = false,
    List<String>? availableCurrencies,
  }) {
    return SupplierAccountStatementLoaded(
      suppliers: suppliers ?? this.suppliers,
      selectedSupplier: clearSelectedSupplier ? null : (selectedSupplier ?? this.selectedSupplier),
      statementRows: statementRows ?? this.statementRows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      statementNumber: statementNumber ?? this.statementNumber,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      rowNotes: rowNotes ?? this.rowNotes,
      openingBalance: openingBalance ?? this.openingBalance,
      openingBalancesByCurrency: openingBalancesByCurrency ?? this.openingBalancesByCurrency,
      finalBalancesByCurrency: finalBalancesByCurrency ?? this.finalBalancesByCurrency,
      totalDebitsByCurrency: totalDebitsByCurrency ?? this.totalDebitsByCurrency,
      totalCreditsByCurrency: totalCreditsByCurrency ?? this.totalCreditsByCurrency,
      selectedCurrency: clearSelectedCurrency ? 'ALL' : (selectedCurrency ?? this.selectedCurrency),
      availableCurrencies: availableCurrencies ?? this.availableCurrencies,
    );
  }

  @override
  List<Object?> get props => [
        suppliers,
        selectedSupplier,
        statementRows,
        totalDebit,
        totalCredit,
        finalBalance,
        fromDate,
        toDate,
        rowNotes,
        openingBalancesByCurrency,
        finalBalancesByCurrency,
        selectedCurrency,
        availableCurrencies,
      ];
}

class SupplierAccountStatementError extends SupplierAccountStatementState {
  final String message;
  const SupplierAccountStatementError({required this.message});
  @override
  List<Object?> get props => [message];
}
