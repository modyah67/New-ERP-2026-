import 'package:equatable/equatable.dart';
import '../../data/models/stock_transfer_model.dart';
import '../../data/models/station_model.dart';
import '../../data/models/station_product_model.dart';

abstract class TransferState extends Equatable {
  const TransferState();

  @override
  List<Object?> get props => [];
}

class TransferInitial extends TransferState {
  const TransferInitial();
}

class TransferLoading extends TransferState {
  const TransferLoading();
}

class TransferLoaded extends TransferState {
  final List<StockTransferModel> transfers;
  final Map<int, String> stationNames;
  final Map<int, bool> deletableTransfers;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;
  final DateTime? fromDate;
  final DateTime? toDate;

  const TransferLoaded({
    required this.transfers,
    this.stationNames = const {},
    this.deletableTransfers = const {},
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.fromDate,
    this.toDate,
  });

  TransferLoaded copyWith({
    List<StockTransferModel>? transfers,
    Map<int, String>? stationNames,
    Map<int, bool>? deletableTransfers,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return TransferLoaded(
      transfers: transfers ?? this.transfers,
      stationNames: stationNames ?? this.stationNames,
      deletableTransfers: deletableTransfers ?? this.deletableTransfers,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
    );
  }

  @override
  List<Object?> get props => [transfers, stationNames, deletableTransfers, searchQuery, hasMore, isFetchingMore, fromDate, toDate];
}

class TransferError extends TransferState {
  final String message;

  const TransferError({required this.message});

  @override
  List<Object?> get props => [message];
}

class TransferFormState extends TransferState {
  final bool isSaving;
  final List<StationModel> allStations;
  final List<StationProductModel> sourceProducts;
  final String productSearchQuery;

  const TransferFormState({
    this.isSaving = false,
    this.allStations = const [],
    this.sourceProducts = const [],
    this.productSearchQuery = '',
  });

  TransferFormState copyWith({
    bool? isSaving,
    List<StationModel>? allStations,
    List<StationProductModel>? sourceProducts,
    String? productSearchQuery,
  }) {
    return TransferFormState(
      isSaving: isSaving ?? this.isSaving,
      allStations: allStations ?? this.allStations,
      sourceProducts: sourceProducts ?? this.sourceProducts,
      productSearchQuery: productSearchQuery ?? this.productSearchQuery,
    );
  }

  @override
  List<Object?> get props => [isSaving, allStations, sourceProducts, productSearchQuery];
}
