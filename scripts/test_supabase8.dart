import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final sup = await client.from('suppliers').select('id').limit(1);
    print('suppliers: $sup');
  } catch (e) {
    print('error: $e');
  }
}
