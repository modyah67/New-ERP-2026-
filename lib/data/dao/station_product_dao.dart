import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/station_product_batch.dart';
import '../models/station_product_model.dart';

class StationProductDao {
  final _client = Supabase.instance.client;
  static const _table = 'station_products';

  String _canonicalKeyForProduct(StationProductModel p) {
    final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
    if (isFruit) {
      if (p.fruitTypeId != null && p.fruitTypeId! > 0) {
        return 'fruit_${p.fruitTypeId}';
      }
      if (p.productCode.trim().isNotEmpty) {
        return 'fruit_code_${p.productCode.trim()}';
      }
      final cleanName = p.productName.trim().toLowerCase();
      if (cleanName.isNotEmpty) {
        return 'fruit_name_$cleanName';
      }
      return 'fruit_unknown';
    } else {
      if (p.rawMaterialId != null && p.rawMaterialId!.isNotEmpty) {
        return 'material_${p.rawMaterialId}';
      }
      if (p.productCode.trim().isNotEmpty) {
        return 'material_code_${p.productCode.trim()}';
      }
      final cleanName = p.productName.trim().toLowerCase();
      if (cleanName.isNotEmpty) {
        return 'material_name_$cleanName';
      }
      return 'material_unknown';
    }
  }

  String _canonicalKeyForBatch(StationProductBatch b) {
    final isFruit = b.itemType == 'fruit' ||
        b.fruitTypeId != null ||
        b.sourceType == 'lot_receipt' ||
        b.sourceType == 'crop_purchase';
    if (isFruit) {
      if (b.fruitTypeId != null && b.fruitTypeId! > 0) {
        return 'fruit_${b.fruitTypeId}';
      }
      if (b.productCode.trim().isNotEmpty) {
        return 'fruit_code_${b.productCode.trim()}';
      }
      final cleanName = b.productName.trim().toLowerCase();
      if (cleanName.isNotEmpty) {
        return 'fruit_name_$cleanName';
      }
      return 'fruit_unknown';
    } else {
      if (b.rawMaterialId != null && b.rawMaterialId!.isNotEmpty) {
        return 'material_${b.rawMaterialId}';
      }
      if (b.productCode.trim().isNotEmpty) {
        return 'material_code_${b.productCode.trim()}';
      }
      final cleanName = b.productName.trim().toLowerCase();
      if (cleanName.isNotEmpty) {
        return 'material_name_$cleanName';
      }
      return 'material_unknown';
    }
  }

  List<StationProductBatch> _collectBatches(
    String canonKey,
    String itemKey,
    String productName,
    String productCode,
    String itemType,
    Map<String, List<StationProductBatch>> batchMap,
  ) {
    final list = <StationProductBatch>[];
    final seenIds = <int>{};
    final isTargetFruit = itemType == 'fruit';

    void addBatches(List<StationProductBatch>? batches) {
      if (batches == null) return;
      for (final b in batches) {
        final bIsFruit = b.itemType == 'fruit' ||
            b.fruitTypeId != null ||
            b.sourceType == 'lot_receipt' ||
            b.sourceType == 'crop_purchase';
        if (bIsFruit != isTargetFruit) continue;

        final id = b.id ?? b.hashCode;
        if (!seenIds.contains(id)) {
          seenIds.add(id);
          list.add(b);
        }
      }
    }

    addBatches(batchMap[canonKey]);
    addBatches(batchMap[itemKey]);
    final cleanName = productName.trim().toLowerCase();
    if (cleanName.isNotEmpty) {
      addBatches(batchMap['${itemType}_name_$cleanName']);
    }
    if (productCode.trim().isNotEmpty) {
      addBatches(batchMap['${itemType}_code_${productCode.trim()}']);
    }
    return list;
  }

