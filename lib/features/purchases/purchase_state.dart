import 'package:equatable/equatable.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/station_model.dart';
import '../../data/models/raw_material_model.dart';

abstract class PurchaseState extends Equatable {
  const PurchaseState();

  @override
  List<Object?> get props => [];
}

class PurchaseInitial extends PurchaseState {
  const PurchaseInitial();
}

class PurchaseLoading extends PurchaseState {
  const PurchaseLoading();
}

class PurchaseLoaded extends PurchaseState {
  final List<PurchaseModel> purchases;
  final List<SupplierModel> suppliers;
  final List<ItemModel> allItems;
  final List<StationModel> stations;
  final List<RawMaterialModel> rawMaterials;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;
  final bool isLoading;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? selectedProductId;

  const PurchaseLoaded({
    required this.purchases,
    required this.suppliers,
    required this.allItems,
    this.stations = const [],
    this.rawMaterials = const [],
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.isLoading = false,
    this.fromDate,
    this.toDate,
    this.selectedProductId,
  });

  List<ItemModel> itemsByCurrency(String currency) {
    final matchingRmIds = rawMaterials
        .where((rm) => rm.currency.toUpperCase() == currency.toUpperCase())
        .map((rm) => rm.id.toString())
        .toSet();
    return allItems.where((item) {
      if (item.type == 'raw_material') {
        return matchingRmIds.contains(item.id);
      }
      return false;
    }).toList();
  }

  PurchaseLoaded copyWith({
    List<PurchaseModel>? purchases,
    List<SupplierModel>? suppliers,
    List<ItemModel>? allItems,
    List<StationModel>? stations,
    List<RawMaterialModel>? rawMaterials,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
    bool? isLoading,
    DateTime? fromDate,
    DateTime? toDate,
    String? selectedProductId,
    bool clearFromDate = false,
    bool clearToDate = false,
    bool clearProductId = false,
  }) {
    return PurchaseLoaded(
      purchases: purchases ?? this.purchases,
      suppliers: suppliers ?? this.suppliers,
      allItems: allItems ?? this.allItems,
      stations: stations ?? this.stations,
      rawMaterials: rawMaterials ?? this.rawMaterials,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      isLoading: isLoading ?? this.isLoading,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      selectedProductId: clearProductId ? null : (selectedProductId ?? this.selectedProductId),
    );
  }

  @override
  List<Object?> get props => [
        purchases,
        suppliers,
        allItems,
        stations,
        rawMaterials,
        searchQuery,
        hasMore,
        isFetchingMore,
        isLoading,
        fromDate,
        toDate,
        selectedProductId,
      ];
}

class PurchaseError extends PurchaseState {
  final String message;

  const PurchaseError({required this.message});

  @override
  List<Object?> get props => [message];
}

class PurchaseFormState extends Equatable {
  final SupplierModel? selectedSupplier;
  final DateTime purchaseDate;
  final List<PurchaseLineData> purchaseLines;
  final String nextPurchaseNumber;
  final double subtotal;
  final double paidAmount;
  final bool isSaving;
  final int? editingPurchaseId;
  final String? paymentTreasuryId;
  final String? paymentSourceType;
  final int? paymentBankAccountId;

  const PurchaseFormState({
    this.selectedSupplier,
    required this.purchaseDate,
    this.purchaseLines = const [],
    this.nextPurchaseNumber = '1',
    this.subtotal = 0.0,
    this.paidAmount = 0.0,
    this.isSaving = false,
    this.editingPurchaseId,
    this.paymentTreasuryId,
    this.paymentSourceType,
    this.paymentBankAccountId,
  });

  bool get isEditing => editingPurchaseId != null;

  PurchaseFormState copyWith({
    SupplierModel? selectedSupplier,
    DateTime? purchaseDate,
    List<PurchaseLineData>? purchaseLines,
    String? nextPurchaseNumber,
    double? subtotal,
    double? paidAmount,
    bool? isSaving,
    int? editingPurchaseId,
    String? paymentTreasuryId,
    String? paymentSourceType,
    int? paymentBankAccountId,
    bool clearSelectedSupplier = false,
    bool clearEditingPurchaseId = false,
    bool clearPaymentTreasuryId = false,
  }) {
    return PurchaseFormState(
      selectedSupplier: clearSelectedSupplier
          ? null
          : (selectedSupplier ?? this.selectedSupplier),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseLines: purchaseLines ?? this.purchaseLines,
      nextPurchaseNumber: nextPurchaseNumber ?? this.nextPurchaseNumber,
      subtotal: subtotal ?? this.subtotal,
      paidAmount: paidAmount ?? this.paidAmount,
      isSaving: isSaving ?? this.isSaving,
      editingPurchaseId: clearEditingPurchaseId
          ? null
          : (editingPurchaseId ?? this.editingPurchaseId),
      paymentTreasuryId: clearPaymentTreasuryId
          ? null
          : (paymentTreasuryId ?? this.paymentTreasuryId),
      paymentSourceType: paymentSourceType ?? this.paymentSourceType,
      paymentBankAccountId: paymentBankAccountId ?? this.paymentBankAccountId,
    );
  }

  @override
  List<Object?> get props => [
        selectedSupplier,
        purchaseDate,
        purchaseLines,
        nextPurchaseNumber,
        subtotal,
        paidAmount,
        isSaving,
        editingPurchaseId,
        paymentTreasuryId,
        paymentSourceType,
        paymentBankAccountId,
      ];
}

class PurchaseFormSaved extends PurchaseState {
  const PurchaseFormSaved();
  @override
  List<Object?> get props => [];
}
