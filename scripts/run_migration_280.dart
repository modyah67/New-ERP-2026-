import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
  );
  
  print('=== Applying Migration 280: Fix BIGINT → UUID + FK Constraints ===');
  
  try {
    final sql = File('supabase/migrations/280_fix_purchase_invoice_id_type.sql').readAsStringSync();
    print('SQL file loaded (${sql.length} chars)');
    
    // Try with 'sql' param first
    try {
      final result = await client.rpc('exec_sql', params: {'sql': sql});
      print('Result (sql param): $result');
    } catch (e1) {
      print('sql param failed: $e1');
      // Try with 'query' param
      try {
        final result = await client.rpc('exec_sql', params: {'query': sql});
        print('Result (query param): $result');
      } catch (e2) {
        print('query param also failed: $e2');
        print('exec_sql function may not exist on production DB.');
        print('Migration must be applied manually via Supabase Dashboard SQL Editor.');
      }
    }
    
    // Verify the fix
    print('\n=== Verifying Fix ===');
    try {
      final r1 = await client.rpc('exec_sql', params: {
        'query': "SELECT data_type FROM information_schema.columns WHERE table_name='station_product_batches' AND column_name='purchase_invoice_id'"
      });
      print('station_product_batches.purchase_invoice_id type: ${r1}');
    } catch (_) {}
    
  } catch (e) {
    print('ERROR: $e');
  }
}
