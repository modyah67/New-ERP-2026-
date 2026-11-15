import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // Check JE 38 lines
  final lines38 = await c.from('v_journal_entry_lines').select('*').eq('journal_entry_id', 38);
  print('JE 38 lines (${lines38.length}):');
  for (var l in lines38) {
    print('  Line: acc=${l["account_code"]} (${l["account_name"]}) | Dr=${l["debit"]} | Cr=${l["credit"]} | desc=${l["description"]}');
  }

  // Check treasury_transactions for treasury 2
  final tt = await c.from('treasury_transactions').select('*').eq('treasury_id', 2);
  print('\nTreasury 2 transactions (${tt.length}):');
  for (var t in tt) {
    print('  ${t["id"]} | type:${t["type"]} | amt:${t["amount"]} | desc:${t["description"]} | ref:${t["reference_id"]}');
  }

  // Check treasury_balances for treasury 2
  final tb = await c.from('treasury_balances').select('*').eq('treasury_id', 2);
  print('\nTreasury 2 balances: $tb');
}
