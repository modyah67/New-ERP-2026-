import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryValuationService {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getBatchValuation({
    int? productId,
    String? grade,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _client
        .from('stock_batches')
        .select('*, fruit_types!left(name), stock_batches(batch_number)')
        .gt('remaining_quantity', 0)
        .eq('status', 'active');

    if (productId != null) query = query.eq('product_id', productId);
    if (grade != null) query = query.eq('quality_grade', grade);
    if (fromDate != null) query = query.gte('created_at', fromDate.toIso8601String());
    if (toDate != null) query = query.lte('created_at', toDate.toIso8601String());

    final data = await query.order('created_at', ascending: false);

    return (data as List).map((row) {
      final r = row as Map<String, dynamic>;
      final qty = (r['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (r['purchase_cost'] as num?)?.toDouble() ?? 0;
      final fruit = r['fruit_types'] as Map? ?? {};
      final raw = r['raw_materials'] as Map? ?? {};
      return {
        'batch_id': r['id'],
        'batch_number': r['batch_number'] ?? '',
        'product_id': r['product_id'],
        'product_name': fruit['name'] ?? raw['name'] ?? '',
        'product_sku': raw['code'] ?? '',
        'grade': r['quality_grade'] ?? '',
        'remaining_qty': qty,
        'purchase_cost_kg': cost,
        'inventory_value': qty * cost,
        'station': r['notes'] ?? '',
        'created_at': r['created_at'] ?? '',
      };
    }).toList();
  }

  Future<Map<String, double>> getValuationSummary() async {
    final data = await _client
        .from('stock_batches')
        .select('remaining_quantity, purchase_cost')
        .gt('remaining_quantity', 0)
        .eq('status', 'active');

    double totalQty = 0, totalValue = 0;
    for (final row in data) {
      final qty = (row['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (row['purchase_cost'] as num?)?.toDouble() ?? 0;
      totalQty += qty;
      totalValue += qty * cost;
    }
    return {'total_qty': totalQty, 'total_value': totalValue};
  }

  Future<List<Map<String, dynamic>>> getValueByProduct() async {
    final data = await _client
        .from('stock_batches')
        .select('product_id, fruit_types!left(name), remaining_quantity, purchase_cost')
        .gt('remaining_quantity', 0)
        .eq('status', 'active');

    final groups = <int, Map<String, dynamic>>{};
    for (final row in data) {
      final pid = row['product_id'] as int;
      final qty = (row['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (row['purchase_cost'] as num?)?.toDouble() ?? 0;
      final fruit = row['fruit_types'] as Map? ?? {};
      final raw = row['raw_materials'] as Map? ?? {};
      groups.putIfAbsent(pid, () => {
        'product_id': pid,
        'product_name': fruit['name'] ?? raw['name'] ?? '',
        'total_qty': 0.0,
        'total_value': 0.0,
      });
      groups[pid]!['total_qty'] = (groups[pid]!['total_qty'] as double) + qty;
      groups[pid]!['total_value'] = (groups[pid]!['total_value'] as double) + (qty * cost);
    }
    return groups.values.toList()
      ..sort((a, b) => (b['total_value'] as double).compareTo(a['total_value'] as double));
  }

  Future<List<Map<String, dynamic>>> getValueByGrade() async {
    final data = await _client
        .from('stock_batches')
        .select('quality_grade, remaining_quantity, purchase_cost')
        .gt('remaining_quantity', 0)
        .eq('status', 'active');

    final groups = <String, Map<String, dynamic>>{};
    for (final row in data) {
      final grade = (row['quality_grade'] as String?) ?? 'N/A';
      final qty = (row['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (row['purchase_cost'] as num?)?.toDouble() ?? 0;
      groups.putIfAbsent(grade, () => {
        'grade': grade,
        'total_qty': 0.0,
        'total_value': 0.0,
      });
      groups[grade]!['total_qty'] = (groups[grade]!['total_qty'] as double) + qty;
      groups[grade]!['total_value'] = (groups[grade]!['total_value'] as double) + (qty * cost);
    }
    return groups.values.toList()
      ..sort((a, b) => (b['total_value'] as double).compareTo(a['total_value'] as double));
  }

}
