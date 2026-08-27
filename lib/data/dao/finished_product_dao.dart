import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/finished_product_model.dart';

class FinishedProductDao {
  final _client = Supabase.instance.client;
  static const _table = 'finished_products';

  FinishedProductModel _fromRow(Map<String, dynamic> row) {
    return FinishedProductModel.fromMap(row);
  }

  Future<List<FinishedProductModel>> getAll({String? search, bool? onlyActive}) async {
    var query = _client.from(_table).select('*, packing_recipes!finished_products_packing_recipe_id_fkey(name)');
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,code.ilike.%$search%');
    }
    if (onlyActive != null) {
      query = query.eq('is_active', onlyActive);
    }
    final data = await query.order('name');
    return data.map(_fromRow).toList();
  }

  Future<FinishedProductModel?> getById(String id) async {
    final data = await _client
        .from(_table)
        .select('*, packing_recipes!finished_products_packing_recipe_id_fkey(name)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<String> insert(FinishedProductModel item) async {
    final result = await _client.from(_table).insert(item.toMap()).select().single();
    return result['id']?.toString() ?? '';
  }

  Future<void> update(FinishedProductModel item) async {
    await _client.from(_table).update(item.toMap()).eq('id', item.id!.toString());
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<String> generateCode() async {
    try {
      final data = await _client.rpc('generate_finished_product_code');
      return data?.toString() ?? 'FP001';
    } catch (e) {
      return 'FP001';
    }
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
