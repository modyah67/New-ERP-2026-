import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final res = await c
      .from('accounts')
      .select('id, account_code, account_name, parent_id, level, is_leaf')
      .like('account_code', '3%')
      .order('account_code');
  print('Total accounts under 3%: ${res.length}');
  for (var a in res) {
    print('${a["account_code"]} | ${a["account_name"]} | level:${a["level"]} | leaf:${a["is_leaf"]} | parent:${a["parent_id"]} | id:${a["id"]}');
  }

  final cats = await c.from('cost_report_categories').select('*').order('id');
  print('\n=== cost_report_categories (${cats.length}) ===');
  for (var cat in cats) {
    print('${cat["id"]} | ${cat["name"]} | scope:${cat["scope"]} | supplier_type:${cat["supplier_type"]} | account_id:${cat["account_id"]} | cc_id:${cat["cost_center_id"]}');
  }
}
