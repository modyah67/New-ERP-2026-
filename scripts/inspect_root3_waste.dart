import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: 'password123');
  } catch (_) {}

  final res = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting')
      .or('account_code.like.312%,account_code.like.331%,account_code.like.314%')
      .limit(30);
  print('=== ROOT 3 EXPENSE ACCOUNTS ===');
  for (final a in res) {
    print('${a['account_code']} | ${a['account_name'] ?? a['name']} | id:${a['id']} | leaf:${a['is_leaf']} | allow_posting:${a['allow_posting']}');
  }
  exit(0);
}
