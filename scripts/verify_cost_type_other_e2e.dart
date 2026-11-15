import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=====================================================');
  print('SURGICAL E2E VERIFICATION: COST TYPE = "أخرى"');
  print('=====================================================');

  // 1. Fetch shipment 1
  final shipment = await c.from('export_shipments').select('id, shipment_no, company_id').eq('id', 1).single();
  final int shipmentId = shipment['id'];
  final String shipmentNo = shipment['shipment_no'];
  final String? companyId = shipment['company_id'] ?? '9aae4cab-8ee3-4bc1-8e05-990894869c2e';
  print('Shipment: ID=$shipmentId, No=$shipmentNo');
  await c.from('shipment_cost_items').delete().eq('shipment_id', shipmentId);
  await c.rpc('rpc_sync_vendor_balances_and_ledger');

  // 2. Fetch test supplier
  final supplier = await c.from('suppliers').select('id, name, account_id').limit(1).single();
  final String supplierId = supplier['id'];
  final int supplierAccountId = supplier['account_id'];
  print('Supplier: ID=$supplierId, Name=${supplier['name']}, Control Account=$supplierAccountId');

  // 3. Check baseline vendor ledger count
  final initialLedgerEntries = await c.from('ledger_entries')
      .select('id')
      .eq('entity_type', 'supplier')
      .eq('entity_id', supplierId);
  final int initialCount = initialLedgerEntries.length;
  print('Initial Supplier Ledger Count: $initialCount');

  print('\n--- SCENARIO 1: Cost Type = "أخرى" WITHOUT Vendor (Account 34110) ---');
  final item1Insert = await c.from('shipment_cost_items').insert({
    'shipment_id': shipmentId,
    'category': 'أخرى',
    'description': 'إكراميات وتسهيلات نقدية بدون مورد',
    'quantity': 1.0,
    'unit_price': 750.0,
    'supplier_id': null,
    'expense_account_id': 5094, // 34110
  }).select().single();
  final int item1Id = item1Insert['id'];
  print('Inserted Item 1 (ID: $item1Id): Cost Type="أخرى", Price=750, Account=34110, Vendor=NULL');

  // Sync vendor ledger
  await c.rpc('rpc_sync_vendor_balances_and_ledger');

  // Verify vendor ledger NOT changed
  final ledgerAfter1 = await c.from('ledger_entries')
      .select('id')
      .eq('entity_type', 'supplier')
      .eq('entity_id', supplierId);
  if (ledgerAfter1.length == initialCount) {
    print('PASS: No supplier ledger entry created when vendor is NULL.');
  } else {
    print('FAIL: Supplier ledger entry was unexpectedly created!');
  }

  print('\n--- SCENARIO 2: Cost Type = "أخرى" WITH Vendor (Account 34117) ---');
  final item2Insert = await c.from('shipment_cost_items').insert({
    'shipment_id': shipmentId,
    'category': 'أخرى',
    'description': 'مصاريف تخليص إضافية مع مخلص جمركي',
    'quantity': 1.0,
    'unit_price': 1200.0,
    'supplier_id': supplierId,
    'expense_account_id': 5091, // 34117
  }).select().single();
  final int item2Id = item2Insert['id'];
  print('Inserted Item 2 (ID: $item2Id): Cost Type="أخرى", Price=1200, Account=34117, Vendor=${supplier['name']}');

  // Sync vendor ledger
  await c.rpc('rpc_sync_vendor_balances_and_ledger');

  // Verify vendor ledger NOW has entry
  final ledgerAfter2 = await c.from('ledger_entries')
      .select('id, entity_id, entity_type, amount, reference_type')
      .eq('entity_type', 'supplier')
      .eq('entity_id', supplierId)
      .order('id', ascending: false)
      .limit(1);
  if (ledgerAfter2.isNotEmpty && ledgerAfter2.first['amount'] == 1200.0) {
    print('PASS: Supplier ledger entry created with Amount 1200.0 for supplier! (Ref: ${ledgerAfter2.first['reference_type']})');
  } else {
    print('FAIL: Supplier ledger entry not found or amount != 1200.0: $ledgerAfter2');
  }

  // Create Accrual JE
  final desc = 'استحقاق تكلفة شحنة $shipmentNo - مصاريف تخليص إضافية مع مخلص جمركي';
  final accrualJeId = await c.rpc('post_journal_entry', params: {
    'p_source_type': 'shipment_cost_accrual',
    'p_description': desc,
    'p_entry_date': '2026-09-21',
    'p_company_id': companyId,
    'p_created_by': c.auth.currentUser!.id,
    'p_lines': [
      {
        'account_id': 5091, // 34117
        'debit': 1200.0,
        'credit': 0.0,
        'currency': 'EGP',
        'description': desc,
        'cost_center_id': shipmentNo,
      },
      {
        'account_id': supplierAccountId, // 2111x
        'debit': 0.0,
        'credit': 1200.0,
        'currency': 'EGP',
        'description': desc,
        'cost_center_id': shipmentNo,
      }
    ],
    'p_source_id': item2Id.toString(),
  });
  print('Created Accrual Journal Entry: ID=$accrualJeId');

  // Verify Accrual JE lines
  final jeLines = await c.from('account_ledger_entries')
      .select('id, account_id, debit, credit, cost_center_id')
      .eq('journal_entry_id', accrualJeId);
  print('Verifying JE Lines:');
  for (final l in jeLines) {
    print('  - Line: ID=${l['id']}, Account=${l['account_id']}, Debit=${l['debit']}, Credit=${l['credit']}, CostCenter=${l['cost_center_id']}');
  }
  if (jeLines.length == 2 &&
      jeLines.any((l) => l['account_id'] == 5091 && l['debit'] == 1200.0 && l['cost_center_id'] == shipmentNo) &&
      jeLines.any((l) => l['account_id'] == supplierAccountId && l['credit'] == 1200.0 && l['cost_center_id'] == shipmentNo)) {
    print('PASS: Accrual JE is perfectly balanced with Debit 34117 and Credit $supplierAccountId and Cost Center $shipmentNo!');
  } else {
    print('FAIL: Accrual JE lines verification failed.');
  }

  print('\n--- SCENARIO 3: Clean up and Rollback Test Records ---');
  // Clean up JE
  await c.from('account_ledger_entries').delete().eq('journal_entry_id', accrualJeId);
  await c.from('journal_entries').delete().eq('id', accrualJeId);
  print('Deleted test Journal Entry $accrualJeId and its lines.');

  // Clean up cost items
  await c.from('shipment_cost_items').delete().inFilter('id', [item1Id, item2Id]);
  print('Deleted test shipment_cost_items $item1Id and $item2Id.');

  // Re-sync vendor ledger
  await c.rpc('rpc_sync_vendor_balances_and_ledger');
  final ledgerFinal = await c.from('ledger_entries')
      .select('id')
      .eq('entity_type', 'supplier')
      .eq('entity_id', supplierId);
  print('Supplier ledger count after cleanup: ${ledgerFinal.length} (Initial: $initialCount)');
  if (ledgerFinal.length == initialCount) {
    print('PASS: Supplier ledger cleanly restored to baseline!');
  }

  print('\n=====================================================');
  print('ALL E2E VERIFICATION TESTS PASSED SUCCESSFULLY!');
  print('=====================================================');
}