  Future<List<StationProductModel>> getByStation(int stationId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('station_id', stationId)
        .order('product_name');
    final products = data.map(StationProductModel.fromMap).toList();

    try {
      final batchData = await _client
          .from('station_product_batches')
          .select()
          .eq('station_id', stationId);

      if (batchData.isNotEmpty) {
        final parsedBatches =
            batchData.map(StationProductBatch.fromMap).toList();

        final batchMap = <String, List<StationProductBatch>>{};
        for (final b in parsedBatches) {
          final canonKey = _canonicalKeyForBatch(b);
          final bIsFruit = b.itemType == 'fruit' ||
              b.fruitTypeId != null ||
              b.sourceType == 'lot_receipt' ||
              b.sourceType == 'crop_purchase';
          final bType = bIsFruit ? 'fruit' : 'material';

          batchMap.putIfAbsent(canonKey, () => []).add(b);
          batchMap.putIfAbsent(b.itemKey, () => []).add(b);
          if (b.productName.trim().isNotEmpty) {
            batchMap.putIfAbsent(
                '${bType}_name_${b.productName.trim().toLowerCase()}', () => []).add(b);
          }
          if (b.productCode.trim().isNotEmpty) {
            batchMap.putIfAbsent(
                '${bType}_code_${b.productCode.trim()}', () => []).add(b);
          }
        }

        final productMap = <String, StationProductModel>{};
        final matchedBatchIds = <int>{};

        for (final p in products) {
          final canonKey = _canonicalKeyForProduct(p);
          final bList = _collectBatches(
            canonKey,
            p.itemKey,
            p.productName,
            p.productCode,
            p.itemType,
            batchMap,
          );
          for (final b in bList) {
            if (b.id != null) matchedBatchIds.add(b.id!);
          }
          final isFruit = p.itemType == 'fruit' || p.fruitTypeId != null;
          final cleanUnit = isFruit
              ? p.unit
              : (p.unit == 'kg' ? 'piece' : p.unit);

          if (bList.isNotEmpty) {
            final remQty = bList.fold<double>(
                0.0, (sum, b) => sum + b.remainingQuantity);
            productMap[canonKey] = p.copyWith(
              quantity: remQty,
              unit: cleanUnit,
            );
          } else {
            productMap[canonKey] = p.copyWith(unit: cleanUnit);
          }
        }

        for (final b in parsedBatches) {
          if (b.id != null && matchedBatchIds.contains(b.id!)) continue;
          final canonKey = _canonicalKeyForBatch(b);
          if (!productMap.containsKey(canonKey)) {
            final bList = _collectBatches(
              canonKey,
              b.itemKey,
              b.productName,
              b.productCode,
              b.itemType,
              batchMap,
            );
            for (final item in bList) {
              if (item.id != null) matchedBatchIds.add(item.id!);
            }
            final remQty = bList.fold<double>(
                0.0, (sum, item) => sum + item.remainingQuantity);
            if (remQty > 0) {
              final isFruit = b.itemType == 'fruit' ||
                  b.fruitTypeId != null ||
                  b.sourceType == 'lot_receipt' ||
                  b.sourceType == 'crop_purchase';
              productMap[canonKey] = StationProductModel(
                stationId: stationId,
                productName: b.productName,
                productCode: b.productCode,
                quantity: remQty,
                unit: isFruit ? 'carton' : 'piece',
                itemType: isFruit ? 'fruit' : 'material',
                rawMaterialId: b.rawMaterialId,
                fruitTypeId: b.fruitTypeId,
              );
            }
          }
        }
        return productMap.values.toList();
      }
    } catch (_) {}

    return products;
  }

  Future<StationProductModel?> findByStationAndItem({
    required int stationId,
    required String itemType,
    String? rawMaterialId,
    int? fruitTypeId,
    String? productCode,
    String? productName,
  }) async {
    var query = _client.from(_table).select().eq('station_id', stationId);

    if (itemType.isNotEmpty) {
      query = query.eq('item_type', itemType);
    }

    if (itemType == 'material' && rawMaterialId != null && rawMaterialId.isNotEmpty) {
      query = query.eq('raw_material_id', rawMaterialId);
    } else if (itemType == 'fruit' && fruitTypeId != null) {
      query = query.eq('fruit_type_id', fruitTypeId);
    } else if (fruitTypeId != null) {
      query = query.eq('fruit_type_id', fruitTypeId);
    } else if (productCode != null && productCode.isNotEmpty) {
      query = query.eq('product_code', productCode);
    } else if (productName != null && productName.isNotEmpty) {
      query = query.eq('product_name', productName);
    }

    final data = await query.maybeSingle();
    if (data == null) return null;
    return StationProductModel.fromMap(data);
  }

