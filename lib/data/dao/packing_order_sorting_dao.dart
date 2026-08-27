import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/packing_order_sorting_model.dart';

class PackingOrderSortingDao {
  final _client = Supabase.instance.client;

  Future<List<PackingOrderSortingModel>> getAll({
    String? status,
    int? packingOrderId,
  }) async {
    try {
      var query = _client.from('packing_order_sortings').select(
        packingOrderId == null ? '*, packing_orders!inner(status)' : '*'
      );
      if (status != null) query = query.eq('status', status);
      if (packingOrderId != null) {
        query = query.eq('packing_order_id', packingOrderId);
      } else {
        query = query.eq('packing_orders.status', 'completed');
      }
      final data = await query.order('created_at', ascending: false);
      return data.map((e) => PackingOrderSortingModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e, st) {
      debugPrint('❌ PackingOrderSortingDao.getAll error: $e\n$st');
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
