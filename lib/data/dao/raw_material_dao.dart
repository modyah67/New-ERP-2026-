import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../models/raw_material_model.dart';

class RawMaterialDao {
  final _client = Supabase.instance.client;
  static const _table = 'raw_materials';
  static const _selectWithCategory = '*, raw_material_categories(name)';

  RawMaterialModel _fromRow(Map<String, dynamic> row) {
    final flat = Map<String, dynamic>.from(row);
    flat['category_name'] = flat['raw_material_categories']?['name'];
    flat.remove('raw_material_categories');
    return RawMaterialModel.fromMap(flat);
  }

  static String cleanProductName(String raw) {
    var s = raw.trim();
    // Remove (مادة تعبئة) or (مستلزمات) or (خامة) or similar suffixes
    s = s.replaceAll(RegExp(r'\s*\((مادة تعبئة|مستلزمات|خامة|مادة)\)\s*$', caseSensitive: false), '');
    return normalizeName(s);
  }

  static bool isBatchMatchingMaterial({
    required String? batchRawMaterialId,
    required String? batchProductName,
    required String? batchProductCode,
    required String materialId,
    required String materialName,
    required String materialCode,
  }) {
    final mId = materialId.trim();
    final mName = normalizeName(materialName);
    final mCode = materialCode.trim().toLowerCase();

    final bRawId = (batchRawMaterialId ?? '').trim();
    final bName = cleanProductName(batchProductName ?? '');
    final bCode = (batchProductCode ?? '').trim().toLowerCase();

    // 1. Direct ID match (Highest priority)
    if (bRawId.isNotEmpty && mId.isNotEmpty) {
      return bRawId == mId;
    }

    // If batch has a DIFFERENT raw_material_id, it belongs strictly to that other material
    if (bRawId.isNotEmpty && mId.isNotEmpty && bRawId != mId) {
      return false;
    }

    // 2. Exact cleaned name match
    if (bName.isNotEmpty && mName.isNotEmpty && bName == mName) {
      return true;
    }

    // 3. Exact code match ONLY if both codes exist and names are not conflicting
    if (mCode.isNotEmpty && bCode.isNotEmpty && mCode == bCode) {
      if (bName.isEmpty || mName.isEmpty || bName == mName) {
        return true;
      }
    }

    return false;
  }

  static bool isStationProductMatchingMaterial({
    required String? spRawMaterialId,
    required String? spProductName,
    required String? spProductCode,
    required String materialId,
    required String materialName,
    required String materialCode,
  }) {
    final mId = materialId.trim();
    final mName = normalizeName(materialName);
    final mCode = materialCode.trim().toLowerCase();

    final spRawId = (spRawMaterialId ?? '').trim();
    final spName = cleanProductName(spProductName ?? '');
    final spCode = (spProductCode ?? '').trim().toLowerCase();

    // 1. Direct ID match
    if (spRawId.isNotEmpty && mId.isNotEmpty) {
      return spRawId == mId;
    }
    if (spRawId.isNotEmpty && mId.isNotEmpty && spRawId != mId) {
      return false;
    }

    // 2. Exact cleaned name match
    if (spName.isNotEmpty && mName.isNotEmpty && spName == mName) {
      return true;
    }

    // 3. Exact code match
    if (mCode.isNotEmpty && spCode.isNotEmpty && mCode == spCode) {
      if (spName.isEmpty || mName.isEmpty || spName == mName) {
        return true;
      }
    }

    return false;
  }

