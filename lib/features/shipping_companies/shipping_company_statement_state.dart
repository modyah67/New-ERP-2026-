import 'package:equatable/equatable.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class ShippingCompanyStatementState extends Equatable {
  const ShippingCompanyStatementState();
  @override
  List<Object?> get props => [];
}

class ShippingCompanyStatementInitial extends ShippingCompanyStatementState {
  const ShippingCompanyStatementInitial();
}

class ShippingCompanyStatementLoaded extends ShippingCompanyStatementState {
  final List<ShippingCompanyModel> companies;
  final ShippingCompanyModel? selectedCompany;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Map<String, String> rowNotes;
  final double openingBalance;

  const ShippingCompanyStatementLoaded({
    this.companies = const [],
    this.selectedCompany,
    this.statementRows = const [],
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.finalBalance = 0,
    this.statementNumber = 0,
    this.fromDate,
    this.toDate,
    this.rowNotes = const {},
    this.openingBalance = 0,
  });

  ShippingCompanyStatementLoaded copyWith({
    List<ShippingCompanyModel>? companies,
    ShippingCompanyModel? selectedCompany,
    bool clearSelectedCompany = false,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    Map<String, String>? rowNotes,
    double? openingBalance,
  }) {
    return ShippingCompanyStatementLoaded(
      companies: companies ?? this.companies,
      selectedCompany: clearSelectedCompany ? null : (selectedCompany ?? this.selectedCompany),
      statementRows: statementRows ?? this.statementRows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      statementNumber: statementNumber ?? this.statementNumber,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      rowNotes: rowNotes ?? this.rowNotes,
      openingBalance: openingBalance ?? this.openingBalance,
    );
  }

  @override
  List<Object?> get props => [companies, selectedCompany, statementRows, totalDebit, totalCredit, finalBalance, fromDate, toDate, rowNotes, openingBalance];
}

class ShippingCompanyStatementError extends ShippingCompanyStatementState {
  final String message;
  const ShippingCompanyStatementError({required this.message});
  @override
  List<Object?> get props => [message];
}
