import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../models/packing_order_model.dart';
import '../models/packing_order_line_model.dart';
import '../services/cost_calculation_engine.dart';
import '../services/currency_conversion_service.dart';
import 'financial_audit_log_dao.dart';

class PackingOrderDao {
  final _client = Supabase.instance.client;

  Future<List<PackingOrderModel>> getAll({
    String? status,
    int? lotId,
    int? shipmentId,
  }) async {
    try {
      var query = _client.from('packing_orders').select(
          '*, lot_receipts(lot_number, suppliers(name))');

      if (status != null) query = query.eq('status', status);
      if (lotId != null) query = query.eq('lot_id', lotId);
      if (shipmentId != null) {
        query = query.eq('export_shipment_id', shipmentId);
      }

      final data = await query.order('created_at', ascending: false);
      final list = (data as List);
      if (list.isEmpty) return [];

      final poIds = list
          .map((e) => (e as Map)['id'] as int?)
          .whereType<int>()
          .toList();
      final Map<int, List<Map<String, dynamic>>> linesByOrderId = {};
      try {
        if (poIds.isNotEmpty) {
          final linesData = await _client
              .from('packing_order_lines')
              .select()
              .inFilter('packing_order_id', poIds);
          for (final l in linesData) {
            final pId = l['packing_order_id'] as int?;
            if (pId != null) {
              linesByOrderId
                  .putIfAbsent(pId, () => [])
                  .add(Map<String, dynamic>.from(l as Map));
            }
          }
        }
      } catch (lineErr) {
        debugPrint('⚠️ PackingOrderDao.getAll lines batch load fallback: $lineErr');
      }

      return list.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final lot = AppUtils.asMap(row.remove('lot_receipts'));
        final supplier = AppUtils.asMap(lot?['suppliers']);
        final pId = row['id'] as int?;
        if (pId != null && linesByOrderId.containsKey(pId)) {
          row['packing_order_lines'] = linesByOrderId[pId];
        }
        return PackingOrderModel.fromMap({
          ...row,
          'lot_number': lot?['lot_number'],
          'supplier_name': supplier?['name'] as String?,
        });
      }).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getAll error: $e\n$st');
      rethrow;
    }
  }

  /// Get packing orders linked to a shipment via export_shipment_items.packing_order_id
  /// This supports many-to-many: same packing order can appear in multiple shipments
  Future<List<PackingOrderModel>> getByShipmentIdViaItems(
      int shipmentId) async {
    try {
      final itemsData = await _client
          .from('export_shipment_items')
          .select('packing_order_id')
          .eq('shipment_id', shipmentId)
          .not('packing_order_id', 'is', null);

      final poIds = itemsData
          .map((e) => e['packing_order_id'] as int?)
          .where((id) => id != null)
          .toSet()
          .toList();

      if (poIds.isEmpty) return [];

      final data = await _client
          .from('packing_orders')
          .select('*, lot_receipts(lot_number, suppliers(name))')
          .inFilter('id', poIds)
          .order('created_at', ascending: false);

      return data.map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        final lot = AppUtils.asMap(row.remove('lot_receipts'));
        final supplier = AppUtils.asMap(lot?['suppliers']);
        return PackingOrderModel.fromMap({
          ...row,
          'lot_number': lot?['lot_number'],
          'supplier_name': supplier?['name'] as String?,
        });
      }).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getByShipmentIdViaItems error: $e\n$st');
      return [];
    }
  }

  Future<List<String>> getUsedLotIds() async {
    try {
      final data = await _client.from('packing_orders').select('lot_id');
      return data.map((e) => e['lot_id'].toString()).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getUsedLotIds error: $e\n$st');
      return [];
    }
  }

  Future<int> insert(PackingOrderModel order) async {
    try {
      final countResult = await _client
          .from('packing_orders')
          .select('id')
          .count(CountOption.exact);
      final nextNum = countResult.count + 1;
      final orderNum = nextNum.toString();
      final insertData = {
        ...order.toMap(),
        'order_number': orderNum,
        'currency_snapshot': CurrencyConversionService.instance
            .createSnapshot(
              currency: order.displayCurrency,
              amount: order.totalPackingCost,
              exchangeRate: order.displayExchangeRate,
            )
            .toJson(),
      };
      final result = await _client
          .from('packing_orders')
          .insert(insertData)
          .select('id')
          .single();
      final insertedId = result['id'] as int;
      await _syncCostItemsToTable(insertedId, order.notes);
      // Save lines if present
      if (order.lines.isNotEmpty) {
        await _saveLines(insertedId, order.lines);
      }
      return insertedId;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateStatus(int id, String status) async {
    try {
      final update = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == 'completed') {
        update['packed_at'] = DateTime.now().toIso8601String();
      }
      await _client.from('packing_orders').update(update).eq('id', id);

      final existing = await _client
          .from('packing_orders')
          .select('notes')
          .eq('id', id)
          .maybeSingle();
      if (existing != null) {
        await _syncCostItemsToTable(id, existing['notes']?.toString());
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateStatus error: $e\n$st');
      rethrow;
    }
  }

  Future<void> update(int id, PackingOrderModel order) async {
    try {
      final data = {...order.toMap()};
      data.remove('id');
      data['updated_at'] = DateTime.now().toIso8601String();
      await _client.from('packing_orders').update(data).eq('id', id);
      await _syncCostItemsToTable(id, order.notes);
      // Save lines if present
      if (order.lines.isNotEmpty) {
        await _saveLines(id, order.lines);
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.update error: $e\n$st');
      rethrow;
    }
  }

  Future<PackingOrderModel?> getById(int id) async {
    try {
      final data = await _client
          .from('packing_orders')
          .select('*, lot_receipts(lot_number, suppliers(name))')
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;
      final row = Map<String, dynamic>.from(data as Map);
      try {
        final lines = await getLines(id);
        row['packing_order_lines'] = lines.map((l) => l.toMap()).toList();
      } catch (_) {}

      final lot = AppUtils.asMap(row.remove('lot_receipts'));
      final supplier = AppUtils.asMap(lot?['suppliers']);
      return PackingOrderModel.fromMap({
        ...row,
        'lot_number': lot?['lot_number'],
        'supplier_name': supplier?['name'] as String?,
      });
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<void> refreshPrices(int id) async {
    try {
      await _client
          .rpc('rpc_refresh_packing_order_prices', params: {'p_order_id': id});
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.refreshPrices error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateCosting(
      int id, double packingCostPerCarton, double totalPackingCost) async {
    try {
      await _client.from('packing_orders').update({
        'packing_cost_per_carton': packingCostPerCarton,
        'total_packing_cost': totalPackingCost,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      await FinancialAuditLogDao().logUpdate(
        tableName: 'packing_orders',
        recordId: id.toString(),
        oldSnapshot: {},
        newSnapshot: {
          'packing_cost_per_carton': packingCostPerCarton,
          'total_packing_cost': totalPackingCost,
        },
        reason: 'Packing order costing updated',
      );
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateCosting error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateFruitCost(int id, double fruitCostAllocated) async {
    try {
      await _client.from('packing_orders').update({
        'fruit_cost_allocated': fruitCostAllocated,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateFruitCost error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateMaterialCost(
      int id, double actualCost, double estimatedCost) async {
    try {
      await _client.from('packing_orders').update({
        'actual_material_cost': actualCost,
        'estimated_material_cost': estimatedCost,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateMaterialCost error: $e\n$st');
      rethrow;
    }
  }

  /// Update cost breakdown with full currency context — uses CostCalculationEngine.
  Future<void> updateCostBreakdown({
    required int id,
    required CostBreakdown breakdown,
  }) async {
    try {
      final cs = CurrencyConversionService.instance;
      final displayRate = await cs.getRate(breakdown.displayCurrency);
      await _client.from('packing_orders').update({
        'fruit_cost_base': breakdown.totalFruitBase,
        'material_cost_base': breakdown.totalMaterialBase,
        'other_cost_base': breakdown.totalOtherBase,
        'fruit_cost_allocated': breakdown.totalFruitBase,
        'actual_material_cost': breakdown.totalMaterialBase,
        'display_currency': breakdown.displayCurrency,
        'display_exchange_rate': displayRate,
        'total_packing_cost': breakdown.totalBase,
        'currency_snapshot': CurrencyConversionService.instance
            .createSnapshot(
              currency: breakdown.displayCurrency,
              amount: breakdown.totalBase,
              exchangeRate: displayRate,
            )
            .toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      await FinancialAuditLogDao().logUpdate(
        tableName: 'packing_orders',
        recordId: id.toString(),
        oldSnapshot: {},
        newSnapshot: {
          'fruit_cost_base': breakdown.totalFruitBase,
          'material_cost_base': breakdown.totalMaterialBase,
          'other_cost_base': breakdown.totalOtherBase,
          'total_packing_cost': breakdown.totalBase,
          'display_currency': breakdown.displayCurrency,
        },
        reason: 'Packing order cost breakdown updated',
      );
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateCostBreakdown error: $e\n$st');
      rethrow;
    }
  }

  /// Insert a cost line item for a packing order.
  Future<void> insertCostItem({
    required int packingOrderId,
    required String name,
    required String category,
    required String originalCurrency,
    required double originalAmount,
    required double exchangeRate,
    required double baseAmount,
    int? reportCategoryId,
  }) async {
    try {
      await _client.from('packing_order_cost_items').insert({
        'packing_order_id': packingOrderId,
        'name': name,
        'category': category,
        'report_category_id': reportCategoryId,
        'original_currency': originalCurrency,
        'original_amount': originalAmount,
        'exchange_rate': exchangeRate,
        'base_amount': baseAmount,
        'expected_amount': baseAmount,
        'cost_status': 'expected',
        'currency_snapshot': CurrencyConversionService.instance
            .createSnapshot(
              currency: originalCurrency,
              amount: originalAmount,
              exchangeRate: exchangeRate,
            )
            .toJson(),
      });
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.insertCostItem error: $e\n$st');
      rethrow;
    }
  }

  /// Delete all cost items for a packing order (before re-inserting).
  Future<void> deleteCostItems(int packingOrderId) async {
    try {
      await _client
          .from('packing_order_cost_items')
          .delete()
          .eq('packing_order_id', packingOrderId);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.deleteCostItems error: $e\n$st');
      rethrow;
    }
  }

  /// Fetch all cost items for a packing order.
  Future<List<CostLineItem>> getCostItems(int packingOrderId) async {
    try {
      final data = await _client
          .from('packing_order_cost_items')
          .select('*, cost_report_categories(name)')
          .eq('packing_order_id', packingOrderId)
          .isFilter('deleted_at', null)
          .order('id');
      return data.map((row) {
        return CostLineItem(
          name: row['name'] as String,
          amount: CurrencyAmount(
            originalAmount: (row['original_amount'] as num).toDouble(),
            originalCurrency: row['original_currency'] as String,
            exchangeRate: (row['exchange_rate'] as num).toDouble(),
            baseAmount: (row['base_amount'] as num).toDouble(),
          ),
          category: row['category'] as String,
          reportCategoryId: row['report_category_id'] as int?,
          reportCategoryName: row['cost_report_categories'] != null
              ? (row['cost_report_categories'] as Map)['name']?.toString()
              : null,
        );
      }).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getCostItems error: $e\n$st');
      return [];
    }
  }

  Future<List<PackingOrderModel>> getAvailableForShipment() async {
    try {
      // جلب كافة أوامر التعبئة المعتمدة نهائياً بصرف النظر عن تطابق العميل
      List<dynamic> data;
      try {
        data = await _client
            .from('packing_orders')
            .select('*, lot_receipts(lot_number, suppliers(name))')
            .or('status.in.(final_approved,completed,confirmed),final_approved_at.not.is.null')
            .neq('status', 'cancelled')
            .neq('status', 'returned')
            .order('created_at', ascending: false);
      } catch (_) {
        data = await _client
            .from('packing_orders')
            .select('*, lot_receipts(lot_number, suppliers(name))')
            .inFilter('status', ['final_approved', 'completed', 'confirmed'])
            .order('created_at', ascending: false);
      }

      final orderRows = data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final poIds = orderRows
          .map((r) => (r['id'] as num?)?.toInt())
          .whereType<int>()
          .toList();

      final Map<int, List<Map<String, dynamic>>> linesByOrderId = {};
      if (poIds.isNotEmpty) {
        try {
          final dbLines = await _client
              .from('packing_order_lines')
              .select()
              .inFilter('packing_order_id', poIds);
          for (final l in (dbLines as List)) {
            final lMap = Map<String, dynamic>.from(l as Map);
            final poId = (lMap['packing_order_id'] as num?)?.toInt();
            if (poId != null) {
              linesByOrderId.putIfAbsent(poId, () => []).add(lMap);
            }
          }
        } catch (_) {}
      }

      return buildAvailableForShipmentList(
        orderRows,
        linesByOrderId: linesByOrderId,
      );
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getAvailableForShipment error: $e\n$st');
      rethrow;
    }
  }

  /// يبني قائمة أوامر التعبئة المؤهلة للشحن من صفوف الرأس والسطور:
  /// الشرط الوحيد هو وصول الأمر لحالة الاعتماد النهائي ووجود رصيد كراتين متبقٍ > 0،
  /// دون أي تقييد أو اشتراط لتطابق حقل العميل.
  static List<PackingOrderModel> buildAvailableForShipmentList(
    List<Map<String, dynamic>> orderRows, {
    Map<int, List<Map<String, dynamic>>> linesByOrderId = const {},
  }) {
    final List<PackingOrderModel> result = [];

    for (final rawRow in orderRows) {
      final row = Map<String, dynamic>.from(rawRow);
      final lot = AppUtils.asMap(row.remove('lot_receipts'));
      final supplier = AppUtils.asMap(lot?['suppliers']);
      final inlineLines = row.remove('packing_order_lines');

      final headerProbe = PackingOrderModel.fromMap(row);
      final normalizedStatus = headerProbe.status.trim().toLowerCase();
      if (normalizedStatus == 'cancelled' ||
          normalizedStatus == 'returned' ||
          !headerProbe.isFinalApproved) {
        continue;
      }

      final poId = (row['id'] as num?)?.toInt();
      final List<Map<String, dynamic>> lines;
      if (inlineLines is List) {
        lines = inlineLines
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else if (poId != null && linesByOrderId.containsKey(poId)) {
        lines = linesByOrderId[poId]!;
      } else {
        lines = const [];
      }

      if (lines.length > 1) {
        // Multi-product order: expand each line into a separate entry
        for (final line in lines) {
          final lineSoldCartons =
              (line['sold_cartons'] as num?)?.toInt() ?? 0;
          final lineCartonCount =
              (line['carton_count'] as num?)?.toInt() ?? 0;
          final lineRemaining = lineCartonCount - lineSoldCartons;
          if (lineRemaining <= 0) continue;

          final finalCost = (line['final_cost'] as num?)?.toDouble() ?? 0.0;
          final headerCost =
              (row['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
          final costPerCarton = (finalCost > 0 && lineCartonCount > 0)
              ? finalCost / lineCartonCount
              : (headerCost > 0
                  ? headerCost
                  : ((line['final_unit_cost'] as num?)?.toDouble() ?? 0.0));

          final po = PackingOrderModel.fromMap({
            ...row,
            // Override with line-specific data
            'product_name': line['product_name'] ?? row['product_name'],
            'fruit_type_id': line['fruit_type_id'] ?? row['fruit_type_id'],
            'grade': line['grade'] ?? row['grade'],
            'carton_count': lineCartonCount,
            'sold_cartons': lineSoldCartons,
            'net_weight_per_carton':
                line['net_weight_per_carton'] ?? row['net_weight_per_carton'],
            'gross_weight_per_carton': line['gross_weight_per_carton'] ??
                row['gross_weight_per_carton'],
            'total_net_weight': line['total_net_weight'] ??
                (lineCartonCount *
                    ((line['net_weight_per_carton'] as num?)?.toDouble() ?? 0)),
            'total_gross_weight': line['total_gross_weight'] ??
                (lineCartonCount *
                    ((line['gross_weight_per_carton'] as num?)?.toDouble() ??
                        0)),
            'packing_cost_per_carton': costPerCarton,
            'batch_id': line['batch_id'] ?? row['batch_id'],
            'lot_number': lot?['lot_number'],
            'supplier_name': supplier?['name'] as String?,
            'line_id': line['id'],
          });
          if (po.hasStock) result.add(po);
        }
      } else {
        // Single-product order
        final line = lines.isNotEmpty ? lines[0] : null;
        final int lineCartonCount =
            line != null ? ((line['carton_count'] as num?)?.toInt() ?? 0) : 0;
        final int lineSoldCartons =
            line != null ? ((line['sold_cartons'] as num?)?.toInt() ?? 0) : 0;
        final finalCost = line != null
            ? ((line['final_cost'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final headerCost =
            (row['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;

        final effectiveSoldCartons = lineSoldCartons > 0
            ? lineSoldCartons
            : ((row['sold_cartons'] as num?)?.toInt() ?? 0);
        final effectiveCartonCount = lineCartonCount > 0
            ? lineCartonCount
            : ((row['carton_count'] as num?)?.toInt() ?? 0);

        if (effectiveCartonCount - effectiveSoldCartons <= 0) continue;

        final effectiveCostCount =
            lineCartonCount > 0 ? lineCartonCount : effectiveCartonCount;
        final costPerCarton = (finalCost > 0 && effectiveCostCount > 0)
            ? finalCost / effectiveCostCount
            : (headerCost > 0
                ? headerCost
                : (line != null
                    ? ((line['final_unit_cost'] as num?)?.toDouble() ?? 0.0)
                    : 0.0));

        final po = PackingOrderModel.fromMap({
          ...row,
          if (line != null) ...{
            if (line['product_name'] != null)
              'product_name': line['product_name'],
            if (line['fruit_type_id'] != null)
              'fruit_type_id': line['fruit_type_id'],
            if (line['grade'] != null) 'grade': line['grade'],
            if (line['net_weight_per_carton'] != null)
              'net_weight_per_carton': line['net_weight_per_carton'],
            if (line['gross_weight_per_carton'] != null)
              'gross_weight_per_carton': line['gross_weight_per_carton'],
            if (line['batch_id'] != null) 'batch_id': line['batch_id'],
          },
          'carton_count': effectiveCartonCount,
          'sold_cartons': effectiveSoldCartons,
          'packing_cost_per_carton': costPerCarton,
          'lot_number': lot?['lot_number'],
          'supplier_name': supplier?['name'] as String?,
          'line_id': line?['id'],
        });
        if (po.hasStock) result.add(po);
      }
    }

    return result;
  }

  /// يرشح قائمة أوامر التعبئة المعروضة في قائمة الاختيار داخل شاشة الشحنة
  /// باستبعاد البنود المضافة مسبقاً وتطبيق نص البحث فقط (دون فلتر للعميل).
  static List<PackingOrderModel> filterAvailableOrdersForSelector({
    required List<PackingOrderModel> orders,
    Set<String> excludedSelectionKeys = const {},
    String pattern = '',
  }) {
    final available = orders.where((po) {
      if (!po.hasStock) return false;
      final key = po.lineId != null ? 'line_${po.lineId}' : 'po_${po.id}';
      return !excludedSelectionKeys.contains(key);
    }).toList();

    final query = pattern.trim().toLowerCase();
    if (query.isEmpty) return available;

    return available.where((po) {
      return (po.productName?.toLowerCase().contains(query) ?? false) ||
          po.orderNumber.toLowerCase().contains(query) ||
          (po.exportShipmentNo?.toLowerCase().contains(query) ?? false) ||
          (po.customerName?.toLowerCase().contains(query) ?? false) ||
          (po.lotNumber?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> linkToShipment(int packingOrderId, int shipmentId) async {
    try {
      await _client.from('packing_orders').update({
        'export_shipment_id': shipmentId,
      }).eq('id', packingOrderId);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.linkToShipment error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateSoldCartons(
      int packingOrderId, int additionalCartons) async {
    try {
      await _client.rpc('increment_sold_cartons', params: {
        'p_packing_order_id': packingOrderId,
        'p_additional': additionalCartons,
      });
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateSoldCartons error: $e\n$st');
      rethrow;
    }
  }

  Future<void> restoreSoldCartons(int packingOrderId, int cartons) async {
    try {
      await _client.rpc('decrement_sold_cartons', params: {
        'p_packing_order_id': packingOrderId,
        'p_amount': cartons,
      });
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.restoreSoldCartons error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.from('packing_orders').delete().eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.delete error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> isUsedInShipment(int packingOrderId) async {
    try {
      final data = await _client
          .from('export_shipment_items')
          .select('id')
          .eq('packing_order_id', packingOrderId)
          .limit(1);
      return data.isNotEmpty;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.isUsedInShipment error: $e\n$st');
      return false;
    }
  }

  Future<Set<int>> getOrdersUsedInShipments() async {
    try {
      final data = await _client
          .from('export_shipment_items')
          .select('packing_order_id')
          .not('packing_order_id', 'is', null);
      return data.map((e) => e['packing_order_id'] as int).toSet();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getOrdersUsedInShipments error: $e\n$st');
      return {};
    }
  }

  Future<Set<int>> getOrdersWithSoldSorting() async {
    try {
      final data = await _client
          .from('packing_order_sortings')
          .select('packing_order_id')
          .or('status.eq.sold,total_sale_amount.gt.0');
      return data.map((e) => e['packing_order_id'] as int).toSet();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getOrdersWithSoldSorting error: $e\n$st');
      return {};
    }
  }

  /// Get packing order IDs linked to shipments whose profits have already been distributed
  Future<Set<int>> getOrdersWithDistributedShipments() async {
    try {
      final res = await _client.rpc('rpc_get_orders_with_distributed_shipments');
      if (res is List) {
        return res.map((e) => (e as num).toInt()).toSet();
      }
      return {};
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getOrdersWithDistributedShipments error: $e\n$st');
      return {};
    }
  }

  Future<String?> confirmOrder(int packingOrderId) async {
    try {
      final result = await _client.rpc('rpc_confirm_packing_order', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        debugPrint('═══════════════════════════════════════════');
        debugPrint('PackingOrderDao.confirmOrder — SUCCESS');
        debugPrint('  PackingOrder ID = $packingOrderId');
        debugPrint('  Created JournalEntry ID = ${map['journal_entry_id']}');
        debugPrint('  Total Final Cost = ${map['total_final_cost']}');
        debugPrint('  Total Raw Cost = ${map['total_raw_cost']}');
        debugPrint('  Total Packaging Cost = ${map['total_packaging_cost']}');
        debugPrint('  Total Overhead = ${map['total_overhead']}');
        debugPrint('  Lines Count = ${map['lines_count']}');
        debugPrint('  DR = ${map['debit']}, CR = ${map['credit']}');
        debugPrint('═══════════════════════════════════════════');

        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();

        return null;
      }
      debugPrint('═══════════════════════════════════════════');
      debugPrint('PackingOrderDao.confirmOrder — FAILED');
      debugPrint('  PackingOrder ID = $packingOrderId');
      debugPrint('  Error = ${map?['error']}');
      debugPrint('═══════════════════════════════════════════');
      return map?['error']?.toString() ?? 'فشل في تأكيد أمر التعبئة';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.confirmOrder error: $e\n$st');
      return e.toString();
    }
  }

  Future<String?> cancelOrder(int packingOrderId) async {
    try {
      final result = await _client.rpc('rpc_cancel_packing_order', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        // بنود التكلفة تبقى كما هي في حساب المورد عند الإلغاء
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return null;
      }
      return map?['error']?.toString() ?? 'فشل في إلغاء أمر التعبئة';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.cancelOrder error: $e\n$st');
      return e.toString();
    }
  }

  static final Set<int> _activeCostSyncOrderIds = {};
  static final Set<int> _activeConfirmCostIds = {};

  Future<void> _syncCostItemsToTable(int orderId, String? notes) async {
    if (_activeCostSyncOrderIds.contains(orderId)) {
      debugPrint('⏳ _syncCostItemsToTable already in progress for order $orderId, skipping duplicate execution.');
      return;
    }
    _activeCostSyncOrderIds.add(orderId);

    try {
      if (notes == null || notes.isEmpty) {
        await _client
            .from('packing_order_cost_items')
            .delete()
            .eq('packing_order_id', orderId);
        return;
      }

      Map<String, dynamic>? notesMap;
      try {
        notesMap = jsonDecode(notes) as Map<String, dynamic>;
      } catch (_) {}

      if (notesMap == null || !notesMap.containsKey('cost_items')) {
        await _client
            .from('packing_order_cost_items')
            .delete()
            .eq('packing_order_id', orderId);
        return;
      }

      final costItems = notesMap['cost_items'];
      if (costItems is! List || costItems.isEmpty) {
        await _client
            .from('packing_order_cost_items')
            .delete()
            .eq('packing_order_id', orderId);
        return;
      }

      // ── Step 1: In-memory Deduplication (Strictly by ID/UUID, Never by name+amount) ──
      final Map<String, Map<String, dynamic>> canonicalCostMap = {};
      for (final item in costItems) {
        if (item is! Map) continue;
        final rawItem = Map<String, dynamic>.from(item);
        final rawAmt = (rawItem['total_egp'] ?? rawItem['base_amount'] ?? rawItem['total'] ?? 0) as num;
        if (rawAmt <= 0) continue; // Defense-in-depth: Skip zero-amount or ghost cost items!

        // Ensure every item has a unique item_uuid
        if (rawItem['item_uuid'] == null || rawItem['item_uuid'].toString().trim().isEmpty) {
          final rawId = (rawItem['id'] as num?)?.toInt();
          if (rawId != null && rawId > 0 && rawId < 1000000000) {
            rawItem['item_uuid'] = 'item_$rawId';
          } else {
            rawItem['item_uuid'] = const Uuid().v4();
          }
        }

        final itemUuid = rawItem['item_uuid']!.toString();
        final rawId = (rawItem['id'] as num?)?.toInt();
        final sig = (rawId != null && rawId > 0 && rawId < 1000000000)
            ? 'id_$rawId'
            : 'uuid_$itemUuid';

        if (!canonicalCostMap.containsKey(sig)) {
          canonicalCostMap[sig] = rawItem;
        } else {
          final existing = canonicalCostMap[sig]!;
          final incomingSettled = (rawItem['cost_status'] == 'actual' && rawItem['actual_amount'] != null) ||
              rawItem['variance_journal_entry_id'] != null;
          final existingSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
              existing['variance_journal_entry_id'] != null;
          if (incomingSettled && !existingSettled) {
            if ((rawItem['notes'] == null || rawItem['notes'].toString().isEmpty) &&
                existing['notes'] != null && existing['notes'].toString().isNotEmpty) {
              rawItem['notes'] = existing['notes'];
            }
            if ((rawItem['supplier_id'] == null || rawItem['supplier_id'].toString().isEmpty) &&
                existing['supplier_id'] != null && existing['supplier_id'].toString().isNotEmpty) {
              rawItem['supplier_id'] = existing['supplier_id'];
            }
            if ((rawItem['supplier_name'] == null || rawItem['supplier_name'].toString().isEmpty) &&
                existing['supplier_name'] != null && existing['supplier_name'].toString().isNotEmpty) {
              rawItem['supplier_name'] = existing['supplier_name'];
            }
            canonicalCostMap[sig] = rawItem;
          } else {
            if ((existing['notes'] == null || existing['notes'].toString().isEmpty) &&
                rawItem['notes'] != null && rawItem['notes'].toString().isNotEmpty) {
              existing['notes'] = rawItem['notes'];
            }
            if ((existing['supplier_id'] == null || existing['supplier_id'].toString().isEmpty) &&
                rawItem['supplier_id'] != null && rawItem['supplier_id'].toString().isNotEmpty) {
              existing['supplier_id'] = rawItem['supplier_id'];
            }
            if ((existing['supplier_name'] == null || existing['supplier_name'].toString().isEmpty) &&
                rawItem['supplier_name'] != null && rawItem['supplier_name'].toString().isNotEmpty) {
              existing['supplier_name'] = rawItem['supplier_name'];
            }
          }
        }
      }
      final uniqueCostItems = canonicalCostMap.values.toList();

      // ── Step 2: Prepare Batch Rows ──
      // Defensively fetch valid cost_report_categories IDs to guarantee no FK violations
      Set<int> validReportCatIds = {};
      try {
        final catRows = await _client.from('cost_report_categories').select('id');
        validReportCatIds = (catRows as List)
            .map((r) => (r['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
      } catch (e) {
        debugPrint('⚠️ PackingOrderDao._syncCostItemsToTable: Error fetching valid category IDs: ');
      }

      final rowsToInsert = <Map<String, dynamic>>[];
      for (final item in uniqueCostItems) {
        final name = item['name']?.toString() ?? 'بند تكلفة';
        final categoryStr = item['category']?.toString() ?? 'other';
        final originalCurrency = item['supplier_currency']?.toString() ?? 'EGP';

        final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final exchangeRate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;

        final originalAmount = (item['total'] as num?)?.toDouble() ??
            (originalCurrency == 'EGP'
                ? qty * unitPrice
                : (exchangeRate > 0
                    ? (qty * unitPrice) / exchangeRate
                    : qty * unitPrice));

        final baseAmount =
            (item['total_egp'] as num?)?.toDouble() ?? (qty * unitPrice);

        final rawReportCatId = (item['report_category_id'] as num?)?.toInt();
        final reportCategoryId = (rawReportCatId != null && validReportCatIds.contains(rawReportCatId))
            ? rawReportCatId
            : null;

        String mappedCategory = 'other';
        final lowerCat = categoryStr.toLowerCase();
        if (lowerCat.contains('محصول') || lowerCat.contains('fruit')) {
          mappedCategory = 'fruit';
        } else if (lowerCat.contains('تعبئة') ||
            lowerCat.contains('packing') ||
            lowerCat.contains('material')) {
          mappedCategory = 'material';
        } else if (lowerCat.contains('نقل') || 
                   lowerCat.contains('logistics') || 
                   lowerCat.contains('شحن') || 
                   lowerCat.contains('تفريغ') || 
                   lowerCat.contains('نولون')) {
          mappedCategory = 'logistics';
        } else if (lowerCat.contains('إدار') || lowerCat.contains('ادار') || lowerCat == 'admin') {
          mappedCategory = 'admin';
        } else if (lowerCat.contains('مهندس') || lowerCat.contains('engineer')) {
          mappedCategory = 'engineer_expenses';
        } else {
          mappedCategory = 'other';
        }

        final currencySnapshot = {
          ...CurrencyConversionService.instance
              .createSnapshot(
                currency: originalCurrency,
                amount: originalAmount,
                exchangeRate: exchangeRate,
              )
              .toJson(),
          'supplier_id': item['supplier_id'],
          'supplier_name': item['supplier_name'],
          'supplier_type': item['supplier_type'],
          'item_uuid': item['item_uuid'],
          'category': item['category'],
          'category_name': item['category_name'],
          'quantity': qty,
          'unit_price': unitPrice,
          'total': originalAmount,
          'total_egp': baseAmount,
          'supplier_currency': originalCurrency,
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_index': item['target_line_index'],
          'notes': item['notes'],
          'engineer_name': item['engineer_name'],
          'is_engineer_cost_settled': item['is_engineer_cost_settled'],
          'allocation_type': item['allocation_type'],
          'allocation_percentage': item['allocation_percentage'],
          'pool_total_spent': item['pool_total_spent'],
          'pool_total_allocated': item['pool_total_allocated'],
          'pool_remaining_pool': item['pool_remaining_pool'],
        };

        final bool isEng = item['category'] == 'engineer_expenses' ||
            item['category'] == 'engineer' ||
            item['supplier_type'] == 'engineer' ||
            name.toLowerCase().contains('مهندس') ||
            item['custody_id'] != null;
        final bool isAdminItem = item['category'] == 'admin' ||
            item['supplier_type'] == 'admin' ||
            mappedCategory == 'admin' ||
            name.toLowerCase().contains('إدار') ||
            name.toLowerCase().contains('ادار');
        final bool isAdminSettled = isAdminItem &&
            (item['cost_status'] == 'settled' || item['reconciled_at'] != null || item['variance_journal_entry_id'] != null) &&
            item['actual_amount'] != null;
        final effectiveCostStatus = isEng
            ? 'actual'
            : (isAdminItem
                ? (isAdminSettled ? 'actual' : 'expected')
                : (item['cost_status'] ?? 'expected'));
        final effectiveActualAmount = isEng
            ? ((item['actual_amount'] as num?)?.toDouble() ?? baseAmount)
            : (isAdminItem
                ? (isAdminSettled ? (item['actual_amount'] as num).toDouble() : null)
                : (item['actual_amount'] != null ? (item['actual_amount'] as num).toDouble() : null));

        rowsToInsert.add({
          'packing_order_id': orderId,
          'name': name,
          'category': mappedCategory,
          'report_category_id': reportCategoryId,
          'original_currency': originalCurrency,
          'original_amount': originalAmount,
          'exchange_rate': exchangeRate,
          'base_amount': baseAmount,
          'expected_amount': (item['expected_amount'] as num?)?.toDouble() ?? baseAmount,
          'cost_status': effectiveCostStatus,
          if (effectiveActualAmount != null) 'actual_amount': effectiveActualAmount,
          if (item['variance_amount'] != null) 'variance_amount': (item['variance_amount'] as num).toDouble(),
          if (item['variance_journal_entry_id'] != null) 'variance_journal_entry_id': item['variance_journal_entry_id'],
          if (item['supplier_id'] != null) 'supplier_id': item['supplier_id'].toString(),
          'currency_snapshot': currencySnapshot,
          'payment_source_type': item['payment_source_type'],
          'payment_source_id': item['payment_source_id'],
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_id': item['target_line_id'],
          'settlement_notes': item['notes'] ?? item['settlement_notes'],
          if (item['engineer_name'] != null || isEng) 'engineer_name': item['engineer_name'] ?? 'مجمع عهد الموظفين',
          'is_engineer_cost_settled': isEng ? true : (item['is_engineer_cost_settled'] ?? false),
        });
      }

      // ── Step 3: Smart Reconciliation & Upsert (Never blindly insert duplicates) ──
      List<Map<String, dynamic>> existingDbRows = [];
      try {
        final dbRes = await _client
            .from('packing_order_cost_items')
            .select('*')
            .eq('packing_order_id', orderId)
            .isFilter('deleted_at', null)
            .gt('base_amount', 0)
            .order('id');
        existingDbRows = (dbRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        debugPrint('⚠️ _syncCostItemsToTable: Error reading existing DB rows: $e');
      }

      final Set<int> matchedDbIds = {};

      for (int i = 0; i < rowsToInsert.length; i++) {
        final rowPayload = rowsToInsert[i];
        final sourceItem = uniqueCostItems[i];
        final sourceId = (sourceItem['id'] as num?)?.toInt();
        final sourceUuid = sourceItem['item_uuid']?.toString();

        // 1. Try to find matching existing DB row:
        //    a) Exact DB ID match
        //    b) item_uuid match in currency_snapshot
        //    (NEVER match by name+amount, so identical amount lines remain independent!)
        Map<String, dynamic>? matchedDbRow;
        if (sourceId != null && sourceId > 0 && sourceId < 1000000000) {
          matchedDbRow = existingDbRows.firstWhere(
            (r) => r['id'] == sourceId && !matchedDbIds.contains(r['id']),
            orElse: () => {},
          );
          if (matchedDbRow.isEmpty) matchedDbRow = null;
        }

        if (matchedDbRow == null && sourceUuid != null && sourceUuid.isNotEmpty) {
          matchedDbRow = existingDbRows.firstWhere(
            (r) {
              if (matchedDbIds.contains(r['id'])) return false;
              final snap = r['currency_snapshot'];
              Map<String, dynamic> snapMap = {};
              if (snap is Map) {
                snapMap = Map<String, dynamic>.from(snap);
              } else if (snap is String && snap.isNotEmpty) {
                try {
                  final decoded = jsonDecode(snap);
                  if (decoded is Map) snapMap = Map<String, dynamic>.from(decoded);
                } catch (_) {}
              }
              return snapMap['item_uuid'] == sourceUuid;
            },
            orElse: () => {},
          );
          if (matchedDbRow.isEmpty) matchedDbRow = null;
        }

        if (matchedDbRow != null) {
          // UPDATE existing row in place (reconciles status, notes, amounts)
          final matchedId = matchedDbRow['id'] as int;
          matchedDbIds.add(matchedId);

          // Preserve settled status and journal entry from DB if genuinely settled
          final isDbAdmin = matchedDbRow['category'] == 'admin' ||
              (matchedDbRow['name'] ?? '').toString().toLowerCase().contains('إدار') ||
              (matchedDbRow['name'] ?? '').toString().toLowerCase().contains('ادار');
          final isDbSettled = isDbAdmin
              ? (matchedDbRow['variance_journal_entry_id'] != null ||
                 (matchedDbRow['reconciled_at'] != null && matchedDbRow['actual_amount'] != null))
              : ((matchedDbRow['cost_status'] == 'actual' && matchedDbRow['actual_amount'] != null) ||
                 matchedDbRow['variance_journal_entry_id'] != null);
          if (isDbSettled) {
            rowPayload['cost_status'] = 'actual';
            rowPayload['actual_amount'] = matchedDbRow['actual_amount'];
            rowPayload['variance_amount'] = matchedDbRow['variance_amount'];
            rowPayload['variance_journal_entry_id'] = matchedDbRow['variance_journal_entry_id'];
            if (matchedDbRow['invoice_ref'] != null) rowPayload['invoice_ref'] = matchedDbRow['invoice_ref'];
          }

          // Preserve item_uuid in snapshot
          if (sourceUuid != null) {
            (rowPayload['currency_snapshot'] as Map<String, dynamic>)['item_uuid'] = sourceUuid;
          }

          await _client
              .from('packing_order_cost_items')
              .update(rowPayload)
              .eq('id', matchedId);
        } else {
          // Genuinely new item: INSERT as independent row
          if (sourceUuid != null) {
            (rowPayload['currency_snapshot'] as Map<String, dynamic>)['item_uuid'] = sourceUuid;
          }
          final insRes = await _client
              .from('packing_order_cost_items')
              .insert(rowPayload)
              .select('id')
              .maybeSingle();
          if (insRes != null && insRes['id'] != null) {
            final newId = insRes['id'] as int;
            sourceItem['id'] = newId;
            matchedDbIds.add(newId);
          }
        }
      }

      // Purge / soft-delete any residual un-matched redundant rows in DB
      for (final r in existingDbRows) {
        final rId = r['id'] as int;
        if (!matchedDbIds.contains(rId)) {
          try {
            await _client.from('packing_order_cost_items').delete().eq('id', rId);
          } catch (_) {}
          try {
            await _client.from('packing_order_cost_items').update({
              'deleted_at': DateTime.now().toIso8601String(),
              'base_amount': 0,
              'original_amount': 0,
              'expected_amount': 0,
              'actual_amount': 0,
              'variance_amount': 0,
            }).eq('id', rId);
          } catch (_) {}
        }
      }

      // ── Step 4: Always persist resolved IDs and clean list back to packing_orders.notes ──
      notesMap['cost_items'] = uniqueCostItems;
      try {
        await _client
            .from('packing_orders')
            .update({'notes': jsonEncode(notesMap)})
            .eq('id', orderId);
      } catch (e) {
        debugPrint('⚠️ _syncCostItemsToTable: Error saving updated cost_items to notes: ');
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao._syncCostItemsToTable error: $e\n$st');
    } finally {
      _activeCostSyncOrderIds.remove(orderId);
    }
  }

  /// Fetch all cost items for a packing order as raw maps matching the UI structure.
  Future<List<Map<String, dynamic>>> getCostItemsRaw(int packingOrderId) async {
    try {
      final data = await _client
          .from('packing_order_cost_items')
          .select('*, cost_report_categories(name)')
          .eq('packing_order_id', packingOrderId)
          .isFilter('deleted_at', null)
          .gt('base_amount', 0)
          .order('id');

      final rawItems = data.map((row) {
        final categoryName = row['cost_report_categories'] != null
            ? (row['cost_report_categories'] as Map)['name']?.toString()
            : null;

        // Extract UI-specific metadata fields from the currency_snapshot column.
        Map<String, dynamic> snapshot = {};
        if (row['currency_snapshot'] != null) {
          try {
            snapshot =
                Map<String, dynamic>.from(row['currency_snapshot'] as Map);
          } catch (_) {}
        }

        final rName = (row['name'] as String? ?? '').toLowerCase();
        final sType = (snapshot['supplier_type']?.toString() ?? '').toLowerCase();
        final catStr = (row['category']?.toString() ?? '').toLowerCase();
        final bool isEng = sType == 'engineer' || catStr == 'engineer_expenses' || catStr == 'engineer' || rName.contains('مهندس') || snapshot['custody_id'] != null;
        final bool isAdminItem = sType == 'admin' || catStr == 'admin' || rName.contains('إدار') || rName.contains('ادار');
        final bool isAdminSettled = isAdminItem &&
            (row['cost_status'] == 'settled' || row['reconciled_at'] != null || row['variance_journal_entry_id'] != null) &&
            row['actual_amount'] != null;
        final baseAmt = (row['base_amount'] as num).toDouble();
        final origAmt = (row['original_amount'] as num).toDouble();
        final costStatus = isEng
            ? 'actual'
            : (isAdminItem
                ? (isAdminSettled ? 'actual' : 'expected')
                : (row['cost_status'] ?? 'expected'));
        final actualAmt = isEng
            ? ((row['actual_amount'] as num?)?.toDouble() ?? baseAmt)
            : (isAdminItem
                ? (isAdminSettled ? (row['actual_amount'] as num?)?.toDouble() : null)
                : (row['actual_amount'] as num?)?.toDouble());
        final expAmt = (row['expected_amount'] as num?)?.toDouble() ?? baseAmt;

        return {
          'id': row['id'],
          'name': row['name'] as String,
          'category': isEng ? 'engineer_expenses' : (row['category'] as String),
          'report_category_id': row['report_category_id'] as int?,
          'report_category_name': categoryName,
          'supplier_type': isEng ? 'engineer' : snapshot['supplier_type'],
          'item_uuid': snapshot['item_uuid'] ?? (row['id'] != null ? 'item_${row['id']}' : const Uuid().v4()),
          'category_name': isEng ? 'مصاريف مهندسين وإشراف' : snapshot['category_name'],
          'supplier_id': snapshot['supplier_id'],
          'supplier_name': isEng ? 'مجمع عهد الموظفين' : snapshot['supplier_name'],
          'quantity': snapshot['quantity'] ?? 1.0,
          'unit_price': snapshot['unit_price'] ?? origAmt,
          'total': row['original_amount'] as num,
          'total_egp': row['base_amount'] as num,
          'exchange_rate': row['exchange_rate'] as num,
          'supplier_currency': row['original_currency'] as String,
          'payment_source_type': row['payment_source_type'],
          'payment_source_id': row['payment_source_id'],
          'treasury_transaction_id': row['treasury_transaction_id'],
          'bank_transaction_id': row['bank_transaction_id'],
          'allocation_method': row['allocation_method'] ??
              snapshot['allocation_method'] ??
              'BY_NET_WEIGHT',
          'target_line_id': row['target_line_id'],
          'target_line_index': snapshot['target_line_index'],
          'notes': snapshot['notes'] ?? row['settlement_notes'] ?? '',
          'settlement_notes': row['settlement_notes'] ?? snapshot['notes'] ?? '',
          'cost_status': costStatus,
          'expected_amount': expAmt,
          'actual_amount': actualAmt,
          'variance_amount': (row['variance_amount'] as num?)?.toDouble() ?? 0.0,
          'variance_journal_entry_id': row['variance_journal_entry_id'],
          'settlement_journal_entry_id': row['settlement_journal_entry_id'],
          'journal_entry_id': row['journal_entry_id'],
          'engineer_name': snapshot['engineer_name'] ?? row['engineer_name'] ?? (isEng ? 'مجمع عهد الموظفين' : null),
          'is_engineer_cost_settled': isEng ? true : (snapshot['is_engineer_cost_settled'] ?? row['is_engineer_cost_settled'] ?? false),
          'allocation_type': snapshot['allocation_type'],
          'allocation_percentage': snapshot['allocation_percentage'],
          'pool_total_spent': snapshot['pool_total_spent'],
          'pool_total_allocated': snapshot['pool_total_allocated'],
          'pool_remaining_pool': snapshot['pool_remaining_pool'],
        };
      }).toList();

      // Deduplicate to guarantee clean UI display without duplicate items
      final Map<String, Map<String, dynamic>> canonicalItemsMap = {};
      for (final item in rawItems) {
        final rawId = (item['id'] as num?)?.toInt();
        final itemUuid = item['item_uuid']?.toString();
        final sig = (rawId != null && rawId > 0)
            ? 'id_$rawId'
            : ((itemUuid != null && itemUuid.isNotEmpty)
                ? 'uuid_$itemUuid'
                : 'idx_${item.hashCode}');

        if (!canonicalItemsMap.containsKey(sig)) {
          canonicalItemsMap[sig] = item;
        } else {
          final existing = canonicalItemsMap[sig]!;
          final incomingSettled = (item['cost_status'] == 'actual' && item['actual_amount'] != null) ||
              item['variance_journal_entry_id'] != null;
          final existingSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
              existing['variance_journal_entry_id'] != null;
          if (incomingSettled && !existingSettled) {
            canonicalItemsMap[sig] = item;
          } else {
            if ((existing['supplier_id'] == null || existing['supplier_id'].toString().isEmpty) &&
                item['supplier_id'] != null && item['supplier_id'].toString().isNotEmpty) {
              existing['supplier_id'] = item['supplier_id'];
            }
            if ((existing['supplier_name'] == null || existing['supplier_name'].toString().isEmpty) &&
                item['supplier_name'] != null && item['supplier_name'].toString().isNotEmpty) {
              existing['supplier_name'] = item['supplier_name'];
            }
          }
        }
      }
      return canonicalItemsMap.values.toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getCostItemsRaw error: $e\n$st');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Packing Order Lines Management
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetch all lines for a packing order.
  Future<List<PackingOrderLineModel>> getLines(int packingOrderId) async {
    try {
      final data = await _client
          .from('packing_order_lines')
          .select()
          .eq('packing_order_id', packingOrderId)
          .order('id', ascending: true);
      return data
          .map((e) => PackingOrderLineModel.fromMap(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getLines error: $e\n$st');
      return [];
    }
  }

  /// Save lines for a packing order — atomic DELETE+INSERT via RPC.
  Future<void> _saveLines(
      int packingOrderId, List<PackingOrderLineModel> lines) async {
    try {
      final linesJson = lines.map((line) {
        final m = line.copyWith(packingOrderId: packingOrderId).toInsertMap();
        m['updated_at'] = DateTime.now().toIso8601String();
        return m;
      }).toList();

      final result = await _client.rpc('rpc_save_packing_order_lines', params: {
        'p_packing_order_id': packingOrderId,
        'p_lines': linesJson,
      });

      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map == null || map['success'] != true) {
        throw Exception(map?['error']?.toString() ?? 'فشل حفظ أسطر التعبئة');
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao._saveLines error: $e\n$st');
      rethrow;
    }
  }

  /// Add a single line to a packing order.
  Future<int> addLine(PackingOrderLineModel line) async {
    try {
      final result = await _client
          .from('packing_order_lines')
          .insert(line.toInsertMap())
          .select('id')
          .single();
      return result['id'] as int;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.addLine error: $e\n$st');
      rethrow;
    }
  }

  /// Update a single packing order line.
  Future<void> updateLine(int lineId, PackingOrderLineModel line) async {
    try {
      final data = line.toMap();
      data.remove('id');
      data.remove('packing_order_id');
      data['updated_at'] = DateTime.now().toIso8601String();
      await _client.from('packing_order_lines').update(data).eq('id', lineId);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.updateLine error: $e\n$st');
      rethrow;
    }
  }

  /// Delete a single packing order line.
  Future<void> deleteLine(int lineId) async {
    try {
      await _client.from('packing_order_lines').delete().eq('id', lineId);
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.deleteLine error: $e\n$st');
      rethrow;
    }
  }

  /// Apply a granular Debit Note / cost adjustment to a specific item in a packing order
  Future<Map<String, dynamic>> applyItemDebitNote({
    required int orderId,
    required String itemType,
    required int batchId,
    required double discountAmount,
    String? supplierId,
    String? reason,
    String? itemName,
  }) async {
    try {
      final res = await _client.rpc('rpc_apply_packing_order_item_debit_note', params: {
        'p_order_id': orderId,
        'p_item_type': itemType,
        'p_batch_id': batchId,
        'p_discount_amount': discountAmount,
        'p_supplier_id': supplierId,
        'p_reason': reason ?? 'تسوية سعر / إشعار خصم مورد',
        if (itemName != null) 'p_item_name': itemName,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      DataChangeEventBus.instance.notifyStationsChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyItemsChanged();
      return map;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.applyItemDebitNote error: $e\n$st');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Multi-Stage Confirmation Workflow & Waste/Variance Settlements
  // ═══════════════════════════════════════════════════════════════════════

  /// Stage 1: Confirm Crops Disbursement
  Future<String?> confirmCropsStage(int packingOrderId) async {
    try {
      final result = await _client.rpc('rpc_confirm_packing_crops', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return null;
      }
      return map?['error']?.toString() ?? 'فشل في تأكيد مرحلة المحاصيل';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.confirmCropsStage error: $e\n$st');
      return e.toString();
    }
  }

  /// Stage 2: Confirm Packaging Materials Disbursement
  Future<String?> confirmPackagingStage(int packingOrderId) async {
    try {
      final result = await _client.rpc('rpc_confirm_packing_packaging', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return null;
      }
      return map?['error']?.toString() ?? 'فشل في تأكيد مرحلة مواد التعبئة';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.confirmPackagingStage error: $e\n$st');
      return e.toString();
    }
  }

  /// Stage 3: Confirm Cost Items & Post Supplier Liabilities
  Future<String?> confirmCostsStage(int packingOrderId) async {
    if (_activeConfirmCostIds.contains(packingOrderId)) {
      debugPrint('⏳ confirmCostsStage already in progress for packing order $packingOrderId');
      return 'عملية الترحيل قيد التنفيذ بالفعل، يرجى الانتظار...';
    }
    _activeConfirmCostIds.add(packingOrderId);

    try {
      // Clean up notes and table cost items before RPC execution to eliminate any residual duplicates
      final ordData = await _client
          .from('packing_orders')
          .select('notes')
          .eq('id', packingOrderId)
          .maybeSingle();
      if (ordData != null && ordData['notes'] != null) {
        await _syncCostItemsToTable(packingOrderId, ordData['notes']?.toString());
      }

      final result = await _client.rpc('rpc_confirm_packing_costs', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return null;
      }
      return map?['error']?.toString() ?? 'فشل في تأكيد مرحلة بنود التكاليف';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.confirmCostsStage error: $e\n$st');
      return e.toString();
    } finally {
      _activeConfirmCostIds.remove(packingOrderId);
    }
  }

  /// Stage 4: Final Approval & Lock
  Future<String?> confirmFinalStage(int packingOrderId) async {
    try {
      final result = await _client.rpc('rpc_confirm_packing_final', params: {
        'p_packing_order_id': packingOrderId,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : null;
      if (map != null && map['success'] == true) {
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        return null;
      }
      return map?['error']?.toString() ?? 'فشل في الاعتماد النهائي لأمر التعبئة';
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.confirmFinalStage error: $e\n$st');
      return e.toString();
    }
  }

  /// Batch Cost Variance Settlement (Actual vs Expected)
  Future<Map<String, dynamic>> settleCostVariancesBatch({
    required int packingOrderId,
    required List<Map<String, dynamic>> settlements,
    String? generalNotes,
  }) async {
    try {
      final res = await _client.rpc('rpc_settle_packing_cost_variances', params: {
        'p_packing_order_id': packingOrderId,
        'p_settlements': settlements,
        if (generalNotes != null) 'p_general_notes': generalNotes,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      return map;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.settleCostVariancesBatch error: $e\n$st');
      rethrow;
    }
  }

  /// Get Packing Material Waste Settlements for an order
  Future<Map<String, dynamic>> getPackingWasteSettlements(int packingOrderId) async {
    try {
      final res = await _client.rpc('rpc_get_packing_waste_settlements', params: {
        'p_packing_order_id': packingOrderId,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getPackingWasteSettlements error: $e\n$st');
      return {};
    }
  }

  /// Get Seasonal Packing Waste Balance
  Future<Map<String, dynamic>> getSeasonalPackingWasteBalance({
    required DateTime seasonStart,
    required DateTime seasonEnd,
    int? currentPackingOrderId,
  }) async {
    try {
      final res = await _client.rpc('rpc_get_seasonal_packing_waste_balance', params: {
        'p_season_start': seasonStart.toIso8601String().split('T').first,
        'p_season_end': seasonEnd.toIso8601String().split('T').first,
        if (currentPackingOrderId != null) 'p_current_packing_order_id': currentPackingOrderId,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getSeasonalPackingWasteBalance error: $e\n$st');
      return {};
    }
  }

  /// Settle Packing Material Waste
  Future<Map<String, dynamic>> settlePackingMaterialWaste({
    required int packingOrderId,
    required double amount,
    String? notes,
    DateTime? settlementDate,
  }) async {
    try {
      final res = await _client.rpc('rpc_settle_packing_material_waste', params: {
        'p_packing_order_id': packingOrderId,
        'p_amount': amount,
        if (notes != null) 'p_notes': notes,
        if (settlementDate != null) 'p_settlement_date': settlementDate.toIso8601String().split('T').first,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      return map;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.settlePackingMaterialWaste error: $e\n$st');
      rethrow;
    }
  }

  /// Settle Engineer Cost Item from Employee Custody
  Future<Map<String, dynamic>> settleEngineerCostItem({
    required int packingOrderId,
    int? costItemId,
    int? custodyId,
    int? expenseAccountId,
    required double actualAmount,
    String? invoiceRef,
    String? notes,
  }) async {
    try {
      final res = await _client.rpc('rpc_settle_packing_cost_variances', params: {
        'p_packing_order_id': packingOrderId,
        'p_settlements': [
          {
            'cost_item_id': costItemId,
            'actual_amount': actualAmount,
            'invoice_ref': invoiceRef,
            'notes': notes,
            'custody_id': custodyId,
            'expense_account_id': expenseAccountId,
          }
        ],
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      return map;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.settleEngineerCostItem error: $e\n$st');
      rethrow;
    }
  }

  /// Get packing cost variance details (Actual vs Expected)
  Future<Map<String, dynamic>> getVarianceDetails(int packingOrderId) async {
    try {
      final res = await _client.rpc('rpc_get_packing_order_variance_details', params: {
        'p_packing_order_id': packingOrderId,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{'success': false, 'error': 'رد غير متوقع'};
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getVarianceDetails error: $e\n$st');
      return {'success': false, 'error': e.toString()};
    }
  }

}
