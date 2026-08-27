import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBqa2hkbm9leXl2cmFjbG9tZXB4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDAwMDAwMDAsImV4cCI6MjA1NTU1NTU1NX0.dummy_token_if_needed',
  );

  try {
    final res = await client.from('stations').select();
    print('Stations count: ${res.length}');
    print('Stations data: $res');
  } catch (e) {
    print('Error: $e');
  }
}
