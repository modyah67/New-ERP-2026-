import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final results = await client.from('raw_materials').select('id, name').eq('id', '0426f5b8-6b4d-4868-b6e5-ec7cb27d1936');
    print('raw_materials: $results');
  } catch (e) {
    print('error: $e');
  }
}
