import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  final sql = File('supabase/migrations/260_fix_station_product_batch_merging.sql').readAsStringSync();
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('Migration 260 executed successfully');
  } catch (e) {
    print('exec_sql failed: $e');
  }
  exit(0);
}
