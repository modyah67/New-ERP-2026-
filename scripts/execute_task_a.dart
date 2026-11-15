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

  print('=== STEP 1: CONNECTED TO SUPABASE AS ADMIN/TENANT ===');

  // We can execute SQL RPC or DDL via RPC or direct table queries.
  // Let's test if we have exec_sql RPC or direct table manipulation.
  try {
    // 1.1 Insert Level 4 Parent Accounts 2116 and 2117 if not existing
    print('\n--- 1.1 Inserting Level 4 Accounts 2116 & 2117 ---');
    final parent211 = await c.from('accounts').select('id').eq('account_code', '211').single();
    final parent211Id = parent211['id'] as int;

    final existing2116 = await c.from('accounts').select('id').eq('account_code', '2116').maybeSingle();
    int id2116;
    if (existing2116 == null) {
      final ins2116 = await c.from('accounts').insert({
        'account_code': '2116',
        'name': 'Shared Suppliers',
        'account_name': 'الموردون المشتركون',
        'account_type': 'liability',
        'normal_balance': 'Credit',
        'sort_order': 21160,
        'company_id': 'a0000000-0000-0000-0000-000000000001',
        'parent_id': parent211Id,
        'level': 4,
        'is_leaf': false,
        'allow_posting': false,
        'is_system': true,
        'is_active': true,
      }).select('id').single();
      id2116 = ins2116['id'] as int;
      print('Inserted Account 2116: ID=$id2116');
    } else {
      id2116 = existing2116['id'] as int;
      print('Account 2116 already exists: ID=$id2116');
    }

    final existing2117 = await c.from('accounts').select('id').eq('account_code', '2117').maybeSingle();
    int id2117;
    if (existing2117 == null) {
      final ins2117 = await c.from('accounts').insert({
        'account_code': '2117',
        'name': 'Transport Suppliers',
        'account_name': 'موردو النقل والسيارات',
        'account_type': 'liability',
        'normal_balance': 'Credit',
        'sort_order': 21170,
        'company_id': 'a0000000-0000-0000-0000-000000000001',
        'parent_id': parent211Id,
        'level': 4,
        'is_leaf': false,
        'allow_posting': false,
        'is_system': true,
        'is_active': true,
      }).select('id').single();
      id2117 = ins2117['id'] as int;
      print('Inserted Account 2117: ID=$id2117');
    } else {
      id2117 = existing2117['id'] as int;
      print('Account 2117 already exists: ID=$id2117');
    }

    // 1.1b Level 5 sub-ledger templates: 21161 and 21171
    final existing21161 = await c.from('accounts').select('id').eq('account_code', '21161').maybeSingle();
    if (existing21161 == null) {
      await c.from('accounts').insert({
        'account_code': '21161',
        'name': 'Shared Suppliers Sub-ledger',
        'account_name': 'الموردون المشتركون - فرعي',
        'account_type': 'liability',
        'normal_balance': 'Credit',
        'sort_order': 21161,
        'company_id': 'a0000000-0000-0000-0000-000000000001',
        'parent_id': id2116,
        'level': 5,
        'is_leaf': true,
        'allow_posting': true,
        'is_system': false,
        'is_active': true,
      });
      print('Inserted Account 21161 (Level 5 template)');
    }

    final existing21171 = await c.from('accounts').select('id').eq('account_code', '21171').maybeSingle();
    if (existing21171 == null) {
      await c.from('accounts').insert({
        'account_code': '21171',
        'name': 'Transport Suppliers Sub-ledger',
        'account_name': 'موردو النقل والسيارات - فرعي',
        'account_type': 'liability',
        'normal_balance': 'Credit',
        'sort_order': 21171,
        'company_id': 'a0000000-0000-0000-0000-000000000001',
        'parent_id': id2117,
        'level': 5,
        'is_leaf': true,
        'allow_posting': true,
        'is_system': false,
        'is_active': true,
      });
      print('Inserted Account 21171 (Level 5 template)');
    }

    // 1.6 Migrate existing accounts (ACCOUNTS ONLY, suppliers.code remains intact!)
    print('\n--- 1.6 Migrating Existing Accounts ---');
    // Yasser (Account ID: 4416) -> parent: 2116, code: 211601
    await c.from('accounts').update({
      'parent_id': id2116,
      'account_code': '211601',
      'account_name': 'مورد مشترك - ياسر',
      'name': 'Shared Supplier - ياسر',
      'sort_order': 211601,
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
    }).eq('id', 4416);
    print('Migrated Yasser Account ID 4416 -> 211601 under parent 2116 (ID: $id2116)');

    // Khaled (Account ID: 4421) -> parent: 2116, code: 211602
    await c.from('accounts').update({
      'parent_id': id2116,
      'account_code': '211602',
      'account_name': 'مورد مشترك - خالد',
      'name': 'Shared Supplier - خالد',
      'sort_order': 211602,
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
    }).eq('id', 4421);
    print('Migrated Khaled Account ID 4421 -> 211602 under parent 2116 (ID: $id2116)');

    // Hamza (Account ID: 4417) -> parent: 2117, code: 211701
    await c.from('accounts').update({
      'parent_id': id2117,
      'account_code': '211701',
      'account_name': 'مورد نقل - حمزه',
      'name': 'Transporter - حمزه',
      'sort_order': 211701,
      'level': 5,
      'is_leaf': true,
      'allow_posting': true,
    }).eq('id', 4417);
    print('Migrated Hamza Account ID 4417 -> 211701 under parent 2117 (ID: $id2117)');

    // 1.7 Fix company_id for the 4 specific rows and their accounts
    print('\n--- 1.7 Fixing company_id for 4 operational rows and their accounts ---');
    const tenantCompanyId = '9aae4cab-8ee3-4bc1-8e05-990894869c2e';

    // transport_suppliers (Hamza, id=1)
    await c.from('transport_suppliers').update({
      'company_id': tenantCompanyId,
    }).eq('id', 1);
    print('Updated transport_suppliers ID 1 with company_id: $tenantCompanyId');

    // shipping_companies (id=1)
    await c.from('shipping_companies').update({
      'company_id': tenantCompanyId,
    }).eq('id', 1);
    print('Updated shipping_companies ID 1 with company_id: $tenantCompanyId');

    // clearing_agents (id=1, id=2)
    await c.from('clearing_agents').update({
      'company_id': tenantCompanyId,
    }).inFilter('id', [1, 2]);
    print('Updated clearing_agents IDs 1, 2 with company_id: $tenantCompanyId');

    // accounts 4417, 4418, 4419, 4420
    await c.from('accounts').update({
      'company_id': tenantCompanyId,
    }).inFilter('id', [4417, 4418, 4419, 4420]);
    print('Updated accounts 4417, 4418, 4419, 4420 with company_id: $tenantCompanyId');

    print('\n=== LIVE DATA MIGRATION COMPLETED SUCCESSFULLY ===');
  } catch (e, st) {
    print('ERROR executing migration: $e\n$st');
  }
}
