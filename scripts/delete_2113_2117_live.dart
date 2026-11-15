import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // Repoint any entities that might still have account_id pointing to these obsolete accounts:
  // Level 5 children:
  // 21131 (shipping) -> repoint to 21115
  // 21141 (clearing) -> repoint to 21116
  // 21151 (packaging) -> repoint to 21112
  // 21161 (shared) -> repoint to 21114
  // 21171 (transport) -> repoint to 21111

  final obsoleteCodes = [
    '21131', '21141', '21151', '21161', '21171',
    '2113', '2114', '2115', '2116', '2117',
  ];

  print('=== Querying obsolete accounts ===');
  final accounts = await c
      .from('accounts')
      .select('id, account_code, account_name, parent_id, is_system')
      .inFilter('account_code', obsoleteCodes);

  print('Found ${accounts.length} obsolete accounts:');
  for (var a in accounts) {
    print('  ${a['account_code']} | ${a['account_name']} (id: ${a['id']}, is_system: ${a['is_system']})');
  }

  // Get replacement IDs for 21111-21116
  final replacements = await c
      .from('accounts')
      .select('id, account_code')
      .inFilter('account_code', ['21111', '21112', '21113', '21114', '21115', '21116']);
  
  final repMap = {for (var r in replacements) r['account_code']: r['id']};
  print('Replacements available: $repMap');

  // If any account has is_system = true, set to false first
  for (var a in accounts) {
    if (a['is_system'] == true) {
      await c.from('accounts').update({'is_system': false}).eq('id', a['id']);
      print('Set is_system=false for ${a['account_code']}');
    }
  }

  // Repoint references in tables: shipping_companies, clearing_agents, suppliers
  final acctMap = {for (var a in accounts) a['account_code']: a['id']};

  // 1. Shipping companies: 2113 / 21131 -> 21115
  if (repMap.containsKey('21115')) {
    final shipOldIds = [acctMap['2113'], acctMap['21131']].whereType<int>().toList();
    if (shipOldIds.isNotEmpty) {
      await c.from('shipping_companies').update({'account_id': repMap['21115']}).inFilter('account_id', shipOldIds);
      print('Repointed shipping_companies to 21115');
    }
  }

  // 2. Clearing agents: 2114 / 21141 -> 21116
  if (repMap.containsKey('21116')) {
    final clearOldIds = [acctMap['2114'], acctMap['21141']].whereType<int>().toList();
    if (clearOldIds.isNotEmpty) {
      await c.from('clearing_agents').update({'account_id': repMap['21116']}).inFilter('account_id', clearOldIds);
      print('Repointed clearing_agents to 21116');
    }
  }

  // 3. Packaging suppliers: 2115 / 21151 -> 21112
  if (repMap.containsKey('21112')) {
    final packOldIds = [acctMap['2115'], acctMap['21151']].whereType<int>().toList();
    if (packOldIds.isNotEmpty) {
      await c.from('suppliers').update({'account_id': repMap['21112']}).inFilter('account_id', packOldIds);
      print('Repointed packaging suppliers to 21112');
    }
  }

  // 4. Shared suppliers: 2116 / 21161 -> 21114
  if (repMap.containsKey('21114')) {
    final sharedOldIds = [acctMap['2116'], acctMap['21161']].whereType<int>().toList();
    if (sharedOldIds.isNotEmpty) {
      await c.from('suppliers').update({'account_id': repMap['21114']}).inFilter('account_id', sharedOldIds);
      print('Repointed shared suppliers to 21114');
    }
  }

  // 5. Transport suppliers: 2117 / 21171 -> 21111
  if (repMap.containsKey('21111')) {
    final transOldIds = [acctMap['2117'], acctMap['21171']].whereType<int>().toList();
    if (transOldIds.isNotEmpty) {
      await c.from('suppliers').update({'account_id': repMap['21111']}).inFilter('account_id', transOldIds);
      print('Repointed transport suppliers to 21111');
    }
  }

  // Step A: Delete Level 5 subaccounts FIRST (21131, 21141, 21151, 21161, 21171)
  final level5Codes = ['21131', '21141', '21151', '21161', '21171'];
  for (var code in level5Codes) {
    if (acctMap.containsKey(code)) {
      final res = await c.from('accounts').delete().eq('id', acctMap[code]!).select('id, account_code');
      print('Deleted Level 5 account $code: $res');
    }
  }

  // Step B: Delete Level 4 accounts SECOND (2113, 2114, 2115, 2116, 2117)
  final level4Codes = ['2113', '2114', '2115', '2116', '2117'];
  for (var code in level4Codes) {
    if (acctMap.containsKey(code)) {
      final res = await c.from('accounts').delete().eq('id', acctMap[code]!).select('id, account_code');
      print('Deleted Level 4 account $code: $res');
    }
  }

  print('\n=== Final verification ===');
  final remaining = await c
      .from('accounts')
      .select('id, account_code')
      .inFilter('account_code', obsoleteCodes);
  print('Remaining obsolete accounts: ${remaining.length}');
  if (remaining.isEmpty) {
    print('SUCCESS: All 10 obsolete accounts (2113-2117 and 21131-21171) have been deleted completely from live DB!');
  } else {
    for (var r in remaining) {
      print('  Still remaining: ${r['account_code']}');
    }
  }
}
