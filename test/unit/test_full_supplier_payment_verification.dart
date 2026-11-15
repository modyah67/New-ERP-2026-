import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/dao/transport_supplier_dao.dart';
import 'package:accounting_system/data/dao/payment_dao.dart';

void main() {
  test('Full Supplier Payment Lookup and Multi-Classification Verification', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseOptions.url,
      anonKey: SupabaseOptions.anonKey,
    );

    final client = Supabase.instance.client;
    await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

    final supplierDao = SupplierDao();
    final transportDao = TransportSupplierDao();
    final paymentDao = PaymentDao();

    print('\n=== TEST A: Existing Shared Supplier 75000 Lookup ===');
    for (final q in ['75000', ' 75000 ', 'مورد مشترك', 'موردين مشتركين', 'مشترك']) {
      final res = await supplierDao.search(q);
      expect(res.isNotEmpty, true, reason: 'Failed to find supplier 75000 with query: "$q"');
      final s = res.firstWhere((item) => item.supplierCode == '75000');
      expect(s.supplierCode, '75000');
      expect(s.name, 'مورد مشترك');
      print('  ✓ Query "$q" matched supplier: ${s.supplierCode} - ${s.name} (outBal: ${s.outstandingBalance})');
    }

    final sup75000 = (await supplierDao.search('75000')).first;
    final liabilities75000 = await paymentDao.getUnpaidLiabilities('SUPPLIER', sup75000.id!);
    print('  Liabilities count for 75000: ${liabilities75000.length}');
    expect(liabilities75000.isNotEmpty, true);
    final egpLiab = liabilities75000.firstWhere((l) => l.currency == 'EGP');
    expect(egpLiab.dueAmount, 1000.0);
    expect(egpLiab.liabilityType, 'packing_cost_item');
    print('  ✓ Found expected EGP liability of ${egpLiab.dueAmount} ${egpLiab.currency} (ref: ${egpLiab.referenceNumber})');

    print('\n=== TEST C: Packing Actual Cost Accounting Invariant ===');
    final pkEntry = await client.from('journal_entries').select().eq('entry_number', 'PK-00001').single();
    expect(pkEntry['entry_number'], 'PK-00001');
    final pkLines = await client.from('journal_entry_lines').select().eq('journal_entry_id', pkEntry['id']);
    final supCreditLine = pkLines.firstWhere((l) => l['account_code'] == '21114' || l['account_id'] == 5105);
    expect(supCreditLine['credit'], 1000.0);
    print('  ✓ PK-00001 Journal Entry line 108 is intact: credit=${supCreditLine['credit']} account=${supCreditLine['account_code']}');

    print('\n=== TEST D: Multi-Currency Grouping Logic ===');
    expect(sup75000.isMultiCurrency, true);
    final currenciesWithBal = <String>{...sup75000.initialBalancesByCurrency.keys, ...liabilities75000.map((l) => l.currency)};
    print('  Currencies identified for supplier 75000: $currenciesWithBal');
    expect(currenciesWithBal.contains('EGP'), true);
    expect(currenciesWithBal.contains('USD'), true);

    print('\n=== TEST E: All 4 Supplier Classifications Lookup ===');
    // 1. Crop
    final cropSearch = await supplierDao.search('موردين المحاصيل');
    expect(cropSearch.isNotEmpty, true);
    print('  ✓ Crop supplier classification search found ${cropSearch.length} suppliers: ${cropSearch.map((s) => "${s.supplierCode}: ${s.name}").toList()}');

    // 2. Packaging
    final pkgSearch = await supplierDao.search('موردين مواد التعبئة والتغليف');
    expect(pkgSearch.isNotEmpty, true);
    print('  ✓ Packaging supplier classification search found ${pkgSearch.length} suppliers: ${pkgSearch.map((s) => "${s.supplierCode}: ${s.name}").toList()}');

    // 3. Shared
    final sharedSearch = await supplierDao.search('موردين مشتركين');
    expect(sharedSearch.isNotEmpty, true);
    print('  ✓ Shared supplier classification search found ${sharedSearch.length} suppliers: ${sharedSearch.map((s) => "${s.supplierCode}: ${s.name}").toList()}');

    // 4. Transport
    final transSearch = await transportDao.search('مورد نقل');
    expect(transSearch.isNotEmpty, true);
    final transSup = transSearch.first;
    expect(transSup.code, '60000');
    print('  ✓ Transport supplier classification search found transport supplier: ${transSup.code} - ${transSup.name} (id: ${transSup.id})');
    // Verify transport supplier ID is integer and preserved
    expect(transSup.id is int, true);

    print('\n=== TEST F: Duplicate Protection / Idempotency ===');
    final jeCountBefore = (await client.from('journal_entries').select('id').count(CountOption.exact)).count;
    final leCountBefore = (await client.from('ledger_entries').select('id').count(CountOption.exact)).count;

    // Simulate multiple searches and selections
    for (int i = 0; i < 5; i++) {
      await supplierDao.search('75000');
      await supplierDao.search('موردين مشتركين');
      await paymentDao.getUnpaidLiabilities('SUPPLIER', sup75000.id!);
    }

    final jeCountAfter = (await client.from('journal_entries').select('id').count(CountOption.exact)).count;
    final leCountAfter = (await client.from('ledger_entries').select('id').count(CountOption.exact)).count;

    expect(jeCountBefore, jeCountAfter, reason: 'Searching created unexpected journal entries!');
    expect(leCountBefore, leCountAfter, reason: 'Searching created unexpected ledger entries!');
    print('  ✓ Zero duplicate journal entries or ledger movements created by searching/inspecting.');

    print('\nALL VERIFICATION TESTS COMPLETED SUCCESSFULLY!\n');
  });
}
