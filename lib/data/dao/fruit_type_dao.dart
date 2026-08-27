import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fruit_type_model.dart';

class FruitTypeDao {
  final _client = Supabase.instance.client;
  static const _table = 'fruit_types';

  Future<String> generateNextCode() async {
    try {
      final response = await _client.from(_table).select('code');
      int maxCode = 0;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxCode) maxCode = num;
      }
      return (maxCode + 1).toString();
    } catch (e) {
      return '1';
    }
  }

  FruitTypeModel _fromRow(Map<String, dynamic> row) {
    return FruitTypeModel.fromMap(row);
  }

  Future<List<FruitTypeModel>> getAll({String? search}) async {
    var query = _client.from(_table).select();
    if (search != null && search.isNotEmpty) {
      query = query.or('name.ilike.%$search%,code.ilike.%$search%');
    }
    final data = await query.order('name');
    return data.map(_fromRow).toList();
  }

  Future<Map<int, double>> getStockByFruitTypeId() async {
    try {
      final data = await _client.rpc('rpc_get_stock_by_fruit_type');
      final result = <int, double>{};
      for (final row in (data as List)) {
        final fruitTypeId = row['fruit_type_id'] as int?;
        final qty = (row['total_qty'] as num?)?.toDouble() ?? 0.0;
        if (fruitTypeId != null && qty > 0) {
          result[fruitTypeId] = qty;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<List<FruitTypeModel>> getAllWithPrices() async {
    try {
      final prices = await _client.from('latest_fruit_purchase_prices').select();
      final priceMapById = <String, Map<String, dynamic>>{};
      final priceMapByCode = <String, Map<String, dynamic>>{};
      final priceMapByName = <String, Map<String, dynamic>>{};
      for (final row in prices) {
        final id = row['fruit_type_id']?.toString() ?? row['id']?.toString();
        final code = row['code']?.toString();
        final name = row['name']?.toString() ?? row['product_name']?.toString();
        if (id != null && id.isNotEmpty) priceMapById[id] = row;
        if (code != null && code.isNotEmpty) priceMapByCode[code] = row;
        if (name != null && name.isNotEmpty) priceMapByName[name] = row;
      }

      final items = await _client.from(_table).select().order('name');
      return items.map((row) {
        final id = row['id']?.toString() ?? '';
        final code = row['code']?.toString() ?? '';
        final name = row['name']?.toString() ?? '';
        final priceData = priceMapById[id] ?? priceMapByCode[code] ?? priceMapByName[name];
        return FruitTypeModel.fromMap({
          ...row,
          if (priceData != null) 'latest_price': priceData['latest_price'],
          if (priceData != null) 'avg_price': priceData['avg_price'],
          if (priceData != null) 'last_purchase_date': priceData['last_purchase_date'],
          if (priceData != null && priceData['purchase_mode'] != null) 'purchase_mode': priceData['purchase_mode'],
          if (priceData != null) 'carton_count': priceData['carton_count'],
          if (priceData != null) 'weight_per_carton_kg': priceData['weight_per_carton_kg'],
          if (priceData != null) 'gross_weight_per_carton_kg': priceData['gross_weight_per_carton_kg'],
          if (priceData != null) 'price_per_carton': priceData['price_per_carton'],
          if (priceData != null) 'total_stock_quantity': priceData['total_stock_quantity'],
          if (priceData != null) 'total_stock_value': priceData['total_stock_value'],
        });
      }).toList();
    } catch (_) {
      return getAll();
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> getWarehouseDistribution() async {
    try {
      final batchesData = await _client
          .from('station_product_batches')
          .select('id, product_name, product_code, remaining_quantity, station_id, fruit_type_id, raw_material_id, item_type, source_type')
          .gt('remaining_quantity', 0);

      // Only include fruit batches (source_type=lot_receipt, fruit_type_id != null, or item_type=fruit)
      final fruitBatches = batchesData.where((b) {
        final itemType = b['item_type']?.toString();
        final rawMatId = b['raw_material_id']?.toString();
        final srcType = b['source_type']?.toString();
        if (itemType == 'material' || rawMatId != null) return false;
        if (srcType == 'lot_receipt' || srcType == 'crop_purchase' || itemType == 'fruit' || b['fruit_type_id'] != null) {
          return true;
        }
        return false;
      }).toList();

      final stationIds = <int>{};
      for (final row in fruitBatches) {
        final sid = row['station_id'] as int?;
        if (sid != null) stationIds.add(sid);
      }

      Map<int, String> stationNames = {};
      Map<int, String> stationCodes = {};
      if (stationIds.isNotEmpty) {
        try {
          final stationsData = await _client
              .from('stations')
              .select('id, name, code')
              .inFilter('id', stationIds.toList());
          for (final row in stationsData) {
            final id = row['id'] as int;
            stationNames[id] = row['name']?.toString() ?? '';
            stationCodes[id] = row['code']?.toString() ?? '';
          }
        } catch (_) {}
      }

      final result = <String, List<Map<String, dynamic>>>{};
      for (final row in fruitBatches) {
        final fruitId = row['fruit_type_id']?.toString();
        final productCode = row['product_code']?.toString() ?? '';
        final productName = row['product_name']?.toString() ?? '';
        final stationId = row['station_id'] as int? ?? 0;
        final qty = (row['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) continue;
        final entry = {
          'station_id': stationId,
          'station_name': stationNames[stationId] ?? 'محطة $stationId',
          'station_code': stationCodes[stationId] ?? '',
          'quantity': qty,
        };
        void addUnique(String key) {
          final list = result.putIfAbsent(key, () => []);
          if (!list.contains(entry)) {
            list.add(entry);
          }
        }

        if (fruitId != null && fruitId.isNotEmpty) {
          addUnique('fruit_$fruitId');
          addUnique(fruitId);
        }
        if (productName.isNotEmpty) {
          addUnique(productName);
          addUnique(productName.trim().toLowerCase());
        }
        if (productCode.isNotEmpty) {
          addUnique(productCode);
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getWarehouseDistributionForFruit(String fruitName, {String? fruitCode, int? fruitTypeId}) async {
    try {
      var query = _client
          .from('station_products')
          .select('product_name, product_code, quantity, station_id, item_type, fruit_type_id, stations(name, code)');

      if (fruitTypeId != null) {
        query = query.eq('fruit_type_id', fruitTypeId);
      } else if (fruitCode != null && fruitCode.isNotEmpty) {
        query = query.eq('product_code', fruitCode);
      } else {
        query = query.eq('product_name', fruitName);
      }

      final data = await query.gt('quantity', 0);
      return data.map((row) {
        final station = row['stations'];
        return {
          'station_id': row['station_id'],
          'station_name': station is Map ? (station['name']?.toString() ?? '') : '',
          'station_code': station is Map ? (station['code']?.toString() ?? '') : '',
          'quantity': (row['quantity'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<FruitTypeModel?> getById(String id) async {
    final data = await _client.from(_table).select().eq('id', int.tryParse(id) ?? id).maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<String> insert(FruitTypeModel item) async {
    final result = await _client.from(_table).insert(item.toMap()).select().single();
    return result['id']?.toString() ?? '';
  }

  Future<void> update(FruitTypeModel item) async {
    await _client.from(_table).update(item.toMap()).eq('id', int.tryParse(item.id!) ?? item.id!);
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', int.tryParse(id) ?? id);
  }

  Future<String> generateCode() async {
    try {
      final response = await _client.from(_table).select('code');
      int maxCode = 0;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxCode) maxCode = num;
      }
      return (maxCode + 1).toString();
    } catch (e) {
      return '1';
    }
  }

  Future<List<FruitTypeModel>> getLatestPrices() async {
    try {
      final data = await _client.from('latest_fruit_purchase_prices').select();
      return data.map((row) {
        return FruitTypeModel.fromMap({
          ...row,
          'latest_price': row['latest_price'],
          'avg_price': row['avg_price'],
          'last_purchase_date': row['last_purchase_date'],
          'purchase_mode': row['purchase_mode'],
          'carton_count': row['carton_count'],
          'weight_per_carton_kg': row['weight_per_carton_kg'],
          'gross_weight_per_carton_kg': row['gross_weight_per_carton_kg'],
          'price_per_carton': row['price_per_carton'],
          'total_stock_quantity': row['total_stock_quantity'],
          'total_stock_value': row['total_stock_value'],
        });
      }).toList();
    } catch (_) {
      return getAll();
    }
  }

  Future<int> getCount() async {
    final response = await _client.from(_table).select().count(CountOption.exact);
    return response.count;
  }
}
