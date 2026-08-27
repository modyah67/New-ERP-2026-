import 'package:equatable/equatable.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsInitial extends SettingsState {
  const SettingsInitial();
}

class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

class SettingsLoaded extends SettingsState {
  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final int chequeNotificationDays;

  const SettingsLoaded({
    required this.companyName,
    required this.companyAddress,
    required this.companyPhone,
    this.chequeNotificationDays = 3,
  });

  SettingsLoaded copyWith({
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    int? chequeNotificationDays,
  }) {
    return SettingsLoaded(
      companyName: companyName ?? this.companyName,
      companyAddress: companyAddress ?? this.companyAddress,
      companyPhone: companyPhone ?? this.companyPhone,
      chequeNotificationDays: chequeNotificationDays ?? this.chequeNotificationDays,
    );
  }

  @override
  List<Object?> get props => [companyName, companyAddress, companyPhone, chequeNotificationDays];
}

class SettingsError extends SettingsState {
  final String message;

  const SettingsError({required this.message});

  @override
  List<Object?> get props => [message];
}

class ExportProgressState extends SettingsState {
  final String section;
  final int current;
  final int total;

  const ExportProgressState({
    required this.section,
    required this.current,
    required this.total,
  });

  @override
  List<Object?> get props => [section, current, total];
}

class ExportSuccess extends SettingsState {
  final String filePath;

  const ExportSuccess({required this.filePath});

  @override
  List<Object?> get props => [filePath];
}

class ExportError extends SettingsState {
  final String message;

  const ExportError({required this.message});

  @override
  List<Object?> get props => [message];
}
