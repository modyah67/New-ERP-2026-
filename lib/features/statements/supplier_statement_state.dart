import 'package:equatable/equatable.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class SupplierStatementState extends Equatable {
  const SupplierStatementState();

  @override
  List<Object?> get props => [];
}

class SupplierStatementInitial extends SupplierStatementState {
  const SupplierStatementInitial();
}

class SupplierStatementLoading extends SupplierStatementState {
  const SupplierStatementLoading();
}

class SupplierStatementLoaded extends SupplierStatementState {
  final List<SupplierModel> suppliers;
  final SupplierModel? selectedSupplier;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;

  const SupplierStatementLoaded({
    required this.suppliers,
    this.selectedSupplier,
    required this.statementRows,
    required this.totalDebit,
    required this.totalCredit,
    required this.finalBalance,
    required this.statementNumber,
    this.fromDate,
    this.toDate,
  });

  SupplierStatementLoaded copyWith({
    List<SupplierModel>? suppliers,
    SupplierModel? selectedSupplier,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearSelectedSupplier = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return SupplierStatementLoaded(
      suppliers: suppliers ?? this.suppliers,
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      statementRows: statementRows ?? this.statementRows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      statementNumber: statementNumber ?? this.statementNumber,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
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
        statementNumber,
        fromDate,
        toDate,
      ];
}

class SupplierStatementError extends SupplierStatementState {
  final String message;

  const SupplierStatementError({required this.message});

  @override
  List<Object?> get props => [message];
}
