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

  print('================================================================');
  print('Q1. SUPPLIERS CODE vs SUPPLIER_CODE vs ACCOUNT_CODE');
  print('================================================================');
  final supps = await c.from('suppliers').select('id, name, code, supplier_code, account_id, supplier_type, company_id');
  for (final s in supps) {
    print('  Supplier: name=${s['name']} | code=${s['code']} | supplier_code=${s['supplier_code']} | account_id=${s['account_id']} | type=${s['supplier_type']}');
  }

  print('\n================================================================');
  print('Q2. COA PARENT ACCOUNTS UNDER 211 & TEMPLATE COMPANY');
  print('================================================================');
  final parents = await c
      .from('accounts')
      .select('id, account_code, name, account_name, level, parent_id, company_id, is_leaf, allow_posting')
      .inFilter('account_code', ['211', '2111', '2112', '2113', '2114', '2115', '2116', '2117']);
  for (final p in parents) {
    print('  Parent: code=${p['account_code']} | ID=${p['id']} | name=${p['account_name']} | company_id=${p['company_id']} | level=${p['level']}');
  }

  // Test trigger parent lookup query for active company: 9aae4cab-8ee3-4bc1-8e05-990894869c2e
  final testCompId = '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
  for (final code in ['2111', '2115', '2116', '2117']) {
    final directMatch = await c
        .from('accounts')
        .select('id, account_code, company_id')
        .eq('account_code', code)
        .or('company_id.eq.$testCompId,company_id.is.null');
    final fallbackMatch = await c
        .from('accounts')
        .select('id, account_code, company_id')
        .eq('account_code', code)
        .limit(1);
    print('  Testing lookup for code=$code: directMatch=${directMatch.length}, fallbackMatch=${fallbackMatch.length} (fallback company=${fallbackMatch.isNotEmpty ? fallbackMatch.first['company_id'] : 'none'})');
  }

  print('\n================================================================');
  print('Q3. ROWS WITH company_id = NULL ACROSS OPERATIONAL TABLES');
  print('================================================================');
  final tablesToCheck = [
    'suppliers',
    'transport_suppliers',
    'shipping_companies',
    'clearing_agents',
    'customers',
    'accounts'
  ];

  for (final table in tablesToCheck) {
    try {
      final nullRows = await c.from(table).select('*').isFilter('company_id', null);
      final totalRows = await c.from(table).select('id').count(CountOption.exact);
      print('  Table: $table -> NULL company_id count: ${nullRows.length} / ${totalRows.count}');
      for (final r in nullRows) {
        print('    Row details: id=${r['id']} | name=${r['name']} | created_at=${r['created_at']} | account_id=${r['account_id']} | code=${r['code']}');
      }
    } catch (e) {
      print('  Table: $table -> Error: $e');
    }
  }

  print('\n================================================================');
  print('Q5. UNIQUENESS CHECK FOR 2116, 2117 & SUB-ACCOUNTS');
  print('================================================================');
  final existing2116_2117 = await c
      .from('accounts')
      .select('id, account_code, name, company_id')
      .or('account_code.eq.2116,account_code.eq.2117,account_code.like.2116%,account_code.like.2117%');
  print('  Existing accounts matching 2116* or 2117*: ${existing2116_2117.length}');
  for (final a in existing2116_2117) {
    print('    Found: code=${a['account_code']} | ID=${a['id']} | name=${a['name']}');
  }
}
