import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );

  print('Signing in...');
  bool loggedIn = false;
  final credentials = [
    {'email': 'ma@gmail.com', 'password': '123456'},
    {'email': 'admin@fruityfarms.com', 'password': 'Admin123456'},
    {'email': 'mahmooud@fruityfarms.com', 'password': 'Admin123456'},
  ];

  for (final cred in credentials) {
    try {
      await client.auth.signInWithPassword(
        email: cred['email']!,
        password: cred['password']!
      );
      print('Logged in successfully as ${cred['email']}.');
      loggedIn = true;
      break;
    } catch (e) {
      print('Auth failed for ${cred['email']}: $e');
    }
  }

  if (!loggedIn) {
    print('Could not login. Running without active auth context.');
    exit(1);
  }

  // 1. Fetch dependencies
  print('\nFetching database dependencies (lot, station, treasury, supplier)...');
  final lots = await client.from('lot_receipts').select('id, lot_number').limit(1);
  final stations = await client.from('stations').select('id, name').limit(1);
  final treasuries = await client.from('treasuries').select('id, name').limit(1);
  final suppliers = await client.from('suppliers').select('id, name, outstanding_balance').limit(1);

  if (lots.isEmpty || stations.isEmpty || treasuries.isEmpty || suppliers.isEmpty) {
    print('Error: Could not fetch one or more database dependencies.');
    exit(1);
  }

  final lotId = lots[0]['id'];
  final lotNum = lots[0]['lot_number'];
  final stationId = stations[0]['id'];
  final stationName = stations[0]['name'];
  final treasuryId = treasuries[0]['id'];
  final treasuryName = treasuries[0]['name'];
  final supplierId = suppliers[0]['id'];
  final supplierName = suppliers[0]['name'];
  final initialSupplierBal = (suppliers[0]['outstanding_balance'] as num).toDouble();

  // Get Safe balance
  final treasuryBalances = await client.from('treasury_balances')
      .select('balance')
      .eq('treasury_id', treasuryId)
      .eq('currency', 'EGP')
      .maybeSingle();
  final initialSafeBal = treasuryBalances != null ? (treasuryBalances['balance'] as num).toDouble() : 0.0;

  print('Selected Lot: $lotNum (ID: $lotId)');
  print('Selected Station: $stationName (ID: $stationId)');
  print('Selected Safe: $treasuryName (ID: $treasuryId, Balance: $initialSafeBal EGP)');
  print('Selected Supplier: $supplierName (ID: $supplierId, Outstanding Balance: $initialSupplierBal)');

  // 2. Deposit 100 EGP into the safe to make sure it has funds
  print('\nDepositing 100 EGP into the Safe...');
  try {
    await client.rpc('deposit_treasury', params: {
      'p_treasury_id': treasuryId,
      'p_currency': 'EGP',
      'p_amount': 100.0,
      'p_description': 'إيداع تجريبي مؤقت للفحص فاز 1'
    });
    print('Deposited 100 EGP successfully.');
  } catch (e) {
    print('Failed to deposit to Safe: $e');
    exit(1);
  }

  // Get Safe balance after deposit
  final afterDepositSafeBalances = await client.from('treasury_balances')
      .select('balance')
      .eq('treasury_id', treasuryId)
      .eq('currency', 'EGP')
      .maybeSingle();
  final safeBalAfterDeposit = afterDepositSafeBalances != null ? (afterDepositSafeBalances['balance'] as num).toDouble() : 0.0;
  print('Safe Balance after deposit: $safeBalAfterDeposit EGP');

  // 3. Create a temporary draft packing order
  print('\nCreating temporary draft packing order...');
  final orderNum = 'TEST_ORD_${DateTime.now().millisecondsSinceEpoch}';
  final orderData = {
    'order_number': orderNum,
    'lot_id': lotId,
    'station_id': stationId,
    'grade': 'A',
    'status': 'pending',
    'notes': '{"materials": [], "fruit_allocation": []}',
  };
  
  final insertedOrderList = await client.from('packing_orders').insert(orderData).select('id');
  if (insertedOrderList.isEmpty) {
    print('Error: Failed to create temporary packing order.');
    exit(1);
  }
  final orderId = insertedOrderList[0]['id'];
  print('Temporary Packing Order created with ID: $orderId');

  // 4. Create a cost item linked to this packing order
  print('\nInserting test cost item linked to payment source...');
  final costItemData = {
    'packing_order_id': orderId,
    'name': 'بند اختبار صرف الخزينة فاز 1',
    'category': 'other',
    'report_category_id': 14, // تعبئة وتغليف
    'original_currency': 'EGP',
    'original_amount': 50.0,
    'exchange_rate': 1.0,
    'base_amount': 50.0,
    'payment_source_type': 'treasury',
    'payment_source_id': treasuryId,
    'currency_snapshot': {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'quantity': 1,
      'unit_price': 50.0
    }
  };

  await client.from('packing_order_cost_items').insert(costItemData);
  print('Test cost item inserted.');

  // 5. Confirm the packing order
  print('\nConfirming packing order (calling rpc_confirm_packing_order)...');
  try {
    final confirmResult = await client.rpc('rpc_confirm_packing_order', params: {
      'p_packing_order_id': orderId
    });
    print('Confirm RPC result: $confirmResult');
  } catch (e) {
    print('Confirm RPC failed: $e');
    // Cleanup draft order and deposit before exiting
    await client.from('packing_orders').delete().eq('id', orderId);
    // Remove the 100 EGP we deposited
    await client.from('treasury_balances').update({'balance': initialSafeBal}).eq('treasury_id', treasuryId).eq('currency', 'EGP');
    exit(1);
  }

  // 6. Verify results
  print('\n=== VERIFYING RESULTS ===');
  
  // Verify safe balance
  final updatedSafeBalances = await client.from('treasury_balances')
      .select('balance')
      .eq('treasury_id', treasuryId)
      .eq('currency', 'EGP')
      .maybeSingle();
  final updatedSafeBal = updatedSafeBalances != null ? (updatedSafeBalances['balance'] as num).toDouble() : 0.0;
  final safeDiff = safeBalAfterDeposit - updatedSafeBal;

  // Verify supplier balance
  final updatedSupplier = await client.from('suppliers').select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final updatedSupplierBal = updatedSupplier != null ? (updatedSupplier['outstanding_balance'] as num).toDouble() : 0.0;
  final supplierDiff = updatedSupplierBal - initialSupplierBal;

  // Verify cost item transaction stamping
  final updatedCostItem = await client.from('packing_order_cost_items')
      .select('treasury_transaction_id')
      .eq('packing_order_id', orderId)
      .maybeSingle();
  final treasuryTxId = updatedCostItem != null ? updatedCostItem['treasury_transaction_id'] : null;

  print('Safe Balance: BeforeTest=$initialSafeBal | PostDeposit=$safeBalAfterDeposit | PostConfirm=$updatedSafeBal | Deducted=$safeDiff EGP');
  print('Supplier Outstanding Balance: BeforeTest=$initialSupplierBal | PostConfirm=$updatedSupplierBal | Difference=$supplierDiff');
  print('Stamped Treasury Transaction ID: $treasuryTxId');

  // Assertions
  bool pass = true;
  if ((safeDiff - 50.0).abs() < 0.01) {
    print('✅ SUCCESS: Safe balance was correctly deducted by 50.0 EGP.');
  } else {
    print('❌ FAILURE: Safe balance deduction mismatch.');
    pass = false;
  }

  if (supplierDiff.abs() < 0.01) {
    print('✅ SUCCESS: Supplier outstanding balance remained unchanged (Credit and Debit balanced each other).');
  } else {
    print('❌ FAILURE: Supplier outstanding balance changed.');
    pass = false;
  }

  if (treasuryTxId != null) {
    print('✅ SUCCESS: Treasury transaction ID was successfully stamped on the cost item.');
  } else {
    print('❌ FAILURE: Treasury transaction ID is missing.');
    pass = false;
  }

  // 7. Cleanup
  print('\nCleaning up test data...');
  if (treasuryTxId != null) {
    await client.from('treasury_transactions').delete().eq('id', treasuryTxId);
    print('Deleted test treasury transaction.');
  }
  
  // Find and delete the deposit transaction we made
  final depositTxs = await client.from('treasury_transactions')
      .select('id')
      .eq('treasury_id', treasuryId)
      .eq('type', 'deposit')
      .eq('description', 'إيداع تجريبي مؤقت للفحص فاز 1')
      .order('created_at', ascending: false)
      .limit(1);
  if (depositTxs.isNotEmpty) {
    await client.from('treasury_transactions').delete().eq('id', depositTxs[0]['id']);
    print('Deleted test deposit transaction.');
  }

  // Restore the original Safe balance exactly
  await client.from('treasury_balances').update({'balance': initialSafeBal}).eq('treasury_id', treasuryId).eq('currency', 'EGP');
  print('Restored Safe balance to original: $initialSafeBal EGP');

  await client.from('packing_orders').delete().eq('id', orderId);
  print('Deleted test packing order.');
  
  if (pass) {
    print('\n🎉 === PHASE 1 TEST PASSED === 🎉');
  } else {
    print('\n❌ === PHASE 1 TEST FAILED === ❌');
  }
}
