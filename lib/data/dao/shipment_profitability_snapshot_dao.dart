import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipment_profitability_snapshot_model.dart';
import '../services/currency_conversion_service.dart';

class ShipmentProfitabilitySnapshotDao {
  final _client = Supabase.instance.client;

  Future<ShipmentProfitabilitySnapshotModel?> getByShipmentId(int shipmentId) async {
    try {
      final data = await _client
          .from('shipment_profitability_snapshots')
          .select()
.eq('shipment_id', shipmentId)
      .maybeSingle();
      
      if (data != null) {
        return ShipmentProfitabilitySnapshotModel.fromMap(data);
      }
      return null;
    } catch (e) {
      print('Error getting profitability snapshot for shipment $shipmentId: $e');
      return null;
    }
  }

  Future<List<ShipmentProfitabilitySnapshotModel>> getAll({
    int? limit,
    int? offset,
    String? shipmentNo,
  }) async {
    try {
      dynamic query = _client
          .from('shipment_profitability_snapshots')
          .select();
      
      if (shipmentNo != null) {
        query = query.ilike('shipment_no', '%$shipmentNo%');
      }
      
      query = query.order('created_at', ascending: false);
      
      if (limit != null) {
        query = query.limit(limit);
      }
      
      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 50) - 1);
      }
      
      final data = await query;
      return data.map((e) => ShipmentProfitabilitySnapshotModel.fromMap(e)).toList();
    } catch (e) {
      print('Error getting all profitability snapshots: $e');
      return [];
    }
  }

  Future<int> create(ShipmentProfitabilitySnapshotModel snapshot) async {
    try {
      final data = snapshot.toMap();
      data['created_by'] = _client.auth.currentUser?.id;
      data['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
        currency: snapshot.currencyCode,
        amount: snapshot.revenueLocal,
        exchangeRate: snapshot.exchangeRate,
      ).toJson();
      
      final result = await _client
          .from('shipment_profitability_snapshots')
          .insert(data)
          .select()
          .single();
      
      return result['id'] as int;
    } catch (e) {
      print('Error creating profitability snapshot: $e');
      rethrow;
    }
  }

  Future<void> delete(int shipmentId) async {
    try {
      await _client
          .from('shipment_profitability_snapshots')
          .delete()
          .eq('shipment_id', shipmentId);
    } catch (e) {
      print('Error deleting profitability snapshot for shipment $shipmentId: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSummaryStatistics() async {
    try {
      final result = await _client
          .from('shipment_profitability_snapshots')
          .select('''
            total_revenue_local,
            total_cost,
            net_profit,
            gross_margin,
            net_margin
          ''');
      
      final snapshots = result as List<dynamic>;
      
      if (snapshots.isEmpty) {
        return {
          'total_revenue_local': 0.0,
          'total_cost': 0.0,
          'total_net_profit': 0.0,
          'average_gross_margin': 0.0,
          'average_net_margin': 0.0,
          'shipment_count': 0,
        };
      }
      
      final totalRevenue = snapshots.fold<double>(
        0.0,
        (sum, s) => sum + ((s['total_revenue_local'] as num?)?.toDouble() ?? 0.0),
      );
      
      final totalCost = snapshots.fold<double>(
        0.0,
        (sum, s) => sum + ((s['total_cost'] as num?)?.toDouble() ?? 0.0),
      );
      
      final totalNetProfit = snapshots.fold<double>(
        0.0,
        (sum, s) => sum + ((s['net_profit'] as num?)?.toDouble() ?? 0.0),
      );
      
      final totalGrossMargin = snapshots.fold<double>(
        0.0,
        (sum, s) => sum + ((s['gross_margin'] as num?)?.toDouble() ?? 0.0),
      );
      
      final totalNetMargin = snapshots.fold<double>(
        0.0,
        (sum, s) => sum + ((s['net_margin'] as num?)?.toDouble() ?? 0.0),
      );
      
      return {
        'total_revenue_local': totalRevenue,
        'total_cost': totalCost,
        'total_net_profit': totalNetProfit,
        'average_gross_margin': totalGrossMargin / snapshots.length,
        'average_net_margin': totalNetMargin / snapshots.length,
        'shipment_count': snapshots.length,
      };
    } catch (e) {
      print('Error getting profitability summary statistics: $e');
      return {
        'total_revenue_local': 0.0,
        'total_cost': 0.0,
        'total_net_profit': 0.0,
        'average_gross_margin': 0.0,
        'average_net_margin': 0.0,
        'shipment_count': 0,
      };
    }
  }
}
