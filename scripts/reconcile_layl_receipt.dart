import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(
    SupabaseOptions.url,
    SupabaseOptions.anonKey,
  );

  await c.auth.signInWithPassword(
    email: 'mahmoud@gmail.com',
    password: '123456',
  );

  final supId = '80b7eeaf-ccf5-4577-8015-ad42a430ea52';

  // Test updating lot_receipts ID 1
  print('Updating lot_receipts 1 to paid...');
  final upd = await c.from('lot_receipts').update({
    'paid_amount': 8000.0,
    'payment_status': 'paid',
  }).eq('id', 1).select();
  print('Updated lot_receipt: $upd');

  // Query vw_unpaid_liabilities
  final liabs = await c.from('vw_unpaid_liabilities').select('*').eq('entity_id', supId);
  print('\nRemaining unpaid liabilities for supplier: ${liabs.length}');
  for (var l in liabs) {
    print(l);
  }
}
