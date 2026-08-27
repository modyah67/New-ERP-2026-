import 'dart:developer' as dev;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class UserManagementDao {
  final _client = Supabase.instance.client;
  static const String _tag = 'UserManagementDao';

  UserManagementDao();

  void _log(String msg) => dev.log(msg, name: _tag);

  Future<bool> isCurrentUserAdmin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final data = await _client
          .from('users')
          .select('is_admin')
          .eq('id', userId)
          .maybeSingle();
      return data?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    final data = await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => UserModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> getUserRole(String userId) async {
    final data = await _client
        .from('user_roles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> getAllUserRoles() async {
    final data = await _client
        .from('user_roles')
        .select('*, users!user_id(full_name, email)')
        .order('created_at', ascending: false);
    return (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<UserModel> createEmployee({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final username = email.split('@').first;
    final result = await _client.rpc('admin_create_employee', params: {
      'p_username': username,
      'p_password': password,
      'p_full_name': fullName,
    });

    final map = result as Map<String, dynamic>;
    _log('createEmployee via RPC: OK (id=${map['id']})');

    return UserModel(
      id: map['id'] as String,
      email: map['email'] as String,
      fullName: map['full_name'] as String,
      isAdmin: map['is_admin'] as bool? ?? false,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Future<void> updateUser({
    required String userId,
    String? fullName,
    bool? isAdmin,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (isAdmin != null) updates['is_admin'] = isAdmin;
    if (updates.isEmpty) return;
    await _client.from('users').update(updates).eq('id', userId);
    _log('updateUser($userId): $updates');
  }

  Future<void> deleteUser(String userId) async {
    await _client.rpc('admin_delete_employee', params: {
      'p_user_id': userId,
    });
    _log('deleteUser: $userId');
  }

  Future<void> setUserRole({
    required String userId,
    required String role,
    required Map<String, dynamic> permissions,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'role': role,
      ...permissions,
    };
    final existing = await _client
        .from('user_roles')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client.from('user_roles').update(payload).eq('user_id', userId);
    } else {
      await _client.from('user_roles').insert(payload);
    }
    _log('setUserRole($userId): $role');
  }

  Future<void> removeUserRole(String userId) async {
    await _client.from('user_roles').delete().eq('user_id', userId);
    _log('removeUserRole($userId)');
  }
}
