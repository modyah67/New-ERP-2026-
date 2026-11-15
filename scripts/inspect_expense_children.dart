import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  final accounts = await c
      .from('accounts')
      .select('id, account_code, account_name, name, level, is_leaf, allow_posting, parent_id')
      .or('account_code.like.312%,account_code.like.313%,account_code.like.314%,account_code.like.341%')
      .order('account_code');

  for (var a in accounts) {
    print('${a["account_code"]} | ${a["account_name"]} | lvl:${a["level"]} | leaf:${a["is_leaf"]} | post:${a["allow_posting"]} | parent:${a["parent_id"]} | id:${a["id"]}');
  }
}
