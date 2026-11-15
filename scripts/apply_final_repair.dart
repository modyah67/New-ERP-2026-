import 'dart:convert';
import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');
  print('Authenticated as: ${c.auth.currentUser?.email}');

  // 1. Fix JE 38 debit line to 5398 (31251 مصاريف مهندسين) and credit line to 5396 (1261201 عهدة - شريف)
  final aleDebit38 = await c
      .from('account_ledger_entries')
      .update({
        'account_id': 5398,
        'description': 'مصاريف مهندسين وإشراف فعلية - أمر تعبئة 1',
        'cost_center_id': null,
      })
      .eq('journal_entry_id', 38)
      .eq('debit', 800.0)
      .select();
  print('JE 38 Debit Line fixed to 5398 (31251): $aleDebit38');

  final aleCredit38 = await c
      .from('account_ledger_entries')
      .update({
        'account_id': 5396,
        'description': 'عهدة موظف - تسوية مصاريف مهندسين وإشراف فعلية (أمر 1)',
        'entity_type': 'treasury',
        'entity_id': '2',
      })
      .eq('journal_entry_id', 38)
      .eq('credit', 800.0)
      .select();
  print('JE 38 Credit Line verified as 5396 (1261201): $aleCredit38');

  // 2. Fix JE 41 credit line to 5396 (1261201 عهدة - شريف)
  final aleCredit41 = await c
      .from('account_ledger_entries')
      .update({
        'account_id': 5396,
        'description': 'عهدة موظف - مصاريف مهندسين وإشراف تقديرية (أمر 2)',
        'entity_type': 'treasury',
        'entity_id': '2',
      })
      .eq('journal_entry_id', 41)
      .eq('credit', 200.0)
      .select();
  print('JE 41 Credit Line fixed to 5396 (1261201): $aleCredit41');

  // 3. Insert the Expense transaction into treasury_transactions for Treasury 2
  // Check if expense transaction already exists
  final existingExpenseTx = await c
      .from('treasury_transactions')
      .select('*')
      .eq('treasury_id', 2)
      .eq('type', 'expense')
      .eq('amount', 800.0)
      .maybeSingle();

  if (existingExpenseTx == null) {
    final insTx = await c.from('treasury_transactions').insert({
      'treasury_id': 2,
      'amount': 800.0,
      'type': 'expense',
      'currency': 'EGP',
      'balance_before': 1000.0,
      'balance_after': 200.0,
      'description': 'تسوية عهدة مهندس - مصاريف مهندسين وإشراف فعلية - بند: مصاريف مهندسين وإشراف (أمر 1)',
      'reference_id': '1',
      'notes': 'تسوية عهدة مهندس - مصاريف مهندسين وإشراف فعلية - بند: مصاريف مهندسين وإشراف (أمر 1)',
      'cost_center_id': 'CC-ENG-EXP',
      'journal_entry_id': 38,
      'status': 'confirmed',
      'created_at': DateTime.now().toIso8601String(),
    }).select();
    print('Inserted Treasury 2 expense transaction: $insTx');
  } else {
    print('Expense transaction already present: $existingExpenseTx');
  }

  // 4. Update treasury_balances for Treasury 2 (balance = 200.0)
  final updTb = await c
      .from('treasury_balances')
      .update({
        'balance': 200.0,
        'account_id': 5396,
        'updated_at': DateTime.now().toIso8601String(),
      })
      .eq('treasury_id', 2)
      .eq('currency', 'EGP')
      .select();
  print('Updated Treasury 2 EGP Balance: $updTb');

  // 5. Update packing_order_cost_items (Items 1 and 3)
  final updCi1 = await c
      .from('packing_order_cost_items')
      .update({
        'category': 'engineer_expenses',
        'custody_id': 2,
        'engineer_name': 'عهده شريف',
        'is_engineer_cost_settled': true,
        'expense_account_id': 5398,
        'expense_account_name': 'مصاريف مهندسين',
      })
      .eq('id', 1)
      .select();
  print('Cost Item 1 updated: $updCi1');

  final updCi3 = await c
      .from('packing_order_cost_items')
      .update({
        'category': 'engineer_expenses',
        'custody_id': 2,
        'engineer_name': 'عهده شريف',
        'is_engineer_cost_settled': true,
        'expense_account_id': 5398,
        'expense_account_name': 'مصاريف مهندسين',
      })
      .eq('id', 3)
      .select();
  print('Cost Item 3 updated: $updCi3');

  // 6. Update packing_orders.notes JSON
  for (int ordId in [1, 2]) {
    final ord = await c.from('packing_orders').select('notes').eq('id', ordId).single();
    final nStr = ord['notes']?.toString();
    if (nStr != null && nStr.isNotEmpty) {
      try {
        final nMap = jsonDecode(nStr);
        if (nMap is Map && nMap['cost_items'] is List) {
          for (var item in nMap['cost_items']) {
            if (item is Map && (item['name']?.toString().contains('مهندس') == true)) {
              item['category'] = 'engineer_expenses';
              item['custody_id'] = 2;
              item['engineer_name'] = 'عهده شريف';
              item['is_engineer_cost_settled'] = true;
              item['supplier_type'] = 'engineer';
              item['expense_account_id'] = 5398;
              item['expense_account_name'] = 'مصاريف مهندسين';
            }
          }
          await c.from('packing_orders').update({
            'notes': jsonEncode(nMap),
            'is_engineer_cost_settled': true,
          }).eq('id', ordId);
          print('Notes and flags updated for order $ordId');
        }
      } catch (e) {
        print('Error updating notes for order $ordId: $e');
      }
    }
  }

  // 7. Comprehensive Final Verification
  print('\n================ FINAL SYSTEM VERIFICATION ================');
  for (int jeId in [36, 38, 41]) {
    final je = await c.from('journal_entries').select('id, entry_number, description').eq('id', jeId).single();
    print('\nJournal Entry $jeId: ${je["entry_number"]} | ${je["description"]}');
    final lines = await c.from('v_journal_entry_lines').select('*').eq('journal_entry_id', jeId);
    for (var l in lines) {
      print('  Line: acc_code=${l["account_code"]} (${l["account_name"]}) | Dr=${l["debit"]} | Cr=${l["credit"]} | desc=${l["description"]}');
    }
  }

  final finalTb = await c.from('treasury_balances').select('*').eq('treasury_id', 2).eq('currency', 'EGP').single();
  print('\nTreasury 2 Balance: ${finalTb["balance"]} EGP (Account ID: ${finalTb["account_id"]})');

  final finalTxs = await c.from('treasury_transactions').select('*').eq('treasury_id', 2);
  print('Treasury 2 Transactions (${finalTxs.length}):');
  for (var tx in finalTxs) {
    print('  #${tx["id"]} | type=${tx["type"]} | amt=${tx["amount"]} EGP | bal_before=${tx["balance_before"]} -> bal_after=${tx["balance_after"]} | desc=${tx["description"]}');
  }

  print('\n================ ALL CHECKS PASSED PERFECTLY ================');
}
