import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/packing_recipe_model.dart';
import '../models/raw_material_model.dart';

class PackingRecipeDao {
  final _client = Supabase.instance.client;

  static const _selectWithMaterials = '''
    *,
    raw_materials!packing_recipes_raw_material_id_fkey(name, default_purchase_price)
  ''';

  List<PackingRecipeModel> _mapRows(List<dynamic> data) {
    return data.map((e) {
      final row = Map<String, dynamic>.from(e as Map);
      final material = AppUtils.asMap(row.remove('raw_materials'));
      return PackingRecipeModel.fromMap({
        ...row,
        'raw_material_name': material?['name'],
      });
    }).toList();
  }

  Future<List<PackingRecipeModel>> getAll({bool? onlyActive}) async {
    try {
      var query = _client.from('packing_recipes').select(_selectWithMaterials);
      if (onlyActive == true) {
        query = query.eq('is_active', true);
      }
      final data = await query.order('name').order('grade');
      return _mapRows(data);
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.getAll error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PackingRecipeModel>> getByRecipeName(String recipeName) async {
    try {
      final data = await _client
          .from('packing_recipes')
          .select(_selectWithMaterials)
          .eq('name', recipeName)
          .eq('is_active', true);
      return _mapRows(data);
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.getByRecipeName error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PackingRecipeModel>> getByRecipeNameAll(String recipeName) async {
    try {
      final data = await _client
          .from('packing_recipes')
          .select(_selectWithMaterials)
          .eq('name', recipeName);
      return _mapRows(data);
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.getByRecipeNameAll error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PackingRecipeModel>> getByRecipeId(String recipeId) async {
    try {
      final data = await _client
          .from('packing_recipes')
          .select(_selectWithMaterials)
          .eq('id', recipeId);
      return _mapRows(data);
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.getByRecipeId error: $e\n$st');
      rethrow;
    }
  }

  Future<void> insert(PackingRecipeModel recipe) async {
    try {
      await _client.from('packing_recipes').insert(recipe.toMap());
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> update(PackingRecipeModel recipe) async {
    try {
      await _client.from('packing_recipes').update(recipe.toMap()).eq('id', recipe.id!);
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.update error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> isUsedInShipments(String id) async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('id')
          .eq('packing_recipe_id', id)
          .limit(1);
      return shipments.isNotEmpty;
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.isUsedInShipments error: $e\n$st');
      return false;
    }
  }

  Future<bool> isUsedInSnapshots(String id) async {
    try {
      final snapshots = await _client
          .from('shipment_recipe_snapshots')
          .select('id')
          .eq('packing_recipe_id', id)
          .limit(1);
      return snapshots.isNotEmpty;
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.isUsedInSnapshots error: $e\n$st');
      return false;
    }
  }

  Future<String?> deleteWithCheck(String id) async {
    try {
      final inShipments = await isUsedInShipments(id);
      if (inShipments) return 'لا يمكن حذف الوصفة لأنها مستخدمة في شحنة واحدة أو أكثر.';

      final inSnapshots = await isUsedInSnapshots(id);
      if (inSnapshots) return 'لا يمكن حذف الوصفة لأنها مستخدمة في Snapshot وصفة لواحدة أو أكثر.';

      await _client.from('packing_recipes').delete().eq('id', id);
      return null;
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.deleteWithCheck error: $e\n$st');
      return 'حدث خطأ أثناء محاولة حذف الوصفة: $e';
    }
  }

  Future<String?> deleteGroupWithCheck(String recipeName) async {
    try {
      final existing = await _client
          .from('packing_recipes')
          .select('id')
          .eq('name', recipeName);

      for (final row in existing) {
        final id = row['id'] as String;
        final inShipments = await isUsedInShipments(id);
        if (inShipments) return 'لا يمكن حذف الوصفة لأنها مستخدمة في شحنة واحدة أو أكثر.';
        final inSnapshots = await isUsedInSnapshots(id);
        if (inSnapshots) return 'لا يمكن حذف الوصفة لأنها مستخدمة في Snapshot وصفة لواحدة أو أكثر.';
      }

      await _client.from('packing_recipes').delete().eq('name', recipeName);
      return null;
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.deleteGroupWithCheck error: $e\n$st');
      return 'حدث خطأ أثناء محاولة حذف الوصفة: $e';
    }
  }

  Future<String?> saveAllWithCheck(String recipeName, String grade, List<PackingRecipeModel> items) async {
    try {
      final existing = await _client
          .from('packing_recipes')
          .select('id')
          .eq('name', recipeName)
          .eq('grade', grade);

      for (final row in existing) {
        final id = row['id'] as String;
        final inShipments = await isUsedInShipments(id);
        if (inShipments) return 'لا يمكن تعديل وصفات هذا المنتج/الدرجة لأنها مستخدمة في شحنة واحدة أو أكثر.';
        final inSnapshots = await isUsedInSnapshots(id);
        if (inSnapshots) return 'لا يمكن تعديل وصفات هذا المنتج/الدرجة لأنها مستخدمة في Snapshot وصفة لواحدة أو أكثر.';
      }

      await _client.from('packing_recipes').delete().eq('name', recipeName).eq('grade', grade);
      if (items.isEmpty) return null;
      await _client.from('packing_recipes').insert(items.map((r) => r.toMap()).toList());
      return null;
    } catch (e, st) {
      debugPrint('❌ PackingRecipeDao.saveAllWithCheck error: $e\n$st');
      return 'حدث خطأ أثناء محاولة حفظ الوصفات: $e';
    }
  }

  /// Get raw materials for use in the recipe editor
  Future<List<RawMaterialModel>> getRawMaterials() async {
    try {
      final data = await _client
          .from('raw_materials')
          .select()
          .eq('is_active', true)
          .order('name');
      return data.map((e) => RawMaterialModel.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
