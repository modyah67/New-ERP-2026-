import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final data = await c
      .from('accounts')
      .select('id, account_code, account_name, name, level, parent_id, is_leaf, allow_posting')
      .like('account_code', '4%')
      .order('account_code');

  print('=== REVENUES TREE (ROOT 4) ===');
  for (var a in data) {
    final lvl = a['level'] as int;
    final indent = '  ' * (lvl - 1);
    final leafMarker = a['is_leaf'] == true ? ' [مستوى 5 - تحليلي]' : ' [مستوى $lvl - مجموعة]';
    print('$indent• ${a['account_code']} - ${a['account_name']}$leafMarker');
  }
}
