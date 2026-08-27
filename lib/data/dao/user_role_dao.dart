import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_role_model.dart';

class UserRoleDao {
  final _client = Supabase.instance.client;

  Future<UserRoleModel?> getByUserId(String userId) async {
    final data = await _client
        .from('user_roles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserRoleModel.fromMap(data);
  }

  Future<List<UserRoleModel>> getAll() async {
    final data = await _client
        .from('user_roles')
        .select()
        .order('created_at', ascending: false);
    return data.map((e) => UserRoleModel.fromMap(e)).toList();
  }

  Future<String> insert(UserRoleModel role) async {
    final data = role.toMap();
    final result = await _client.from('user_roles').insert(data).select().single();
    return result['id'] as String;
  }

  Future<void> update(UserRoleModel role) async {
    await _client.from('user_roles').update(role.toMap()).eq('id', role.id!);
  }

  Future<void> delete(String id) async {
    await _client.from('user_roles').delete().eq('id', id);
  }

  Future<bool> hasPermission(String userId, String permission) async {
    final role = await getByUserId(userId);
    if (role == null) return false;
    switch (permission) {
      case 'edit_invoice_prices':
        return role.canEditInvoicePrices;
      case 'edit_after_save':
        return role.canEditAfterSave;
      case 'edit_quantity':
        return role.canEditQuantity;
      case 'edit_discounts':
        return role.canEditDiscounts;
      case 'admin':
        return role.role == 'admin';
      case 'manager':
        return role.role == 'admin' || role.role == 'manager';
      default:
        return false;
    }
  }
}
