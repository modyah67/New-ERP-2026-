import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class StatementState extends Equatable {
  const StatementState();

  @override
  List<Object?> get props => [];
}

class StatementInitial extends StatementState {
  const StatementInitial();
}

class StatementLoading extends StatementState {
  const StatementLoading();
}

class StatementLoaded extends StatementState {
  final List<CustomerModel> customers;
  final CustomerModel? selectedCustomer;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;

  const StatementLoaded({
    required this.customers,
    this.selectedCustomer,
    required this.statementRows,
    required this.totalDebit,
    required this.totalCredit,
    required this.finalBalance,
    required this.statementNumber,
    this.fromDate,
    this.toDate,
  });

  StatementLoaded copyWith({
    List<CustomerModel>? customers,
    CustomerModel? selectedCustomer,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearSelectedCustomer = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return StatementLoaded(
      customers: customers ?? this.customers,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
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
        customers,
        selectedCustomer,
        statementRows,
        totalDebit,
        totalCredit,
        finalBalance,
        statementNumber,
        fromDate,
        toDate,
      ];
}

class StatementError extends StatementState {
  final String message;

  const StatementError({required this.message});

  @override
  List<Object?> get props => [message];
}
