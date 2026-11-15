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

  // 1. Update allocation 1 (TX 3 opening balance) to 100
  await c.from('supplier_payment_allocations').update({
    'amount': 100.0,
    'allocated_amount': 100.0,
  }).eq('id', 1);

  // 2. Insert allocation for Lot 1 from TX 3
  await c.from('supplier_payment_allocations').insert({
    'source_type': 'treasury',
    'source_id': 3,
    'lot_receipt_id': 1,
    'supplier_id': supId,
    'allocation_type': 'lot_receipt',
    'amount': 8000.0,
    'allocated_amount': 8000.0,
  });

  // 3. Print all allocations
  final allAlloc = await c.from('supplier_payment_allocations').select('*').eq('supplier_id', supId);
  print('ALLOCATIONS FOR SUPPLIER:');
  for (var a in allAlloc) {
    print(a);
  }
}
