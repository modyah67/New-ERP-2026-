import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // 1. Query tree under 234 and 235
  final rows = await c
      .from('accounts')
      .select('id, account_code, code, name, account_name, level, parent_id, account_type, normal_balance, is_leaf, allow_posting')
      .or('account_code.like.234%,account_code.like.235%,code.like.234%,code.like.235%')
      .order('account_code');

  print('=== RAW EVIDENCE: Tree under 234 & 235 ===');
  for (final r in rows) {
    print(r);
  }

  // Also query parent 234 and 235 directly
  final parents = await c
      .from('accounts')
      .select('id, account_code, code, name, account_name, level, parent_id, account_type, normal_balance, is_leaf, allow_posting')
      .inFilter('account_code', ['23', '234', '235']);
  print('\n=== RAW EVIDENCE: Parents 23, 234, 235 ===');
  for (final p in parents) {
    print(p);
  }

  // 3. Search for any existing account with opening/suspense keywords
  final suspenseRows = await c
      .from('accounts')
      .select('id, account_code, code, name, account_name, level, parent_id, account_type, normal_balance')
      .or('name.ilike.%opening%,name.ilike.%suspense%,account_name.ilike.%افتتاح%,account_name.ilike.%معلق%');

  print('\n=== RAW EVIDENCE: Existing Opening/Suspense accounts ===');
  for (final s in suspenseRows) {
    print(s);
  }
}
