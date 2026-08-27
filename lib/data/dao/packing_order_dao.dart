import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
          '*, lot_receipts(lot_number, suppliers(name)), packing_order_lines(*)');

      if (status != null) query = query.eq('status', status);
      if (lotId != null) query = query.eq('lot_id', lotId);
      if (shipmentId != null) {
        query = query.eq('export_shipment_id', shipmentId);
      }

      final data = await query.order('created_at', ascending: false);
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
          .select(
              '*, lot_receipts(lot_number, suppliers(name)), packing_order_lines(*)')
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      final row = Map<String, dynamic>.from(data as Map);
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
      final data = await _client
          .from('packing_orders')
          .select(
              '*, lot_receipts(lot_number, suppliers(name)), packing_order_lines(*)')
          .inFilter('status', ['completed']).order('created_at',
              ascending: false);

      final List<PackingOrderModel> result = [];

      for (final e in data) {
        final row = Map<String, dynamic>.from(e as Map);
        final lot = AppUtils.asMap(row.remove('lot_receipts'));
        final supplier = AppUtils.asMap(lot?['suppliers']);
        final linesRaw = row.remove('packing_order_lines');
        final lines = (linesRaw is List) ? linesRaw : [];

        if (lines.length > 1) {
          // Multi-product order: expand each line into a separate entry
          for (final lineRaw in lines) {
            final line = Map<String, dynamic>.from(lineRaw as Map);
            final lineSoldCartons =
                (line['sold_cartons'] as num?)?.toInt() ?? 0;
            final lineCartonCount =
                (line['carton_count'] as num?)?.toInt() ?? 0;
            final lineRemaining = lineCartonCount - lineSoldCartons;
            if (lineRemaining <= 0) continue;

            final finalCost = (line['final_cost'] as num?)?.toDouble() ?? 0.0;
            final headerCost = (row['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
            final costPerCarton = (finalCost > 0 && lineCartonCount > 0)
                ? finalCost / lineCartonCount
                : (headerCost > 0
                    ? headerCost
                    : ((line['final_unit_cost'] as num?)?.toDouble() ?? 0.0));

            result.add(PackingOrderModel.fromMap({
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
                      ((line['net_weight_per_carton'] as num?)?.toDouble() ??
                          0)),
              'total_gross_weight': line['total_gross_weight'] ??
                  (lineCartonCount *
                      ((line['gross_weight_per_carton'] as num?)?.toDouble() ??
                          0)),
              'packing_cost_per_carton': costPerCarton,
              'batch_id': line['batch_id'] ?? row['batch_id'],
              'lot_number': lot?['lot_number'],
              'supplier_name': supplier?['name'] as String?,
              'line_id': line['id'],
            }));
          }
        } else {
          // Single-product order
          final line = lines.isNotEmpty
              ? Map<String, dynamic>.from(lines[0] as Map)
              : null;
          final int lineCartonCount =
              line != null ? ((line['carton_count'] as num?)?.toInt() ?? 0) : 0;
          final int lineSoldCartons =
              line != null ? ((line['sold_cartons'] as num?)?.toInt() ?? 0) : 0;
          final finalCost = line != null
              ? ((line['final_cost'] as num?)?.toDouble() ?? 0.0)
              : 0.0;
          final headerCost = (row['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
          final costPerCarton = (finalCost > 0 && lineCartonCount > 0)
              ? finalCost / lineCartonCount
              : (headerCost > 0
                  ? headerCost
                  : (line != null
                      ? ((line['final_unit_cost'] as num?)?.toDouble() ?? 0.0)
                      : 0.0));

          final effectiveSoldCartons = lineSoldCartons > 0
              ? lineSoldCartons
              : ((row['sold_cartons'] as num?)?.toInt() ?? 0);
          final effectiveCartonCount = lineCartonCount > 0
              ? lineCartonCount
              : ((row['carton_count'] as num?)?.toInt() ?? 0);

          if (effectiveCartonCount - effectiveSoldCartons <= 0) continue;

          final po = PackingOrderModel.fromMap({
            ...row,
            if (line != null) ...{
              'carton_count': lineCartonCount,
              'sold_cartons': lineSoldCartons,
            },
            'packing_cost_per_carton': costPerCarton,
            'lot_number': lot?['lot_number'],
            'supplier_name': supplier?['name'] as String?,
            'line_id': line?['id'],
          });
          if (po.hasStock) result.add(po);
        }
      }

      return result;
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao.getAvailableForShipment error: $e\n$st');
      rethrow;
    }
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

  Future<void> _syncCostItemNotesOnly(int orderId, String? notes) async {
    try {
      if (notes == null || notes.isEmpty) return;
      Map<String, dynamic>? notesMap;
      try {
        notesMap = jsonDecode(notes) as Map<String, dynamic>;
      } catch (_) {}
      if (notesMap == null || !notesMap.containsKey('cost_items')) return;
      final costItems = notesMap['cost_items'];
      if (costItems is! List) return;

      final orderIdStr = orderId.toString();
      final existingEntries = await _client
          .from('ledger_entries')
          .select('id, entity_id')
          .or('and(reference_type.eq.packing_cost_item,reference_id.eq.$orderIdStr),and(reference_type.eq.packing_cost,reference_text.like.%$orderIdStr%)');

      for (final entry in existingEntries) {
        final entryId = entry['id']?.toString() ?? '';
        if (entryId.isEmpty) continue;
        final entityId = entry['entity_id']?.toString() ?? '';
        final match = costItems.cast<Map<String, dynamic>>().firstWhere(
              (item) => item['supplier_id']?.toString() == entityId,
              orElse: () => {},
            );
        final itemNotes = match['notes']?.toString() ?? '';
        if (itemNotes.isNotEmpty) {
          await _client.from('statement_notes').upsert({
            'entity_type': 'supplier',
            'entity_id': entityId,
            'reference_id': entryId,
            'note': itemNotes,
          }, onConflict: 'entity_type,entity_id,reference_id');
        } else {
          await _client
              .from('statement_notes')
              .delete()
              .eq('entity_type', 'supplier')
              .eq('entity_id', entityId)
              .eq('reference_id', entryId);
        }
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao._syncCostItemNotesOnly error: $e\n$st');
    }
  }

  Future<void> _syncCostItemsToTable(int orderId, String? notes) async {
    try {
      await _client
          .from('packing_order_cost_items')
          .delete()
          .eq('packing_order_id', orderId);

      if (notes == null || notes.isEmpty) return;

      Map<String, dynamic>? notesMap;
      try {
        notesMap = jsonDecode(notes) as Map<String, dynamic>;
      } catch (_) {}

      if (notesMap == null || !notesMap.containsKey('cost_items')) return;

      final costItems = notesMap['cost_items'];
      if (costItems is! List) return;

      for (final item in costItems) {
        if (item is! Map) continue;

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

        final reportCategoryId = item['report_category_id'] as int?;

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
        } else {
          mappedCategory = 'other';
        }

        // NOTE: We reuse the currency_snapshot column as a metadata container
        // to store UI-specific fields (supplier_id, supplier_name, quantity, unit_price)
        // because the packing_order_cost_items table does not have dedicated columns for them.
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
          'quantity': qty,
          'unit_price': unitPrice,
          'total': originalAmount,
          'total_egp': baseAmount,
          'supplier_currency': originalCurrency,
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_index': item['target_line_index'],
          'notes': item['notes'],
        };

        await _client.from('packing_order_cost_items').insert({
          'packing_order_id': orderId,
          'name': name,
          'category': mappedCategory,
          'report_category_id': reportCategoryId,
          'original_currency': originalCurrency,
          'original_amount': originalAmount,
          'exchange_rate': exchangeRate,
          'base_amount': baseAmount,
          'currency_snapshot': currencySnapshot,
          'payment_source_type': item['payment_source_type'],
          'payment_source_id': item['payment_source_id'],
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_id': item['target_line_id'],
        });
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderDao._syncCostItemsToTable error: $e\n$st');
    }
  }

  /// Fetch all cost items for a packing order as raw maps matching the UI structure.
  Future<List<Map<String, dynamic>>> getCostItemsRaw(int packingOrderId) async {
    try {
      final data = await _client
          .from('packing_order_cost_items')
          .select('*, cost_report_categories(name)')
          .eq('packing_order_id', packingOrderId)
          .order('id');

      return data.map((row) {
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

        return {
          'name': row['name'] as String,
          'category': row['category'] as String,
          'report_category_id': row['report_category_id'] as int?,
          'report_category_name': categoryName,
          'supplier_id': snapshot['supplier_id'],
          'supplier_name': snapshot['supplier_name'],
          'quantity': snapshot['quantity'] ?? 1.0,
          'unit_price': snapshot['unit_price'] ??
              (row['original_amount'] as num).toDouble(),
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
          'notes': snapshot['notes'] ?? '',
        };
      }).toList();
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
  }) async {
    try {
      final res = await _client.rpc('rpc_apply_packing_order_item_debit_note', params: {
        'p_order_id': orderId,
        'p_item_type': itemType,
        'p_batch_id': batchId,
        'p_discount_amount': discountAmount,
        'p_supplier_id': supplierId,
        'p_reason': reason ?? 'تسوية سعر / إشعار خصم مورد',
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
}

