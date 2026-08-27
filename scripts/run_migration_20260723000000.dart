import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Apply the v3 cancel RPC migration via Supabase Management API.
/// Requires: SUPABASE_ACCESS_TOKEN environment variable
/// Get your token from: https://app.supabase.com/account/tokens
void main() async {
  final accessToken = Platform.environment['SUPABASE_ACCESS_TOKEN'];
  if (accessToken == null || accessToken.isEmpty) {
    stdout.write('Enter your Supabase Management API Access Token\n(get it from https://app.supabase.com/account/tokens):\n> ');
    final token = stdin.readLineSync()?.trim();
    if (token == null || token.isEmpty) {
      print('Error: access token required.'); exit(1);
    }
    // Re-run with env var set isn't possible in-script, so we use the token directly.
    await _applyMigration(token);
    return;
  }
  await _applyMigration(accessToken);
}

Future<void> _applyMigration(String token) async {
  const projectRef = 'pjkhdnoeyyvraclomepx';
  final sql = File('supabase/migrations/20260723000000_fix_rpc_cancel_packing_order_v3.sql')
      .readAsStringSync();

  print('Applying v3 migration via Supabase Management API...');
  print('SQL length: ${sql.length} chars');

  final resp = await http.post(
    Uri.parse('https://api.supabase.com/v1/projects/$projectRef/database/query'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'query': sql}),
  );

  print('HTTP Status: ${resp.statusCode}');
  print('Response: ${resp.body}');

  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    print('✅ Migration applied successfully!');
  } else {
    print('❌ Migration failed. Check the response above.');
    exit(1);
  }
}
