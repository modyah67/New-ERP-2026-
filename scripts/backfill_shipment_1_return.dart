import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  print('=== Starting Backfill for Shipment #1 Return ===');
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  // 1. Insert / Upsert into cost_center_transactions FIRST
  print('Upserting cost_center_transactions for crop waste and return freight...');

  // A. Crop Waste
  await client.from('cost_center_transactions').upsert({
    'cost_center_id': 'CC-MANGO-2026-2027',
    'cost_center_name': 'مانجو (موسم 2026-2027)',
    'cost_center_type': 'crop',
    'source_type': 'export_return_waste',
    'source_id': 'exr_crop_waste_EXR-00001_0',
    'transaction_date': '2026-09-28',
    'supplier_name': 'عميل: mahmoud',
    'item_name': 'هالك رجوع شحنة (محصول) - مانجو عويسي',
    'category': 'تكلفة الهالك',
    'quantity': 120.0,
    'unit_price': 309.0116666666667,
    'currency': 'EGP',
    'exchange_rate': 1.0,
    'total_in_currency': 37081.40,
    'amount': 37081.40,
    'notes': 'هالك وتلف محصول عند رجوع الشحنة التصديرية رقم 26/12000/01 (EXR-00001)',
    'is_confirmed': true,
  }, onConflict: 'source_type,source_id');
  print('✅ Crop waste upserted into cost_center_transactions.');

  // B. Extra Freight Expense
  await client.from('cost_center_transactions').upsert({
    'cost_center_id': 'CC-MANGO-2026-2027',
    'cost_center_name': 'مانجو (موسم 2026-2027)',
    'cost_center_type': 'crop',
    'source_type': 'export_return_expense',
    'source_id': 'exr_exp_EXR-00001_0',
    'transaction_date': '2026-09-28',
    'supplier_id': '7',
    'supplier_name': 'مورد نقل تجريبي',
    'item_name': 'نولون نقل عودة من المطار',
    'category': 'لوجستيك ونقل',
    'quantity': 1.0,
    'unit_price': 1000.0,
    'currency': 'EGP',
    'exchange_rate': 1.0,
    'total_in_currency': 1000.0,
    'amount': 1000.0,
    'notes': 'نولون نقل عودة من المطار - شحنة رقم 26/12000/01 (EXR-00001)',
    'is_confirmed': true,
  }, onConflict: 'source_type,source_id');
  print('✅ Extra freight expense upserted into cost_center_transactions.');

  // 2. Update Journal Entry #36 Lines to link to CC-MANGO-2026-2027
  print('Updating JE #36 lines with cost_center_id...');
  final jeLines = await client
      .from('journal_entry_lines')
      .select()
      .eq('journal_entry_id', 36);

  for (final l in jeLines) {
    final lineId = l['id'];
    final debit = (l['debit'] as num?)?.toDouble() ?? 0.0;
    final desc = l['description']?.toString() ?? '';

    if (debit > 0 && (desc.contains('هالك') || desc.contains('نولون') || desc.contains('نقل'))) {
      await client
          .from('account_ledger_entries')
          .update({'cost_center_id': 'CC-MANGO-2026-2027'})
          .eq('id', lineId);
      print('✅ Updated account_ledger_entries line #$lineId ($desc) with cost_center_id=CC-MANGO-2026-2027');
    }
  }

  // 3. Ensure return_journal_entry_id on shipment
  await client
      .from('export_shipments')
      .update({'return_journal_entry_id': 36})
      .eq('id', 1);
  print('✅ Shipment #1 return_journal_entry_id ensured to 36');

  // 4. Try export_shipment_returns
  try {
    final existingReturns = await client.from('export_shipment_returns').select().eq('shipment_id', 1);
    if (existingReturns.isEmpty) {
      await client.from('export_shipment_returns').insert({
        'return_number': 'EXR-00001',
        'shipment_id': 1,
        'return_date': '2026-09-28',
        'cost_center_id': 'CC-MANGO-2026-2027',
        'total_cartons': 450,
        'intact_cartons': 330,
        'damaged_cartons': 120,
        'total_crop_weight': 4050.0,
        'intact_crop_weight': 2970.0,
        'damaged_crop_weight': 1080.0,
        'crop_waste_cost': 37081.40,
        'material_waste_cost': 0.0,
        'extra_expenses_cost': 1000.0,
        'reversed_revenue_amount': 9000.0,
        'reversed_revenue_egp': 450000.0,
        'reversed_customer_amount': 9000.0,
        'reversed_customer_egp': 450000.0,
        'currency': 'USD',
        'exchange_rate': 50.0,
        'return_reason': 'رجوع وإلغاء الشحنة من المطار',
        'notes': 'تم تسجيل رجوع الشحنة من المطار برقم EXR-00001 (سليم: 330 كرتونة / تالف: 120 كرتونة)',
        'journal_entry_id': 36,
      });
      print('✅ Inserted into export_shipment_returns');
    } else {
      print('ℹ️ export_shipment_returns row already exists.');
    }
  } catch (e) {
    print('ℹ️ export_shipment_returns insert notice: $e');
  }

  print('=== Backfill Completed Successfully ===');
}