  Future<StationProductModel?> findByStationAndProduct(
      int stationId, String productName,
      {String? productCode, int? fruitTypeId, String? rawMaterialId, String? itemType}) async {
    return findByStationAndItem(
      stationId: stationId,
      itemType: itemType ?? (fruitTypeId != null ? 'fruit' : 'material'),
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
      productCode: productCode,
      productName: productName,
    );
  }

  Future<void> upsertQuantity({
    required int stationId,
    required String productName,
    required String productCode,
    required num delta,
    int? fruitTypeId,
    String? rawMaterialId,
    String? itemType,
  }) async {
    final determinedType = itemType ?? (fruitTypeId != null ? 'fruit' : 'material');
    final response = await _client
        .from(_table)
        .select()
        .eq('station_id', stationId)
        .eq('product_name', productName)
        .maybeSingle();
        
    final existing = response != null ? StationProductModel.fromMap(response) : null;

    if (existing == null) {
      final newQty = delta > 0 ? delta : 0;
      if (newQty <= 0) return;
      final insertMap = <String, dynamic>{
        'station_id': stationId,
        'product_name': productName,
        'product_code': productCode,
        'quantity': newQty.toDouble(),
        'item_type': determinedType,
        'unit': determinedType == 'fruit' ? 'kg' : 'piece',
      };
      if (fruitTypeId != null) {
        insertMap['fruit_type_id'] = fruitTypeId;
      }
      if (rawMaterialId != null) {
        insertMap['raw_material_id'] = rawMaterialId;
      }
      await _client.from(_table).insert(insertMap);
    } else {
      final newQty = existing.quantity + delta;
      if (newQty <= 0) {
        await _client.from(_table).delete().eq('id', existing.id!);
      } else {
        final updateMap = <String, dynamic>{
          'quantity': newQty.toDouble(),
          'item_type': determinedType, // Fix any corrupted item_type
        };
        if (fruitTypeId != null) updateMap['fruit_type_id'] = fruitTypeId;
        if (rawMaterialId != null) updateMap['raw_material_id'] = rawMaterialId;
        
        await _client
            .from(_table)
            .update(updateMap)
            .eq('id', existing.id!);
      }
    }
  }

  Future<void> executeTransfer({
    required int fromStationId,
    required int toStationId,
    required String productCode,
    required String productName,
    required double quantity,
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    await upsertQuantity(
      stationId: fromStationId,
      productName: productName,
      productCode: productCode,
      delta: -quantity,
      itemType: itemType,
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
    );

    await upsertQuantity(
      stationId: toStationId,
      productName: productName,
      productCode: productCode,
      delta: quantity,
      itemType: itemType,
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
    );
  }

  Future<void> addProduct({
    required int stationId,
    required String productName,
    required String productCode,
    required double quantity,
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
  }) async {
    await upsertQuantity(
      stationId: stationId,
      productName: productName,
      productCode: productCode,
      delta: quantity,
      itemType: itemType,
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
    );
  }

  Future<void> delete(int id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<void> deleteByStationAndProduct(int stationId, String productName,
      {String? productCode, String? rawMaterialId, int? fruitTypeId, String? itemType}) async {
    final existing = await findByStationAndItem(
      stationId: stationId,
      itemType: itemType ?? (fruitTypeId != null ? 'fruit' : 'material'),
      rawMaterialId: rawMaterialId,
      fruitTypeId: fruitTypeId,
      productCode: productCode,
      productName: productName,
    );
    if (existing == null) return;
    await _client.from(_table).delete().eq('id', existing.id!);
    var batchQuery = _client
        .from('station_product_batches')
        .delete()
        .eq('station_id', stationId);

    if (rawMaterialId != null) {
      batchQuery = batchQuery.eq('raw_material_id', rawMaterialId);
    } else if (fruitTypeId != null) {
      batchQuery = batchQuery.eq('fruit_type_id', fruitTypeId);
    } else if (productCode != null && productCode.isNotEmpty) {
      batchQuery = batchQuery.eq('product_code', productCode);
    } else {
      batchQuery = batchQuery.eq('product_name', productName);
    }
    await batchQuery;
  }
}
