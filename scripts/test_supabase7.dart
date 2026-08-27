import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final result = await client.rpc('exec_sql', params: {'sql': "SELECT data_type FROM information_schema.columns WHERE table_name = 'purchase_invoices' AND column_name = 'id';"});
    print('result: $result');
  } catch (e) {
    print('error: $e');
  }
}
