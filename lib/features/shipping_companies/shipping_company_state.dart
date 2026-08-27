import 'package:equatable/equatable.dart';
import '../../data/models/shipping_company_model.dart';

abstract class ShippingCompanyState extends Equatable {
  const ShippingCompanyState();

  @override
  List<Object?> get props => [];
}

class ShippingCompanyInitial extends ShippingCompanyState {
  const ShippingCompanyInitial();
}

class ShippingCompanyLoading extends ShippingCompanyState {
  const ShippingCompanyLoading();
}

class ShippingCompanyLoaded extends ShippingCompanyState {
  final List<ShippingCompanyModel> companies;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;

  const ShippingCompanyLoaded({
    required this.companies,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  ShippingCompanyLoaded copyWith({
    List<ShippingCompanyModel>? companies,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return ShippingCompanyLoaded(
      companies: companies ?? this.companies,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [companies, searchQuery, hasMore, isFetchingMore];
}

class ShippingCompanyError extends ShippingCompanyState {
  final String message;
  const ShippingCompanyError({required this.message});

  @override
  List<Object?> get props => [message];
}

class ShippingCompanyFormState extends ShippingCompanyState {
  final bool isEditing;
  final ShippingCompanyModel? editingCompany;
  final bool isSaving;

  const ShippingCompanyFormState({
    this.isEditing = false,
    this.editingCompany,
    this.isSaving = false,
  });

  ShippingCompanyFormState copyWith({
    bool? isEditing,
    ShippingCompanyModel? editingCompany,
    bool? isSaving,
    bool clearEditingCompany = false,
  }) {
    return ShippingCompanyFormState(
      isEditing: isEditing ?? this.isEditing,
      editingCompany: clearEditingCompany ? null : (editingCompany ?? this.editingCompany),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [isEditing, editingCompany, isSaving];
}
