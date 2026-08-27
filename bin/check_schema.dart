import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  final supabase = SupabaseClient(
    dotenv.env['SUPABASE_URL']!,
    dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  try {
    final data = await supabase.from('expense_categories').select().limit(1);
    print(data);
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}