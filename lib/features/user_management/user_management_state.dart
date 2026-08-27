import 'package:equatable/equatable.dart';
import '../../data/models/user_model.dart';

abstract class UserManagementState extends Equatable {
  const UserManagementState();

  @override
  List<Object?> get props => [];
}

class UserManagementInitial extends UserManagementState {
  const UserManagementInitial();
}

class UserManagementLoading extends UserManagementState {
  const UserManagementLoading();
}

class UserManagementLoaded extends UserManagementState {
  final List<UserModel> users;
  final Map<String, Map<String, dynamic>> userRoles;
  final bool isAdmin;
  final bool isSaving;
  final String? errorMessage;

  const UserManagementLoaded({
    required this.users,
    required this.userRoles,
    required this.isAdmin,
    this.isSaving = false,
    this.errorMessage,
  });

  UserManagementLoaded copyWith({
    List<UserModel>? users,
    Map<String, Map<String, dynamic>>? userRoles,
    bool? isAdmin,
    bool? isSaving,
    String? errorMessage,
  }) {
    return UserManagementLoaded(
      users: users ?? this.users,
      userRoles: userRoles ?? this.userRoles,
      isAdmin: isAdmin ?? this.isAdmin,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage, // We don't default to this.errorMessage so we can clear it
    );
  }

  @override
  List<Object?> get props => [users, userRoles, isAdmin, isSaving, errorMessage];
}

class UserManagementError extends UserManagementState {
  final String message;

  const UserManagementError({required this.message});

  @override
  List<Object?> get props => [message];
}
