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
  final bool hasMore;
  final bool isFetchingMore;

  const CustomerLoaded({
    required this.customers,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  CustomerLoaded copyWith({
    List<CustomerModel>? customers,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return CustomerLoaded(
      customers: customers ?? this.customers,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [
        customers,
        searchQuery,
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
