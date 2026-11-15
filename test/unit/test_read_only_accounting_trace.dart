import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/dao/payment_dao.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseOptions.url,
      anonKey: SupabaseOptions.anonKey,
    );
    await Supabase.instance.client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  });

  test('Read-only accounting trace for Supplier 75000 and PK-00001', () async {
    final client = Supabase.instance.client;

    print('\n================================================================');
    print('ACCOUNTING TRACE VERIFICATION: SUPPLIER 75000 & PK-00001');
    print('================================================================');

    // 1. Supplier 75000 row
    final suppRows = await client.from('suppliers').select().eq('code', '75000');
    final supp = suppRows.first;
    final suppId = supp['id'];
    print('\n[1] SUPPLIER ROW (table: suppliers):');
    print('  ID: $suppId');
    print('  Code: ${supp['code']}');
    print('  Name: ${supp['name']}');
    print('  Currency: ${supp['currency']}');
    print('  is_multi_currency: ${supp['is_multi_currency']}');
    print('  initial_balance: ${supp['initial_balance']} (${supp['initial_balance_direction']})');
    print('  initial_balances_by_currency: ${supp['initial_balances_by_currency']}');
    print('  current_balances_by_currency: ${supp['current_balances_by_currency']}');
    print('  outstanding_balance: ${supp['outstanding_balance']}');

    // 2. PK-00001 Journal Entry & Lines
    final jeRows = await client.from('journal_entries').select('*, journal_entry_lines(*)').eq('entry_number', 'PK-00001');
    print('\n[2] JOURNAL ENTRY PK-00001:');
    if (jeRows.isNotEmpty) {
      final je = jeRows.first;
      print('  JE ID: ${je['id']}');
      print('  Source Type: ${je['source_type']}');
      print('  Source ID: ${je['source_id']}');
      print('  Status: ${je['status']}');
      final lines = (je['journal_entry_lines'] as List);
      print('  Lines Count: ${lines.length}');
      for (final line in lines) {
        if (line['credit'] != null && (line['credit'] as num) > 0) {
          print('    CREDIT Line -> Line ID: ${line['id']}, Account ID: ${line['account_id']}, Account: ${line['account_name'] ?? line['description']}, Credit: ${line['credit']}, Currency: ${line['currency'] ?? 'EGP'}');
        }
      }
    } else {
      print('  JE PK-00001 NOT FOUND BY entry_number');
    }

    // 3. Ledger entries for supplier
    final leRows = await client.from('ledger_entries').select().eq('entity_type', 'supplier').eq('entity_id', suppId);
    print('\n[3] LEDGER ENTRIES (table: ledger_entries for supplier $suppId):');
    print('  Count: ${leRows.length}');
    for (final le in leRows) {
      print('  - ID: ${le['id']}, ref_type: ${le['reference_type']}, ref_id: ${le['reference_id']}, entry_type: ${le['entry_type']}, amount: ${le['amount']}, currency: ${le['currency'] ?? 'EGP'}');
    }

    // 4. packing_order_cost_items for supplier
    final pociRows = await client.from('packing_order_cost_items').select().eq('supplier_id', suppId);
    print('\n[4] PACKING ORDER COST ITEMS (table: packing_order_cost_items):');
    print('  Count: ${pociRows.length}');
    for (final poci in pociRows) {
      print('  - ID: ${poci['id']}, name: ${poci['name']}, amount: ${poci['original_amount']}, currency: ${poci['original_currency']}, paid_amount: ${poci['paid_amount']}, status: ${poci['payment_status']}');
    }

    // 5. RPC: get_supplier_true_balances_by_currency()
    print('\n[5] RPC get_supplier_true_balances_by_currency():');
    try {
      final rpcRes = await client.rpc('get_supplier_true_balances_by_currency');
      final suppRpc = (rpcRes as List).where((r) => r['supplier_id'].toString() == suppId.toString()).toList();
      print('  Rows for 75000: ${suppRpc.length}');
      for (final r in suppRpc) {
        print('  - Currency: ${r['currency']}, True Balance: ${r['true_balance']}, True Balance EGP: ${r['true_balance_egp']}');
      }
    } catch (e) {
      print('  RPC Error: $e');
    }

    // 6. View: vw_unpaid_liabilities
    print('\n[6] VIEW vw_unpaid_liabilities:');
    final unpRows = await PaymentDao().getUnpaidLiabilities('supplier', suppId.toString());
    print('  Unpaid liabilities count: ${unpRows.length}');
    for (final u in unpRows) {
      print('  - Type: ${u.liabilityType}, ID: ${u.liabilityId}, Ref: ${u.referenceNumber}, Due: ${u.dueAmount} ${u.currency}');
    }

    // 7. SupplierDao getAll() and search()
    print('\n[7] SupplierDao search("75000"):');
    final daoResults = await SupplierDao().search('75000');
    if (daoResults.isNotEmpty) {
      final s = daoResults.first;
      print('  Supplier: ${s.name} (${s.supplierCode})');
      print('  outstandingBalance: ${s.outstandingBalance}');
      print('  initialBalance: ${s.initialBalance}');
      print('  currentBalancesByCurrency: ${s.currentBalancesByCurrency}');
      print('  initialBalancesByCurrency: ${s.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.amount))}');
      print('  supportedCurrencies: ${s.supportedCurrencies}');
    }

    // 8. Test Cost Items Without Supplier Linkage
    print('\n[8] TEST COST ITEMS WITHOUT SUPPLIER LINKAGE:');
    final allPoci = await client.from('packing_order_cost_items').select();
    print('  Total packing_order_cost_items in DB: ${allPoci.length}');
    for (final it in allPoci) {
      print('    - Cost Item ID: ${it['id']}, PO: ${it['packing_order_id']}, Name: ${it['name']}, Amount: ${it['original_amount']}, Supplier ID: ${it['supplier_id']}');
    }

    final inVw = await client.from('vw_unpaid_liabilities').select().eq('liability_type', 'packing_cost_item');
    print('  Total packing costs in vw_unpaid_liabilities: ${inVw.length}');
    for (final v in inVw) {
      print('    - Liability ID: ${v['liability_id']}, Ref: ${v['reference_number']}, Entity ID (Supplier): ${v['entity_id']}, Due: ${v['due_amount']} ${v['currency']}');
    }

    print('\n================================================================\n');
  });
}
