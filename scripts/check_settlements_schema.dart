import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://rakdzuvlauphupkywoik.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJha2R6dXZsYXVwaHVwa3l3b2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjYyNTksImV4cCI6MjEwNDgwMjI1OX0.gK5YRX3oCy8VHLeFcfcw9I1jfZY3gE75tflyyP_owZk',
  );
  try {
    final res = await client.from('packing_order_waste_settlements').select().limit(1);
    print('Settlements columns: ' + (res.isNotEmpty ? res.first.keys.toList().toString() : 'empty table'));
  } catch (e) {
    print('Error: $e');
  }
}
