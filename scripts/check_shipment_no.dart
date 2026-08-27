import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final supabaseUrl = 'YOUR_SUPABASE_URL';
  final supabaseKey = 'YOUR_SUPABASE_KEY';
  // Read from .env if possible, but let's just parse lib/core/service_module.dart
  final content = File('lib/core/service_module.dart').readAsStringSync();
  final urlMatch = RegExp(r"const supabaseUrl = '(.*?)';").firstMatch(content);
  final keyMatch = RegExp(r"const supabaseAnonKey = '(.*?)';").firstMatch(content);
  
  if (urlMatch == null || keyMatch == null) {
    print('Could not find credentials');
    return;
  }
  
  final client = SupabaseClient(urlMatch.group(1)!, keyMatch.group(1)!);
  final res = await client.from('export_shipments').select('shipment_no').limit(10);
  print(res);
  exit(0);
}
