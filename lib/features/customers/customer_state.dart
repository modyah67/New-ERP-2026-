import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';

// ── Customer States ──────────────────────────────

abstract class CustomerState extends Equatable {
  const CustomerState();

  @override
  List<Object?> get props => [];
}

class CustomerInitial extends CustomerState {
  const CustomerInitial();
}

class CustomerLoading extends CustomerState {
  const CustomerLoading();
}

class CustomerLoaded extends CustomerState {
  final List<CustomerModel> customers;
  final String searchQuery;
  final String typeFilter; // 'all' | 'local' | 'export'
  final bool hasMore;
  final bool isFetchingMore;

  const CustomerLoaded({
    required this.customers,
    this.searchQuery = '',
    this.typeFilter = 'all',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  List<CustomerModel> get filteredCustomers {
    if (typeFilter == 'local') {
      return customers.where((c) => c.customerType == 'local').toList();
    } else if (typeFilter == 'export') {
      return customers.where((c) => c.customerType == 'export').toList();
    }
    return customers;
  }

  int get allCount => customers.length;
  int get localCount => customers.where((c) => c.customerType == 'local').length;
  int get exportCount => customers.where((c) => c.customerType == 'export').length;

  CustomerLoaded copyWith({
    List<CustomerModel>? customers,
    String? searchQuery,
    String? typeFilter,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return CustomerLoaded(
      customers: customers ?? this.customers,
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: typeFilter ?? this.typeFilter,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [
        customers,
        searchQuery,
        typeFilter,
        hasMore,
        isFetchingMore,
      ];
}

class CustomerError extends CustomerState {
  final String message;

  const CustomerError({required this.message});

  @override
  List<Object?> get props => [message];
}

class CustomerFormState extends CustomerState {
  final bool isEditing;
  final CustomerModel? editingCustomer;
  final bool isSaving;
  final int addressesVersion;

  const CustomerFormState({
    this.isEditing = false,
    this.editingCustomer,
    this.isSaving = false,
    this.addressesVersion = 0,
  });

  CustomerFormState copyWith({
    bool? isEditing,
    CustomerModel? editingCustomer,
    bool? isSaving,
    bool clearEditingCustomer = false,
    int? addressesVersion,
  }) {
    return CustomerFormState(
      isEditing: isEditing ?? this.isEditing,
      editingCustomer:
          clearEditingCustomer ? null : (editingCustomer ?? this.editingCustomer),
      isSaving: isSaving ?? this.isSaving,
      addressesVersion: addressesVersion ?? this.addressesVersion,
    );
  }

  @override
  List<Object?> get props => [
        isEditing,
        editingCustomer,
        isSaving,
        addressesVersion,
      ];
}
