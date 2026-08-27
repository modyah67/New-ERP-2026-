import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessHealthService {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getHealthMetrics() async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('total_revenue_egp, net_profit_egp, total_fruit_cost, total_packing_material_cost, '
              'cost_per_carton, export_price_per_carton, total_landed_cost, cartons_count, net_weight');

      double totalRevenue = 0, totalNetProfit = 0;
      double totalFruitCost = 0, totalPackingCost = 0;
      double totalLandedCost = 0;
      int totalCartons = 0;
      int shipmentCount = 0;

      for (final s in shipments) {
        totalRevenue += (s['total_revenue_egp'] as num?)?.toDouble() ?? 0;
        totalNetProfit += (s['net_profit_egp'] as num?)?.toDouble() ?? 0;
        totalFruitCost += (s['total_fruit_cost'] as num?)?.toDouble() ?? 0;
        totalPackingCost += (s['total_packing_material_cost'] as num?)?.toDouble() ?? 0;
        totalLandedCost += (s['total_landed_cost'] as num?)?.toDouble() ?? 0;
        totalCartons += (s['cartons_count'] as int?) ?? 0;
        shipmentCount++;
      }

      // Inventory turnover (annualized estimate)
      double avgInventory = 0;
      double cogs = totalFruitCost + totalPackingCost;
      try {
        final batches = await _client
            .from('stock_batches')
            .select('remaining_quantity, purchase_cost')
            .gt('remaining_quantity', 0)
            .eq('status', 'active');
        for (final b in batches) {
          final qty = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
          final cost = (b['purchase_cost'] as num?)?.toDouble() ?? 0;
          avgInventory += qty * cost;
        }
      } catch (_) {}

      final grossProfit = totalRevenue - totalFruitCost - totalPackingCost;
      final grossMargin = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0;
      final netMargin = totalRevenue > 0 ? (totalNetProfit / totalRevenue) * 100 : 0;
      final inventoryTurnover = avgInventory > 0 ? cogs / avgInventory : 0;
      final avgShipmentProfit = shipmentCount > 0 ? totalNetProfit / shipmentCount : 0;
      final avgCostPerCarton = totalCartons > 0 ? totalLandedCost / totalCartons : 0;
      final avgRevenuePerCarton = totalCartons > 0 ? totalRevenue / totalCartons : 0;

      return {
        'gross_margin_pct': grossMargin,
        'net_margin_pct': netMargin,
        'inventory_turnover': inventoryTurnover,
        'avg_shipment_profit': avgShipmentProfit,
        'avg_cost_per_carton': avgCostPerCarton,
        'avg_revenue_per_carton': avgRevenuePerCarton,
        'total_cogs': cogs,
        'avg_inventory': avgInventory,
        'shipment_count': shipmentCount,
        'total_cartons': totalCartons,
      };
    } catch (e) {
      return {
        'gross_margin_pct': 0, 'net_margin_pct': 0, 'inventory_turnover': 0,
        'avg_shipment_profit': 0, 'avg_cost_per_carton': 0, 'avg_revenue_per_carton': 0,
        'total_cogs': 0, 'avg_inventory': 0, 'shipment_count': 0, 'total_cartons': 0,
      };
    }
  }
}
