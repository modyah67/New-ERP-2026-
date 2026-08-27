import 'package:supabase_flutter/supabase_flutter.dart';

class CostReportDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getDetails({
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
    int? shipmentId,
    String? itemName,
  }) async {
    // Fetch all cost items from unified live view
    var query = _client.from('vw_cost_details_live').select();
    
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (shipmentId != null) {
      query = query.eq('shipment_id', shipmentId);
    }
    if (customer != null && customer.isNotEmpty) {
      query = query.eq('customer_name', customer);
    }
    if (itemName != null && itemName.isNotEmpty) {
      query = query.eq('item_name', itemName);
    }
    if (fromDate != null && fromDate.isNotEmpty) {
      query = query.gte('shipment_date', fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      query = query.lte('shipment_date', toDate);
    }

    final result = await query.order('shipment_date', ascending: false);
    return List<Map<String, dynamic>>.from(result);


  }

  Future<List<Map<String, dynamic>>> getSummary({
    String? fromDate,
    String? toDate,
    String? customer,
  }) async {
    final details = await getDetails(
      fromDate: fromDate,
      toDate: toDate,
      customer: customer,
    );
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final row in details) {
      final item = (row['item_name'] as String?)?.trim();
      final name = (item != null && item.isNotEmpty) ? item : ((row['category'] as String?) ?? 'unknown');
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (!grouped.containsKey(name)) {
        grouped[name] = {
          'item_name': name,
          'total_amount': 0.0,
          'transaction_count': 0,
        };
      }
      grouped[name]!['total_amount'] =
          (grouped[name]!['total_amount'] as double) + amount;
      grouped[name]!['transaction_count'] =
          (grouped[name]!['transaction_count'] as int) + 1;
    }
    final result = grouped.values.toList();
    result.sort((a, b) =>
        (b['total_amount'] as double).compareTo(a['total_amount'] as double));
    // Filter out generic/unknown names
    final generic = {'أخرى', 'other', 'OTHER', 'unknown', ''};
    result.removeWhere((e) {
      final name = (e['item_name'] as String?)?.trim() ?? '';
      return generic.contains(name);
    });
    return result;
  }

  Future<List<String>> getDistinctCustomers() async {
    final result = await _client
        .from('vw_cost_details_live')
        .select('customer_name')
        .not('customer_name', 'is', null);
    
    final names = result.map((e) => e['customer_name'] as String?).where((n) => n != null && n.isNotEmpty).toSet().toList();
    names.sort();
    return List<String>.from(names);
  }

}
