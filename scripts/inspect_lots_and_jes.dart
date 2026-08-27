import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final url = 'https://pjkhdnoeyyvraclomepx.supabase.co';
  final key = 'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12';
  
  final client = SupabaseClient(url, key);
  
    final vLines = await client.from('v_journal_entry_lines').select('*');
    print('Total lines in v_journal_entry_lines: ${vLines.length}');










    print('--- TEST FALLBACK QUERY ---');
    try {
      final fb = await client.from('account_ledger_entries').select('''
        id, account_id, debit, credit, description, created_at,
        journal_entries!inner(id, entry_number, entry_date, description, source_type, source_id)
      ''').gte('journal_entries.entry_date', '2026-08-01').lte('journal_entries.entry_date', '2026-08-06');
      print('Fallback count: ${fb.length}');
      for (var row in fb) {
        print(row);
      }
    } catch (e) {
      print('Fallback error: $e');
    }

    print('--- V_JOURNAL_ENTRY_LINES ALL ---');
    try {
      final vlines = await client.from('v_journal_entry_lines').select('*').limit(20);
      for (var l in vlines) {
        print('VLine: entry_number=${l['entry_number']}, debit=${l['debit']}, credit=${l['credit']}, desc=${l['description']}');
      }
    } catch (e) {
      print('Error querying v_journal_entry_lines: $e');
    }

    print('--- LOT RECEIPTS ---');
    final lots = await client.from('lot_receipts').select('id, lot_number, journal_entry_id').order('id', ascending: false).limit(5);
    for (var l in lots) {
      print('LOT: id=${l['id']}, num=${l['lot_number']}, je_id=${l['journal_entry_id']}');
    }

    print('--- V_DAILY_JOURNAL_BOOK ---');
    try {
      final book = await client.from('v_daily_journal_book').select('*').limit(3);
      print('Daily book: $book');
    } catch (e) {
      print('Error querying v_daily_journal_book: $e');
    }
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
