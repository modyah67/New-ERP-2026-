import 'package:equatable/equatable.dart';
import '../../data/models/station_model.dart';

abstract class StationState extends Equatable {
  const StationState();

  @override
  List<Object?> get props => [];
}

class StationInitial extends StationState {
  const StationInitial();
}

class StationLoading extends StationState {
  const StationLoading();
}

class StationLoaded extends StationState {
  final List<StationModel> stations;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;

  const StationLoaded({
    required this.stations,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  StationLoaded copyWith({
    List<StationModel>? stations,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return StationLoaded(
      stations: stations ?? this.stations,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [stations, searchQuery, hasMore, isFetchingMore];
}

class StationError extends StationState {
  final String message;

  const StationError({required this.message});

  @override
  List<Object?> get props => [message];
}

class StationFormState extends StationState {
  final bool isEditing;
  final StationModel? editingStation;
  final bool isSaving;
  final bool isLoading;

  const StationFormState({
    this.isEditing = false,
    this.editingStation,
    this.isSaving = false,
    this.isLoading = false,
  });

  StationFormState copyWith({
    bool? isEditing,
    StationModel? editingStation,
    bool? isSaving,
    bool? isLoading,
    bool clearEditingStation = false,
  }) {
    return StationFormState(
      isEditing: isEditing ?? this.isEditing,
      editingStation: clearEditingStation ? null : (editingStation ?? this.editingStation),
      isSaving: isSaving ?? this.isSaving,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [isEditing, editingStation, isSaving, isLoading];
}