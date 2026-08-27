import 'package:equatable/equatable.dart';
import '../../data/models/supplier_model.dart';

// ── Supplier States ──────────────────────────────

abstract class SupplierState extends Equatable {
  const SupplierState();

  @override
  List<Object?> get props => [];
}

class SupplierInitial extends SupplierState {
  const SupplierInitial();
}

class SupplierLoading extends SupplierState {
  const SupplierLoading();
}

class SupplierLoaded extends SupplierState {
  final List<SupplierModel> suppliers;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;

  const SupplierLoaded({
    required this.suppliers,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  SupplierLoaded copyWith({
    List<SupplierModel>? suppliers,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return SupplierLoaded(
      suppliers: suppliers ?? this.suppliers,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [
        suppliers,
        searchQuery,
        hasMore,
        isFetchingMore,
      ];
}

class SupplierError extends SupplierState {
  final String message;

  const SupplierError({required this.message});

  @override
  List<Object?> get props => [message];
}

class SupplierFormState extends SupplierState {
  final bool isEditing;
  final SupplierModel? editingSupplier;
  final bool isSaving;

  const SupplierFormState({
    this.isEditing = false,
    this.editingSupplier,
    this.isSaving = false,
  });

  SupplierFormState copyWith({
    bool? isEditing,
    SupplierModel? editingSupplier,
    bool? isSaving,
    bool clearEditingSupplier = false,
  }) {
    return SupplierFormState(
      isEditing: isEditing ?? this.isEditing,
      editingSupplier:
          clearEditingSupplier ? null : (editingSupplier ?? this.editingSupplier),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        isEditing,
        editingSupplier,
        isSaving,
      ];
}