  Future<List<RawMaterialModel>> getAll({String? search, String? categoryId}) async {
    var query = _client.from(_table).select(_selectWithCategory).eq('is_active', true);
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,code.ilike.%$search%');
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    final data = await query.order('name');
    
    final batchesData = await _client
        .from('station_product_batches')
        .select('id, station_id, product_code, product_name, remaining_quantity, unit_cost, source_type, item_type, raw_material_id')
        .neq('source_type', 'lot_receipt')
        .neq('source_type', 'crop_purchase');

    final stationProductsData = await _client
        .from('station_products')
        .select('id, raw_material_id, product_code, product_name, quantity, item_type');

    return data.map((row) {
      final flat = Map<String, dynamic>.from(row);
      flat['category_name'] = flat['raw_material_categories']?['name'];
      flat.remove('raw_material_categories');
      
      final mId = flat['id']?.toString() ?? '';
      final mCode = flat['code']?.toString() ?? '';
      final mName = flat['name']?.toString() ?? '';
      
      double totalQty = 0;
      double totalVal = 0;
      bool hasMatchingBatches = false;
      
      for (final b in batchesData) {
        final bSrc = b['source_type']?.toString();
        final bItemType = b['item_type']?.toString();
        if (bSrc == 'lot_receipt' || bSrc == 'crop_purchase' || bItemType == 'fruit') continue;

        final matches = isBatchMatchingMaterial(
          batchRawMaterialId: b['raw_material_id']?.toString(),
          batchProductName: b['product_name']?.toString(),
          batchProductCode: b['product_code']?.toString(),
          materialId: mId,
          materialName: mName,
          materialCode: mCode,
        );

        if (matches) {
           hasMatchingBatches = true;
           final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
           final cost = (b['unit_cost'] as num?)?.toDouble() ?? 0;
           totalQty += rem;
           totalVal += (rem * cost);
        }
      }

      if (!hasMatchingBatches) {
        for (final sp in stationProductsData) {
          final spType = sp['item_type']?.toString() ?? '';
          if (spType == 'fruit') continue;

          final matches = isStationProductMatchingMaterial(
            spRawMaterialId: sp['raw_material_id']?.toString(),
            spProductName: sp['product_name']?.toString(),
            spProductCode: sp['product_code']?.toString(),
            materialId: mId,
            materialName: mName,
            materialCode: mCode,
          );

          if (matches) {
            hasMatchingBatches = true;
            final spQty = (sp['quantity'] as num?)?.toDouble() ?? 0;
            totalQty += spQty;
          }
        }
      }
      
      if (hasMatchingBatches) {
        flat['quantity'] = totalQty;
        if (totalQty > 0) {
          flat['default_purchase_price'] = totalVal / totalQty;
        }
      }
      
      return RawMaterialModel.fromMap(flat);
    }).toList();
  }

  Future<RawMaterialModel?> getById(String id) async {
    final data = await _client.from(_table).select(_selectWithCategory).eq('id', id).maybeSingle();
    if (data == null) return null;
    
    final flat = Map<String, dynamic>.from(data);
    flat['category_name'] = flat['raw_material_categories']?['name'];
    flat.remove('raw_material_categories');
    
    final mId = flat['id']?.toString() ?? '';
    final mCode = flat['code']?.toString() ?? '';
    final mName = flat['name']?.toString() ?? '';
    
    final batchesData = await _client
        .from('station_product_batches')
        .select('id, station_id, product_code, product_name, remaining_quantity, unit_cost, source_type, item_type, raw_material_id')
        .neq('source_type', 'lot_receipt')
        .neq('source_type', 'crop_purchase');

    final stationProductsData = await _client
        .from('station_products')
        .select('id, raw_material_id, product_code, product_name, quantity, item_type');
        
    double totalQty = 0;
    double totalVal = 0;
    bool hasMatchingBatches = false;

    for (final b in batchesData) {
      final bSrc = b['source_type']?.toString();
      final bItemType = b['item_type']?.toString();
      if (bSrc == 'lot_receipt' || bSrc == 'crop_purchase' || bItemType == 'fruit') continue;

      final matches = isBatchMatchingMaterial(
        batchRawMaterialId: b['raw_material_id']?.toString(),
        batchProductName: b['product_name']?.toString(),
        batchProductCode: b['product_code']?.toString(),
        materialId: mId,
        materialName: mName,
        materialCode: mCode,
      );

      if (matches) {
        hasMatchingBatches = true;
        final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
        final cost = (b['unit_cost'] as num?)?.toDouble() ?? 0;
        totalQty += rem;
        totalVal += (rem * cost);
      }
    }

    if (!hasMatchingBatches) {
      for (final sp in stationProductsData) {
        final spType = sp['item_type']?.toString() ?? '';
        if (spType == 'fruit') continue;

        final matches = isStationProductMatchingMaterial(
          spRawMaterialId: sp['raw_material_id']?.toString(),
          spProductName: sp['product_name']?.toString(),
          spProductCode: sp['product_code']?.toString(),
          materialId: mId,
          materialName: mName,
          materialCode: mCode,
        );

        if (matches) {
          hasMatchingBatches = true;
          final spQty = (sp['quantity'] as num?)?.toDouble() ?? 0;
          totalQty += spQty;
        }
      }
    }
    
    if (hasMatchingBatches) {
      flat['quantity'] = totalQty;
      if (totalQty > 0) {
        flat['default_purchase_price'] = totalVal / totalQty;
      }
    }
    
    return RawMaterialModel.fromMap(flat);
  }

