import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );

  print('Signing in...');
  try {
    await client.auth.signInWithPassword(
      email: 'ma@gmail.com',
      password: '123456'
    );
    print('Logged in successfully.');
  } catch (e) {
    print('Auth failed: $e');
    exit(1);
  }

  // Fetch dependencies
  final lots = await client.from('lot_receipts').select('id').limit(1);
  final stations = await client.from('stations').select('id').limit(1);
  final treasuries = await client.from('treasuries').select('id, name').limit(1);
  final suppliers = await client.from('suppliers').select('id, name, outstanding_balance').limit(1);

  if (lots.isEmpty || stations.isEmpty || treasuries.isEmpty || suppliers.isEmpty) {
    print('Error: Could not fetch database dependencies.');
    exit(1);
  }

  final lotId = lots[0]['id'];
  final stationId = stations[0]['id'];
  final treasuryId = treasuries[0]['id'];
  final treasuryName = treasuries[0]['name'];
  final supplierId = suppliers[0]['id'];
  final supplierName = suppliers[0]['name'];

  print('\nUsing Safe: $treasuryName (ID: $treasuryId)');
  print('Using Supplier: $supplierName (ID: $supplierId)');

  // ==========================================================================
  // TEST 1: Insufficient funds failure (Rollback test)
  // ==========================================================================
  print('\n--- RUNNING TEST 1: Insufficient Funds Rollback ---');
  
  // Get initial Safe balance
  final tBalRow = await client.from('treasury_balances')
      .select('balance')
      .eq('treasury_id', treasuryId)
      .eq('currency', 'EGP')
      .maybeSingle();
  final initSafeBal = tBalRow != null ? (tBalRow['balance'] as num).toDouble() : 0.0;

  // We set a cost amount way higher than the safe balance
  final hugeCostAmount = initSafeBal + 10000.0;

  // Create temporary packing order
  final orderNum1 = 'TEST_FAIL_ORD_${DateTime.now().millisecondsSinceEpoch}';
  final orderId1 = (await client.from('packing_orders').insert({
    'order_number': orderNum1,
    'lot_id': lotId,
    'station_id': stationId,
    'grade': 'A',
    'status': 'pending',
    'notes': '{"materials": [], "fruit_allocation": []}',
  }).select('id'))[0]['id'];

  print('Created test order ID: $orderId1');

  // Insert cost item with huge cost
  await client.from('packing_order_cost_items').insert({
    'packing_order_id': orderId1,
    'name': 'بند تكلفة ضخم يفوق الرصيد',
    'category': 'other',
    'report_category_id': 14,
    'original_currency': 'EGP',
    'original_amount': hugeCostAmount,
    'exchange_rate': 1.0,
    'base_amount': hugeCostAmount,
    'payment_source_type': 'treasury',
    'payment_source_id': treasuryId,
    'currency_snapshot': {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'quantity': 1,
      'unit_price': hugeCostAmount
    }
  });

  print('Inserted over-budget cost item of amount $hugeCostAmount EGP.');

  // Try to confirm the order (should fail and rollback)
  bool rpcFailed = false;
  try {
    await client.rpc('rpc_confirm_packing_order', params: {
      'p_packing_order_id': orderId1
    });
    print('❌ FAILURE: Confirm RPC succeeded but should have failed due to insufficient funds!');
  } catch (e) {
    print('✅ SUCCESS: Confirm RPC failed as expected with error: $e');
    rpcFailed = true;
  }

  // Verify database state after rollback
  final orderAfterFail = await client.from('packing_orders').select('status').eq('id', orderId1).maybeSingle();
  final orderStatusAfterFail = orderAfterFail?['status'];

  final costItemAfterFail = await client.from('packing_order_cost_items')
      .select('treasury_transaction_id')
      .eq('packing_order_id', orderId1)
      .maybeSingle();
  final txIdAfterFail = costItemAfterFail?['treasury_transaction_id'];

  final currentSafeBal = await client.from('treasury_balances')
      .select('balance')
      .eq('treasury_id', treasuryId)
      .eq('currency', 'EGP')
      .maybeSingle();
  final safeBalAfterFail = currentSafeBal != null ? (currentSafeBal['balance'] as num).toDouble() : 0.0;

  bool test1Passed = rpcFailed &&
      orderStatusAfterFail == 'pending' &&
      txIdAfterFail == null &&
      (safeBalAfterFail - initSafeBal).abs() < 0.01;

  if (test1Passed) {
    print('🎉 TEST 1 PASSED: Database rolled back completely. No funds deducted, order status remains pending, no transaction recorded.');
  } else {
    print('❌ TEST 1 FAILED: Rollback check failed!');
  }

  // Cleanup Test 1
  await client.from('packing_orders').delete().eq('id', orderId1);
  print('Cleaned up Test 1 packing order.');


  // ==========================================================================
  // TEST 2: Hybrid cash/credit (unpaid) test
  // ==========================================================================
  print('\n--- RUNNING TEST 2: Hybrid Cash/Credit Test ---');

  // Let's deposit 100 EGP into the safe to make sure it has funds
  await client.rpc('deposit_treasury', params: {
    'p_treasury_id': treasuryId,
    'p_currency': 'EGP',
    'p_amount': 100.0,
    'p_description': 'إيداع تجريبي فاز 1 جزء 2'
  });
  print('Deposited 100 EGP for cash item.');

  // Fetch initial outstanding balance of the supplier
  final initialSupplier = await client.from('suppliers').select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final initialSupplierBal = (initialSupplier?['outstanding_balance'] as num).toDouble();

  // Create temporary packing order
  final orderNum2 = 'TEST_HYBRID_ORD_${DateTime.now().millisecondsSinceEpoch}';
  final orderId2 = (await client.from('packing_orders').insert({
    'order_number': orderNum2,
    'lot_id': lotId,
    'station_id': stationId,
    'grade': 'A',
    'status': 'pending',
    'notes': '{"materials": [], "fruit_allocation": []}',
  }).select('id'))[0]['id'];

  print('Created test order ID: $orderId2');

  // Insert Cost Item 1 (Paid: 40 EGP)
  await client.from('packing_order_cost_items').insert({
    'packing_order_id': orderId2,
    'name': 'بند مدفوع نقدا',
    'category': 'other',
    'report_category_id': 14,
    'original_currency': 'EGP',
    'original_amount': 40.0,
    'exchange_rate': 1.0,
    'base_amount': 40.0,
    'payment_source_type': 'treasury',
    'payment_source_id': treasuryId,
    'currency_snapshot': {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'quantity': 1,
      'unit_price': 40.0
    }
  });

  // Insert Cost Item 2 (Credit: 60 EGP)
  await client.from('packing_order_cost_items').insert({
    'packing_order_id': orderId2,
    'name': 'بند آجل على الحساب',
    'category': 'other',
    'report_category_id': 14,
    'original_currency': 'EGP',
    'original_amount': 60.0,
    'exchange_rate': 1.0,
    'base_amount': 60.0,
    'payment_source_type': null,
    'payment_source_id': null,
    'currency_snapshot': {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'quantity': 1,
      'unit_price': 60.0
    }
  });

  print('Inserted 2 cost items: 1 Paid (40 EGP) and 1 Credit (60 EGP).');

  // Confirm the packing order
  try {
    final res = await client.rpc('rpc_confirm_packing_order', params: {
      'p_packing_order_id': orderId2
    });
    print('Confirm RPC completed successfully: $res');
  } catch (e) {
    print('Confirm RPC failed unexpectedly: $e');
    // Cleanup before exiting
    await client.from('packing_orders').delete().eq('id', orderId2);
    exit(1);
  }

  // Verify Test 2
  final costItems = await client.from('packing_order_cost_items')
      .select('name, treasury_transaction_id')
      .eq('packing_order_id', orderId2);

  final paidItem = costItems.firstWhere((item) => item['name'] == 'بند مدفوع نقدا');
  final creditItem = costItems.firstWhere((item) => item['name'] == 'بند آجل على الحساب');

  final paidTxId = paidItem['treasury_transaction_id'];
  final creditTxId = creditItem['treasury_transaction_id'];

  final updatedSupplier = await client.from('suppliers').select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final updatedSupplierBal = (updatedSupplier?['outstanding_balance'] as num).toDouble();
  final supplierDiff = updatedSupplierBal - initialSupplierBal;

  print('Cost Item 1 (Paid) Stamped Tx ID: $paidTxId');
  print('Cost Item 2 (Credit) Stamped Tx ID: $creditTxId');
  print('Supplier outstanding balance difference: +$supplierDiff (Expected: +60.0)');

  bool test2Passed = paidTxId != null &&
      creditTxId == null &&
      (supplierDiff - 60.0).abs() < 0.01;

  if (test2Passed) {
    print('🎉 TEST 2 PASSED: Only the paid item got a transaction ID. Supplier outstanding balance was only increased by the credit item (60 EGP) as the cash item balanced itself out.');
  } else {
    print('❌ TEST 2 FAILED: Balance checks failed.');
  }

  // Cleanup Test 2
  print('\nCleaning up Test 2...');
  if (paidTxId != null) {
    await client.from('treasury_transactions').delete().eq('id', paidTxId);
  }
  
  final depositTxs = await client.from('treasury_transactions')
      .select('id')
      .eq('treasury_id', treasuryId)
      .eq('type', 'deposit')
      .eq('description', 'إيداع تجريبي فاز 1 جزء 2')
      .order('created_at', ascending: false)
      .limit(1);
  if (depositTxs.isNotEmpty) {
    await client.from('treasury_transactions').delete().eq('id', depositTxs[0]['id']);
  }

  await client.from('treasury_balances').update({'balance': initSafeBal}).eq('treasury_id', treasuryId).eq('currency', 'EGP');
  await client.from('suppliers').update({'outstanding_balance': initialSupplierBal}).eq('id', supplierId);
  await client.from('packing_orders').delete().eq('id', orderId2);
  print('Test 2 cleaned up successfully.');

  if (test1Passed && test2Passed) {
    print('\n🚀 ALL EXTRA TESTS PASSED SUCCESSFULLY! 🚀');
  } else {
    print('\n❌ SOME EXTRA TESTS FAILED. ❌');
  }
}
