import 'package:equatable/equatable.dart';
import '../../data/models/clearing_agent_model.dart';

abstract class ClearingAgentState extends Equatable {
  const ClearingAgentState();

  @override
  List<Object?> get props => [];
}

class ClearingAgentInitial extends ClearingAgentState {
  const ClearingAgentInitial();
}

class ClearingAgentLoading extends ClearingAgentState {
  const ClearingAgentLoading();
}

class ClearingAgentLoaded extends ClearingAgentState {
  final List<ClearingAgentModel> agents;
  final String searchQuery;
  final String typeFilter;
  final bool hasMore;
  final bool isFetchingMore;

  const ClearingAgentLoaded({
    required this.agents,
    this.searchQuery = '',
    this.typeFilter = 'all',
    this.hasMore = true,
    this.isFetchingMore = false,
  });

  ClearingAgentLoaded copyWith({
    List<ClearingAgentModel>? agents,
    String? searchQuery,
    String? typeFilter,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return ClearingAgentLoaded(
      agents: agents ?? this.agents,
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: typeFilter ?? this.typeFilter,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [agents, searchQuery, typeFilter, hasMore, isFetchingMore];
}

class ClearingAgentError extends ClearingAgentState {
  final String message;
  const ClearingAgentError({required this.message});

  @override
  List<Object?> get props => [message];
}

class ClearingAgentFormState extends ClearingAgentState {
  final bool isEditing;
  final ClearingAgentModel? editingAgent;
  final bool isSaving;
  final int addressesVersion;

  const ClearingAgentFormState({
    this.isEditing = false,
    this.editingAgent,
    this.isSaving = false,
    this.addressesVersion = 0,
  });

  ClearingAgentFormState copyWith({
    bool? isEditing,
    ClearingAgentModel? editingAgent,
    bool? isSaving,
    bool clearEditingAgent = false,
    int? addressesVersion,
  }) {
    return ClearingAgentFormState(
      isEditing: isEditing ?? this.isEditing,
      editingAgent: clearEditingAgent ? null : (editingAgent ?? this.editingAgent),
      isSaving: isSaving ?? this.isSaving,
      addressesVersion: addressesVersion ?? this.addressesVersion,
    );
  }

  @override
  List<Object?> get props => [isEditing, editingAgent, isSaving, addressesVersion];
}
