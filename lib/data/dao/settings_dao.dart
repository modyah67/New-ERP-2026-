import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<void> saveSetting(String key, String value) async {
    await _client.from('settings').upsert({
      'key': key,
      'value': value,
      'user_id': _userId,
    });
  }

  Future<String?> getSetting(String key) async {
    final result = await _client
        .from('settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();
    return result?['value'] as String?;
  }

  Future<Map<String, String>> getAllSettings() async {
    final result = await _client.from('settings').select();
    final Map<String, String> map = {};
    for (final row in result) {
      final key = (row['key'] as String?)?.toString();
      final value = (row['value'] as String?)?.toString();
      if (key != null) map[key] = value ?? '';
    }
    return map;
  }
}
