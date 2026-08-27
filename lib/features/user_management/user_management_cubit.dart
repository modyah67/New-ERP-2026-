import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/user_management_dao.dart';
import 'user_management_state.dart';

class UserManagementCubit extends Cubit<UserManagementState> {
  final UserManagementDao _dao = UserManagementDao();

  UserManagementCubit() : super(UserManagementInitial());

  void init() {
    loadAll();
  }

  Future<void> loadAll() async {
    try {
      emit(UserManagementLoading());
      
      final isAdmin = await _dao.isCurrentUserAdmin();
      if (!isAdmin) {
        emit(const UserManagementError(message: 'غير مصرح لك بهذه الصفحة'));
        return;
      }

      final users = await _dao.getAllUsers();
      final roleList = await _dao.getAllUserRoles();
      final userRoles = <String, Map<String, dynamic>>{};
      for (final r in roleList) {
        final uid = r['user_id']?.toString();
        if (uid != null) userRoles[uid] = r;
      }

      emit(UserManagementLoaded(
        users: users,
        userRoles: userRoles,
        isAdmin: true,
      ));
    } catch (e, st) {
      debugPrint('UserManagementCubit.loadAll error: $e\n$st');
      emit(UserManagementError(message: 'فشل تحميل المستخدمين: $e'));
    }
  }

  Future<void> createEmployee({
    required String email,
    required String password,
    required String fullName,
  }) async {
    if (state is! UserManagementLoaded) return;
    final loaded = state as UserManagementLoaded;
    emit(loaded.copyWith(isSaving: true));

    if (password.length < 8) {
      emit(UserManagementError(
          message: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل'));
      return;
    }

    try {
      await _dao.createEmployee(
        email: email,
        password: password,
        fullName: fullName,
      );
      await loadAll();
    } catch (e) {
      String msg = 'فشل إنشاء المستخدم: $e';
      if (e.toString().contains('email_exists')) {
        msg = 'فشل إنشاء المستخدم: هذا البريد الإلكتروني مسجل بالفعل.';
      }
      emit(loaded.copyWith(isSaving: false, errorMessage: msg));
    }
  }

  Future<void> updateUser({
    required String userId,
    String? fullName,
    bool? isAdmin,
  }) async {
    if (state is! UserManagementLoaded) return;
    final loaded = state as UserManagementLoaded;
    emit(loaded.copyWith(isSaving: true));

    try {
      await _dao.updateUser(
        userId: userId,
        fullName: fullName,
        isAdmin: isAdmin,
      );
      await loadAll();
    } catch (e) {
      emit(loaded.copyWith(isSaving: false, errorMessage: 'فشل تحديث المستخدم: $e'));
    }
  }

  Future<void> deleteUser(String userId) async {
    if (state is! UserManagementLoaded) return;
    final loaded = state as UserManagementLoaded;
    emit(loaded.copyWith(isSaving: true));

    try {
      await _dao.deleteUser(userId);
      await loadAll();
    } catch (e) {
      emit(loaded.copyWith(isSaving: false, errorMessage: 'فشل حذف المستخدم: $e'));
    }
  }

  Future<void> setUserRole({
    required String userId,
    required String role,
    required Map<String, dynamic> permissions,
  }) async {
    if (state is! UserManagementLoaded) return;
    final loaded = state as UserManagementLoaded;
    emit(loaded.copyWith(isSaving: true));

    try {
      await _dao.setUserRole(
        userId: userId,
        role: role,
        permissions: permissions,
      );
      await loadAll();
    } catch (e) {
      emit(UserManagementError(message: 'فشل تحديث الصلاحيات: $e'));
    }
  }

  Future<void> removeUserRole(String userId) async {
    if (state is! UserManagementLoaded) return;
    final loaded = state as UserManagementLoaded;
    emit(loaded.copyWith(isSaving: true));

    try {
      await _dao.removeUserRole(userId);
      await loadAll();
    } catch (e) {
      emit(UserManagementError(message: 'فشل إزالة الصلاحيات: $e'));
    }
  }
}
