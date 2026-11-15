import 'package:equatable/equatable.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../data/models/transport_transaction_model.dart';

abstract class TransportSupplierStatementState extends Equatable {
  const TransportSupplierStatementState();

  @override
  List<Object?> get props => [];
}

class TransportSupplierStatementInitial extends TransportSupplierStatementState {
  const TransportSupplierStatementInitial();
}

class TransportSupplierStatementLoading extends TransportSupplierStatementState {
  const TransportSupplierStatementLoading();
}

class TransportSupplierStatementLoaded extends TransportSupplierStatementState {
  final List<TransportSupplierModel> suppliers;
  final TransportSupplierModel? selectedSupplier;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<TransportTransactionModel> transactions;
  final double openingBalance;
  final double totalDebit; // Payments made to transporter
  final double totalCredit; // Invoices / Dues owed to transporter
  final double finalBalance;
  final bool isLoadingStatement;

  const TransportSupplierStatementLoaded({
    required this.suppliers,
    this.selectedSupplier,
    this.fromDate,
    this.toDate,
    this.transactions = const [],
    this.openingBalance = 0.0,
    this.totalDebit = 0.0,
    this.totalCredit = 0.0,
    this.finalBalance = 0.0,
    this.isLoadingStatement = false,
  });

  TransportSupplierStatementLoaded copyWith({
    List<TransportSupplierModel>? suppliers,
    TransportSupplierModel? selectedSupplier,
    bool clearSelectedSupplier = false,
    DateTime? fromDate,
    DateTime? toDate,
    List<TransportTransactionModel>? transactions,
    double? openingBalance,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    bool? isLoadingStatement,
  }) {
    return TransportSupplierStatementLoaded(
      suppliers: suppliers ?? this.suppliers,
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      transactions: transactions ?? this.transactions,
      openingBalance: openingBalance ?? this.openingBalance,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      isLoadingStatement: isLoadingStatement ?? this.isLoadingStatement,
    );
  }

  @override
  List<Object?> get props => [
        suppliers,
        selectedSupplier,
        fromDate,
        toDate,
        transactions,
        openingBalance,
        totalDebit,
        totalCredit,
        finalBalance,
        isLoadingStatement,
      ];
}

class TransportSupplierStatementError extends TransportSupplierStatementState {
  final String message;

  const TransportSupplierStatementError({required this.message});

  @override
  List<Object?> get props => [message];
}
