import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final result = await client.rpc('exec_sql', params: {'sql': "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'rpc_edit_purchase_item_price';"});
    print('result: $result');
  } catch (e) {
    print('error: $e');
  }
}
