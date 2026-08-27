import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L'
  );
  try {
    final materialId = '0426f5b8-6b4d-4868-b6e5-ec7cb27d1936';
    final data = await client
            .from('stock_batches')
            .select('*, suppliers(name)')
            .eq('product_id', materialId)
            .order('created_at', ascending: true);
    print('stock_batches for material: $data');
  } catch (e) {
    print('error: $e');
  }
}
