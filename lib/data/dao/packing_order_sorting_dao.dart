import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/packing_order_sorting_model.dart';
import '../services/product_cost_center_sync_service.dart';

class PackingOrderSortingDao {
  final _client = Supabase.instance.client;

  /// Completes a sorting sale transaction:
  /// 1. Executes RPC `rpc_sell_sorting` to update remaining weight, total sales,
  ///    record treasury transaction, and post journal entry.
  /// 2. Records financial transaction in `cost_center_transactions` linked to the
  ///    parent fruit's cost center with negative amount to offset net product cost.
  Future<Map<String, dynamic>> processSortingSale({
    required PackingOrderSortingModel sorting,
    required double quantityKg,
    required double unitPrice,
    required int treasuryId,
    required String treasuryName,
    int? customerId,
    String? customerName,
  }) async {
    final amount = quantityKg * unitPrice;

    // 1. Execute database RPC with optional customer_id
    final Map<String, dynamic> rpcParams = {
      'p_sorting_id': sorting.id,
      'p_qty': quantityKg,
      'p_price': unitPrice,
      'p_treasury_id': treasuryId,
      'p_treasury_name': treasuryName,
      if (customerId != null) 'p_customer_id': customerId,
    };

    dynamic rpcRes;
    try {
      rpcRes = await _client.rpc('rpc_sell_sorting', params: rpcParams);
    } catch (e) {
      // Graceful fallback if database function has not yet been updated with p_customer_id
      if (rpcParams.containsKey('p_customer_id')) {
        rpcParams.remove('p_customer_id');
        rpcRes = await _client.rpc('rpc_sell_sorting', params: rpcParams);
      } else {
        rethrow;
      }
    }

    final resMap = (rpcRes is Map) ? Map<String, dynamic>.from(rpcRes) : <String, dynamic>{};
    final txId = (resMap['treasury_transaction_id'] as num?)?.toInt();
    final jeId = (resMap['journal_entry_id'] as num?)?.toInt();

    // 2. Ensure customer_id is recorded in treasury_transactions & customer balance
    if (customerId != null && txId != null) {
      try {
        await _client.from('treasury_transactions').update({
          'customer_id': customerId,
        }).eq('id', txId);
      } catch (_) {}
    }

    // 3. Inject cost center transaction entry linked to original fruit
    await ProductCostCenterSyncService.instance.recordSortingSaleTransaction(
      sortingId: sorting.id ?? 0,
      packingOrderId: sorting.packingOrderId,
      productName: sorting.productName,
      quantityKg: quantityKg,
      unitPrice: unitPrice,
      totalRevenue: amount,
      treasuryName: treasuryName,
      treasuryId: treasuryId,
      treasuryTransactionId: txId,
      journalEntryId: jeId,
      notes: customerName != null && customerName.isNotEmpty
          ? 'بيع فرز للعميل: $customerName'
          : null,
    );

    return resMap;
  }

