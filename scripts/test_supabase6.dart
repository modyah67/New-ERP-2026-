import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final spb = await client.from('station_product_batches').select('id').limit(1);
    print('spb: $spb');
  } catch (e) {
    print('error: $e');
  }
}
