import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  print('=== VERIFYING ADMIN EXPENSES IMPLEMENTATION ===');

  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);

  try {
    await client.auth.signInWithPassword(
      email: 'mahmoud@gmail.com',
      password: 'password123',
    );
    print('✅ Authenticated successfully');
  } catch (e) {
    try {
      await client.auth.signInWithPassword(
        email: 'mahmoud@gmail.com',
        password: 'password123',
      );
    } catch (_) {}
  }

  // 1. Verify Parent 313
  final p313 = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting')
      .eq('account_code', '313')
      .maybeSingle();
  print('\n1. Level 3 Parent: $p313');

  // 2. Verify Level 4 Control Account 3133
  final a3133 = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting, parent_id')
      .eq('account_code', '3133')
      .maybeSingle();
  print('2. Level 4 Control: $a3133');

  // 3. Verify Level 5 Leaf Account 31331
  final a31331 = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting, parent_id, cost_center_id')
      .eq('account_code', '31331')
      .maybeSingle();
  print('3. Level 5 Leaf Account: $a31331');

  // 4. Verify Cost Center
  final cc = await client
      .from('cost_centers')
      .select('id, code, name, name_ar, cost_center_type, is_active')
      .eq('code', 'CC-ADMIN-EXPENSES')
      .maybeSingle();
  print('4. Cost Center: $cc');

  // 5. Verify Cost Category
  final cat = await client
      .from('cost_report_categories')
      .select('id, name, scope, type, supplier_type, account_id, cost_center_id')
      .eq('name', 'مصاريف إدارية')
      .maybeSingle();
  print('5. Cost Report Category: $cat');

  print('\n🎯 ALL DATABASE INTEGRITY CHECKS COMPLETED!');
  exit(0);
}
