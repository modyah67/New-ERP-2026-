import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

/// Phase 2 Test: rpc_cancel_packing_order
///
/// This script:
/// 1. Detects whether the v3 migration (return_in audit trail) is deployed.
/// 2. Creates a hybrid order (1 paid + 1 credit cost item) and confirms it.
/// 3. Cancels it and verifies full reversal of all financial effects.
/// 4. Reports clearly whether v2 (DELETE) or v3 (return_in) behavior is observed.
/// 5. Cleans up all test data.
///
/// To deploy v3 migration before running, either:
///   - Set SUPABASE_ACCESS_TOKEN env var (Management API token from app.supabase.com/account/tokens)
///   - OR apply the SQL manually in Supabase SQL Editor.

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );

  print('=== Phase 2: rpc_cancel_packing_order Full Reversal Test ===\n');
  print('Signing in...');
  bool loggedIn = false;
  for (final cred in [
    {'email': 'ma@gmail.com', 'password': '123456'},
    {'email': 'admin@fruityfarms.com', 'password': 'Admin123456'},
    {'email': 'mahmooud@fruityfarms.com', 'password': 'Admin123456'},
  ]) {
    try {
      await client.auth.signInWithPassword(email: cred['email']!, password: cred['password']!);
      print('Logged in as ${cred['email']}');
      loggedIn = true;
      break;
    } catch (_) {}
  }
  if (!loggedIn) { print('Could not login.'); exit(1); }

  // ── Try applying v3 migration via Management API if token is available ──
  final accessToken = Platform.environment['SUPABASE_ACCESS_TOKEN'];
  bool migrationApplied = false;
  if (accessToken != null && accessToken.isNotEmpty) {
    migrationApplied = await _applyV3Migration(accessToken);
  } else {
    print('\n[INFO] SUPABASE_ACCESS_TOKEN not set → skipping automatic migration.');
    print('[INFO] Current deployed version will be tested as-is.\n');
  }

  // ── Fetch dependencies ──
  final lots      = await client.from('lot_receipts').select('id').limit(1);
  final stations  = await client.from('stations').select('id').limit(1);
  final treasuries= await client.from('treasuries').select('id, name').limit(1);
  final suppliers = await client.from('suppliers').select('id, name, outstanding_balance').limit(1);

  if (lots.isEmpty || stations.isEmpty || treasuries.isEmpty || suppliers.isEmpty) {
    print('Error: Could not fetch dependencies.'); exit(1);
  }

  final lotId       = lots[0]['id'];
  final stationId   = stations[0]['id'];
  final treasuryId  = treasuries[0]['id'];
  final treasuryName= treasuries[0]['name'];
  final supplierId  = suppliers[0]['id'];
  final supplierName= suppliers[0]['name'];

  print('Using Safe: $treasuryName (ID: $treasuryId)');
  print('Using Supplier: $supplierName (ID: $supplierId)');

  // ── SETUP ──
  print('\n--- SETUP: Confirming hybrid order (paid=70 EGP + credit=50 EGP) ---');

  final baselineRow = await client.from('suppliers')
      .select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final baselineSupplierBal = (baselineRow?['outstanding_balance'] as num).toDouble();

  // Ensure safe has enough funds
  await client.rpc('deposit_treasury', params: {
    'p_treasury_id': treasuryId, 'p_currency': 'EGP',
    'p_amount': 300.0, 'p_description': 'إيداع اختبار فاز 2 v3'
  });

  final safeBefore = await client.from('treasury_balances')
      .select('balance').eq('treasury_id', treasuryId).eq('currency', 'EGP').maybeSingle();
  final safeBalBeforeConfirm = (safeBefore?['balance'] as num).toDouble();

  // Create order
  final orderNum = 'TEST_CANCEL_V3_${DateTime.now().millisecondsSinceEpoch}';
  final orderId = (await client.from('packing_orders').insert({
    'order_number': orderNum, 'lot_id': lotId, 'station_id': stationId,
    'grade': 'A', 'status': 'pending',
    'notes': '{"materials": [], "fruit_allocation": []}',
  }).select('id'))[0]['id'];

  // Item A: Paid via treasury (70 EGP)
  await client.from('packing_order_cost_items').insert({
    'packing_order_id': orderId, 'name': 'بند مدفوع نقدا',
    'category': 'other', 'report_category_id': 14,
    'original_currency': 'EGP', 'original_amount': 70.0,
    'exchange_rate': 1.0, 'base_amount': 70.0,
    'payment_source_type': 'treasury', 'payment_source_id': treasuryId,
    'currency_snapshot': {
      'supplier_id': supplierId, 'supplier_name': supplierName,
      'quantity': 1, 'unit_price': 70.0
    }
  });

  // Item B: Credit/unpaid (50 EGP)
  await client.from('packing_order_cost_items').insert({
    'packing_order_id': orderId, 'name': 'بند آجل',
    'category': 'other', 'report_category_id': 14,
    'original_currency': 'EGP', 'original_amount': 50.0,
    'exchange_rate': 1.0, 'base_amount': 50.0,
    'currency_snapshot': {
      'supplier_id': supplierId, 'supplier_name': supplierName,
      'quantity': 1, 'unit_price': 50.0
    }
  });

  // Confirm
  await client.rpc('rpc_confirm_packing_order', params: {'p_packing_order_id': orderId});

  final safeAfterConfirm = await client.from('treasury_balances')
      .select('balance').eq('treasury_id', treasuryId).eq('currency', 'EGP').maybeSingle();
  final safeBalAfterConfirm = (safeAfterConfirm?['balance'] as num).toDouble();

  final supplierAfterConfirm = await client.from('suppliers')
      .select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final supplierBalAfterConfirm = (supplierAfterConfirm?['outstanding_balance'] as num).toDouble();

  final paidItem = await client.from('packing_order_cost_items')
      .select('treasury_transaction_id').eq('packing_order_id', orderId)
      .eq('name', 'بند مدفوع نقدا').maybeSingle();
  final paidTxId = paidItem?['treasury_transaction_id'];

  print('Order ID: $orderId');
  print('Safe: $safeBalBeforeConfirm → $safeBalAfterConfirm (delta: ${safeBalAfterConfirm - safeBalBeforeConfirm})');
  print('Supplier: $baselineSupplierBal → $supplierBalAfterConfirm (delta: ${supplierBalAfterConfirm - baselineSupplierBal})');
  print('Paid item treasury_transaction_id: $paidTxId');

  // Validate setup
  bool setupOk = true;
  if ((safeBalAfterConfirm - safeBalBeforeConfirm + 70.0).abs() > 0.01) {
    print('❌ Setup check failed: safe deduction wrong.'); setupOk = false;
  }
  if ((supplierBalAfterConfirm - baselineSupplierBal - 50.0).abs() > 0.01) {
    print('❌ Setup check failed: supplier delta wrong.'); setupOk = false;
  }
  if (paidTxId == null) {
    print('❌ Setup check failed: no treasury_transaction_id on paid item.'); setupOk = false;
  }
  if (!setupOk) {
    await client.from('packing_orders').delete().eq('id', orderId);
    exit(1);
  }
  print('✅ Setup verified correctly (confirm worked).');

  // ── Mark completed for cancel ──
  await client.from('packing_orders').update({'status': 'completed'}).eq('id', orderId);

  // ── CANCEL ──
  print('\n--- Cancelling order $orderId ---');
  try {
    final r = await client.rpc('rpc_cancel_packing_order', params: {'p_packing_order_id': orderId});
    print('Cancel RPC result: $r');
  } catch (e) {
    print('❌ Cancel RPC failed: $e');
    await client.from('packing_orders').delete().eq('id', orderId);
    exit(1);
  }

  // ── Post-cancel snapshots ──
  final safeAfterCancel = await client.from('treasury_balances')
      .select('balance').eq('treasury_id', treasuryId).eq('currency', 'EGP').maybeSingle();
  final safeBalAfterCancel = (safeAfterCancel?['balance'] as num).toDouble();

  final supplierAfterCancel = await client.from('suppliers')
      .select('outstanding_balance').eq('id', supplierId).maybeSingle();
  final supplierBalAfterCancel = (supplierAfterCancel?['outstanding_balance'] as num).toDouble();

  final originalTxRow = await client.from('treasury_transactions')
      .select('id, type, amount').eq('id', paidTxId).maybeSingle();
  final originalTxExists = originalTxRow != null;

  final reversalRows = await client.from('treasury_transactions')
      .select('id, type, amount, description')
      .eq('treasury_id', treasuryId)
      .eq('type', 'return_in')
      .ilike('description', '%$orderId%');
  final hasReversalRecord = reversalRows.isNotEmpty;

  final costItemsPost = await client.from('packing_order_cost_items')
      .select('name, treasury_transaction_id').eq('packing_order_id', orderId);
  final allStampsCleared = costItemsPost.every((i) => i['treasury_transaction_id'] == null);

  final orderPost = await client.from('packing_orders')
      .select('status').eq('id', orderId).maybeSingle();
  final orderStatus = orderPost?['status'];

  final safeDelta    = safeBalAfterCancel - safeBalAfterConfirm;
  final supplierDelta = supplierBalAfterCancel - supplierBalAfterConfirm;

  // ── PRINT RESULTS ──
  print('\n════════════════════════════════════════════════════════════');
  print('=== PHASE 2 VERIFICATION RESULTS ===');
  print('════════════════════════════════════════════════════════════');
  print('Safe Balance:');
  print('  BeforeConfirm : $safeBalBeforeConfirm EGP');
  print('  AfterConfirm  : $safeBalAfterConfirm EGP  (deducted 70.0)');
  print('  AfterCancel   : $safeBalAfterCancel EGP  (delta: +$safeDelta)');
  print('');
  print('Supplier Outstanding Balance:');
  print('  Baseline      : $baselineSupplierBal');
  print('  AfterConfirm  : $supplierBalAfterConfirm  (delta: +${supplierBalAfterConfirm - baselineSupplierBal})');
  print('  AfterCancel   : $supplierBalAfterCancel  (delta: $supplierDelta)');
  print('');
  print('Original expense TX (ID $paidTxId) still exists : $originalTxExists');
  print('Reversal (return_in) record found               : $hasReversalRecord');
  if (hasReversalRecord) {
    for (final r in reversalRows) {
      print('  → Reversal TX: id=${r['id']}, type=${r['type']}, amount=${r['amount']}');
      print('    description: ${r['description']}');
    }
  }
  print('All cost item stamps cleared to NULL            : $allStampsCleared');
  print('Order status                                    : $orderStatus');
  print('────────────────────────────────────────────────────────────');

  bool pass = true;

  // Check 1: Safe restored
  if ((safeDelta - 70.0).abs() < 0.01) {
    print('✅ Safe balance: +70 EGP correctly restored (paid item reversed).');
  } else {
    print('❌ Safe balance: got +$safeDelta, expected +70.'); pass = false;
  }

  // Check 2: Supplier delta only from credit item
  if ((supplierDelta + 50.0).abs() < 0.01) {
    print('✅ Supplier: -50 EGP correctly reversed (only credit item, paid item net=0).');
  } else {
    print('❌ Supplier delta: got $supplierDelta, expected -50.'); pass = false;
  }

  // Check 3: Supplier fully restored to baseline
  if ((supplierBalAfterCancel - baselineSupplierBal).abs() < 0.01) {
    print('✅ Supplier fully restored to baseline ($baselineSupplierBal).');
  } else {
    print('❌ Supplier not fully restored: got $supplierBalAfterCancel.'); pass = false;
  }

  // Check 4: Audit trail (v3 requirement)
  if (originalTxExists) {
    print('✅ Original expense treasury_transaction preserved (audit history intact) — v3 behavior.');
  } else {
    print('⚠️  Original treasury transaction DELETED — v2 behavior detected.');
    print('   → Run v3 migration to fix audit trail (does not affect financial correctness).');
    // Not a blocking failure for financial correctness, but note it
  }

  // Check 5: Reversal record (v3 requirement)
  if (hasReversalRecord) {
    print('✅ New return_in reversal record created — v3 audit trail confirmed.');
  } else if (!originalTxExists) {
    print('⚠️  No return_in record: v2 used DELETE instead (no audit trail).');
  } else {
    print('❌ Original exists but no return_in record — inconsistent state!'); pass = false;
  }

  // Check 6: Stamps cleared
  if (allStampsCleared) {
    print('✅ All cost item treasury_transaction_id stamps cleared to NULL.');
  } else {
    print('❌ Some cost item stamps still set.'); pass = false;
  }

  // Check 7: Order status
  if (orderStatus == 'cancelled') {
    print('✅ Order status = "cancelled".');
  } else {
    print('❌ Order status = "$orderStatus", expected "cancelled".'); pass = false;
  }

  // Determine deployed version
  final deployedVersion = (originalTxExists && hasReversalRecord) ? 'v3 (audit trail)' :
      (!originalTxExists && !hasReversalRecord) ? 'v2 (delete-based)' : 'unknown';
  print('\nDeployed RPC behavior detected: $deployedVersion');

  // ── CLEANUP ──
  print('\n--- Cleaning up test data ---');
  await client.from('packing_orders').delete().eq('id', orderId);
  print('Deleted packing order $orderId (cascades cost items).');

  for (final r in reversalRows) {
    await client.from('treasury_transactions').delete().eq('id', r['id']);
    print('Deleted reversal treasury_transaction ${r['id']}.');
  }

  final depositTxs = await client.from('treasury_transactions')
      .select('id').eq('treasury_id', treasuryId).eq('type', 'deposit')
      .eq('description', 'إيداع اختبار فاز 2 v3')
      .order('created_at', ascending: false).limit(1);
  if (depositTxs.isNotEmpty) {
    await client.from('treasury_transactions').delete().eq('id', depositTxs[0]['id']);
    print('Deleted deposit treasury_transaction ${depositTxs[0]['id']}.');
  }

  await client.from('suppliers')
      .update({'outstanding_balance': baselineSupplierBal}).eq('id', supplierId);

  final remainingTxs = await client.from('treasury_transactions')
      .select('amount, type').eq('treasury_id', treasuryId).eq('currency', 'EGP');
  const outflow = {'expense', 'withdrawal', 'transfer_out', 'return_out', 'disbursement_out'};
  double recalc = 0;
  for (final tx in remainingTxs) {
    final amt = (tx['amount'] as num).toDouble();
    recalc += outflow.contains(tx['type']) ? -amt : amt;
  }
  await client.from('treasury_balances')
      .update({'balance': recalc}).eq('treasury_id', treasuryId).eq('currency', 'EGP');
  print('Restored safe balance to $recalc EGP (from remaining transactions).');
  print('Restored supplier to $baselineSupplierBal.');

  print('\n════════════════════════════════════════════════════════════');
  // Financial correctness is the key pass/fail criteria
  final financiallyCorrect = ((safeDelta - 70.0).abs() < 0.01) &&
      ((supplierDelta + 50.0).abs() < 0.01) &&
      ((supplierBalAfterCancel - baselineSupplierBal).abs() < 0.01) &&
      allStampsCleared &&
      orderStatus == 'cancelled';

  if (financiallyCorrect && hasReversalRecord) {
    print('🎉 === PHASE 2 TEST PASSED (v3 — full audit trail + financial correctness) === 🎉');
  } else if (financiallyCorrect && !hasReversalRecord) {
    print('⚠️  PHASE 2 FINANCIALLY CORRECT (v2) but AUDIT TRAIL MISSING.');
    print('   → Apply migration 20260723000000_fix_rpc_cancel_packing_order_v3.sql');
    print('   → Then re-run this test to confirm v3 behavior.');
  } else {
    print('❌ === PHASE 2 TEST FAILED — FINANCIAL ERRORS DETECTED === ❌');
  }
}

Future<bool> _applyV3Migration(String accessToken) async {
  const projectRef = 'pjkhdnoeyyvraclomepx';
  final sql = File('supabase/migrations/20260723000000_fix_rpc_cancel_packing_order_v3.sql')
      .readAsStringSync();
  print('\nApplying v3 migration via Supabase Management API...');
  try {
    final resp = await http.post(
      Uri.parse('https://api.supabase.com/v1/projects/$projectRef/database/query'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'query': sql}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      print('✅ Migration v3 applied via Management API.');
      return true;
    } else {
      print('⚠️  Management API ${resp.statusCode}: ${resp.body}');
      return false;
    }
  } catch (e) {
    print('⚠️  Management API call failed: $e');
    return false;
  }
}
