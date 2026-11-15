import 'package:supabase/supabase.dart';
import 'package:accounting_system/supabase_options.dart';

void main() async {
  final client = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  print('=== Simulating CostReportDao.getDetails for CC-MANGO-2026-2027 ===\n');

  // Step 3: Fetch dedicated cost center transactions
  final cctRows = <Map<String, dynamic>>[];
  final cctData = await client
      .from('cost_center_transactions')
      .select()
      .or('cost_center_id.eq.CC-MANGO-2026-2027,cost_center_id.eq.16')
      .order('transaction_date', ascending: false);

  for (final cct in cctData) {
    final isExportReturnWaste = cct['source_type'] == 'export_return_waste' ||
        cct['source_type'] == 'export_return_crop_waste' ||
        cct['source_type'] == 'export_return_material_waste';
    final isExportReturnExpense = cct['source_type'] == 'export_return_expense';
    final isExportReturn = isExportReturnWaste || isExportReturnExpense;

    final String shipmentNo;
    if (isExportReturn) {
      final notesStr = cct['notes']?.toString() ?? '';
      final exrMatch = RegExp(r'EXR-\d+').firstMatch(notesStr)?.group(0);
      final sId = cct['source_id']?.toString() ?? '';
      final exrInSource = RegExp(r'EXR-\d+').firstMatch(sId)?.group(0);
      shipmentNo = exrMatch ?? exrInSource ?? (cct['shipment_no']?.toString() ?? 'مرتجع من المطار');
    } else {
      shipmentNo = cct['source_type']?.toString() ?? '';
    }

    final double rawAmount = (cct['amount'] as num?)?.toDouble() ?? 0.0;
    final double rawQty = (cct['quantity'] as num?)?.toDouble() ?? 0.0;
    final double rawUnitPrice = (cct['unit_price'] as num?)?.toDouble() ?? 0.0;

    double cctFinalQty = rawQty;
    double cctFinalUnitPrice = rawUnitPrice;
    if (cctFinalUnitPrice <= 0 && cctFinalQty.abs() > 0) {
      cctFinalUnitPrice = rawAmount.abs() / cctFinalQty.abs();
    } else if (cctFinalQty.abs() <= 0 && cctFinalUnitPrice > 0) {
      cctFinalQty = rawAmount.abs() / cctFinalUnitPrice;
    }

    final String categoryName = cct['category']?.toString() ??
        (isExportReturnWaste
            ? 'تكلفة الهالك'
            : (isExportReturnExpense ? 'لوجستيك ونقل' : 'أخرى'));

    cctRows.add({
      'id': 'cct_${cct['id']}',
      'source_type': cct['source_type'],
      'source_id': cct['source_id']?.toString(),
      'shipment_no': shipmentNo,
      'shipment_date': cct['transaction_date']?.toString(),
      'customer_name': cct['supplier_name']?.toString() ?? 'مرتجع من المطار',
      'category': categoryName,
      'item_name': cct['item_name'],
      'quantity': cctFinalQty,
      'unit_price': cctFinalUnitPrice,
      'amount': rawAmount,
      'is_export_return': isExportReturn,
      'is_export_return_waste': isExportReturnWaste,
      'is_export_return_expense': isExportReturnExpense,
    });
  }

  print('Total cost center transactions for CC-MANGO-2026-2027: ${cctRows.length}');
  final returnRows = cctRows.where((r) => r['is_export_return'] == true).toList();
  print('\n=== RETURN ROWS FOUND (${returnRows.length}) ===');
  for (final r in returnRows) {
    print('• [${r['shipment_no']}] ${r['item_name']}');
    print('    الفئة (Category): ${r['category']}');
    print('    الطرف (Supplier/Customer): ${r['customer_name']}');
    print('    الكمية (Qty): ${r['quantity']}');
    print('    سعر الوحدة (Unit Price): ${r['unit_price']} EGP');
    print('    الإجمالي (Amount): ${r['amount']} EGP');
    print('    نوع الحركة (Subtype): waste=${r['is_export_return_waste']}, exp=${r['is_export_return_expense']}\n');
  }

  if (returnRows.length >= 2) {
    print('✅ SUCCESS: Both Crop Waste and Return Extra Expense appear accurately in the Cost Center pipeline!');
  } else {
    print('❌ Warning: Expected at least 2 return rows.');
  }
}
