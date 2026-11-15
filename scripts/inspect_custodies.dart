import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  
  // 1. Inspect treasuries where type is custody or similar
  final treasuries = await c.from('treasuries').select('*');
  print('=== Treasuries (${treasuries.length}) ===');
  for (var t in treasuries) {
    print('ID: ${t["id"]} | Name: ${t["name"]} | Type: ${t["type"]} | AccountID: ${t["account_id"]} | UserID: ${t["user_id"]}');
  }

  // 2. Inspect accounts for custody (126, 1261, 12612 or search for عهدة or شريف)
  final accs = await c.from('accounts').select('id, account_code, account_name, parent_id, is_leaf, allow_posting').or('account_code.like.126%,account_name.ilike.%عهدة%,account_name.ilike.%شريف%');
  print('\n=== Custody Accounts (${accs.length}) ===');
  for (var a in accs) {
    print('ID: ${a["id"]} | Code: ${a["account_code"]} | Name: ${a["account_name"]} | Leaf: ${a["is_leaf"]} | AllowPosting: ${a["allow_posting"]}');
  }

  // 3. Inspect packing_order_cost_items for order 1 and 2
  final items = await c.from('packing_order_cost_items').select('*');
  print('\n=== All packing_order_cost_items (${items.length}) ===');
  for (var it in items) {
    print('ID: ${it["id"]} | PO: ${it["packing_order_id"]} | Name: ${it["name"]} | Cat: ${it["category"]} | SuppID: ${it["supplier_id"]} | CustodyID: ${it["custody_id"]} | EngName: ${it["engineer_name"]} | Snapshot: ${it["currency_snapshot"]}');
  }
}
