import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/export_shipment_model.dart';
import '../services/currency_conversion_service.dart';
import '../services/packing_calculation_service.dart';
import '../services/cost_center_service.dart';
import '../services/product_cost_center_sync_service.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/services/cost_allocation_engine.dart';
import 'export_shipment_item_dao.dart';

class ExportShipmentDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ExportShipmentModel>> getAll({
    String? status,
    String? searchQuery,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
    String? excludeStatus,
    List<String>? excludeStatuses,
  }) async {
    try {
      var query = _client.from('export_shipments').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      } else {
        if (excludeStatus != null && excludeStatus.isNotEmpty) {
          query = query.neq('status', excludeStatus);
        }
        if (excludeStatuses != null && excludeStatuses.isNotEmpty) {
          query = query.not('status', 'in', '(${excludeStatuses.map((s) => '"$s"').join(',')})');
        }
      }
      if (fromDate != null) query = query.gte('shipment_date', fromDate);
      if (toDate != null) query = query.lte('shipment_date', toDate);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'shipment_no.ilike.%$searchQuery%,vessel_name.ilike.%$searchQuery%,container_number.ilike.%$searchQuery%');
      }
      final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
      return data.map((row) => ExportShipmentModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getAll): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getAll): $e');
    }
  }

  Future<ExportShipmentModel?> getLatest() async {
    try {
      final data = await _client
          .from('export_shipments')
          .select()
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return ExportShipmentModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getLatest): ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error (getLatest): $e');
    }
  }

  Future<ExportShipmentModel?> getById(dynamic id) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      final data = await _client.from('export_shipments').select().eq('id', parsedId).maybeSingle();
      if (data == null) return null;
      return ExportShipmentModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getById): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getById): $e');
    }
  }

  Future<dynamic> saveWithRpc(ExportShipmentModel shipment, List<Map<String, dynamic>> items) async {
    try {
      if (shipment.shipmentNo.trim().isEmpty) {
        throw Exception(' shipment_no cannot be empty');
      }
      final data = shipment.toMap();
      // Remove created_at if updating
      if (shipment.id != null) {
        data.remove('created_at');
      } else {
        data.remove('id');
      }
      
      try {
        final result = await _client.rpc('rpc_save_export_shipment', params: {
          'p_shipment': data,
          'p_items': items,
        });
        
        if (result != null && result['id'] != null) {
          final savedId = result['id'];
          try {
            await ProductCostCenterSyncService().recordExportShipmentRevenueTransactions(
              shipmentId: savedId,
              shipmentNo: shipment.shipmentNo,
              customerName: shipment.customerName,
              customerId: shipment.customerId,
              currency: shipment.currencyCode.isNotEmpty ? shipment.currencyCode : (shipment.currency ?? 'USD'),
              exchangeRate: shipment.exchangeRate,
              items: items,
              date: shipment.shipmentDate,
            );
          } catch (e) {
            debugPrint('Export shipment cost center sync notice: $e');
          }
          DataChangeEventBus.instance.notifyCostCentersChanged();
          return savedId;
        }
      } on PostgrestException catch (pe) {
        if (pe.code != 'PGRST202' && !pe.message.contains('Could not find the function')) {
          rethrow;
        }
        debugPrint('ℹ️ rpc_save_export_shipment not in DB, falling back to direct table save');
      }

      // Fallback: Direct database insert / update
      final dynamic shipmentId;
      if (shipment.id != null && shipment.id!.isNotEmpty) {
        final Object sid = int.tryParse(shipment.id!) ?? shipment.id!;
        await _client.from('export_shipments').update(data).eq('id', sid);
        shipmentId = sid;
        await ExportShipmentItemDao().deleteByShipmentId(sid);
      } else {
        final result = await _client.from('export_shipments').insert(data).select('id').single();
        shipmentId = result['id'];
      }

      if (items.isNotEmpty && shipmentId != null) {
        await ExportShipmentItemDao().insertAll(
          shipmentId,
          items,
          currencyCode: shipment.currencyCode,
          exchangeRate: shipment.exchangeRate,
        );
      }

      if (shipmentId != null) {
        try {
          await ProductCostCenterSyncService().recordExportShipmentRevenueTransactions(
            shipmentId: shipmentId,
            shipmentNo: shipment.shipmentNo,
            customerName: shipment.customerName,
            customerId: shipment.customerId,
            currency: shipment.currencyCode.isNotEmpty ? shipment.currencyCode : (shipment.currency ?? 'USD'),
            exchangeRate: shipment.exchangeRate,
            items: items,
            date: shipment.shipmentDate,
          );
        } catch (e) {
          debugPrint('Export shipment cost center sync notice: $e');
        }
        DataChangeEventBus.instance.notifyCostCentersChanged();
      }

      return shipmentId;
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (saveWithRpc): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (saveWithRpc): $e');
    }
  }

  Future<dynamic> insert(ExportShipmentModel shipment) async {
    try {
      if (shipment.shipmentNo.trim().isEmpty) {
        throw Exception(' shipment_no cannot be empty');
      }
      final data = shipment.toMap();
      data.remove('id');
      // user_id is NOT sent — Supabase fills it via DEFAULT auth.uid()
      final result = await _client.from('export_shipments').insert(data).select().single();
      return result['id'];
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (insert): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (insert): $e');
    }
  }

  Future<void> update(ExportShipmentModel shipment) async {
    try {
      final data = shipment.toMap();
      data.remove('id');
      data.remove('created_at');
      await _client.from('export_shipments').update(data).eq('id', int.parse(shipment.id!));
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (update): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (update): $e');
    }
  }

  Future<void> updatePackingRecipeId(dynamic shipmentId, String recipeId) async {
    try {
      final parsedSid = shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId;
      await _client.from('export_shipments').update({'packing_recipe_id': recipeId}).eq('id', parsedSid);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updatePackingRecipeId): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updatePackingRecipeId): $e');
    }
  }

  Future<void> updateStatus(dynamic id, String status) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      await _client.from('export_shipments').update({'status': status}).eq('id', parsedId);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateStatus): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateStatus): $e');
    }
  }

  /// Cancel shipment with full accounting reversal via SQL RPC.
  /// Reverses customer balance, ledger entries, creates journal entries
  /// and treasury transaction for cancellation audit trail.
  Future<Map<String, dynamic>> cancelShipment(dynamic id) async {
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) throw Exception('Invalid shipment id: $id');

      final result = await _client
          .rpc('rpc_cancel_export_shipment', params: {
        'p_shipment_id': sid,
      });

      if (result is Map<String, dynamic>) {
        if (result['success'] == false) {
          throw Exception(result['error'] ?? 'Failed to cancel shipment');
        }
        return result;
      }
      throw Exception('Unexpected response from cancel RPC');
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (cancelShipment): ${e.message} | code: ${e.code}');
    } catch (e) {
      if (e.toString().contains('Invalid shipment') ||
          e.toString().contains('Failed to cancel')) {
        rethrow;
      }
      throw Exception('Unexpected error (cancelShipment): $e');
    }
  }

  /// Get cancel info for UI display (check if cancellable, amounts, etc.)
  Future<Map<String, dynamic>?> getCancelInfo(dynamic id) async {
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) return null;

      final result = await _client
          .rpc('rpc_get_export_shipment_cancel_info', params: {
        'p_shipment_id': sid,
      });

      if (result is Map<String, dynamic> && result['success'] == true) {
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to get cancel info for shipment $id: $e');
      return null;
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      final result = await _client
          .from('export_shipments')
          .delete()
          .eq('id', parsedId)
          .select() as List;
      debugPrint('ExportShipmentDao.delete: id=$id, rows_affected=${result.length}');
      if (result.isEmpty) {
        throw Exception('لم يتم العثور على الشحنة أو لا تملك صلاحية الحذف (id=$id)');
      }
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (delete): ${e.message} | code: ${e.code}');
    }
  }

  Future<Map<String, dynamic>> syncLedger(dynamic shipmentId) async {
    final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
    if (sid == null) {
      throw Exception('معرف الشحنة غير صالح');
    }
    try {
      final result = await _client.rpc('rpc_process_export_shipment_ledger', params: {
        'p_shipment_id': sid,
      });
      if (result is Map && result['success'] == false) {
        throw Exception(result['error']?.toString() ?? 'فشل ترحيل قيود الشحنة');
      }
      DataChangeEventBus.instance.notifyCostCentersChanged();
      return result is Map<String, dynamic>
          ? result
          : {'success': true, 'result': result};
    } on PostgrestException catch (e) {
      throw Exception('فشل ترحيل قيود الشحنة: ${e.message}');
    } catch (e) {
      throw Exception('فشل ترحيل قيود الشحنة: $e');
    }
  }

  Future<String> getNextShipmentNo(String customerCode, int year) async {
    try {
      final yy = (year % 100).toString().padLeft(2, '0');
      final prefix = '$yy/$customerCode/';
      final data = await _client
          .from('export_shipments')
          .select('shipment_no')
          .like('shipment_no', '$prefix%')
          .order('shipment_no', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return '${prefix}01';
      final last = (data['shipment_no'] ?? '').toString();
      final suffix = last.replaceFirst(prefix, '');
      final lastNum = int.tryParse(suffix) ?? 0;
      final nextNum = lastNum + 1;
      return '$prefix${nextNum.toString().padLeft(2, '0')}';
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getNextShipmentNo): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getNextShipmentNo): $e');
    }
  }

  Future<List<ExportShipmentModel>> getByCustomer(dynamic customerId) async {
    try {
      final data = await _client
          .from('export_shipments')
          .select()
          .eq('customer_id', customerId is int ? customerId : int.tryParse(customerId.toString()) ?? customerId)
          .order('created_at', ascending: false);
      return data.map((row) => ExportShipmentModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getByCustomer): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getByCustomer): $e');
    }
  }

  Future<void> updateCosting({
    required int shipmentId,
    required double totalLandedCost,
    required int cartonCount,
    required double exportPricePerCarton,
    required String currencyCode,
    required double exchangeRate,
    double totalFruitCost = 0.0,
    double totalPackingMaterialCost = 0.0,
    double nonPackingLandedCost = 0.0,
  }) async {
    try {
      final costPerCarton = cartonCount > 0 ? totalLandedCost / cartonCount : 0.0;
      
      // Accurately calculate total revenue from items
      final itemsData = await _client.from('export_shipment_items').select('quantity, export_price_per_carton').eq('shipment_id', shipmentId);
      double totalRevenueForeign = 0.0;
      for (final item in itemsData) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totalRevenueForeign += qty * price;
      }
      
      // Fetch discount from existing shipment
      final shipmentData = await _client.from('export_shipments').select('discount_amount').eq('id', shipmentId).maybeSingle();
      final discount = (shipmentData?['discount_amount'] as num?)?.toDouble() ?? 0.0;
      
      totalRevenueForeign = totalRevenueForeign - discount;
      final totalRevenueEgp = CurrencyConversionService.instance.toBase(totalRevenueForeign, currencyCode, exchangeRate);
      
      final netProfit = totalRevenueEgp - totalLandedCost;
      final grossProfit = totalRevenueEgp - totalFruitCost - totalPackingMaterialCost;

      await _client.from('export_shipments').update({
        'total_landed_cost': totalLandedCost,
        'cost_per_carton': costPerCarton,
        'export_price_per_carton': exportPricePerCarton,
        'currency_code': currencyCode,
        'exchange_rate': exchangeRate,
        'total_revenue_foreign': totalRevenueForeign,
        'total_revenue_egp': totalRevenueEgp,
        'net_profit_egp': netProfit,
        'total_fruit_cost': totalFruitCost,
        'total_packing_material_cost': totalPackingMaterialCost,
        'gross_profit': grossProfit,
        'net_profit': netProfit,
        'needs_profit_redistribution': true,
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: currencyCode,
          amount: totalRevenueForeign,
          exchangeRate: exchangeRate,
        ).toJson(),
      }).eq('id', shipmentId);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateCosting): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateCosting): $e');
    }
  }

  Future<Map<String, dynamic>> getProfitSummary() async {
    try {
      final data = await _client
        .from('export_shipments')
        .select('total_revenue_egp, total_landed_cost, net_profit_egp')
        .not('status', 'in', '("cancelled","returned_from_airport","returned","rejected")')
        .eq('is_confirmed', true);

      double totalRevenue = 0, totalCost = 0, totalProfit = 0;
      for (final row in data) {
        totalRevenue += (row['total_revenue_egp'] as num?)?.toDouble() ?? 0;
        totalCost += (row['total_landed_cost'] as num?)?.toDouble() ?? 0;
        totalProfit += (row['net_profit_egp'] as num?)?.toDouble() ?? 0;
      }
      return {
        'total_revenue_egp': totalRevenue,
        'total_cost_egp': totalCost,
        'net_profit_egp': totalProfit,
        'shipment_count': data.length,
      };
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getProfitSummary): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getProfitSummary): $e');
    }
  }

  Future<List<Map<String, dynamic>>> getJournalEntriesForShipment(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return [];

      final Set<int> jeIds = {};
      final Map<int, String> jeSourceCategory = {};

      // 1. Direct commercial entry for shipment (sales / discount)
      final commercialRows = await _client
          .from('journal_entries')
          .select('id, source_type')
          .inFilter('source_type', ['export_shipment', 'export_discount'])
          .eq('source_id', sid.toString());
      for (final r in commercialRows) {
        final id = r['id'] as int;
        jeIds.add(id);
        jeSourceCategory[id] = 'commercial';
      }

      // 1.b Return / Cancellation journal entry for shipment (direct source_type)
      try {
        final returnRows = await _client
            .from('journal_entries')
            .select('id, source_type')
            .inFilter('source_type', ['export_return', 'export_shipment_return'])
            .eq('source_id', sid.toString());
        for (final r in returnRows) {
          final id = r['id'] as int;
          jeIds.add(id);
          jeSourceCategory[id] = 'return';
        }
      } catch (e) {
        debugPrint('getJournalEntriesForShipment returnRows error: $e');
      }

      // 1.c Direct check on export_shipment_returns table
      try {
        final retRecords = await _client
            .from('export_shipment_returns')
            .select('journal_entry_id')
            .eq('shipment_id', sid)
            .not('journal_entry_id', 'is', null);
        for (final rec in retRecords) {
          final jId = rec['journal_entry_id'];
          final int? id = jId is int ? jId : int.tryParse('$jId');
          if (id != null) {
            jeIds.add(id);
            jeSourceCategory[id] = 'return';
          }
        }
      } catch (e) {
        debugPrint('getJournalEntriesForShipment retRecords error: $e');
      }

      // 1.d Check export_shipments.return_journal_entry_id and shipment_no description match
      try {
        final shipmentRow = await _client
            .from('export_shipments')
            .select('return_journal_entry_id, shipment_no')
            .eq('id', sid)
            .maybeSingle();
        if (shipmentRow != null) {
          final retJeId = shipmentRow['return_journal_entry_id'];
          final int? id = retJeId is int ? retJeId : int.tryParse('$retJeId');
          if (id != null) {
            jeIds.add(id);
            jeSourceCategory[id] = 'return';
          }
          final sNo = shipmentRow['shipment_no']?.toString();
          if (sNo != null && sNo.isNotEmpty) {
            final jeByDesc = await _client
                .from('journal_entries')
                .select('id, source_type')
                .inFilter('source_type', ['export_return', 'export_shipment_return'])
                .ilike('description', '%$sNo%');
            for (final r in jeByDesc) {
              final id = r['id'] as int;
              jeIds.add(id);
              jeSourceCategory[id] = 'return';
            }
          }
        }
      } catch (e) {
        debugPrint('getJournalEntriesForShipment shipmentRow return check error: $e');
      }

      // 2. Fetch shipment cost items
      final costItems = await _client
          .from('shipment_cost_items')
          .select('id, journal_entry_id, payment_source_type, payment_source_id, treasury_transaction_id, bank_transaction_id')
          .eq('shipment_id', sid);

      final costItemIds = <String>[];
      for (final item in costItems) {
        final cid = item['id']?.toString();
        if (cid != null) costItemIds.add(cid);

        if (item['journal_entry_id'] != null) {
          final jId = item['journal_entry_id'] as int;
          jeIds.add(jId);
          jeSourceCategory[jId] = 'shipment_cost_paid';
        }
      }

      // 3. Accruals linked to cost items
      if (costItemIds.isNotEmpty) {
        final accrualRows = await _client
            .from('journal_entries')
            .select('id')
            .eq('source_type', 'shipment_cost_accrual')
            .inFilter('source_id', costItemIds);
        for (final r in accrualRows) {
          final id = r['id'] as int;
          jeIds.add(id);
          jeSourceCategory[id] = 'shipment_cost_accrual';
        }
      }

      // 4. Packing orders linked to shipment items
      final shipmentItems = await _client
          .from('export_shipment_items')
          .select('packing_order_id')
          .eq('shipment_id', sid)
          .not('packing_order_id', 'is', null);
      final packingOrderIds = shipmentItems
          .map((r) => r['packing_order_id'])
          .whereType<int>()
          .toSet();

      for (final pId in packingOrderIds) {
        final poRows = await _client
            .from('journal_entries')
            .select('id, source_type')
            .inFilter('source_type', ['packing_order', 'packing_debit_note'])
            .eq('source_id', pId.toString());
        for (final r in poRows) {
          final id = r['id'] as int;
          jeIds.add(id);
          jeSourceCategory[id] = r['source_type'] == 'packing_debit_note'
              ? 'packing_debit_note'
              : 'packing_order';
        }
      }

      if (jeIds.isEmpty) return [];

      // 5. Fetch full details and lines for each journal entry
      final entries = await _client
          .from('journal_entries')
          .select('id, entry_number, entry_date, description, source_type, source_id, status, created_at')
          .inFilter('id', jeIds.toList())
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> results = [];

      for (final je in entries) {
        final jeId = je['id'] as int;
        final catKey = jeSourceCategory[jeId] ?? 'cost';
        final isReturn = catKey == 'return' ||
            catKey == 'export_return' ||
            catKey == 'export_shipment_return' ||
            je['source_type'] == 'export_return' ||
            je['source_type'] == 'export_shipment_return';
        final isCost = catKey != 'commercial' && !isReturn;

        // Fetch lines from v_journal_entry_lines with fallback to account_ledger_entries
        List<dynamic> linesData = [];
        try {
          linesData = await _client
              .from('v_journal_entry_lines')
              .select('id, account_id, account_code, account_name, debit, credit, currency, description, cost_center_id')
              .eq('journal_entry_id', jeId)
              .order('id');
        } catch (_) {}

        if (linesData.isEmpty) {
          try {
            linesData = await _client
                .from('account_ledger_entries')
                .select('id, account_id, debit, credit, currency, description, cost_center_id')
                .eq('journal_entry_id', jeId)
                .order('id');
          } catch (_) {}
        }

        double totalDebit = 0.0;
        double totalCredit = 0.0;
        String currency = 'EGP';

        final lines = <Map<String, dynamic>>[];
        for (final l in linesData) {
          final dr = (l['debit'] as num?)?.toDouble() ?? 0.0;
          final cr = (l['credit'] as num?)?.toDouble() ?? 0.0;
          totalDebit += dr;
          totalCredit += cr;
          if (l['currency'] != null && l['currency'].toString().isNotEmpty) {
            currency = l['currency'].toString();
          }
          lines.add({
            'id': l['id'],
            'account_id': l['account_id'],
            'account_code': l['account_code']?.toString() ?? '',
            'account_name': l['account_name']?.toString() ?? '',
            'debit': dr,
            'credit': cr,
            'currency': l['currency']?.toString() ?? 'EGP',
            'description': l['description']?.toString() ?? '',
            'cost_center_id': l['cost_center_id']?.toString() ?? '',
          });
        }

        String categoryLabel;
        switch (catKey) {
          case 'return':
          case 'export_return':
          case 'export_shipment_return':
            categoryLabel = 'قيد إلغاء الشحنة / مرتجع التصدير';
            break;
          case 'commercial':
            categoryLabel = 'مبيعات وإيرادات الشحنة';
            break;
          case 'packing_order':
            categoryLabel = 'تكاليف أمر التعبئة والمحاصيل';
            break;
          case 'packing_debit_note':
            categoryLabel = 'إشعار خصم مورد (تخفيض تكلفة)';
            break;
          case 'shipment_cost_accrual':
            categoryLabel = 'استحقاق تكاليف الشحنة';
            break;
          case 'shipment_cost_paid':
            categoryLabel = 'سداد تكاليف الشحنة';
            break;
          default:
            categoryLabel = isReturn
                ? 'قيد إلغاء الشحنة / مرتجع التصدير'
                : (isCost ? 'تكلفة فعلية' : 'قيد شحنة');
        }

        results.add({
          'journal_entry_id': jeId,
          'entry_number': je['entry_number'] ?? '#$jeId',
          'entry_date': je['entry_date'],
          'description': je['description'],
          'source_type': je['source_type'],
          'source_id': je['source_id'],
          'status': je['status'] ?? 'مرحّل',
          'category': isReturn ? 'return' : catKey,
          'category_label': categoryLabel,
          'is_cost_entry': isCost,
          'is_return_entry': isReturn,
          'total_debit': totalDebit,
          'total_credit': totalCredit,
          'currency': currency,
          'is_balanced': (totalDebit - totalCredit).abs() < 0.01,
          'lines': lines,
          'created_at': je['created_at'],
        });
      }
      return results;
    } catch (e) {
      debugPrint('ExportShipmentDao.getJournalEntriesForShipment error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> applyDiscount({
    required dynamic shipmentId,
    required double discountAmount,
    String? reason,
  }) async {
    final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
    if (sid == null) throw Exception('Invalid shipment id: $shipmentId');

    try {
      final result = await _client.rpc('rpc_apply_export_discount', params: {
        'p_shipment_id': sid,
        'p_discount_amount': discountAmount,
        'p_discount_reason': reason,
      });

      if (result is Map<String, dynamic> && result['success'] == false) {
        throw Exception(result['error'] ?? 'Failed to apply discount');
      }
      return result is Map<String, dynamic> ? result : {'success': true};
    } on PostgrestException catch (pe) {
      if (pe.code == 'PGRST202' ||
          pe.message.contains('Could not find the function') ||
          pe.message.contains('rpc_apply_export_discount')) {
        debugPrint('ℹ️ rpc_apply_export_discount not in DB, falling back to direct update + ledger sync');
        await _client.from('export_shipments').update({
          'discount_amount': discountAmount,
          'discount_reason': reason,
          'applied_discount_amount': discountAmount,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', sid);

        try {
          await _client.rpc('rpc_process_export_shipment_ledger', params: {
            'p_shipment_id': sid,
          });
        } catch (e) {
          debugPrint('⚠️ Warning during ledger reprocessing: $e');
        }

        return {'success': true, 'fallback': true};
      }
      rethrow;
    }
  }

  Future<Map<String, double>> getItemTotals(List<dynamic> shipmentIds) async {
    if (shipmentIds.isEmpty) return {};
    try {
      final idStrs = shipmentIds.map((id) => id.toString()).toList();
      final data = await _client
          .from('export_shipment_items')
          .select('shipment_id, quantity, export_price_per_carton')
          .inFilter('shipment_id', idStrs);
          
      final shipmentData = await _client
          .from('export_shipments')
          .select('id, discount_amount')
          .inFilter('id', idStrs);
          
      final discounts = <String, double>{};
      for (final row in shipmentData) {
        discounts[row['id'].toString()] = (row['discount_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final totals = <String, double>{};
      for (final row in data) {
        final sid = row['shipment_id']?.toString() ?? '';
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        final price = (row['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totals[sid] = (totals[sid] ?? 0) + qty * price;
      }
      
      for (final sid in totals.keys) {
        totals[sid] = totals[sid]! - (discounts[sid] ?? 0.0);
      }
      return totals;
    } catch (e) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getProfitDistributionJournalEntries(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return [];

      final result = await _client.rpc('rpc_get_profit_distribution_journal_entries', params: {
        'p_shipment_id': sid,
      });

      if (result is List) {
        return List<Map<String, dynamic>>.from(result);
      }
      return [];
    } catch (e) {
      debugPrint('ExportShipmentDao.getProfitDistributionJournalEntries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> saveAllocatedAdminExpenses({
    required int shipmentId,
    required double allocatedAdminExpenses,
  }) async {
    try {
      final res = await _client.rpc('rpc_save_shipment_admin_expenses', params: {
        'p_shipment_id': shipmentId,
        'p_allocated_admin_expenses': allocatedAdminExpenses,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      debugPrint('ExportShipmentDao.saveAllocatedAdminExpenses error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveAllocatedTaxes({
    required int shipmentId,
    required double allocatedTaxes,
  }) async {
    try {
      final res = await _client.rpc('rpc_save_shipment_taxes', params: {
        'p_shipment_id': shipmentId,
        'p_allocated_taxes': allocatedTaxes,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      debugPrint('ExportShipmentDao.saveAllocatedTaxes error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> isShipmentProfitDistributed(int shipmentId) async {
    try {
      final data = await _client
          .from('shareholder_profit_distributions')
          .select('id')
          .eq('shipment_id', shipmentId)
          .isFilter('deleted_at', null)
          .limit(1);
      return (data as List).isNotEmpty;
    } catch (e, st) {
      debugPrint('ExportShipmentDao.isShipmentProfitDistributed error: $e\n$st');
      return false;
    }
  }

  /// Process export shipment return from airport (تسجيل رجوع شحنة من المطار)
  Future<Map<String, dynamic>> processShipmentReturn({
    required int shipmentId,
    required int stationId,
    required DateTime returnDate,
    required String? costCenterId,
    required String returnReason,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> extraExpenses = const [],
    String notes = '',
  }) async {
    final dateStr = returnDate.toIso8601String().split('T').first;

    // 1. Try server-side RPC first
    try {
      final res = await _client.rpc('rpc_process_export_shipment_return', params: {
        'p_shipment_id': shipmentId,
        'p_station_id': stationId,
        'p_return_date': dateStr,
        'p_cost_center_id': costCenterId,
        'p_return_reason': returnReason,
        'p_items': items,
        'p_extra_expenses': extraExpenses,
        'p_notes': notes,
      });

      if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        if (map['success'] == true) {
          var returnJeId = map['journal_entry_id'];
          if (returnJeId == null) {
            final shipRow = await _client.from('export_shipments').select('return_journal_entry_id').eq('id', shipmentId).maybeSingle();
            returnJeId = shipRow?['return_journal_entry_id'];
          }
          if (returnJeId == null) {
            try {
              final fallbackRes = await _fallbackProcessShipmentReturn(
                shipmentId: shipmentId,
                stationId: stationId,
                returnDate: returnDate,
                costCenterId: costCenterId,
                returnReason: returnReason,
                items: items,
                extraExpenses: extraExpenses,
                notes: notes,
              );
              map['journal_entry_id'] = fallbackRes['journal_entry_id'];
            } catch (e) {
              debugPrint('⚠️ Error in post-RPC fallback JE creation: $e');
            }
          }
          // Guarantee that Cost Center Transactions are synced & populated under the season cost center
          try {
            await _syncReturnCostCenterTransactions(
              shipmentId: shipmentId,
              returnNo: map['return_number']?.toString() ?? 'EXR-$shipmentId',
              returnDate: returnDate,
              costCenterId: costCenterId,
              items: items,
              extraExpenses: extraExpenses,
            );
          } catch (e) {
            debugPrint('⚠️ Error syncing cost center transactions in processExportShipmentReturn: $e');
          }
          return map;
        } else {
          throw Exception(map['error'] ?? 'فشل تسجيل رجوع الشحنة');
        }
      }
    } on PostgrestException catch (pe) {
      if (pe.code != 'PGRST202' && !pe.message.contains('Could not find the function')) {
        rethrow;
      }
      debugPrint('ℹ️ rpc_process_export_shipment_return not found in DB, executing client-side fallback');
    } catch (e) {
      if (e.toString().contains('فشل تسجيل رجوع') || e.toString().contains('مسبقاً')) {
        rethrow;
      }
      debugPrint('ℹ️ RPC error, falling back to direct table update: $e');
    }

    // 2. Client-side fallback
    return await _fallbackProcessShipmentReturn(
      shipmentId: shipmentId,
      stationId: stationId,
      returnDate: returnDate,
      costCenterId: costCenterId,
      returnReason: returnReason,
      items: items,
      extraExpenses: extraExpenses,
      notes: notes,
    );
  }

  Future<Map<String, dynamic>?> _findExistingStationProduct({
    required int stationId,
    String? rawMaterialId,
    int? fruitTypeId,
    String? productCode,
    String? productName,
    required String itemType,
  }) async {
    try {
      final cleanCode = (productCode ?? '').trim();
      final cleanName = (productName ?? '').trim();
      final cleanMatId = (rawMaterialId ?? '').trim();

      // 1. By ID (fruit_type_id or raw_material_id)
      if (itemType == 'fruit' && fruitTypeId != null && fruitTypeId > 0) {
        final res = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('fruit_type_id', fruitTypeId)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      } else if (itemType == 'material' && cleanMatId.isNotEmpty) {
        final res = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('raw_material_id', cleanMatId)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      }

      // 2. By product_code
      if (cleanCode.isNotEmpty) {
        final res = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('product_code', cleanCode)
            .eq('item_type', itemType)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      }

      // 3. By exact product_name
      if (cleanName.isNotEmpty) {
        final res = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('product_name', cleanName)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      }

      // 4. By fuzzy product_name
      if (cleanName.isNotEmpty) {
        final all = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('item_type', itemType);
        for (final row in all) {
          final pName = (row['product_name'] ?? '').toString().trim();
          if (pName.isNotEmpty && (pName.contains(cleanName) || cleanName.contains(pName))) {
            return Map<String, dynamic>.from(row);
          }
        }
      }

      // 5. For packaging materials: any carton card if it mentions كرتون
      if (itemType == 'material') {
        final all = await _client
            .from('station_products')
            .select()
            .eq('station_id', stationId)
            .eq('item_type', 'material');
        for (final row in all) {
          final pName = (row['product_name'] ?? '').toString();
          if (pName.contains('كرتون') || pName.toLowerCase().contains('carton') || pName.contains('صندوق')) {
            return Map<String, dynamic>.from(row);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error in _findExistingStationProduct: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> _fallbackProcessShipmentReturn({
    required int shipmentId,
    required int stationId,
    required DateTime returnDate,
    required String? costCenterId,
    required String returnReason,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> extraExpenses = const [],
    String notes = '',
  }) async {
    final dateStr = returnDate.toIso8601String().split('T').first;

    // A. Fetch current shipment
    final sData = await _client.from('export_shipments').select().eq('id', shipmentId).maybeSingle();
    if (sData == null) throw Exception('الشحنة التصديرية غير موجودة');

    int totalCartons = 0;
    int intactCartons = 0;
    int damagedCartons = 0;
    double totalWeight = 0.0;
    double intactWeight = 0.0;
    double damagedWeight = 0.0;
    double cropWasteCost = 0.0;
    double matWasteCost = 0.0;
    double intactCropCost = 0.0;
    double intactMaterialCost = 0.0;
    double extraExpensesCost = 0.0;

    for (final exp in extraExpenses) {
      extraExpensesCost += (exp['amount'] as num?)?.toDouble() ?? 0.0;
    }

    // B. Process items: restock and decrement sold cartons
    for (final item in items) {
      final tCartons = (item['total_cartons'] as num?)?.toInt() ?? 0;
      final iCartons = (item['intact_cartons'] as num?)?.toInt() ?? 0;
      final dCartons = (item['damaged_cartons'] as num?)?.toInt() ?? 0;
      final tWeight = (item['total_weight'] as num?)?.toDouble() ?? 0.0;
      final iWeight = (item['intact_weight'] as num?)?.toDouble() ?? 0.0;
      final dWeight = (item['damaged_weight'] as num?)?.toDouble() ?? 0.0;
      final cropCost = (item['crop_unit_cost'] as num?)?.toDouble() ?? 0.0;
      final cartonCost = (item['carton_unit_cost'] as num?)?.toDouble() ?? 0.0;

      totalCartons += tCartons;
      intactCartons += iCartons;
      damagedCartons += dCartons;
      totalWeight += tWeight;
      intactWeight += iWeight;
      damagedWeight += dWeight;
      cropWasteCost += dWeight * cropCost;
      matWasteCost += dCartons * cartonCost;
      intactCropCost += iWeight * cropCost;
      intactMaterialCost += iCartons * cartonCost;

      final prodName = item['product_name']?.toString() ?? 'محصول مرتجع';
      final fruitId = item['fruit_type_id'] != null ? int.tryParse(item['fruit_type_id'].toString()) : null;

      // 1. Restock intact crop into EXACT existing station product card (NEVER create duplicate cards)
      if (iWeight > 0) {
        try {
          final existingFruit = await _findExistingStationProduct(
            stationId: stationId,
            fruitTypeId: fruitId,
            productCode: item['product_code']?.toString(),
            productName: prodName,
            itemType: 'fruit',
          );

          final targetFruitName = existingFruit?['product_name'] ?? prodName;
          final targetFruitCode = existingFruit?['product_code'] ?? item['product_code']?.toString() ?? '';
          final targetFruitTypeId = existingFruit?['fruit_type_id'] ?? fruitId;

          await _client.from('station_product_batches').insert({
            'station_id': stationId,
            'product_name': targetFruitName,
            'product_code': targetFruitCode,
            'quantity': iWeight,
            'remaining_quantity': iWeight,
            'unit_cost': cropCost,
            'currency': 'EGP',
            'exchange_rate': 1.0,
            'source_type': 'export_return',
            'source_date': returnDate.toIso8601String(),
            'supplier_name': 'مرتجع شحنة ${sData['shipment_no']}',
            'item_type': 'fruit',
            'fruit_type_id': targetFruitTypeId,
          });

          if (existingFruit != null && existingFruit['id'] != null) {
            final curQty = (existingFruit['quantity'] as num?)?.toDouble() ?? 0.0;
            await _client.from('station_products').update({
              'quantity': curQty + iWeight,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', existingFruit['id']);
          } else {
            await _client.from('station_products').insert({
              'station_id': stationId,
              'product_name': targetFruitName,
              'product_code': targetFruitCode,
              'quantity': iWeight,
              'fruit_type_id': targetFruitTypeId,
              'item_type': 'fruit',
              'unit': 'kg',
            });
          }
        } catch (e) {
          debugPrint('⚠️ Restock crop batch error: $e');
        }
      }

      // 2. Restock intact cartons into EXACT existing station product card (NEVER create duplicate cards)
      if (iCartons > 0) {
        final rawMatId = item['raw_material_id']?.toString();
        final cartonProdName = item['carton_product_name']?.toString();
        final cartonProdCode = item['carton_product_code']?.toString();

        try {
          final existingCarton = await _findExistingStationProduct(
            stationId: stationId,
            rawMaterialId: rawMatId,
            productCode: cartonProdCode,
            productName: cartonProdName,
            itemType: 'material',
          );

          final targetCartonName = existingCarton?['product_name'] ?? cartonProdName ?? 'كراتين تعبئة';
          final targetCartonCode = existingCarton?['product_code'] ?? cartonProdCode ?? '';
          final targetRawMatId = existingCarton?['raw_material_id'] ?? rawMatId;

          await _client.from('station_product_batches').insert({
            'station_id': stationId,
            'product_name': targetCartonName,
            'product_code': targetCartonCode,
            'quantity': iCartons,
            'remaining_quantity': iCartons,
            'unit_cost': cartonCost,
            'currency': 'EGP',
            'exchange_rate': 1.0,
            'source_type': 'export_return',
            'source_date': returnDate.toIso8601String(),
            'supplier_name': 'مرتجع شحنة ${sData['shipment_no']}',
            'item_type': 'material',
            'raw_material_id': targetRawMatId,
          });

          if (existingCarton != null && existingCarton['id'] != null) {
            final curQty = (existingCarton['quantity'] as num?)?.toDouble() ?? 0.0;
            await _client.from('station_products').update({
              'quantity': curQty + iCartons,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', existingCarton['id']);
          } else {
            await _client.from('station_products').insert({
              'station_id': stationId,
              'product_name': targetCartonName,
              'product_code': targetCartonCode,
              'quantity': iCartons,
              'raw_material_id': targetRawMatId,
              'item_type': 'material',
              'unit': 'piece',
            });
          }
        } catch (e) {
          debugPrint('⚠️ Restock carton batch error: $e');
        }
      }
    }

    // 3. Operational unlinking of Packing Orders: reset sold_cartons = 0, status = returned, prepend #
    final poIds = items.map((e) => e['packing_order_id']).where((id) => id != null).toSet();
    final returnNum = 'EXR-$shipmentId';
    for (final pId in poIds) {
      final poIdInt = int.tryParse('$pId');
      if (poIdInt == null) continue;
      try {
        final po = await _client.from('packing_orders').select('order_number, notes').eq('id', poIdInt).maybeSingle();
        final curOrderNum = po?['order_number']?.toString() ?? '$poIdInt';
        final newOrderNum = curOrderNum.startsWith('#') ? curOrderNum : '#$curOrderNum';
        final curNotes = po?['notes']?.toString() ?? '';
        final returnNote = '\n[مرتجع من المطار #$returnNum] تم إرجاع كامل البضاعة للمحطة وفك الارتباط مع الشحنة التصديرية';

        await _client.from('packing_orders').update({
          'export_shipment_id': null,
          'sold_cartons': 0,
          'status': 'returned',
          'order_number': newOrderNum,
          'notes': curNotes + returnNote,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', poIdInt);

        await _client.from('packing_order_lines').update({
          'sold_cartons': 0,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('packing_order_id', poIdInt);
      } catch (e) {
        debugPrint('⚠️ Error updating returned packing order $poIdInt: $e');
      }
    }

    // C. Reverse customer balance
    final custId = sData['customer_id']?.toString();
    double netRevenue = 0.0;
    try {
      final itemsData = await _client.from('export_shipment_items').select('amount').eq('shipment_id', shipmentId);
      final totRev = (itemsData as List).fold<double>(0.0, (sum, i) => sum + ((i['amount'] as num?)?.toDouble() ?? 0.0));
      final disc = (sData['discount_amount'] as num?)?.toDouble() ?? 0.0;
      netRevenue = (totRev - disc).clamp(0.0, double.infinity);

      if (custId != null && custId.isNotEmpty && netRevenue > 0) {
        final cust = await _client.from('customers').select('balance').eq('id', custId).maybeSingle();
        if (cust != null) {
          final curBal = (cust['balance'] as num?)?.toDouble() ?? 0.0;
          await _client.from('customers').update({'balance': curBal - netRevenue}).eq('id', custId);
        }

        await _client.from('ledger_entries').insert({
          'entity_type': 'customer',
          'entity_id': custId,
          'entry_type': 'credit',
          'amount': netRevenue,
          'currency': sData['currency'] ?? 'USD',
          'reference_type': 'export_return',
          'reference_text': 'EXR-$shipmentId',
          'description': 'مرتجع شحنة تصدير من المطار رقم ${sData['shipment_no']}',
        });
      }
    } catch (e) {
      debugPrint('⚠️ Customer balance reversal error: $e');
    }

    // D. Update export shipment status & ZERO OUT Revenue/Profit
    await _client.from('export_shipments').update({
      'status': 'returned_from_airport',
      'total_revenue_foreign': 0.0,
      'total_revenue_egp': 0.0,
      'net_profit': 0.0,
      'net_profit_egp': 0.0,
      'gross_profit': 0.0,
      'internal_notes': '${sData['internal_notes'] ?? ''}\n[$dateStr] تم تسجيل رجوع الشحنة من المطار برقم $returnNum (سليم: $intactCartons كرتونة / تالف: $damagedCartons كرتونة)',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', shipmentId);

    // Extra Expenses Supplier Liabilities & Ledger
    for (final exp in extraExpenses) {
      final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
      final suppId = exp['supplier_id']?.toString();
      final expName = exp['name']?.toString() ?? 'مصروف رجوع شحنة';
      if (amt > 0 && suppId != null && suppId.trim().isNotEmpty) {
        final cleanSuppId = suppId.trim();
        try {
          await _client.from('ledger_entries').insert({
            'entity_type': 'supplier',
            'entity_id': cleanSuppId,
            'entry_type': 'credit',
            'amount': amt,
            'currency': 'EGP',
            'reference_type': 'export_return_expense',
            'reference_text': returnNum,
            'description': 'مصروف رجوع شحنة: $expName (شحنة #${sData['shipment_no']})',
          });

          // Update suppliers balance
          try {
            final supp = await _client.from('suppliers').select('outstanding_balance').or('id.eq.$cleanSuppId,code.eq.$cleanSuppId,supplier_code.eq.$cleanSuppId').maybeSingle();
            if (supp != null) {
              final bal = (supp['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
              await _client.from('suppliers').update({
                'outstanding_balance': bal + amt,
                'updated_at': DateTime.now().toIso8601String(),
              }).or('id.eq.$cleanSuppId,code.eq.$cleanSuppId,supplier_code.eq.$cleanSuppId');
            }
          } catch (_) {}

          // Update transport suppliers balance if applicable
          try {
            final tSupp = await _client.from('transport_suppliers').select('balance').or('id.eq.$cleanSuppId,code.eq.$cleanSuppId').maybeSingle();
            if (tSupp != null) {
              final bal = (tSupp['balance'] as num?)?.toDouble() ?? 0.0;
              await _client.from('transport_suppliers').update({
                'balance': bal + amt,
                'updated_at': DateTime.now().toIso8601String(),
              }).or('id.eq.$cleanSuppId,code.eq.$cleanSuppId');
            }
          } catch (_) {}

          // Update shipping companies balance if applicable
          try {
            final sComp = await _client.from('shipping_companies').select('balance, current_balance').or('id.eq.$cleanSuppId,code.eq.$cleanSuppId').maybeSingle();
            if (sComp != null) {
              final bal = (sComp['balance'] as num?)?.toDouble() ?? 0.0;
              final curBal = (sComp['current_balance'] as num?)?.toDouble() ?? bal;
              await _client.from('shipping_companies').update({
                'balance': bal + amt,
                'current_balance': curBal + amt,
              }).or('id.eq.$cleanSuppId,code.eq.$cleanSuppId');
            }
          } catch (_) {}

          // Update clearing agents balance if applicable
          try {
            final cAgent = await _client.from('clearing_agents').select('balance, current_balance').or('id.eq.$cleanSuppId,code.eq.$cleanSuppId').maybeSingle();
            if (cAgent != null) {
              final bal = (cAgent['balance'] as num?)?.toDouble() ?? 0.0;
              final curBal = (cAgent['current_balance'] as num?)?.toDouble() ?? bal;
              await _client.from('clearing_agents').update({
                'balance': bal + amt,
                'current_balance': curBal + amt,
              }).or('id.eq.$cleanSuppId,code.eq.$cleanSuppId');
            }
          } catch (_) {}
        } catch (e) {
          debugPrint('⚠️ Fallback extra expense ledger error: $e');
        }
      }
    }

    // E. Create & Post Return Journal Entry in GL
    int? returnJournalEntryId;
    try {
      final List<Map<String, dynamic>> jeLines = [];
      final double exchRate = (sData['exchange_rate'] as num?)?.toDouble() ?? 1.0;
      final desc = 'قيد تسوية رجوع شحنة تصدير رقم ${sData['shipment_no']} ($returnNum)';

      // 1. Reverse Revenue & Customer AR
      if (netRevenue > 0) {
        final revAcc = await _client.from('accounts').select('id').like('account_code', '4111%').eq('is_leaf', true).limit(1).maybeSingle();
        final arAcc = await _client.from('accounts').select('id').eq('account_code', '12511').eq('is_leaf', true).limit(1).maybeSingle();
        if (revAcc != null && arAcc != null) {
          jeLines.add({
            'account_id': revAcc['id'],
            'debit': netRevenue * exchRate,
            'credit': 0,
            'base_debit': netRevenue * exchRate,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - إلغاء إيراد التصدير',
            if (costCenterId != null) 'cost_center_id': costCenterId,
          });
          jeLines.add({
            'account_id': arAcc['id'],
            'debit': 0,
            'credit': netRevenue * exchRate,
            'base_debit': 0,
            'base_credit': netRevenue * exchRate,
            'currency': 'EGP',
            'description': '$desc - إلغاء مديونية العميل',
          });
        }
      }

      // 2. Restock & Waste Lines
      final totalGoodsCost = intactCropCost + intactMaterialCost + cropWasteCost + matWasteCost;
      if (totalGoodsCost > 0) {
        final cropInv = await _client.from('accounts').select('id').eq('account_code', '12413').eq('is_leaf', true).limit(1).maybeSingle()
            ?? await _client.from('accounts').select('id').eq('account_code', '12412').eq('is_leaf', true).limit(1).maybeSingle();
        final matInv = await _client.from('accounts').select('id').eq('account_code', '12411').eq('is_leaf', true).limit(1).maybeSingle()
            ?? await _client.from('accounts').select('id').eq('account_code', '12414').eq('is_leaf', true).limit(1).maybeSingle();
        final cropWaste = await _client.from('accounts').select('id').eq('account_code', '34110').eq('is_leaf', true).limit(1).maybeSingle()
            ?? await _client.from('accounts').select('id').eq('account_code', '12414').eq('is_leaf', true).limit(1).maybeSingle();
        final matWaste = await _client.from('accounts').select('id').eq('account_code', '34110').eq('is_leaf', true).limit(1).maybeSingle()
            ?? await _client.from('accounts').select('id').eq('account_code', '33111').eq('is_leaf', true).limit(1).maybeSingle();
        final cogsAcc = await _client.from('accounts').select('id').eq('account_code', '34111').eq('is_leaf', true).limit(1).maybeSingle();

        if (intactCropCost > 0 && cropInv != null) {
          jeLines.add({
            'account_id': cropInv['id'],
            'debit': intactCropCost,
            'credit': 0,
            'base_debit': intactCropCost,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - رد محصول خام سليم للمخزن',
          });
        }
        if (intactMaterialCost > 0 && matInv != null) {
          jeLines.add({
            'account_id': matInv['id'],
            'debit': intactMaterialCost,
            'credit': 0,
            'base_debit': intactMaterialCost,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - رد كراتين تعبئة سليمة للمخزن',
          });
        }
        if (cropWasteCost > 0 && cropWaste != null) {
          jeLines.add({
            'account_id': cropWaste['id'],
            'debit': cropWasteCost,
            'credit': 0,
            'base_debit': cropWasteCost,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - مصروف هالك وتلف محصول',
            if (costCenterId != null) 'cost_center_id': costCenterId,
          });
        }
        if (matWasteCost > 0 && matWaste != null) {
          jeLines.add({
            'account_id': matWaste['id'],
            'debit': matWasteCost,
            'credit': 0,
            'base_debit': matWasteCost,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - مصروف هالك كراتين ومواد تعبئة',
            if (costCenterId != null) 'cost_center_id': costCenterId,
          });
        }
        if (cogsAcc != null) {
          jeLines.add({
            'account_id': cogsAcc['id'],
            'debit': 0,
            'credit': totalGoodsCost,
            'base_debit': 0,
            'base_credit': totalGoodsCost,
            'currency': 'EGP',
            'description': '$desc - تسوية تكلفة بضاعة الشحنة المرتجعة',
          });
        }
      }

      // 3. Extra Expenses Lines (per-item breakdown with supplier resolution)
      for (final exp in extraExpenses) {
        final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
        if (amt <= 0) continue;

        final expName = (exp['name'] ?? 'مصروف رجوع شحنة').toString().trim();
        final rawSuppId = exp['supplier_id']?.toString().trim();
        final suppId = (rawSuppId != null && rawSuppId.isNotEmpty) ? rawSuppId : null;
        final rawSuppName = exp['supplier_name']?.toString().trim();
        final suppType = exp['supplier_type']?.toString().trim() ?? exp['supplier_category']?.toString().trim() ?? '';
        String resolvedSupplierName = (rawSuppName != null && rawSuppName.isNotEmpty) ? rawSuppName : '';

        // A. Resolve Expense Account (Debit)
        int? expenseAccountId;
        final lowerName = expName.toLowerCase();
        if (lowerName.contains('نولون') || lowerName.contains('نقل') || lowerName.contains('مشال') || lowerName.contains('شحن') || lowerName.contains('transport') || lowerName.contains('freight')) {
          final acc = await _client.from('accounts').select('id').eq('account_code', '34114').eq('is_leaf', true).limit(1).maybeSingle();
          expenseAccountId = acc?['id'] as int?;
        } else if (lowerName.contains('تخليص') || lowerName.contains('clearance') || lowerName.contains('جمرك')) {
          final acc = await _client.from('accounts').select('id').eq('account_code', '34117').eq('is_leaf', true).limit(1).maybeSingle();
          expenseAccountId = acc?['id'] as int?;
        } else if (lowerName.contains('عمال') || lowerName.contains('تفريغ') || lowerName.contains('تحميل') || lowerName.contains('labor')) {
          final acc = await _client.from('accounts').select('id').eq('account_code', '34113').eq('is_leaf', true).limit(1).maybeSingle();
          expenseAccountId = acc?['id'] as int?;
        }
        
        if (expenseAccountId == null) {
          final acc = await _client.from('accounts').select('id').eq('account_code', '34110').eq('is_leaf', true).limit(1).maybeSingle()
              ?? await _client.from('accounts').select('id').eq('account_code', '34114').eq('is_leaf', true).limit(1).maybeSingle();
          expenseAccountId = acc?['id'] as int?;
        }

        // B. Resolve Supplier Liability Account (Credit)
        int? supplierAccountId;
        if (suppId != null) {
          // Check suppliers table (UUID id or code)
          try {
            final suppRow = await _client.from('suppliers').select('account_id, name, supplier_type').or('id.eq.$suppId,code.eq.$suppId,supplier_code.eq.$suppId').maybeSingle();
            if (suppRow != null) {
              if (suppRow['account_id'] != null) supplierAccountId = suppRow['account_id'] as int?;
              if (resolvedSupplierName.isEmpty && suppRow['name'] != null) resolvedSupplierName = suppRow['name'].toString();
            }
          } catch (_) {}

          // Check transport_suppliers table
          if (supplierAccountId == null) {
            try {
              final tSupp = await _client.from('transport_suppliers').select('account_id, name').or('id.eq.$suppId,code.eq.$suppId').maybeSingle();
              if (tSupp != null) {
                if (tSupp['account_id'] != null) supplierAccountId = tSupp['account_id'] as int?;
                if (resolvedSupplierName.isEmpty && tSupp['name'] != null) resolvedSupplierName = tSupp['name'].toString();
              }
            } catch (_) {}
          }

          // Check shipping_companies table
          if (supplierAccountId == null) {
            try {
              final sComp = await _client.from('shipping_companies').select('account_id, name').or('id.eq.$suppId,code.eq.$suppId').maybeSingle();
              if (sComp != null) {
                if (sComp['account_id'] != null) supplierAccountId = sComp['account_id'] as int?;
                if (resolvedSupplierName.isEmpty && sComp['name'] != null) resolvedSupplierName = sComp['name'].toString();
              }
            } catch (_) {}
          }

          // Check clearing_agents table
          if (supplierAccountId == null) {
            try {
              final cAgent = await _client.from('clearing_agents').select('account_id, name').or('id.eq.$suppId,code.eq.$suppId').maybeSingle();
              if (cAgent != null) {
                if (cAgent['account_id'] != null) supplierAccountId = cAgent['account_id'] as int?;
                if (resolvedSupplierName.isEmpty && cAgent['name'] != null) resolvedSupplierName = cAgent['name'].toString();
              }
            } catch (_) {}
          }

          // Fallback to category control accounts
          if (supplierAccountId == null) {
            final type = suppType.toLowerCase();
            String targetCode = '21113';
            if (type.contains('transport') || type.contains('نقل')) {
              targetCode = '21111';
            } else if (type.contains('shipping') || type.contains('شحن')) {
              targetCode = '21115';
            } else if (type.contains('clearing') || type.contains('تخليص')) {
              targetCode = '21116';
            } else if (type.contains('packaging') || type.contains('تعبئ')) {
              targetCode = '21112';
            }
            final acc = await _client.from('accounts').select('id').eq('account_code', targetCode).eq('is_leaf', true).limit(1).maybeSingle()
                ?? await _client.from('accounts').select('id').eq('account_code', '21111').eq('is_leaf', true).limit(1).maybeSingle();
            supplierAccountId = acc?['id'] as int?;
          }
        }

        // Fallback to general accrued clearing if no supplier found
        if (supplierAccountId == null) {
          final acc = await _client.from('accounts').select('id').eq('account_code', '21111').eq('is_leaf', true).limit(1).maybeSingle()
              ?? await _client.from('accounts').select('id').eq('account_code', '2111').limit(1).maybeSingle();
          supplierAccountId = acc?['id'] as int?;
        }

        if (expenseAccountId != null && supplierAccountId != null) {
          final suppLabel = resolvedSupplierName.isNotEmpty ? ' ($resolvedSupplierName)' : '';
          jeLines.add({
            'account_id': expenseAccountId,
            'debit': amt,
            'credit': 0,
            'base_debit': amt,
            'base_credit': 0,
            'currency': 'EGP',
            'description': '$desc - $expName$suppLabel',
            'cost_center_id': costCenterId ?? sData['shipment_no'],
          });

          jeLines.add({
            'account_id': supplierAccountId,
            'debit': 0,
            'credit': amt,
            'base_debit': 0,
            'base_credit': amt,
            'currency': 'EGP',
            'description': resolvedSupplierName.isNotEmpty
                ? '$desc - استحقاق مورد: $resolvedSupplierName ($expName)'
                : '$desc - مخصص مصروفات رجوع: $expName',
            if (suppId != null) 'entity_type': 'supplier',
            if (suppId != null) 'entity_id': suppId,
          });
        }
      }

      if (jeLines.isNotEmpty) {
        final companyId = sData['company_id'] ?? 'a0000000-0000-0000-0000-000000000001';
        final jeRes = await _client.rpc('post_journal_entry', params: {
          'p_source_type': 'export_return',
          'p_description': desc,
          'p_entry_date': dateStr,
          'p_company_id': companyId,
          'p_created_by': null,
          'p_lines': jeLines,
          'p_source_id': shipmentId.toString(),
        });
        if (jeRes != null) {
          returnJournalEntryId = jeRes is int ? jeRes : int.tryParse('$jeRes');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Fallback journal entry creation notice: $e');
    }

    if (returnJournalEntryId != null) {
      try {
        await _client.from('export_shipments').update({
          'return_journal_entry_id': returnJournalEntryId,
        }).eq('id', shipmentId);
      } catch (_) {}
    }

    // F. Record in export_shipment_returns table
    int? returnRecordId;
    try {
      final retRes = await _client.from('export_shipment_returns').insert({
        'return_number': returnNum,
        'shipment_id': shipmentId,
        'station_id': stationId,
        'return_date': dateStr,
        'cost_center_id': costCenterId,
        'total_cartons': totalCartons,
        'intact_cartons': intactCartons,
        'damaged_cartons': damagedCartons,
        'total_crop_weight': totalWeight,
        'intact_crop_weight': intactWeight,
        'damaged_crop_weight': damagedWeight,
        'crop_waste_cost': cropWasteCost,
        'material_waste_cost': matWasteCost,
        'extra_expenses_cost': extraExpensesCost,
        'reversed_revenue_amount': netRevenue,
        'currency': sData['currency'] ?? 'USD',
        'exchange_rate': (sData['exchange_rate'] as num?)?.toDouble() ?? 1.0,
        'return_reason': returnReason,
        'notes': notes,
        'raw_data': {'items': items, 'extra_expenses': extraExpenses},
        'journal_entry_id': returnJournalEntryId,
      }).select('id').maybeSingle();
      if (retRes != null) returnRecordId = retRes['id'] as int?;
    } catch (e) {
      debugPrint('ℹ️ export_shipment_returns insert notice: $e');
    }

    // Guarantee that Cost Center Transactions are synced & populated under the season cost center
    try {
      await _syncReturnCostCenterTransactions(
        shipmentId: shipmentId,
        returnNo: returnNum,
        returnDate: returnDate,
        costCenterId: costCenterId,
        items: items,
        extraExpenses: extraExpenses,
      );
    } catch (e) {
      debugPrint('⚠️ Error syncing cost center transactions in fallback: $e');
    }

    return {
      'success': true,
      'return_id': returnRecordId ?? shipmentId,
      'return_number': returnNum,
      'journal_entry_id': returnJournalEntryId,
      'intact_cartons': intactCartons,
      'damaged_cartons': damagedCartons,
      'intact_crop_weight': intactWeight,
      'damaged_crop_weight': damagedWeight,
      'crop_waste_cost': cropWasteCost,
      'material_waste_cost': matWasteCost,
      'message': 'تم تسجيل رجوع الشحنة من المطار بنجاح وتسوية المخزون والهالك والقيد المحاسبي',
    };
  }

  /// Get return info if shipment was returned
  Future<Map<String, dynamic>?> getShipmentReturn(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return null;
      final data = await _client
          .from('export_shipment_returns')
          .select()
          .eq('shipment_id', sid)
          .maybeSingle();
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      debugPrint('ExportShipmentDao.getShipmentReturn error: $e');
      return null;
    }
  }

  /// Syncs export shipment return waste and extra expenses directly into cost_center_transactions
  Future<void> _syncReturnCostCenterTransactions({
    required int shipmentId,
    required String returnNo,
    required DateTime returnDate,
    required String? costCenterId,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> extraExpenses = const [],
  }) async {
    final dateStr = returnDate.toIso8601String().split('T').first;

    // 1. Fetch shipment metadata
    final shipRow = await _client.from('export_shipments').select('shipment_no, notes, internal_notes, customer_name, customers(name)').eq('id', shipmentId).maybeSingle();
    final shipmentNo = shipRow?['shipment_no']?.toString() ?? '$shipmentId';
    final custName = shipRow?['customer_name']?.toString() ??
        (shipRow?['customers'] is Map ? (shipRow!['customers'] as Map)['name']?.toString() : null) ??
        'عميل شحنة #$shipmentNo';

    // 2. Resolve target Cost Center
    String resolvedCcId = costCenterId ?? '';
    String resolvedCcName = 'مركز تكلفة الموسم';

    if (resolvedCcId.isEmpty) {
      try {
        final ccList = await CostCenterService.instance.fetchCostCenters();
        final mangoCc = ccList.firstWhere(
          (c) => c.code == 'CC-MANGO-2026-2027' || c.nameAr.contains('مانجو'),
          orElse: () => ccList.first,
        );
        resolvedCcId = mangoCc.code ?? mangoCc.id;
        resolvedCcName = mangoCc.nameAr;
      } catch (_) {
        resolvedCcId = 'CC-MANGO-2026-2027';
      }
    } else {
      try {
        final ccRow = await _client.from('cost_centers').select('name_ar, code').or('code.eq.$resolvedCcId,id.eq.$resolvedCcId').maybeSingle();
        if (ccRow != null && ccRow['name_ar'] != null) {
          resolvedCcName = ccRow['name_ar'].toString();
          if (ccRow['code'] != null) resolvedCcId = ccRow['code'].toString();
        }
      } catch (_) {}
    }

    // 3. Sync Crop Waste
    for (int i = 0; i < items.length; i++) {
      final itm = items[i];
      final damagedWeight = (itm['damaged_weight'] as num?)?.toDouble() ?? 0.0;
      final cropCost = (itm['crop_unit_cost'] as num?)?.toDouble() ?? 0.0;
      final wasteCost = damagedWeight * cropCost;
      final prodName = itm['product_name']?.toString() ?? 'محصول مرتجع';
      final itemId = itm['item_id'] ?? '$i';

      if (wasteCost > 0 || damagedWeight > 0) {
        final sourceId = 'exr_crop_waste_${returnNo}_$itemId';
        await _client.from('cost_center_transactions').upsert({
          'cost_center_id': resolvedCcId,
          'cost_center_name': resolvedCcName,
          'cost_center_type': 'crop',
          'source_type': 'export_return_waste',
          'source_id': sourceId,
          'transaction_date': dateStr,
          'supplier_name': custName,
          'product_id': itm['fruit_type_id'],
          'item_name': 'هالك رجوع شحنة (محصول) - $prodName',
          'category': 'تكلفة الهالك',
          'quantity': damagedWeight,
          'unit_price': cropCost > 0 ? cropCost : (damagedWeight > 0 ? wasteCost / damagedWeight : 0.0),
          'currency': 'EGP',
          'exchange_rate': 1.0,
          'total_in_currency': wasteCost,
          'amount': wasteCost,
          'notes': 'هالك وتلف محصول عند رجوع الشحنة التصديرية رقم $shipmentNo ($returnNo)',
          'is_confirmed': true,
        }, onConflict: 'source_type,source_id');
      }

      // 4. Sync Material Waste (Cartons)
      final damagedCartons = (itm['damaged_cartons'] as num?)?.toInt() ?? 0;
      final cartonCost = (itm['carton_unit_cost'] as num?)?.toDouble() ?? 0.0;
      final matWasteCost = damagedCartons * cartonCost;
      final cartonName = itm['carton_product_name']?.toString() ?? 'كراتين تعبئة';

      if (matWasteCost > 0 || damagedCartons > 0) {
        final sourceId = 'exr_mat_waste_${returnNo}_$itemId';
        await _client.from('cost_center_transactions').upsert({
          'cost_center_id': resolvedCcId,
          'cost_center_name': resolvedCcName,
          'cost_center_type': 'crop',
          'source_type': 'export_return_waste',
          'source_id': sourceId,
          'transaction_date': dateStr,
          'supplier_name': custName,
          'item_name': 'هالك رجوع شحنة (كراتين) - $cartonName',
          'category': 'مواد التعبئة',
          'quantity': damagedCartons.toDouble(),
          'unit_price': cartonCost > 0 ? cartonCost : (damagedCartons > 0 ? matWasteCost / damagedCartons : 0.0),
          'currency': 'EGP',
          'exchange_rate': 1.0,
          'total_in_currency': matWasteCost,
          'amount': matWasteCost,
          'notes': 'هالك كراتين ومواد تعبئة عند رجوع الشحنة التصديرية رقم $shipmentNo ($returnNo)',
          'is_confirmed': true,
        }, onConflict: 'source_type,source_id');
      }
    }

    // 5. Sync Extra Return Expenses
    for (int i = 0; i < extraExpenses.length; i++) {
      final exp = extraExpenses[i];
      final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
      if (amt <= 0) continue;

      final expName = (exp['name'] ?? 'مصروف رجوع شحنة').toString().trim();
      final suppName = exp['supplier_name']?.toString().trim();
      final suppId = exp['supplier_id']?.toString().trim();
      final suppType = (exp['supplier_type'] ?? exp['supplier_category'] ?? '').toString().toLowerCase();

      String category = 'لوجستيك ونقل';
      final lowerName = expName.toLowerCase();
      if (lowerName.contains('نولون') || lowerName.contains('نقل') || lowerName.contains('مشال') || suppType.contains('transport')) {
        category = 'لوجستيك ونقل';
      } else if (lowerName.contains('تخليص') || lowerName.contains('جمرك') || suppType.contains('clearing')) {
        category = 'تكلفة المخلصين';
      } else if (lowerName.contains('شحن') || lowerName.contains('freight') || suppType.contains('shipping')) {
        category = 'تكلفة شركات الشحن';
      }

      final sourceId = 'exr_exp_${returnNo}_$i';
      await _client.from('cost_center_transactions').upsert({
        'cost_center_id': resolvedCcId,
        'cost_center_name': resolvedCcName,
        'cost_center_type': 'crop',
        'source_type': 'export_return_expense',
        'source_id': sourceId,
        'transaction_date': dateStr,
        'supplier_id': suppId,
        'supplier_name': suppName ?? custName,
        'item_name': expName,
        'category': category,
        'quantity': 1.0,
        'unit_price': amt,
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'total_in_currency': amt,
        'amount': amt,
        'notes': 'مصروف رجوع شحنة تصدير رقم $shipmentNo ($returnNo)${exp['notes'] != null ? ' - ${exp['notes']}' : ''}',
        'is_confirmed': true,
      }, onConflict: 'source_type,source_id');
    }
  }

  /// Resolves the actual FIFO unit cost of raw fruit (per kg) and carton packaging (per unit)
  /// from the linked packing orders, packing order lines, purchase lots, or shipment costing.
  Future<Map<String, dynamic>> resolveActualItemCosts({
    required dynamic shipmentId,
    required Map<String, dynamic> item,
  }) async {
    final sId = shipmentId is int ? shipmentId : (int.tryParse('$shipmentId') ?? 0);
    double cropCostPerKg = 0.0;
    double cartonCostPerUnit = 0.0;
    String? cartonName;
    String? cartonCode;
    String? cartonRawMatId;
    int? fruitTypeId = item['finished_product_id'] != null
        ? int.tryParse(item['finished_product_id'].toString())
        : (item['fruit_type_id'] != null ? int.tryParse(item['fruit_type_id'].toString()) : null);
    String? fruitCode = item['product_code']?.toString();
    String costSource = 'افتراضي';

    final poId = item['packing_order_id'] is num
        ? (item['packing_order_id'] as num).toInt()
        : int.tryParse(item['packing_order_id']?.toString() ?? '');
    final poLineId = item['packing_order_line_id'] is num
        ? (item['packing_order_line_id'] as num).toInt()
        : int.tryParse(item['packing_order_line_id']?.toString() ?? '');

    try {
      // 1. Try from Packing Order & Product Cost Summary (packing_order_lines)
      Map<String, dynamic>? poData;
      if (poId != null) {
        poData = await _client
            .from('packing_orders')
            .select()
            .eq('id', poId)
            .maybeSingle();
      }

      // If item did not have poId, check if the shipment itself has linked packing orders
      if (poData == null) {
        try {
          final poList = await _client
              .from('packing_orders')
              .select()
              .or('export_shipment_id.eq.$sId,export_shipment_id.eq.${sId.toString()}')
              .limit(1);
          if (poList.isNotEmpty) {
            poData = poList.first;
          }
        } catch (_) {}
      }

      // If still null, check if any other item in this shipment has packing_order_id
      if (poData == null && sId > 0) {
        try {
          final otherItems = await _client
              .from('export_shipment_items')
              .select('packing_order_id')
              .eq('shipment_id', sId)
              .not('packing_order_id', 'is', null)
              .limit(1);
          if (otherItems.isNotEmpty) {
            final otherPoId = otherItems.first['packing_order_id'];
            if (otherPoId != null) {
              poData = await _client
                  .from('packing_orders')
                  .select()
                  .eq('id', otherPoId)
                  .maybeSingle();
            }
          }
        } catch (_) {}
      }

      if (poData != null) {
        final poNum = poData['order_number'] ?? poData['id'];
        final actualPoId = poData['id'] is num ? (poData['id'] as num).toInt() : int.tryParse(poData['id']?.toString() ?? '') ?? poId;

        // Authoritative resolution from PackingCalculationService (ملخص تكلفة المنتجات)
        List<Map<String, dynamic>> allDbLines = [];
        if (actualPoId != null) {
          try {
            final fetched = await _client
                .from('packing_order_lines')
                .select()
                .eq('packing_order_id', actualPoId)
                .order('id');
            allDbLines = List<Map<String, dynamic>>.from(fetched);
          } catch (_) {}
        }

        final itmName = (item['product_name'] ?? item['invoice_product_name'] ?? '').toString().trim();

        // 1. Calculate authoritative ProductCostLine directly via PackingCalculationService
        if (allDbLines.isNotEmpty) {
          try {
            final calculatedProductLines = PackingCalculationService.calculateProductCostLinesFromDb(
              poData: poData,
              dbLines: allDbLines,
            );
            if (calculatedProductLines.isNotEmpty) {
              ProductCostLine? matchedPl;
              // A. Match by exact name
              for (final p in calculatedProductLines) {
                if (p.productName.trim() == itmName) {
                  matchedPl = p;
                  break;
                }
              }
              // B. Match by contains / substring
              if (matchedPl == null && itmName.isNotEmpty) {
                for (final p in calculatedProductLines) {
                  final pTrim = p.productName.trim();
                  if (pTrim.isNotEmpty && (itmName.contains(pTrim) || pTrim.contains(itmName))) {
                    matchedPl = p;
                    break;
                  }
                }
              }
              // C. Single line fallback
              if (matchedPl == null && calculatedProductLines.length == 1) {
                matchedPl = calculatedProductLines.first;
              }

              if (matchedPl != null && matchedPl.finalCost > 0) {
                if (matchedPl.cartonCount > 0) {
                  cartonCostPerUnit = matchedPl.finalCost / matchedPl.cartonCount;
                }
                if (matchedPl.totalNetWeight > 0) {
                  cropCostPerKg = matchedPl.finalCost / matchedPl.totalNetWeight;
                } else if (cartonCostPerUnit > 0) {
                  final wtPerCtn = (item['weight_per_carton'] as num?)?.toDouble() ?? 0.0;
                  if (wtPerCtn > 0) cropCostPerKg = cartonCostPerUnit / wtPerCtn;
                }
                if (cartonCostPerUnit > 0 || cropCostPerKg > 0) {
                  costSource = 'ملخص تكلفة المنتجات (أمر تعبئة #$poNum)';
                }
              }
            }
          } catch (_) {}
        }

        // 2. If not resolved from service, check specific product line from packing_order_lines table
        if (cartonCostPerUnit <= 0 || cropCostPerKg <= 0) {
          Map<String, dynamic>? lineData;
          if (poLineId != null) {
            try {
              lineData = await _client
                  .from('packing_order_lines')
                  .select()
                  .eq('id', poLineId)
                  .maybeSingle();
            } catch (_) {}
          }

          if (lineData == null && allDbLines.isNotEmpty) {
            // Match in allDbLines
            for (final l in allDbLines) {
              final pName = (l['product_name'] ?? '').toString().trim();
              if (pName == itmName || (itmName.isNotEmpty && (itmName.contains(pName) || pName.contains(itmName)))) {
                lineData = l;
                break;
              }
            }
            lineData ??= allDbLines.length == 1 ? allDbLines.first : null;
          }

          if (lineData != null) {
            final lineFinalCost = (lineData['final_cost'] as num?)?.toDouble() ?? 0.0;
            final lineCartons = (lineData['carton_count'] as num?)?.toInt() ??
                (lineData['actual_cartons'] as num?)?.toInt() ?? 0;
            final lineNetWt = (lineData['total_net_weight'] as num?)?.toDouble() ??
                (lineData['net_weight_kg'] as num?)?.toDouble() ?? 0.0;
            final wtPerCtn = (lineData['net_weight_per_carton'] as num?)?.toDouble() ??
                (item['weight_per_carton'] as num?)?.toDouble() ?? 0.0;
            final lineFinalUnitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;

            if (cartonCostPerUnit <= 0) {
              if (lineCartons > 0 && lineFinalCost > 0) {
                cartonCostPerUnit = lineFinalCost / lineCartons;
              } else if (lineFinalUnitCost > 0) {
                cartonCostPerUnit = lineFinalUnitCost;
              }
            }

            if (cropCostPerKg <= 0) {
              if (lineNetWt > 0 && lineFinalCost > 0) {
                cropCostPerKg = lineFinalCost / lineNetWt;
              } else if (cartonCostPerUnit > 0 && wtPerCtn > 0) {
                cropCostPerKg = cartonCostPerUnit / wtPerCtn;
              }
            }

            if (cartonCostPerUnit > 0 || cropCostPerKg > 0) {
              costSource = 'ملخص تكلفة المنتجات (أمر تعبئة #$poNum)';
            }
          }
        }

        // B. Fallback to packing order comprehensive totals if line costs not found
        if (cartonCostPerUnit <= 0) {
          final poCostPerCarton = (poData['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
          final poTotalCost = (poData['total_packing_cost'] as num?)?.toDouble() ?? 0.0;
          final poCartons = (poData['carton_count'] as num?)?.toInt() ?? 0;

          if (poCartons > 0 && poTotalCost > 0) {
            cartonCostPerUnit = poTotalCost / poCartons;
          } else if (poCostPerCarton > 0) {
            cartonCostPerUnit = poCostPerCarton;
          } else {
            final computed = PackingCalculationService.computeEffectiveCostPerCarton(poData);
            if (computed > 0) cartonCostPerUnit = computed;
          }
          if (cartonCostPerUnit > 0 && costSource == 'افتراضي') {
            costSource = 'ملخص أمر تعبئة #$poNum';
          }
        }

        if (cropCostPerKg <= 0) {
          final poTotalCost = (poData['total_packing_cost'] as num?)?.toDouble() ?? 0.0;
          final poTotalNetWt = (poData['total_net_weight'] as num?)?.toDouble() ?? 0.0;
          final wtPerC = (item['weight_per_carton'] as num?)?.toDouble() ??
              (poData['net_weight_per_carton'] as num?)?.toDouble() ?? 0.0;

          if (poTotalNetWt > 0 && poTotalCost > 0) {
            cropCostPerKg = poTotalCost / poTotalNetWt;
          } else if (cartonCostPerUnit > 0 && wtPerC > 0) {
            cropCostPerKg = cartonCostPerUnit / wtPerC;
          }
          if (cropCostPerKg > 0 && costSource == 'افتراضي') {
            costSource = 'ملخص أمر تعبئة #$poNum';
          }
        }

        // C. Carton material details from notes['materials']
        Map<String, dynamic> notes = {};
        if (poData['notes'] != null) {
          if (poData['notes'] is Map) {
            notes = Map<String, dynamic>.from(poData['notes'] as Map);
          } else if (poData['notes'] is String && (poData['notes'] as String).isNotEmpty) {
            try {
              notes = Map<String, dynamic>.from(jsonDecode(poData['notes'] as String) as Map);
            } catch (_) {}
          }
        }

        if (notes['materials'] is List && (notes['materials'] as List).isNotEmpty) {
          final mats = (notes['materials'] as List);
          Map<String, dynamic>? cartonMat;
          for (final m in mats) {
            if (m is Map) {
              final mName = (m['product_name'] ?? m['name'] ?? '').toString();
              if (mName.contains('كرتون') || mName.toLowerCase().contains('carton') || mName.contains('صندوق')) {
                cartonMat = Map<String, dynamic>.from(m);
                break;
              }
            }
          }
          cartonMat ??= mats.first is Map ? Map<String, dynamic>.from(mats.first as Map) : null;
          if (cartonMat != null) {
            cartonName = cartonMat['product_name']?.toString() ?? cartonMat['name']?.toString();
            cartonCode = cartonMat['product_code']?.toString() ?? cartonMat['code']?.toString();
            cartonRawMatId = cartonMat['raw_material_id']?.toString() ?? cartonMat['id']?.toString();
          }
        }
      }

      // 2. Fallback to shipment_cost_breakdown if costs still 0
      if (cropCostPerKg <= 0 || cartonCostPerUnit <= 0) {
        try {
          final breakdowns = await _client
              .from('shipment_cost_breakdown')
              .select()
              .eq('shipment_id', sId);
          for (final b in breakdowns) {
            final type = b['cost_type']?.toString();
            if (cropCostPerKg <= 0 && type == 'fruit') {
              cropCostPerKg = (b['fruit_cost_per_kg'] as num?)?.toDouble() ?? 0.0;
              if (cropCostPerKg <= 0) {
                final tot = (b['total_cost'] as num?)?.toDouble() ?? 0.0;
                final q = (b['quantity'] as num?)?.toDouble() ?? 0.0;
                if (q > 0 && tot > 0) cropCostPerKg = tot / q;
              }
              if (costSource == 'افتراضي') costSource = 'مركز تكلفة الشحنة';
            }
            if (cartonCostPerUnit <= 0 && type == 'packing_material') {
              cartonCostPerUnit = (b['unit_cost'] as num?)?.toDouble() ?? 0.0;
              if (cartonCostPerUnit <= 0) {
                final tot = (b['total_cost'] as num?)?.toDouble() ?? 0.0;
                final q = (b['quantity'] as num?)?.toDouble() ?? 0.0;
                if (q > 0 && tot > 0) cartonCostPerUnit = tot / q;
              }
              if (costSource == 'افتراضي') costSource = 'مركز تكلفة الشحنة';
            }
          }
        } catch (_) {}
      }

      // 3. Fallback to CostAllocationEngine if still 0
      if (cropCostPerKg <= 0 || cartonCostPerUnit <= 0) {
        try {
          final engine = CostAllocationEngine();
          final costRes = await engine.calculateShipmentCosts(sId);
          if (cropCostPerKg <= 0 && costRes.costPerKg > 0) {
            cropCostPerKg = costRes.costPerKg;
            if (costSource == 'افتراضي') costSource = 'محرك توزيع التكاليف';
          }
          if (cartonCostPerUnit <= 0 && costRes.costPerCarton > 0) {
            cartonCostPerUnit = costRes.costPerCarton;
            if (costSource == 'افتراضي') costSource = 'محرك توزيع التكاليف';
          }
        } catch (_) {}
      }

      // 4. Resolve fruit code from fruit_types if still empty
      if (fruitTypeId != null && (fruitCode == null || fruitCode.isEmpty)) {
        try {
          final ft = await _client.from('fruit_types').select('code, name').eq('id', fruitTypeId).maybeSingle();
          if (ft != null) {
            fruitCode = ft['code']?.toString();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ Error resolving actual item costs: $e');
    }

    return {
      'crop_unit_cost': cropCostPerKg > 0 ? cropCostPerKg : 15.0,
      'carton_unit_cost': cartonCostPerUnit > 0 ? cartonCostPerUnit : 20.0,
      'is_actual': cropCostPerKg > 0 || cartonCostPerUnit > 0,
      'carton_product_name': cartonName,
      'carton_product_code': cartonCode,
      'carton_raw_material_id': cartonRawMatId,
      'fruit_type_id': fruitTypeId,
      'fruit_type_code': fruitCode,
      'cost_source': costSource,
    };
  }
}

