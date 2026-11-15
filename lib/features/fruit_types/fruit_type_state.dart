import 'package:equatable/equatable.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/models/fruit_type_group_model.dart';

abstract class FruitTypeState extends Equatable {
  const FruitTypeState();

  @override
  List<Object?> get props => [];
}

class FruitTypeInitial extends FruitTypeState {
  const FruitTypeInitial();
}

class FruitTypeLoading extends FruitTypeState {
  const FruitTypeLoading();
}

class FruitTypeLoaded extends FruitTypeState {
  final List<FruitTypeModel> items;
  final List<FruitTypeGroupModel> groups;
  final List<FruitTypeGroupModel> filteredGroups;
  final Map<String, List<Map<String, dynamic>>> warehouseDistribution;
  final String searchQuery;
  final String? selectedPurchaseMode; // null = all, 'weight', 'carton', 'shared'

  const FruitTypeLoaded({
    required this.items,
    required this.groups,
    required this.filteredGroups,
    this.warehouseDistribution = const {},
    this.searchQuery = '',
    this.selectedPurchaseMode,
  });

  FruitTypeLoaded copyWith({
    List<FruitTypeModel>? items,
    List<FruitTypeGroupModel>? groups,
    List<FruitTypeGroupModel>? filteredGroups,
    Map<String, List<Map<String, dynamic>>>? warehouseDistribution,
    String? searchQuery,
    String? selectedPurchaseMode,
    bool clearSelectedPurchaseMode = false,
  }) {
    return FruitTypeLoaded(
      items: items ?? this.items,
      groups: groups ?? this.groups,
      filteredGroups: filteredGroups ?? this.filteredGroups,
      warehouseDistribution: warehouseDistribution ?? this.warehouseDistribution,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedPurchaseMode: clearSelectedPurchaseMode
          ? null
          : (selectedPurchaseMode ?? this.selectedPurchaseMode),
    );
  }

  @override
  List<Object?> get props => [
        items,
        groups,
        filteredGroups,
        warehouseDistribution,
        searchQuery,
        selectedPurchaseMode,
      ];
}

class FruitTypeError extends FruitTypeState {
  final String message;
  const FruitTypeError({required this.message});

  @override
  List<Object?> get props => [message];
}
