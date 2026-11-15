import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item_model.dart';

class ItemDao {
  final _client = Supabase.instance.client;

  List<ItemModel> _fromRows(final List<Map<String, dynamic>> data) {
    return data.map((map) {
      final flat = Map<String, dynamic>.from(map);
      flat['code'] = flat['code'] ?? '';
      flat['name'] = flat['name'] ?? '';
      flat['price_per_unit'] = flat['price'] ?? 0.0;
      flat['created_at'] = flat['created_at'] ?? DateTime.now().toIso8601String();
      flat.remove('price');
      flat.remove('min_stock');
      flat.remove('max_stock');
      flat.remove('category_id');
      flat.remove('subcategory_id');
      flat.remove('is_active');
      flat.remove('track_expiry');
      return ItemModel.fromMap(flat);
    }).toList();
  }

  Future<List<ItemModel>> getAll({int limit = 50, int offset = 0, String? currency}) async {
    try {
      var query = _client.from('items').select();
      if (currency != null && currency.isNotEmpty) {
        query = query.eq('currency', currency);
      }
      final data = await query
          .order('name')
          .range(offset, offset + limit - 1);
      return _fromRows(data);
    } catch (_) {
      return [];
    }
  }

  Future<List<ItemModel>> search(String query,
      {int limit = 50, int offset = 0, String? currency}) async {
    try {
      var q = _client
          .from('items')
          .select()
          .or('name.ilike.%$query%,code.ilike.%$query%');
      if (currency != null && currency.isNotEmpty) {
        q = q.eq('currency', currency);
      }
      final data = await q
          .order('name')
          .range(offset, offset + limit - 1);
      return _fromRows(data);
    } catch (_) {
      return [];
    }
  }

  Future<ItemModel?> getById(String id) async {
    try {
      final data =
          await _client.from('items').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      final flat = Map<String, dynamic>.from(data);
      flat['code'] = flat['code'] ?? '';
      flat['name'] = flat['name'] ?? '';
      flat['price_per_unit'] = flat['price'] ?? 0.0;
      flat['created_at'] = flat['created_at'] ?? DateTime.now().toIso8601String();
      flat.remove('price');
      flat.remove('min_stock');
      flat.remove('max_stock');
      flat.remove('category_id');
      flat.remove('subcategory_id');
      flat.remove('is_active');
      flat.remove('track_expiry');
      return ItemModel.fromMap(flat);
    } catch (_) {
      return null;
    }
  }
}
