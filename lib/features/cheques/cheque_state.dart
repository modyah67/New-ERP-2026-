import 'package:equatable/equatable.dart';
import '../../data/models/cheque_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/shareholder_model.dart';

enum ChequeDialogMode { outgoing, incoming }

abstract class ChequeState extends Equatable {
  const ChequeState();
  @override
  List<Object?> get props => [];
}

class ChequeInitial extends ChequeState {
  const ChequeInitial();
}

class ChequeLoading extends ChequeState {
  const ChequeLoading();
}

class ChequeLoaded extends ChequeState {
  final List<ChequeModel> cheques;
  final bool hasMore;
  final bool isSaving;
  final String? typeFilter;
  final String? statusFilter;
  final String searchQuery;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<CustomerModel> customerResults;
  final List<SupplierModel> supplierResults;
  final List<ClearingAgentModel> clearingAgentResults;
  final List<ShippingCompanyModel> shippingCompanyResults;
  final List<ShareholderModel> shareholderResults;
  final bool isLoadingCustomers;
  final bool isLoadingSuppliers;
  final bool isLoadingClearingAgents;
  final bool isLoadingShippingCompanies;
  final bool isLoadingShareholders;
  final int pendingCount;

  const ChequeLoaded({
    this.cheques = const [],
    this.hasMore = true,
    this.isSaving = false,
    this.typeFilter,
    this.statusFilter,
    this.searchQuery = '',
    this.fromDate,
    this.toDate,
    this.customerResults = const [],
    this.supplierResults = const [],
    this.clearingAgentResults = const [],
    this.shippingCompanyResults = const [],
    this.shareholderResults = const [],
    this.isLoadingCustomers = false,
    this.isLoadingSuppliers = false,
    this.isLoadingClearingAgents = false,
    this.isLoadingShippingCompanies = false,
    this.isLoadingShareholders = false,
    this.pendingCount = 0,
  });

  @override
  List<Object?> get props => [
        cheques,
        hasMore,
        isSaving,
        typeFilter,
        statusFilter,
        searchQuery,
        fromDate,
        toDate,
        customerResults,
        supplierResults,
        clearingAgentResults,
        shippingCompanyResults,
        shareholderResults,
        isLoadingCustomers,
        isLoadingSuppliers,
        isLoadingClearingAgents,
        isLoadingShippingCompanies,
        isLoadingShareholders,
        pendingCount,
      ];

  ChequeLoaded copyWith({
    List<ChequeModel>? cheques,
    bool? hasMore,
    bool? isSaving,
    String? typeFilter,
    String? statusFilter,
    String? searchQuery,
    DateTime? fromDate,
    DateTime? toDate,
    List<CustomerModel>? customerResults,
    List<SupplierModel>? supplierResults,
    List<ClearingAgentModel>? clearingAgentResults,
    List<ShippingCompanyModel>? shippingCompanyResults,
    List<ShareholderModel>? shareholderResults,
    bool? isLoadingCustomers,
    bool? isLoadingSuppliers,
    bool? isLoadingClearingAgents,
    bool? isLoadingShippingCompanies,
    bool? isLoadingShareholders,
    int? pendingCount,
    bool clearTypeFilter = false,
    bool clearStatusFilter = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return ChequeLoaded(
      cheques: cheques ?? this.cheques,
      hasMore: hasMore ?? this.hasMore,
      isSaving: isSaving ?? this.isSaving,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      customerResults: customerResults ?? this.customerResults,
      supplierResults: supplierResults ?? this.supplierResults,
      clearingAgentResults: clearingAgentResults ?? this.clearingAgentResults,
      shippingCompanyResults: shippingCompanyResults ?? this.shippingCompanyResults,
      shareholderResults: shareholderResults ?? this.shareholderResults,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      isLoadingSuppliers: isLoadingSuppliers ?? this.isLoadingSuppliers,
      isLoadingClearingAgents: isLoadingClearingAgents ?? this.isLoadingClearingAgents,
      isLoadingShippingCompanies: isLoadingShippingCompanies ?? this.isLoadingShippingCompanies,
      isLoadingShareholders: isLoadingShareholders ?? this.isLoadingShareholders,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

class ChequeError extends ChequeState {
  final String message;
  const ChequeError({required this.message});
  @override
  List<Object?> get props => [message];
}
