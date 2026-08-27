import 'package:equatable/equatable.dart';
import '../../data/models/account_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';

enum CashReceiptMode { customer, supplier, other }

abstract class CashReceiptState extends Equatable {
  const CashReceiptState();

  @override
  List<Object?> get props => [];
}

class CashReceiptInitial extends CashReceiptState {
  const CashReceiptInitial();
}

class CashReceiptLoading extends CashReceiptState {
  const CashReceiptLoading();
}

class CashReceiptLoaded extends CashReceiptState {
  final CashReceiptMode mode;
  final String receiptNumber;
  final DateTime transactionDate;
  final CustomerModel? selectedCustomer;
  final SupplierModel? selectedSupplier;
  final AccountModel? selectedAccount;
  final List<CustomerModel> customerResults;
  final List<SupplierModel> supplierResults;
  final List<AccountModel> accountResults;
  final bool isLoadingCustomers;
  final bool isLoadingSuppliers;
  final bool isLoadingAccounts;
  final bool isSaving;
  final List<Map<String, dynamic>> receipts;
  final String historySearchQuery;
  final DateTime? historyFromDate;
  final DateTime? historyToDate;

  const CashReceiptLoaded({
    this.mode = CashReceiptMode.customer,
    required this.receiptNumber,
    required this.transactionDate,
    this.selectedCustomer,
    this.selectedSupplier,
    this.selectedAccount,
    this.customerResults = const [],
    this.supplierResults = const [],
    this.accountResults = const [],
    this.isLoadingCustomers = false,
    this.isLoadingSuppliers = false,
    this.isLoadingAccounts = false,
    this.isSaving = false,
    this.receipts = const [],
    this.historySearchQuery = '',
    this.historyFromDate,
    this.historyToDate,
  });

  CashReceiptLoaded copyWith({
    CashReceiptMode? mode,
    String? receiptNumber,
    DateTime? transactionDate,
    CustomerModel? selectedCustomer,
    SupplierModel? selectedSupplier,
    AccountModel? selectedAccount,
    List<CustomerModel>? customerResults,
    List<SupplierModel>? supplierResults,
    List<AccountModel>? accountResults,
    bool? isLoadingCustomers,
    bool? isLoadingSuppliers,
    bool? isLoadingAccounts,
    bool? isSaving,
    List<Map<String, dynamic>>? receipts,
    String? historySearchQuery,
    DateTime? historyFromDate,
    DateTime? historyToDate,
    bool clearSelectedCustomer = false,
    bool clearSelectedSupplier = false,
    bool clearSelectedAccount = false,
    bool clearHistoryFromDate = false,
    bool clearHistoryToDate = false,
  }) {
    return CashReceiptLoaded(
      mode: mode ?? this.mode,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      transactionDate: transactionDate ?? this.transactionDate,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      selectedAccount: clearSelectedAccount
          ? null
          : (selectedAccount ?? this.selectedAccount),
      customerResults: customerResults ?? this.customerResults,
      supplierResults: supplierResults ?? this.supplierResults,
      accountResults: accountResults ?? this.accountResults,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      isLoadingSuppliers: isLoadingSuppliers ?? this.isLoadingSuppliers,
      isLoadingAccounts: isLoadingAccounts ?? this.isLoadingAccounts,
      isSaving: isSaving ?? this.isSaving,
      receipts: receipts ?? this.receipts,
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
        receiptNumber,
        transactionDate,
        selectedCustomer,
        selectedSupplier,
        selectedAccount,
        customerResults,
        supplierResults,
        accountResults,
        isLoadingCustomers,
        isLoadingSuppliers,
        isLoadingAccounts,
        isSaving,
        receipts,
        historySearchQuery,
        historyFromDate,
        historyToDate,
      ];
}

class CashReceiptError extends CashReceiptState {
  final String message;

  const CashReceiptError({required this.message});

  @override
  List<Object?> get props => [message];
}
