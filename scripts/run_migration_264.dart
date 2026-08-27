import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final sql = File('supabase/migrations/264_fix_purchase_batch_number.sql').readAsStringSync();
    final result = await client.rpc('exec_sql', params: {'sql': sql});
    print('result: $result');
  } catch (e) {
    print('error: $e');
  }
}
