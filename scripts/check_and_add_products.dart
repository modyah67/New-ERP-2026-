import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

Future<void> main() async {
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final client = Supabase.instance.client;

  // 1. Show existing raw_fruit products
  print('=== Existing raw_fruit products ===');
  final existing = await client
      .from('products')
      .select('id, sku, name_ar, product_type')
      .eq('product_type', 'raw_fruit')
      .order('name_ar');
  for (final p in existing) {
    print('  id=${p['id']}  sku=${p['sku']}  name=${p['name_ar']}  type=${p['product_type']}');
  }

  // 2. Check required columns for insert
  print('\n=== Required (NOT NULL) columns in products ===');
  final required = await client
      .from('information_schema.columns')
      .select('column_name')
      .eq('table_name', 'products')
      .eq('is_nullable', 'NO')
      .neq('column_name', 'id')
      .neq('column_name', 'created_at')
      .neq('column_name', 'updated_at')
      .neq('column_name', 'user_id');
  final reqCols = required.map((r) => r['column_name'] as String).toList();
  print('  ${reqCols.join(', ')}');

  // 3. Check shipment_cost_items constraints
  print('\n=== shipment_cost_items columns ===');
  final cols = await client
      .from('information_schema.columns')
      .select('column_name, is_nullable, column_default')
      .eq('table_name', 'shipment_cost_items')
      .order('ordinal_position');
  for (final c in cols) {
    print('  ${c['column_name']}  nullable=${c['is_nullable']}  default=${c['column_default']}');
  }

  // 4. Check for CHECK constraints on shipment_cost_items
  print('\n=== CHECK constraints on shipment_cost_items ===');
  final checks = await client
      .from('information_schema.check_constraints')
      .select('constraint_name, check_clause')
      .eq('table_name', 'shipment_cost_items');

  // Try via pg_constraint if information_schema doesn't work
  if (checks.isEmpty) {
    print('  (no CHECK constraints found via information_schema)');
  } else {
    for (final c in checks) {
      print('  ${c['constraint_name']}: ${c['check_clause']}');
    }
  }

  // 5. Add new products (commented out — run this after reviewing the above)
  print('\n=== Products to add (PREVIEW) ===');
  final newProducts = [
    {'sku': 'GRP-FL-001', 'name_ar': 'عنب فليم', 'product_type': 'raw_fruit'},
    {'sku': 'GRP-SL-001', 'name_ar': 'عنب ستار لايت', 'product_type': 'raw_fruit'},
    {'sku': 'GRP-SU-001', 'name_ar': 'عنب سوبيريور', 'product_type': 'raw_fruit'},
    {'sku': 'GRP-BM-001', 'name_ar': 'عنب بلاك ماجيك', 'product_type': 'raw_fruit'},
  ];
  for (final np in newProducts) {
    // Check if already exists by name_ar
    final dup = await client
        .from('products')
        .select('id, sku')
        .eq('name_ar', np['name_ar'] as String)
        .maybeSingle();
    if (dup != null) {
      print('  ⏭ SKIP: "${np['name_ar']}" already exists as id=${dup['id']} sku=${dup['sku']}');
    } else {
      print('  ⏳ WILL INSERT: sku=${np['sku']}  name_ar=${np['name_ar']}  type=${np['product_type']}');
    }
  }

  // Uncomment to actually insert:
  // for (final np in newProducts) {
  //   final dup = await client
  //       .from('products')
  //       .select('id')
  //       .eq('name_ar', np['name_ar'] as String)
  //       .maybeSingle();
  //   if (dup == null) {
  //     await client.from('products').insert({
  //       'sku': np['sku'] as String,
  //       'name_ar': np['name_ar'] as String,
  //       'unit': 'كجم',
  //       'product_type': 'raw_fruit',
  //       'is_active': true,
  //     });
  //     print('  ✅ INSERTED: ${np['name_ar']}');
  //   }
  // }

  await client.dispose();
  exit(0);
}
