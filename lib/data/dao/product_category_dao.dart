import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_category_model.dart';

class ProductCategoryDao {
  final _client = Supabase.instance.client;

  static const _columns = 'id, name, parent_id, created_at';

  ProductCategoryModel _fromRow(Map<String, dynamic> row) {
    final flat = Map<String, dynamic>.from(row);
    final parent = flat['parent'];
    if (parent is Map<String, dynamic>) {
      flat['parent_name'] = parent['name']?.toString();
    } else if (parent is String) {
      flat['parent_name'] = parent;
    }
    flat.remove('parent');
    return ProductCategoryModel.fromMap(flat);
  }

  Future<List<ProductCategoryModel>> getAll() async {
    final data = await _client
        .from('product_categories')
        .select(_columns)
        .order('name');
    return data.map(_fromRow).toList();
  }

  Future<List<ProductCategoryModel>> getMainCategories() async {
    final data = await _client
        .from('product_categories')
        .select(_columns)
        .isFilter('parent_id', null)
        .order('name');
    return data.map(_fromRow).toList();
  }

  Future<List<ProductCategoryModel>> getSubcategories(dynamic parentId) async {
    final data = await _client
        .from('product_categories')
        .select(_columns)
        .eq('parent_id', parentId)
        .order('name');
    return data.map(_fromRow).toList();
  }

  Future<dynamic> insert(ProductCategoryModel category) async {
    final data = <String, dynamic>{
      'name': category.name,
      if (category.parentId != null) 'parent_id': category.parentId,
    };
    final result = await _client
        .from('product_categories')
        .insert(data)
        .select('id')
        .single();
    return result['id'];
  }

  Future<void> update(ProductCategoryModel category) async {
    final data = <String, dynamic>{
      'name': category.name,
      if (category.parentId != null) 'parent_id': category.parentId,
    };
    await _client.from('product_categories').update(data).eq('id', category.id!);
  }

  Future<void> delete(dynamic id) async {
    await _client.from('product_categories').delete().eq('id', id);
  }
}
