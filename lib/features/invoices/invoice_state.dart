import 'package:equatable/equatable.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/item_model.dart';

abstract class InvoiceState extends Equatable {
  const InvoiceState();

  @override
  List<Object?> get props => [];
}

class InvoiceInitial extends InvoiceState {
  const InvoiceInitial();
}

class InvoiceLoading extends InvoiceState {
  const InvoiceLoading();
}

class InvoiceLoaded extends InvoiceState {
  final List<InvoiceModel> invoices;
  final List<CustomerModel> customers;
  final List<ItemModel> allItems;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int nextInvoiceNumber;

  const InvoiceLoaded({
    this.invoices = const [],
    this.customers = const [],
    this.allItems = const [],
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.fromDate,
    this.toDate,
    this.nextInvoiceNumber = 0,
  });

  InvoiceLoaded copyWith({
    List<InvoiceModel>? invoices,
    List<CustomerModel>? customers,
    List<ItemModel>? allItems,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearFromDate = false,
    bool clearToDate = false,
    int? nextInvoiceNumber,
  }) {
    return InvoiceLoaded(
      invoices: invoices ?? this.invoices,
      customers: customers ?? this.customers,
      allItems: allItems ?? this.allItems,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      nextInvoiceNumber: nextInvoiceNumber ?? this.nextInvoiceNumber,
    );
  }

  @override
  List<Object?> get props => [
        invoices,
        customers,
        allItems,
        searchQuery,
        hasMore,
        isFetchingMore,
        fromDate,
        toDate,
        nextInvoiceNumber,
      ];
}

class InvoiceError extends InvoiceState {
  final String message;

  const InvoiceError(this.message);

  @override
  List<Object?> get props => [message];
}

class InvoiceFormState extends InvoiceState {
  final CustomerModel? selectedCustomer;
  final DateTime invoiceDate;
  final List<InvoiceLine> invoiceLines;
  final DiscountMode discountMode;
  final bool isSaving;

  const InvoiceFormState({
    this.selectedCustomer,
    required this.invoiceDate,
    this.invoiceLines = const [],
    this.discountMode = DiscountMode.none,
    this.isSaving = false,
  });

  InvoiceFormState copyWith({
    CustomerModel? selectedCustomer,
    bool clearCustomer = false,
    DateTime? invoiceDate,
    List<InvoiceLine>? invoiceLines,
    DiscountMode? discountMode,
    bool? isSaving,
  }) {
    return InvoiceFormState(
      selectedCustomer:
          clearCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
      invoiceDate: invoiceDate ?? this.invoiceDate,
      invoiceLines: invoiceLines ?? this.invoiceLines,
      discountMode: discountMode ?? this.discountMode,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        selectedCustomer,
        invoiceDate,
        invoiceLines,
        discountMode,
        isSaving,
      ];
}
