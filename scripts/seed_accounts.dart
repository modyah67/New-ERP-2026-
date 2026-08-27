import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient('https://pjkhdnoeyyvraclomepx.supabase.co', 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L');

  print('=== SIGNING IN ===');
  try {
    final auth = await c.auth.signInWithPassword(email: 'admin@fruityfarms.com', password: 'Admin123456');
    print('OK: ${auth.user?.email}');
  } catch (e) { print('FAIL: $e'); }

  print('\n=== SEED ACCOUNTS ===');
  final accounts = [
    {'account_code': '1030', 'name': 'المخزون', 'account_type': 'asset', 'account_group': 'assets'},
    {'account_code': '1040', 'name': 'مخزون التعبئة', 'account_type': 'asset', 'account_group': 'assets'},
    {'account_code': '2000', 'name': 'الموردون', 'account_type': 'liability', 'account_group': 'liabilities'},
    {'account_code': '7000', 'name': 'حساب المشتريات', 'account_type': 'expense', 'account_group': 'expenses'},
  ];
  for (final a in accounts) {
    try {
      final existing = await c.from('accounts').select('id').eq('account_code', a['account_code']!);
      if ((existing as List).isEmpty) {
        await c.from('accounts').insert(a);
        print('  Created: ${a['account_code']} - ${a['name']}');
      } else {
        print('  Exists: ${a['account_code']}');
      }
    } catch (e) {
      print('  Error creating ${a['account_code']}: $e');
    }
  }

  print('\n=== VERIFY ===');
  final r = await c.from('accounts').select('account_code, name');
  for (final row in (r as List)) {
    print('  ${row['account_code']} | ${row['name']}');
  }
}
