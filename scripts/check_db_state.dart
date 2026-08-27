import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient('https://pjkhdnoeyyvraclomepx.supabase.co', 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L');

  print('=== accounts columns ===');
  try {
    final r = await c.from('accounts').select('*').limit(1);
    if ((r as List).isNotEmpty) {
      print((r[0] as Map).keys.join(', '));
    } else {
      // Empty table — insert dummy to discover columns
      await c.from('accounts').insert({'account_code': 'TEST', 'name': 'test', 'account_type': 'asset'});
      print('Insert succeeded with account_code, name, account_type');
      // cleanup
      await c.from('accounts').delete().eq('account_code', 'TEST');
    }
  } catch (e) {
    print('ERROR: $e');
    // Try minimal insert
    try {
      await c.from('accounts').insert({'account_code': 'TEST2', 'name': 'test2'});
      print('Minimal insert worked: account_code, name');
      await c.from('accounts').delete().eq('account_code', 'TEST2');
    } catch (e2) {
      print('Minimal also failed: $e2');
    }
  }

  print('\n=== suppliers columns ===');
  try {
    await c.from('suppliers').insert({'name': 'TEST', 'supplier_code': 'TEST'});
    print('Insert worked: name, supplier_code');
    await c.from('suppliers').delete().eq('supplier_code', 'TEST');
  } catch (e) {
    print('ERROR: $e');
    try {
      await c.from('suppliers').insert({'name': 'TEST2', 'code': 'TEST2'});
      print('code column worked');
      await c.from('suppliers').delete().eq('code', 'TEST2');
    } catch (e2) {
      print('code also failed: $e2');
    }
  }

  print('\n=== station_product_batches columns ===');
  try {
    final r = await c.from('station_product_batches').select('*').limit(1);
    if ((r as List).isNotEmpty) {
      print((r[0] as Map).keys.join(', '));
    } else {
      print('Empty — checking migration for schema');
    }
  } catch (e) { print('ERROR: $e'); }

  print('\n=== purchase_invoices columns ===');
  try {
    final r = await c.from('purchase_invoices').select('*').limit(1);
    if ((r as List).isNotEmpty) {
      print((r[0] as Map).keys.join(', '));
    } else {
      print('Empty');
    }
  } catch (e) { print('ERROR: $e'); }

  print('\n=== DONE ===');
}
