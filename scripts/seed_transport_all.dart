import 'package:supabase/supabase.dart';
import '../lib/core/database_seeder.dart';

void main() async {
  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );
  await c.auth.signInWithPassword(email: 'eslam@gmail.com', password: '123456');

  final companyId = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';

  for (final t in DatabaseSeeder.transportSuppliers) {
    try {
      final accCode = '2111${t.code}';
      var acc = await c.from('accounts').select('id').eq('account_code', accCode).maybeSingle();
      int accId;
      if (acc != null) {
        accId = acc['id'] as int;
      } else {
        final ins = await c.from('accounts').insert({
          'account_code': accCode,
          'name': t.name,
          'account_name': t.name,
          'account_type': 'liability',
          'parent_id': 1327,
          'level': 4,
          'is_leaf': true,
          'allow_posting': true,
          'is_active': true,
          'is_system': false,
          'normal_balance': 'Credit',
          'company_id': companyId,
        }).select('id').single();
        accId = ins['id'] as int;
      }

      final existing = await c.from('transport_suppliers').select('id').eq('code', t.code).maybeSingle();
      if (existing != null) {
        await c.from('transport_suppliers').update({
          'name': t.name,
          'account_id': accId,
        }).eq('id', existing['id']);
        print('Updated transport supplier ${t.code}');
      } else {
        await c.from('transport_suppliers').insert({
          'code': t.code,
          'name': t.name,
          'initial_balance': 0.0,
          'initial_balance_direction': 'CREDIT',
          'balance': 0.0,
          'truck_balance': 0,
          'initial_truck_balance': 0,
          'account_id': accId,
          'company_id': companyId,
        });
        print('Inserted transport supplier ${t.code}');
      }
    } catch (e) {
      print('Error on ${t.code}: $e');
    }
  }
}