  static String normalizeName(String name) {
    var s = name.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  Future<bool> isNameExists(String name, {String? excludeId}) async {
    final cleanInput = normalizeName(name);
    if (cleanInput.isEmpty) return false;

    try {
      final data = await _client
          .from(_table)
          .select('id, name')
          .eq('is_active', true);

      for (final row in data) {
        final rowId = row['id']?.toString();
        if (excludeId != null && rowId == excludeId) continue;
        final rowName = row['name']?.toString() ?? '';
        if (normalizeName(rowName) == cleanInput) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('isNameExists error: $e');
    }
    return false;
  }

  Future<String> insert(RawMaterialModel item) async {
    if (await isNameExists(item.name)) {
      throw Exception('لا يمكن إضافة مادة تعبئة بهذا الاسم لأنها موجودة بالفعل.');
    }
    final result = await _client.from(_table).insert(item.toMap()).select().single();
    return result['id']?.toString() ?? '';
  }

  Future<void> update(RawMaterialModel item) async {
    if (item.id != null && await isNameExists(item.name, excludeId: item.id.toString())) {
      throw Exception('لا يمكن تعديل مادة التعبئة بهذا الاسم لأنه موجود بالفعل.');
    }
    await _client.from(_table).update(item.toMap()).eq('id', item.id!.toString());
    
    try {
      await _client.rpc('rpc_recalculate_packing_orders_material_cost', params: {
        'p_raw_material_id': item.id,
      });
    } catch (e) {
      debugPrint('Error recalculating packing order costs: $e');
    }
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<String> generateCode() async {
    try {
      final data = await _client.from(_table).select('code');
      int maxNum = 0;
      for (final row in data) {
        final c = row['code']?.toString() ?? '';
        final nums = RegExp(r'\d+').allMatches(c);
        for (final m in nums) {
          final n = int.tryParse(m.group(0) ?? '');
          if (n != null && n > maxNum) maxNum = n;
        }
      }
      return (maxNum + 1).toString();
    } catch (e) {
      debugPrint('generateCode error: $e');
      return '1';
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final data = await _client.from('raw_material_categories').select('id, name').order('name');
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  Future<void> adjustQuantity(String id, double delta) async {
    final item = await getById(id);
    if (item == null) return;
    final newQty = (item.quantity + delta).clamp(0.0, double.infinity);
    await _client.from(_table).update({
      'quantity': AppUtils.roundDouble(newQty),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }

  Future<Map<String, dynamic>> addCategory(String name) async {
    final data = await _client.from('raw_material_categories').insert({'name': name}).select('id, name').single();
    return Map<String, dynamic>.from(data);
  }

  Future<void> deleteCategory(String id) async {
    await _client.from('raw_material_categories').delete().eq('id', id);
  }

  Future<Map<String, dynamic>> getBatchesForMaterial(String materialId) async {
    try {
      final material = await getById(materialId);
      if (material == null) return {'batches': [], 'totalQuantity': 0, 'totalRemaining': 0, 'totalValue': 0, 'avgCost': 0};

      final mId = material.id?.toString() ?? '';
      final mCode = material.code.trim();
      final mName = normalizeName(material.name);

      // 1. Fetch all material batches safely
      final batchesData = await _client
          .from('station_product_batches')
          .select('id, station_id, product_name, product_code, supplier_name, quantity, remaining_quantity, unit_cost, exchange_rate, currency, source_type, created_at, purchase_invoice_id, raw_material_id, item_type')
          .neq('source_type', 'lot_receipt')
          .neq('source_type', 'crop_purchase')
          .order('created_at', ascending: true);

      // 2. Lookup station names safely
      final stationNames = <int, String>{};
      try {
        final stData = await _client.from('stations').select('id, name');
        for (final st in stData) {
          final sid = st['id'];
          if (sid != null) {
            final intId = sid is int ? sid : int.tryParse(sid.toString());
            if (intId != null) stationNames[intId] = st['name']?.toString() ?? '';
          }
        }
      } catch (_) {}

      // 3. Lookup purchase invoice numbers safely
      final invoiceNumbers = <int, String>{};
      try {
        final invData = await _client.from('purchase_invoices').select('id, invoice_number');
        for (final inv in invData) {
          final iid = inv['id'];
          if (iid != null) {
            final intId = iid is int ? iid : int.tryParse(iid.toString());
            if (intId != null) invoiceNumbers[intId] = inv['invoice_number']?.toString() ?? '';
          }
        }
      } catch (_) {}

      final List<Map<String, dynamic>> matchedBatches = [];
      double totalRemaining = 0;
      double totalValue = 0;

      for (final b in batchesData) {
        final bItemType = b['item_type']?.toString();
        if (bItemType == 'fruit') continue;

        final matches = isBatchMatchingMaterial(
          batchRawMaterialId: b['raw_material_id']?.toString(),
          batchProductName: b['product_name']?.toString(),
          batchProductCode: b['product_code']?.toString(),
          materialId: mId,
          materialName: mName,
          materialCode: mCode,
        );

        if (matches) {
          final flat = Map<String, dynamic>.from(b);
          flat['purchase_cost'] = flat['unit_cost'];
          
          final sid = flat['station_id'] is int ? flat['station_id'] as int : int.tryParse(flat['station_id']?.toString() ?? '');
          flat['station_name'] = sid != null ? (stationNames[sid] ?? '') : '';
          
          final invId = flat['purchase_invoice_id'] is int ? flat['purchase_invoice_id'] as int : int.tryParse(flat['purchase_invoice_id']?.toString() ?? '');
          flat['invoice_number'] = invId != null ? (invoiceNumbers[invId] ?? '') : '';
          
          flat['batch_number'] = flat['source_type'] == 'opening' ? 'OPENING-${flat['id']}' : 'BATCH-${flat['id']}';

          matchedBatches.add(flat);

          final rem = (flat['remaining_quantity'] as num?)?.toDouble() ?? 0;
          final cost = (flat['unit_cost'] as num?)?.toDouble() ?? 0;
          totalRemaining += rem;
          totalValue += (rem * cost);
        }
      }

      return {
        'batches': matchedBatches,
        'totalQuantity': totalRemaining,
        'totalRemaining': totalRemaining,
        'totalValue': AppUtils.roundDouble(totalValue),
        'avgCost': totalRemaining > 0 ? AppUtils.roundDouble(totalValue / totalRemaining) : 0.0,
      };
    } catch (e, st) {
      debugPrint('❌ getBatchesForMaterial error for $materialId: $e');
      debugPrint('   $st');
      return {'batches': [], 'totalQuantity': 0, 'totalRemaining': 0, 'totalValue': 0, 'avgCost': 0, 'error': e.toString()};
    }
  }
}
