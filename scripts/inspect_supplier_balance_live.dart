import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== INSPECTING SUPPLIERS (STATION & DEDUCTIONS) ===');

  final suppliers = await c
      .from('suppliers')
      .select('id, code, supplier_code, name, supplier_type, initial_balance, outstanding_balance, current_balances_by_currency')
      .inFilter('supplier_type', ['station', 'deduction', 'deductions']);

  print('Found ${suppliers.length} station/deduction suppliers:');
  for (final s in suppliers) {
    print('Supplier: ${s['name']} | Code: ${s['code']} / ${s['supplier_code']} | ID: ${s['id']} | OutBal: ${s['outstanding_balance']} | CurBal: ${s['current_balances_by_currency']}');

    final sid = s['id'].toString();
    final scode = (s['code'] ?? s['supplier_code']).toString();

    // Check ledger_entries
    final ledgerEntries = await c
        .from('ledger_entries')
        .select('*')
        .eq('entity_type', 'supplier')
        .or('entity_id.eq.$sid,entity_id.eq.$scode');
    print('  -> Found ${ledgerEntries.length} ledger_entries:');
    for (final le in ledgerEntries) {
      print('     ledger_entry: id=${le['id']}, amount=${le['amount']}, cur=${le['currency']}, type=${le['entry_type']}, ref_type=${le['reference_type']}, ref_id=${le['reference_id']}, desc=${le['description']}');
    }

    // Check packing_order_cost_items
    final costItems = await c
        .from('packing_order_cost_items')
        .select('*')
        .or('supplier_id.eq.$sid,supplier_id.eq.$scode');
    print('  -> Found ${costItems.length} packing_order_cost_items by supplier_id:');
    for (final ci in costItems) {
      print('     cost_item: id=${ci['id']}, name=${ci['name']}, status=${ci['cost_status']}, exp=${ci['expected_amount']}, act=${ci['actual_amount']}, base=${ci['base_amount']}, order_id=${ci['packing_order_id']}');
    }
  }

  // Check active packing_orders
  final orders = await c
      .from('packing_orders')
      .select('id, order_number, status, notes, other_cost_base')
      .order('id', ascending: false)
      .limit(5);

  print('\n=== TESTING SUPPLIER DAO ENRICHMENT ===');
  final daoSuppliers = await c.from('suppliers').select().inFilter('supplier_type', ['station', 'deduction', 'deductions']);
  for (final s in daoSuppliers) {
    print('Supplier row in DB: ${s['name']} -> outstanding_balance=${s['outstanding_balance']}, current_balances_by_currency=${s['current_balances_by_currency']}');
  }

  print('\n=== SIMULATING NEW BALANCE CALCULATION ===');
  final rates = <String, double>{'EGP': 1.0, 'USD': 50.0, 'EUR': 55.0, 'GBP': 65.0};
  final perCurrency = <String, Map<String, double>>{};

  final results = await Future.wait([
    c.from('purchase_invoices').select('supplier_id, currency, total_amount').eq('status', 'confirmed'),
    c.from('lot_receipts').select('supplier_id, currency, total_fruit_cost').eq('is_confirmed', true),
    c.from('treasury_transactions').select('id, supplier_id, currency, amount, type').not('supplier_id', 'is', null).neq('status', 'draft'),
    c.from('bank_account_transactions').select('id, entity_id, amount, type, bank_accounts(currency)').eq('entity_type', 'supplier').neq('status', 'cancelled'),
    c.from('cheques').select('supplier_id, currency, amount, type').eq('counterparty_type', 'supplier').inFilter('status', ['cleared', 'collected']),
    c.from('lot_returns').select('supplier_id, return_value, lot_receipts(currency)'),
    c.from('exchange_rates').select('currency_code, rate_to_egp'),
    c.from('ledger_entries').select('id, entity_id, amount, currency, entry_type, reference_type, reference_id').eq('entity_type', 'supplier'),
  ]);

  final purchases = results[0] as List;
  final lots = results[1] as List;
  final treasuryTxs = results[2] as List;
  final bankTxs = results[3] as List;
  final cheques = results[4] as List;
  final lotReturns = results[5] as List;
  final ratesData = results[6] as List;
  final ledgerTxs = results[7] as List;

  final treasuryTxIds = treasuryTxs.map((t) => t['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
  final bankTxIds = bankTxs.map((b) => b['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();

  for (final le in ledgerTxs) {
    final sid = le['entity_id']?.toString();
    if (sid == null || sid.isEmpty) continue;
    final refType = le['reference_type']?.toString().toLowerCase() ?? '';
    if (refType == 'lot_receipt' || refType == 'lot_adjustment' || refType == 'lot_price_adjustment' || refType == 'lot_return') continue;
    final refId = le['reference_id']?.toString() ?? '';
    if (refId.isNotEmpty && (treasuryTxIds.contains(refId) || bankTxIds.contains(refId))) continue;

    final cur = (le['currency']?.toString() ?? 'EGP').toUpperCase();
    final amt = (le['amount'] as num?)?.toDouble() ?? 0.0;
    final entryType = le['entry_type']?.toString().toLowerCase() ?? 'credit';
    final isCredit = entryType == 'credit' || refType == 'supplier_deposit' || refType == 'export_return_expense';

    final map = perCurrency.putIfAbsent(sid, () => <String, double>{});
    map[cur] = (map[cur] ?? 0.0) + (isCredit ? amt : -amt);
  }

  print('Calculated perCurrency movements: $perCurrency');
  for (final s in suppliers) {
    final id = s['id'].toString();
    final code = (s['code'] ?? s['supplier_code']).toString();
    final curMap = <String, double>{};
    void apply(Map<String, double>? m) {
      if (m == null) return;
      for (final e in m.entries) {
        curMap[e.key] = (curMap[e.key] ?? 0.0) + e.value;
      }
    }
    apply(perCurrency[id]);
    if (code.isNotEmpty && code != id) apply(perCurrency[code]);
    print('Supplier ${s['name']} -> Final Statement / Ledger Balance: $curMap');
  }
}
