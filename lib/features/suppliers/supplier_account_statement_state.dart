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
  });

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
    );
  }

  @override
  List<Object?> get props => [suppliers, selectedSupplier, statementRows, totalDebit, totalCredit, finalBalance, fromDate, toDate, rowNotes];
}

class SupplierAccountStatementError extends SupplierAccountStatementState {
  final String message;
  const SupplierAccountStatementError({required this.message});
  @override
  List<Object?> get props => [message];
}
