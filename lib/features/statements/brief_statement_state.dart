import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class BriefStatementState extends Equatable {
  const BriefStatementState();

  @override
  List<Object?> get props => [];
}

class BriefStatementInitial extends BriefStatementState {
  const BriefStatementInitial();
}

class BriefStatementLoading extends BriefStatementState {
  const BriefStatementLoading();
}

class BriefStatementLoaded extends BriefStatementState {
  final bool isCustomerMode;
  final List<CustomerModel> customers;
  final List<SupplierModel> suppliers;
  final CustomerModel? selectedCustomer;
  final SupplierModel? selectedSupplier;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final double totalMeters;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;

  const BriefStatementLoaded({
    required this.isCustomerMode,
    required this.customers,
    required this.suppliers,
    this.selectedCustomer,
    this.selectedSupplier,
    required this.statementRows,
    required this.totalDebit,
    required this.totalCredit,
    required this.finalBalance,
    required this.totalMeters,
    required this.statementNumber,
    this.fromDate,
    this.toDate,
  });

  BriefStatementLoaded copyWith({
    bool? isCustomerMode,
    List<CustomerModel>? customers,
    List<SupplierModel>? suppliers,
    CustomerModel? selectedCustomer,
    SupplierModel? selectedSupplier,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    double? totalMeters,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearSelectedCustomer = false,
    bool clearSelectedSupplier = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return BriefStatementLoaded(
      isCustomerMode: isCustomerMode ?? this.isCustomerMode,
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      statementRows: statementRows ?? this.statementRows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      totalMeters: totalMeters ?? this.totalMeters,
      statementNumber: statementNumber ?? this.statementNumber,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
    );
  }

  @override
  List<Object?> get props => [
        isCustomerMode,
        customers,
        suppliers,
        selectedCustomer,
        selectedSupplier,
        statementRows,
        totalDebit,
        totalCredit,
        finalBalance,
        totalMeters,
        statementNumber,
        fromDate,
        toDate,
      ];
}

class BriefStatementError extends BriefStatementState {
  final String message;

  const BriefStatementError({required this.message});

  @override
  List<Object?> get props => [message];
}
