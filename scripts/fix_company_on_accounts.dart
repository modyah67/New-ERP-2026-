import 'package:supabase/supabase.dart';

void main() async {
  final c = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
  );
  await c.auth.signInWithPassword(email: 'eslam@gmail.com', password: '123456');

  // Fix company_id on 2111 accounts
  for (int i = 601; i <= 610; i++) {
    final code = '2111$i';
    try {
      await c.from('accounts').update({
        'company_id': 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5',
        'is_active': true,
        'allow_posting': true,
        'is_leaf': true,
      }).eq('account_code', code);
      print('Updated $code');
    } catch (e) {
      print('Error updating $code: $e');
    }
  }
}
