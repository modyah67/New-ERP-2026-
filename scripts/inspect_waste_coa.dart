import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: 'password123');
  } catch (_) {}

  // 1. Packaging Inventory Accounts
  final pkgAccounts = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting')
      .or('account_code.eq.12411,account_code.eq.1040,name.ilike.%تعبئة%')
      .limit(10);
  print('=== PACKAGING INVENTORY ACCOUNTS ===');
  for (final a in pkgAccounts) {
    print('${a['account_code']} | ${a['account_name'] ?? a['name']} | id:${a['id']} | leaf:${a['is_leaf']} | allow_posting:${a['allow_posting']}');
  }

  // 2. Finished Goods Inventory Accounts
  final fgAccounts = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting')
      .or('account_code.eq.12413,account_code.eq.1031,name.ilike.%تام%')
      .limit(10);
  print('\n=== FINISHED GOODS INVENTORY ACCOUNTS ===');
  for (final a in fgAccounts) {
    print('${a['account_code']} | ${a['account_name'] ?? a['name']} | id:${a['id']} | leaf:${a['is_leaf']} | allow_posting:${a['allow_posting']}');
  }

  // 3. Waste / Scrap Accounts in Root 3 and Root 5 and Root 1/2
  final wasteAccounts = await client
      .from('accounts')
      .select('id, account_code, name, account_name, level, is_leaf, allow_posting')
      .or('name.ilike.%هالك%,name.ilike.%فاقد%,name.ilike.%تالف%,account_name.ilike.%هالك%,account_name.ilike.%فاقد%')
      .limit(20);
  print('\n=== WASTE / SCRAP ACCOUNTS IN COA ===');
  for (final a in wasteAccounts) {
    print('${a['account_code']} | ${a['account_name'] ?? a['name']} | id:${a['id']} | leaf:${a['is_leaf']} | allow_posting:${a['allow_posting']}');
  }

  exit(0);
}