  Future<List<PackingOrderSortingModel>> getAll({
    String? status,
    int? packingOrderId,
  }) async {
    try {
      List<dynamic> data;
      try {
        var query = _client.from('packing_order_sortings').select(
          packingOrderId == null ? '*, packing_orders(status)' : '*'
        );
        if (status != null) query = query.eq('status', status);
        if (packingOrderId != null) {
          query = query.eq('packing_order_id', packingOrderId);
        }
        data = await query.order('created_at', ascending: false);
        // Exclude records belonging to cancelled packing orders
        data = data.where((row) {
          if (row is Map && row.containsKey('packing_orders')) {
            final po = row['packing_orders'];
            if (po is Map && po['status'] == 'cancelled') return false;
          }
          return true;
        }).toList();
      } catch (innerErr) {
        // Fallback: Query directly without embedded resource if FK relation is not present in PostgREST cache
        var fallbackQuery = _client.from('packing_order_sortings').select('*');
        if (status != null) fallbackQuery = fallbackQuery.eq('status', status);
        if (packingOrderId != null) {
          fallbackQuery = fallbackQuery.eq('packing_order_id', packingOrderId);
        }
        data = await fallbackQuery.order('created_at', ascending: false);
      }
      return data.map((e) => PackingOrderSortingModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.getAll error: $e\n$st');
      rethrow;
    }
  }

  /// Synchronizes sorting records for a specific packing order:
  /// - Leaves partially or fully sold sorting records intact.
  /// - Replaces unsold pending records with the latest allocated sorting items.
  Future<void> syncSortingsForPackingOrder({
    required int packingOrderId,
    required List<PackingOrderSortingModel> items,
  }) async {
    try {
      final existingData = await _client
          .from('packing_order_sortings')
          .select()
          .eq('packing_order_id', packingOrderId);

      final existingSortings = (existingData as List)
          .map((e) => PackingOrderSortingModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Find any items that have been partially or fully sold
      final soldSortings = existingSortings.where((s) => s.remainingWeightKg < s.weightKg || s.status == 'sold').toList();
      final soldIds = soldSortings.map((s) => s.id).whereType<int>().toSet();

      // Delete pending/unsold sortings that will be refreshed
      for (final s in existingSortings) {
        if (s.id != null && !soldIds.contains(s.id)) {
          await _client.from('packing_order_sortings').delete().eq('id', s.id!);
        }
      }

      // Insert or adjust new sorting items
      for (final item in items) {
        final matchingSold = soldSortings.firstWhere(
          (s) => s.lotNumber == item.lotNumber && s.productName == item.productName,
          orElse: () => const PackingOrderSortingModel(packingOrderId: 0, productName: ''),
        );

        if (matchingSold.id != null) {
          final soldWeight = matchingSold.weightKg - matchingSold.remainingWeightKg;
          final updatedRemaining = (item.weightKg - soldWeight).clamp(0.0, double.infinity);
          await _client.from('packing_order_sortings').update({
            'weight_kg': item.weightKg,
            'remaining_weight_kg': updatedRemaining,
            'cost_per_kg': item.costPerKg,
            'total_cost': item.weightKg * item.costPerKg,
            if (item.exportShipmentNo != null) 'export_shipment_no': item.exportShipmentNo,
            if (item.customerName != null) 'customer_name': item.customerName,
            if (item.customerId != null) 'customer_id': item.customerId,
          }).eq('id', matchingSold.id!);
        } else {
          await _client.from('packing_order_sortings').insert(item.toMap()..remove('id'));
        }
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.syncSortingsForPackingOrder error: $e\n$st');
      rethrow;
    }
  }

  Future<List<PackingOrderSortingModel>> getPending() async {
    return getAll(status: 'pending');
  }

  Future<PackingOrderSortingModel?> getById(int id) async {
    try {
      final data = await _client
          .from('packing_order_sortings')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return PackingOrderSortingModel.fromMap(Map<String, dynamic>.from(data));
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.getById error: $e\n$st');
      rethrow;
    }
  }

  Future<void> insert(PackingOrderSortingModel sorting) async {
    try {
      await _client.from('packing_order_sortings').insert(sorting.toMap()..remove('id'));
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> sell(int id, {
    required double quantityKg,
    required double saleAmount,
    String? treasuryName,
  }) async {
    try {
      final existing = await getById(id);
      if (existing == null) throw Exception('Sorting entry not found');

      final newRemaining = existing.remainingWeightKg - quantityKg;
      final newSaleTotal = existing.totalSaleAmount + saleAmount;
      final newStatus = newRemaining <= 0 ? 'sold' : 'pending';

      String? updatedTreasuryNames = existing.treasuryNames;
      if (treasuryName != null) {
        if (updatedTreasuryNames == null || updatedTreasuryNames.isEmpty) {
          updatedTreasuryNames = treasuryName;
        } else if (!updatedTreasuryNames.contains(treasuryName)) {
          updatedTreasuryNames = '$updatedTreasuryNames، $treasuryName';
        }
      }

      await _client.from('packing_order_sortings').update({
        'remaining_weight_kg': newRemaining <= 0 ? 0 : newRemaining,
        'total_sale_amount': newSaleTotal,
        'status': newStatus,
        if (newStatus == 'sold') 'sold_at': DateTime.now().toIso8601String(),
        if (updatedTreasuryNames != null) 'treasury_names': updatedTreasuryNames,
      }).eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.sell error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.from('packing_order_sortings').delete().eq('id', id);
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.delete error: $e\n$st');
      rethrow;
    }
  }
}
