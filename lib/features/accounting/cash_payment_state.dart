import 'package:equatable/equatable.dart';
import '../../data/models/account_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/customer_model.dart';

enum CashPaymentMode { supplier, customer, other }

abstract class CashPaymentState extends Equatable {
  const CashPaymentState();

  @override
  List<Object?> get props => [];
}

class CashPaymentInitial extends CashPaymentState {
  const CashPaymentInitial();
}

class CashPaymentLoading extends CashPaymentState {
  const CashPaymentLoading();
}

class CashPaymentLoaded extends CashPaymentState {
  final CashPaymentMode mode;
  final String paymentNumber;
  final DateTime transactionDate;
  final SupplierModel? selectedSupplier;
  final CustomerModel? selectedCustomer;
  final AccountModel? selectedAccount;
  final List<SupplierModel> supplierResults;
  final List<CustomerModel> customerResults;
  final List<AccountModel> accountResults;
  final bool isLoadingSuppliers;
  final bool isLoadingCustomers;
  final bool isLoadingAccounts;
  final bool isSaving;
  final List<Map<String, dynamic>> payments;
  final String historySearchQuery;
  final DateTime? historyFromDate;
  final DateTime? historyToDate;

  const CashPaymentLoaded({
    this.mode = CashPaymentMode.supplier,
    required this.paymentNumber,
    required this.transactionDate,
    this.selectedSupplier,
    this.selectedCustomer,
    this.selectedAccount,
    this.supplierResults = const [],
    this.customerResults = const [],
    this.accountResults = const [],
    this.isLoadingSuppliers = false,
    this.isLoadingCustomers = false,
    this.isLoadingAccounts = false,
    this.isSaving = false,
    this.payments = const [],
    this.historySearchQuery = '',
    this.historyFromDate,
    this.historyToDate,
  });

  CashPaymentLoaded copyWith({
    CashPaymentMode? mode,
    String? paymentNumber,
    DateTime? transactionDate,
    SupplierModel? selectedSupplier,
    CustomerModel? selectedCustomer,
    AccountModel? selectedAccount,
    List<SupplierModel>? supplierResults,
    List<CustomerModel>? customerResults,
    List<AccountModel>? accountResults,
    bool? isLoadingSuppliers,
    bool? isLoadingCustomers,
    bool? isLoadingAccounts,
    bool? isSaving,
    List<Map<String, dynamic>>? payments,
    String? historySearchQuery,
    DateTime? historyFromDate,
    DateTime? historyToDate,
    bool clearSelectedSupplier = false,
    bool clearSelectedCustomer = false,
    bool clearSelectedAccount = false,
    bool clearHistoryFromDate = false,
    bool clearHistoryToDate = false,
  }) {
    return CashPaymentLoaded(
      mode: mode ?? this.mode,
      paymentNumber: paymentNumber ?? this.paymentNumber,
      transactionDate: transactionDate ?? this.transactionDate,
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      selectedAccount: clearSelectedAccount
          ? null
          : (selectedAccount ?? this.selectedAccount),
      supplierResults: supplierResults ?? this.supplierResults,
      customerResults: customerResults ?? this.customerResults,
      accountResults: accountResults ?? this.accountResults,
      isLoadingSuppliers: isLoadingSuppliers ?? this.isLoadingSuppliers,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      isLoadingAccounts: isLoadingAccounts ?? this.isLoadingAccounts,
      isSaving: isSaving ?? this.isSaving,
      payments: payments ?? this.payments,
      historySearchQuery: historySearchQuery ?? this.historySearchQuery,
      historyFromDate: clearHistoryFromDate
          ? null
          : (historyFromDate ?? this.historyFromDate),
      historyToDate:
          clearHistoryToDate ? null : (historyToDate ?? this.historyToDate),
    );
  }

  @override
  List<Object?> get props => [
        mode,
        paymentNumber,
        transactionDate,
        selectedSupplier,
        selectedCustomer,
        selectedAccount,
        supplierResults,
        customerResults,
        accountResults,
        isLoadingSuppliers,
        isLoadingCustomers,
        isLoadingAccounts,
        isSaving,
        payments,
        historySearchQuery,
        historyFromDate,
        historyToDate,
      ];
}

class CashPaymentError extends CashPaymentState {
  final String message;

  const CashPaymentError({required this.message});

  @override
  List<Object?> get props => [message];
}
