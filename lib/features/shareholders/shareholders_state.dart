import '../../data/models/shareholder_model.dart';

abstract class ShareholdersState {}

class ShareholdersInitial extends ShareholdersState {}

class ShareholdersLoading extends ShareholdersState {}

class ShareholdersLoaded extends ShareholdersState {
  final List<ShareholderModel> shareholders;
  final bool isSaving;

  ShareholdersLoaded({
    required this.shareholders,
    this.isSaving = false,
  });

  ShareholdersLoaded copyWith({
    List<ShareholderModel>? shareholders,
    bool? isSaving,
  }) {
    return ShareholdersLoaded(
      shareholders: shareholders ?? this.shareholders,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class ShareholdersError extends ShareholdersState {
  final String message;
  ShareholdersError(this.message);
}
