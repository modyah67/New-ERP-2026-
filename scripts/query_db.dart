import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
    print('Auth success: ${client.auth.currentUser?.email}');

  // 1. Check parent 313
  final p313 = await client.from('accounts').select('id, company_id').eq('account_code', '313').maybeSingle();
  print('Parent 313: $p313');
  final parent313Id = p313?['id'] as int;
  final companyId = p313?['company_id'];

  // 2. Check 3133
  var a3133 = await client.from('accounts').select('id, account_code').eq('account_code', '3133').maybeSingle();
  print('3133: $a3133');
  if (a3133 == null) {
    try {
      final ins3133 = await client.from('accounts').insert({
        'account_code': '3133',
        'name': 'Administrative Expenses Control',
        'account_name': 'مصاريف إدارية',
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'is_leaf': false,
        'allow_posting': false,
        'is_active': true,
        'level': 4,
        'parent_id': parent313Id,
        'company_id': companyId,
      }).select().single();
      print('Inserted 3133: $ins3133');
      a3133 = ins3133;
    } catch (e) {
      print('Insert 3133 error: $e');
    }
  }

  // 3. Check 31331
  var a31331 = await client.from('accounts').select('id, account_code').eq('account_code', '31331').maybeSingle();
  print('31331: $a31331');
  if (a31331 == null && a3133 != null) {
    try {
      final ins31331 = await client.from('accounts').insert({
        'account_code': '31331',
        'name': 'مصاريف إدارية',
        'account_name': 'مصاريف إدارية',
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'is_leaf': true,
        'allow_posting': true,
        'is_active': true,
        'level': 5,
        'parent_id': a3133['id'],
        'company_id': companyId,
      }).select().single();
      print('Inserted 31331: $ins31331');
      a31331 = ins31331;
    } catch (e) {
      print('Insert 31331 error: $e');
    }
  }

  // 4. Create or verify Cost Center CC-ADMIN-EXPENSES
  var cc = await client.from('cost_centers').select('id, code').eq('code', 'CC-ADMIN-EXPENSES').maybeSingle();
  if (cc == null) {
    try {
      final insCc = await client.from('cost_centers').insert({
        'code': 'CC-ADMIN-EXPENSES',
        'name': 'مصاريف إدارية',
        'name_ar': 'مصاريف إدارية',
        'name_en': 'Administrative Expenses',
        'cost_center_type': 'operational',
        'is_active': true,
        'color': '#0284C7',
        'icon': 'business_center_rounded',
        'description': 'مركز تكلفة مخصص للمصاريف الإدارية والعمومية',
      }).select().single();
      print('Inserted Cost Center: $insCc');
    } catch (e) {
      print('Insert Cost Center error: $e');
    }
  }

  // 5. Insert or update in cost_report_categories
  var cat = await client.from('cost_report_categories').select('*').eq('name', 'مصاريف إدارية').maybeSingle();
  if (cat == null) {
    try {
      final insCat = await client.from('cost_report_categories').insert({
        'name': 'مصاريف إدارية',
        'scope': 'all',
        'is_system': false,
        'type': 'indirect',
        'account_id': a31331?['id'] ?? 5388,
        'supplier_type': 'admin',
        'cost_center_id': 'CC-ADMIN-EXPENSES',
      }).select().single();
      print('Inserted cost_report_categories: $insCat');
    } catch (e) {
      print('Insert cost category error: $e');
    }
  } else {
    print('Category already exists: $cat');
    await client.from('cost_report_categories').update({
      'scope': 'all',
      'account_id': a31331?['id'] ?? 5388,
      'supplier_type': 'admin',
      'cost_center_id': 'CC-ADMIN-EXPENSES',
    }).eq('id', cat['id']);
    print('Updated category id: ${cat['id']}');
  }

  // 6. Update accounts cost_center_id
  await client.from('accounts').update({
    'cost_center_id': 'CC-ADMIN-EXPENSES',
  }).eq('id', a31331?['id'] ?? 5388);
  print('Updated account 5388 with cost_center_id');

  final cats = await client.from('cost_report_categories').select('*').order('id');
  print('\n=== ALL COST REPORT CATEGORIES (${cats.length}) ===');
  for (var c in cats) {
    print('${c["id"]} | ${c["name"]} | scope:${c["scope"]} | supplier_type:${c["supplier_type"]} | account_id:${c["account_id"]} | cc:${c["cost_center_id"]}');
  }
} catch (e, st) {
  print('ERROR: $e\n$st');
}
}


