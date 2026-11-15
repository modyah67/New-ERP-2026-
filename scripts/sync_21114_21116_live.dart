import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(
    SupabaseOptions.url,
    SupabaseOptions.anonKey,
  );

  await c.auth.signInWithPassword(
    email: 'mahmoud@gmail.com',
    password: '123456',
  );

  // 1. Get 2111 parent info
  final parent2111 = await c
      .from('accounts')
      .select('id, company_id')
      .eq('account_code', '2111')
      .single();
  final parentId = parent2111['id'] as int;
  final companyId = parent2111['company_id'];
  print('Parent 2111 ID: $parentId, Company: $companyId');

  // 2. Ensure 21114, 21115, 21116 exist
  final accountsToEnsure = [
    {
      'account_code': '21114',
      'name': 'Shared Suppliers Sub-ledger',
      'account_name': 'موردين مشتركين',
      'account_type': 'liability',
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
      'parent_id': parentId,
      'company_id': companyId,
      'sort_order': 21114,
      'is_active': true,
    },
    {
      'account_code': '21115',
      'name': 'Shipping Companies Sub-ledger',
      'account_name': 'شركات الشحن',
      'account_type': 'liability',
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
      'parent_id': parentId,
      'company_id': companyId,
      'sort_order': 21115,
      'is_active': true,
    },
    {
      'account_code': '21116',
      'name': 'Customs Clearance Sub-ledger',
      'account_name': 'مخلصي الجمارك',
      'account_type': 'liability',
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
      'parent_id': parentId,
      'company_id': companyId,
      'sort_order': 21116,
      'is_active': true,
    },
  ];

  final resolvedIds = <String, int>{};

  for (final def in accountsToEnsure) {
    final code = def['account_code'] as String;
    final existing = await c
        .from('accounts')
        .select('id')
        .eq('account_code', code)
        .maybeSingle();
    if (existing != null) {
      resolvedIds[code] = existing['id'] as int;
      print('Account $code already exists (ID: ${existing['id']})');
    } else {
      final ins = await c.from('accounts').insert(def).select('id').single();
      resolvedIds[code] = ins['id'] as int;
      print('Created account $code with ID: ${ins['id']}');
    }
  }

  final id21114 = resolvedIds['21114']!;
  final id21115 = resolvedIds['21115']!;
  final id21116 = resolvedIds['21116']!;

  // 3. Repoint shared suppliers -> 21114
  print('\n=== Repointing Shared Suppliers ===');
  final sups = await c.from('suppliers').select('id, name, supplier_type').eq('supplier_type', 'shared');
  for (final s in sups) {
    await c.from('suppliers').update({'account_id': id21114}).eq('id', s['id']);
    print('Repointed shared supplier "${s['name']}" -> account_id $id21114 (21114)');
  }

  // 4. Repoint shipping companies -> 21115
  print('\n=== Repointing Shipping Companies ===');
  final ships = await c.from('shipping_companies').select('id, name');
  for (final sh in ships) {
    await c.from('shipping_companies').update({'account_id': id21115}).eq('id', sh['id']);
    print('Repointed shipping "${sh['name']}" -> account_id $id21115 (21115)');
  }

  // 5. Repoint clearing agents -> 21116
  print('\n=== Repointing Clearing Agents ===');
  final clears = await c.from('clearing_agents').select('id, name');
  for (final cl in clears) {
    await c.from('clearing_agents').update({'account_id': id21116}).eq('id', cl['id']);
    print('Repointed clearing "${cl['name']}" -> account_id $id21116 (21116)');
  }

  print('\n=== Live Sync Complete ===');
}
