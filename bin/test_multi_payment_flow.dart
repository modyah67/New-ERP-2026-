import 'dart:io';
import 'dart:math';
import 'package:supabase/supabase.dart';

void main() async {
  try {
    final client = SupabaseClient(
      'https://pjkhdnoeyyvraclomepx.supabase.co',
      'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12',
    );

    // 1. Fetch supplier '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb' (مورد دولار رصيد 100)
    final suppRes = await client.from('suppliers').select().eq('id', '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb').single();
    print('Supplier: ${suppRes['name']}, initial_balance: ${suppRes['initial_balance']}, dir: ${suppRes['initial_balance_direction']}, outstanding: ${suppRes['outstanding_balance']}');

    // 2. Fetch true balances
    final trueBals = await client.rpc('get_supplier_true_balances');
    final suppTrueBal = (trueBals as List).firstWhere((b) => b['supplier_id'] == '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb');
    print('Supplier true_balance from RPC: $suppTrueBal');

    // 3. Fetch unpaid invoices
    final invs = await client.from('purchase_invoices').select('id, invoice_number, invoice_date, total_amount, discount_amount, paid_amount, payment_status, currency').eq('supplier_id', '34c0ab81-f4ee-48c4-9d0b-bf01bebd0bbb');
    print('Supplier invoices: $invs');

    // 4. Calculate opening balance remaining and total outstanding
    final initialBal = (suppRes['initial_balance'] as num?)?.toDouble() ?? 0.0;
    final initialDir = (suppRes['initial_balance_direction'] ?? 'CREDIT').toString().toUpperCase();
    final trueBal = (suppTrueBal['true_balance'] as num?)?.toDouble() ?? 0.0;

    double totalInvoicesDue = 0.0;
    for (final inv in invs) {
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      final discount = (inv['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final paid = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final due = max(0.0, (total - discount) - paid);
      totalInvoicesDue += due;
    }

    final double openingBalanceRemaining = (initialDir == 'CREDIT')
        ? max(0.0, min(initialBal, trueBal - totalInvoicesDue))
        : 0.0;
    
    final double totalOutstanding = openingBalanceRemaining + totalInvoicesDue;

    print('--- CALCULATION RESULT ---');
    print('Total Invoices Due: $totalInvoicesDue');
    print('Opening Balance Remaining: $openingBalanceRemaining');
    print('Total Outstanding: $totalOutstanding (Matches true_balance: ${totalOutstanding == trueBal})');
  } catch (e, st) {
    print('Error: $e\n$st');
  } finally {
    exit(0);
  }
}
