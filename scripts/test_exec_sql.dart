import 'dart:io';
import 'package:supabase_client/supabase_client.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    print('Testing query...');
    final res = await client.rpc('exec_sql', params: {'query': 'SELECT 1 as val'});
    print('Result: $res');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
