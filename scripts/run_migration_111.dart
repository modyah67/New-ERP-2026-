import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final content = File('lib/core/service_module.dart').readAsStringSync();
  final urlMatch = RegExp(r"const supabaseUrl = '(.*?)';").firstMatch(content);
  final keyMatch = RegExp(r"const supabaseAnonKey = '(.*?)';").firstMatch(content);
  
  if (urlMatch == null || keyMatch == null) {
    print('Could not find credentials');
    return;
  }
  
  final client = SupabaseClient(urlMatch.group(1)!, keyMatch.group(1)!);
  final sql = File('supabase/migrations/111_cost_reporting_live_view.sql').readAsStringSync();
  try {
    await client.rpc('exec_sql', params: {'sql': sql});
    print('SQL executed successfully via exec_sql');
  } catch (e) {
    print('exec_sql failed: $e');
    // If we don't have exec_sql, we can't run DDL via REST API.
    // The user will have to run it in Supabase dashboard.
  }
  exit(0);
}
