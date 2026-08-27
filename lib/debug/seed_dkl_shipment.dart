import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Seeds the DKL Shipment 23/52/067 for testing the shipment invoice.
/// Only runs in debug mode.
Future<void> seedDKLShipment() async {
  if (!kDebugMode) return;
  try {
    final client = Supabase.instance.client;

    // Check if already seeded
    final existing = await client
        .from('export_shipments')
        .select('id')
        .eq('shipment_no', '23/52/067')
        .maybeSingle();
    if (existing != null) {
      debugPrint('ℹ️  DKL shipment already seeded (id=${existing['id']}), skipping.');
      return;
    }

    // 1. Insert shipment
    final result = await client.from('export_shipments').insert({
      'shipment_no': '23/52/067',
      'customer_name': 'DKL',
      'destination_country': 'Netherlands',
      'container_no': 'MSCU8492012',
      'pallet_count': 10,
      'carton_count': 480,
      'net_weight': 2520.0,
      'gross_weight': 2680.0,
      'transport_mode': 'sea',
      'status': 'completed',
      'shipment_date': '2023-06-04',
      'export_price_per_carton': 123.96,
      'currency_code': 'USD',
      'exchange_rate': 30.9,
      'total_revenue_foreign': 59500.80,
      'total_revenue_egp': 1838574.72,
      'total_fruit_cost': 97650.00,
      'total_packing_material_cost': 45893.29,
      'gross_profit': 1713031.43,
      'net_profit': 1694924.14,
      'net_profit_egp': 1694924.14,
    }).select('id').single();

    final sid = result['id'] as int;
    debugPrint('✅ Shipment 23/52/067 created with id=$sid');

    // 2. Exported products
    await client.from('export_shipment_items').insert([
      {
        'shipment_id': sid, 'product_name': 'عنب إيرلي',
        'quantity': 240, 'price': 123.96, 'weight_per_carton': 5,
        'net_weight': 1200, 'gross_weight': 1280, 'amount': 29750.40, 'pallets': 5, 'sort_order': 0,
      },
      {
        'shipment_id': sid, 'product_name': 'عنب ستار لايت',
        'quantity': 240, 'price': 123.96, 'weight_per_carton': 5,
        'net_weight': 1200, 'gross_weight': 1280, 'amount': 29750.40, 'pallets': 5, 'sort_order': 1,
      },
    ]);

    // 3. Raw materials (fruit)
    await client.from('shipment_cost_breakdown').insert([
      {
        'shipment_id': sid, 'cost_type': 'fruit', 'cost_category': 'fruit_a',
        'item_name': 'عنب ستار لايت', 'quantity': 1260, 'unit_cost': 45, 'total_cost': 56700, 'currency': 'EGP', 'supplier': 'ح ياسر', 'sort_order': 0,
      },
      {
        'shipment_id': sid, 'cost_type': 'fruit', 'cost_category': 'fruit_b',
        'item_name': 'عنب إيرلي', 'quantity': 1260, 'unit_cost': 32.5, 'total_cost': 40950, 'currency': 'EGP', 'supplier': 'ح ياسر', 'sort_order': 1,
      },
    ]);

    // 4. Operations & packing
    await client.from('shipment_cost_breakdown').insert([
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'تشغيل 5 كجم', 'quantity': 2520, 'unit_cost': 3.8, 'total_cost': 9576, 'currency': 'EGP', 'sort_order': 2},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'كرتون 5 كجم فروتي', 'quantity': 480, 'unit_cost': 25.646, 'total_cost': 12310.16, 'currency': 'EGP', 'sort_order': 3},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'بانت 500 جم', 'quantity': 4800, 'unit_cost': 1.491, 'total_cost': 7157.14, 'currency': 'EGP', 'sort_order': 4},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'لاينر كبير', 'quantity': 480, 'unit_cost': 0.8, 'total_cost': 384, 'currency': 'EGP', 'sort_order': 5},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'كبريت بروتيكو بلاستيك', 'quantity': 240, 'unit_cost': 8.815, 'total_cost': 2115.60, 'currency': 'EGP', 'sort_order': 6},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'بالت بلاستيك', 'quantity': 6, 'unit_cost': 150, 'total_cost': 900, 'currency': 'EGP', 'sort_order': 7},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'غطاء بالته بلاستيك', 'quantity': 6, 'unit_cost': 7.622, 'total_cost': 45.73, 'currency': 'EGP', 'sort_order': 8},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'شنبر', 'quantity': 0.5, 'unit_cost': 560, 'total_cost': 280, 'currency': 'EGP', 'sort_order': 9},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'زوايا 160 سم مطبوعة', 'quantity': 24, 'unit_cost': 9.25, 'total_cost': 222, 'currency': 'EGP', 'sort_order': 10},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'زوايا 220 سم مطبوعة', 'quantity': 12, 'unit_cost': 11.25, 'total_cost': 135, 'currency': 'EGP', 'sort_order': 11},
      {'shipment_id': sid, 'cost_type': 'packing_material', 'cost_category': 'packing', 'item_name': 'داتا لوجر', 'quantity': 1, 'unit_cost': 237.67, 'total_cost': 237.67, 'currency': 'EGP', 'sort_order': 12},
      {'shipment_id': sid, 'cost_type': 'logistics', 'cost_category': 'logistics', 'item_name': 'نقل ثلاجة', 'quantity': 2, 'unit_cost': 2300, 'total_cost': 4600, 'currency': 'EGP', 'sort_order': 13},
      {'shipment_id': sid, 'cost_type': 'logistics', 'cost_category': 'logistics', 'item_name': 'نقل ثلاجة', 'quantity': 1, 'unit_cost': 2500, 'total_cost': 2500, 'currency': 'EGP', 'sort_order': 14},
      {'shipment_id': sid, 'cost_type': 'admin', 'cost_category': 'admin', 'item_name': 'ورق جزاري', 'quantity': 1, 'unit_cost': 300, 'total_cost': 300, 'currency': 'EGP', 'sort_order': 15},
      {'shipment_id': sid, 'cost_type': 'admin', 'cost_category': 'admin', 'item_name': 'مصاريف مهندسين', 'quantity': 1, 'unit_cost': 910, 'total_cost': 910, 'currency': 'EGP', 'sort_order': 16},
      {'shipment_id': sid, 'cost_type': 'admin', 'cost_category': 'admin', 'item_name': 'مصاريف إدارية', 'quantity': 1, 'unit_cost': 2030, 'total_cost': 2030, 'currency': 'EGP', 'sort_order': 17},
      {'shipment_id': sid, 'cost_type': 'admin', 'cost_category': 'admin', 'item_name': 'تخصيم', 'quantity': 1, 'unit_cost': 1600, 'total_cost': 1600, 'currency': 'EGP', 'sort_order': 18},
      {'shipment_id': sid, 'cost_type': 'admin', 'cost_category': 'admin', 'item_name': 'مصاريف م. إسلام', 'quantity': 1, 'unit_cost': 590, 'total_cost': 590, 'currency': 'EGP', 'sort_order': 19},
    ]);

    debugPrint('✅ DKL Shipment 23/52/067 fully seeded with ${2 + 2 + 18} rows');
  } catch (e, st) {
    debugPrint('❌ seedDKLShipment error: $e\n$st');
  }
}
