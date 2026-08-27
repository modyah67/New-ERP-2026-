import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  try {
    final client = SupabaseClient(
      'https://pjkhdnoeyyvraclomepx.supabase.co',
      'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
    );

    final suppId = '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb';
    final invs = await client.from('purchase_invoices').select('id, invoice_number, total_amount, discount_amount, paid_amount, payment_status, currency').eq('supplier_id', suppId);
    print('Invoices for $suppId: $invs');

    final txs = await client.from('treasury_transactions').select('id, type, amount, currency, description, supplier_id').eq('supplier_id', suppId);
    print('Treasury transactions: $txs');

    final btxs = await client.from('bank_account_transactions').select('id, type, amount, currency, description, entity_id').eq('entity_id', suppId);
    print('Bank transactions: $btxs');
  } catch (e) {
    print('Error: $e');
  } finally {
    exit(0);
  }
}
