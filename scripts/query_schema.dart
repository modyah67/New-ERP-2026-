import 'dart:io';
import 'package:supabase_client/supabase_client.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    print('Querying information_schema.tables...');
    final tables = await client.from('information_schema.tables').select('table_name').eq('table_schema', 'public');
    print('Tables: $tables');
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
