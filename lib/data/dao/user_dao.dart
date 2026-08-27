import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class UserDao {
  final _client = Supabase.instance.client;

  Future<List<UserModel>> getAll() async {
    final data = await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => UserModel.fromMap(e as Map<String, dynamic>)).toList();
  }
}
