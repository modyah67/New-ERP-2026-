import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  try {
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: 'password123');
  } catch (_) {}

  // Check 9111 in accounts
  final acc9111 = await client.from('accounts').select().eq('account_code', '9111').maybeSingle();
  print('Account 9111: $acc9111');

  if (acc9111 != null) {
    final entries = await client
        .from('account_ledger_entries')
        .select('id, journal_entry_id, debit, credit, description, created_at')
        .eq('account_id', acc9111['id'])
        .limit(10);
    print('Ledger entries on 9111: ${entries.length}');
    for (final e in entries) {
      print('Entry: $e');
    }
  }

  // Check 9112
  final acc9112 = await client.from('accounts').select().eq('account_code', '9112').maybeSingle();
  print('\nAccount 9112: $acc9112');
  if (acc9112 != null) {
    final entries = await client
        .from('account_ledger_entries')
        .select('id, journal_entry_id, debit, credit, description, created_at')
        .eq('account_id', acc9112['id'])
        .limit(10);
    print('Ledger entries on 9112: ${entries.length}');
    for (final e in entries) {
      print('Entry: $e');
    }
  }

  // Check 33111
  final acc33111 = await client.from('accounts').select().eq('account_code', '33111').maybeSingle();
  print('\nAccount 33111: $acc33111');
  if (acc33111 != null) {
    final entries = await client
        .from('account_ledger_entries')
        .select('id, journal_entry_id, debit, credit, description, created_at')
        .eq('account_id', acc33111['id'])
        .limit(10);
    print('Ledger entries on 33111: ${entries.length}');
    for (final e in entries) {
      print('Entry: $e');
    }
  }

  exit(0);
}
