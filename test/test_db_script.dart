import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://pjkhdnoeyyvraclomepx.supabase.co',
    anonKey: 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
  );

  final client = Supabase.instance.client;

  try {
    print('Fetching suppliers...');
    final suppliers = await client.from('suppliers').select().limit(1);
    if (suppliers.isEmpty) {
      print('No suppliers found.');
      return;
    }
    
    final supplierId = suppliers.first['id']?.toString() ?? 'SUP-0001';
    print('Testing with supplierId: \$supplierId');

    print('Fetching purchases...');
    final purchases = await client.from('purchase_invoices').select().eq('supplier_id', supplierId);
    print('Purchases count: \${purchases.length}');

    if (purchases.isNotEmpty) {
      final purId = purchases.first['id'];
      print('Fetching items for purchase \$purId...');
      final items = await client.from('purchase_invoice_items').select().eq('invoice_id', purId.toString());
      print('Items count: \${items.length}');
    }

    print('Fetching treasury txs...');
    final treasuryTxs = await client.from('treasury_transactions').select('*').eq('supplier_id', supplierId);
    print('Treasury txs count: \${treasuryTxs.length}');
    
    print('Fetching transactions...');
    final txs = await client.from('transactions').select('*').limit(10);
    print('Txs count: \${txs.length}');

  } catch (e, st) {
    print("Error: \$e\\n\$st");
  }
}
