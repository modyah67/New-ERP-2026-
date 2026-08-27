import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://pjkhdnoeyyvraclomepx.supabase.co',
    'sb_publishable_y6C2YEO2LvomYFBDm80fZw_HHQMqK12'
  );
  try {
    print('Checking for invalid report_category_id in shipment_cost_items...');
    // We can't run arbitrary SQL directly without exec_sql, but we can fetch all categories and cost items
    final categoriesRes = await client.from('cost_report_categories').select('id');
    final validCategoryIds = (categoriesRes as List).map((e) => e['id'] as int).toSet();
    
    final itemsRes = await client.from('shipment_cost_items').select('id, report_category_id, description');
    
    int invalidCount = 0;
    for (final item in itemsRes as List) {
      final catId = item['report_category_id'] as int?;
      if (catId != null && !validCategoryIds.contains(catId)) {
        print('Invalid item found: ID ${item['id']}, CatID $catId, Desc: ${item['description']}');
        invalidCount++;
        // Attempt to fix it by setting it to null
        await client.from('shipment_cost_items').update({'report_category_id': null}).eq('id', item['id']);
        print('Fixed item ${item['id']} by setting report_category_id to null');
      }
    }
    
    if (invalidCount == 0) {
      print('No invalid report_category_id found in existing data.');
    }
    
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
