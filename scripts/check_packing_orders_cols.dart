import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: 'password123');
  } catch (_) {}

  final res = await client.from('packing_orders').select().limit(1);
  if (res.isNotEmpty) {
    print('packing_orders columns: ${res.first.keys.toList()}');
  }
  exit(0);
}
