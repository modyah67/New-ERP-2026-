import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class ExportCustomerStatementState extends Equatable {
  const ExportCustomerStatementState();

  @override
  List<Object?> get props => [];
}

class ExportCustomerStatementInitial extends ExportCustomerStatementState {
  const ExportCustomerStatementInitial();
}

class ExportCustomerStatementLoading extends ExportCustomerStatementState {
  const ExportCustomerStatementLoading();
}

class ExportCustomerStatementLoaded extends ExportCustomerStatementState {
  final List<CustomerModel> customers;
  final CustomerModel? selectedCustomer;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Map<String, String> rowNotes;
  final double openingBalance;
  final String customerTypeFilter; // 'all', 'local', 'export'

  const ExportCustomerStatementLoaded({
    required this.customers,
    this.selectedCustomer,
    required this.statementRows,
    required this.totalDebit,
    required this.totalCredit,
    required this.finalBalance,
    required this.statementNumber,
    this.fromDate,
    this.toDate,
    this.rowNotes = const {},
    this.openingBalance = 0,
    this.customerTypeFilter = 'all',
  });

  List<CustomerModel> get filteredCustomers {
    if (customerTypeFilter == 'local') {
      return customers.where((c) => c.customerType == 'local').toList();
    } else if (customerTypeFilter == 'export') {
      return customers.where((c) => c.customerType != 'local').toList();
    }
    return customers;
  }

  ExportCustomerStatementLoaded copyWith({
    List<CustomerModel>? customers,
    CustomerModel? selectedCustomer,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    Map<String, String>? rowNotes,
    double? openingBalance,
    String? customerTypeFilter,
    bool clearSelectedCustomer = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return ExportCustomerStatementLoaded(
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
      rowNotes: rowNotes ?? this.rowNotes,
      openingBalance: openingBalance ?? this.openingBalance,
      customerTypeFilter: customerTypeFilter ?? this.customerTypeFilter,
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
        rowNotes,
        openingBalance,
        customerTypeFilter,
      ];
}

class ExportCustomerStatementError extends ExportCustomerStatementState {
  final String message;

  const ExportCustomerStatementError({required this.message});

  @override
  List<Object?> get props => [message];
}
