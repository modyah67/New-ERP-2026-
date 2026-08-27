import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/export_shipment_dao.dart';

class ExecutiveDashboardService {
  final _client = Supabase.instance.client;
  final _shipmentDao = ExportShipmentDao();

  /// ── KPIs ──

  Future<Map<String, dynamic>> getKpis() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1)
          .toIso8601String()
          .substring(0, 10); // ignore: unused_local_variable

      // Shipments
      final shipments = await _client
          .from('export_shipments')
          .select('total_revenue_egp, net_profit_egp, total_fruit_cost, total_packing_material_cost, shipment_date, status, cartons_count, net_weight, created_at')
          .neq('status', 'cancelled');

      double todayRevenue = 0, monthRevenue = 0;
      double totalGrossProfit = 0;
      double totalRevenue = 0;
      int activeShipments = 0;

      for (final s in shipments) {
        final rev = (s['total_revenue_egp'] as num?)?.toDouble() ?? 0;
        final fruit = (s['total_fruit_cost'] as num?)?.toDouble() ?? 0;
        final packing = (s['total_packing_material_cost'] as num?)?.toDouble() ?? 0;
        final gp = rev - fruit - packing;
        final sDate = s['shipment_date'] as String? ?? '';
        final status = (s['status'] as String?) ?? '';

        if (sDate.isNotEmpty) {
          if (sDate == today) todayRevenue += rev;
          if (sDate.length >= 7) {
            final sMonth = sDate.substring(0, 7);
            final targetMonth = monthStart.substring(0, 7);
            if (sMonth == targetMonth) monthRevenue += rev;
          }
        }

        totalRevenue += rev;
        totalGrossProfit += gp;

        if (status != 'delivered' && status != 'cancelled') {
          activeShipments++;
        }
      }

      // Get net profit from the same source as profit/loss page
      double totalNetProfit = 0;
      try {
        final profitSummary = await _shipmentDao.getProfitSummary();
        totalNetProfit = (profitSummary['net_profit_egp'] as num?)?.toDouble() ?? 0;
      } catch (_) {}

      // Inventory value
      double inventoryValue = 0;
      try {
        final batches = await _client
            .from('stock_batches')
            .select('remaining_quantity, purchase_cost')
            .gt('remaining_quantity', 0)
            .eq('status', 'active');
        for (final b in batches) {
          final qty = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
          final cost = (b['purchase_cost'] as num?)?.toDouble() ?? 0;
          inventoryValue += qty * cost;
        }
      } catch (_) {}

      // Treasury balance (EGP)
      double treasuryBalance = 0;
      try {
        final tb = await _client
            .from('treasury_balances')
            .select('balance')
            .eq('currency', 'EGP');
        for (final t in tb) {
          treasuryBalance += (t['balance'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      // Customer receivables
      double receivables = 0;
      try {
        final cust = await _client
            .from('customers')
            .select('current_balance');
        for (final c in cust) {
          receivables += (c['current_balance'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      // Supplier payables
      double payables = 0;
      try {
        final supp = await _client
            .from('suppliers')
            .select('outstanding_balance');
        for (final s in supp) {
          payables += (s['outstanding_balance'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      // Open cheques
      int openCheques = 0;
      try {
        final resp = await _client
            .from('cheques')
            .select('id')
            .eq('status', 'pending')
            .count(CountOption.exact);
        openCheques = resp.count;
      } catch (_) {}

      return {
        'today_revenue': todayRevenue,
        'month_revenue': monthRevenue,
        'gross_profit': totalGrossProfit,
        'net_profit': totalNetProfit,
        'inventory_value': inventoryValue,
        'treasury_balance': treasuryBalance,
        'receivables': receivables,
        'payables': payables,
        'active_shipments': activeShipments,
        'open_cheques': openCheques,
        'shipment_count': shipments.length,
        'total_revenue': totalRevenue,
      };
    } catch (e) {
      return {
        'today_revenue': 0, 'month_revenue': 0, 'gross_profit': 0, 'net_profit': 0,
        'inventory_value': 0, 'treasury_balance': 0, 'receivables': 0, 'payables': 0,
        'active_shipments': 0, 'open_cheques': 0, 'shipment_count': 0, 'total_revenue': 0,
      };
    }
  }

  /// ── Trending (monthly) ──

  Future<Map<String, List<MapEntry<String, double>>>> getTrends() async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('total_revenue_egp, net_profit_egp, shipment_date, status')
          .neq('status', 'cancelled');

      final revenueByMonth = <String, double>{};
      final profitByMonth = <String, double>{};
      final shipmentCountByMonth = <String, int>{};

      for (final s in shipments) {
        final date = s['shipment_date'] as String?;
        if (date == null || date.length < 7) continue;
        final month = date.substring(0, 7);

        revenueByMonth.update(month, (v) => v + ((s['total_revenue_egp'] as num?)?.toDouble() ?? 0),
            ifAbsent: () => (s['total_revenue_egp'] as num?)?.toDouble() ?? 0);
        profitByMonth.update(month, (v) => v + ((s['net_profit_egp'] as num?)?.toDouble() ?? 0),
            ifAbsent: () => (s['net_profit_egp'] as num?)?.toDouble() ?? 0);
        shipmentCountByMonth.update(month, (v) => v + 1, ifAbsent: () => 1);
      }

      final sortedMonths = revenueByMonth.keys.toList()..sort();

      return {
        'revenue_trend': sortedMonths.map((m) => MapEntry(m, revenueByMonth[m] ?? 0)).toList(),
        'profit_trend': sortedMonths.map((m) => MapEntry(m, profitByMonth[m] ?? 0)).toList(),
        'shipment_trend': sortedMonths.map((m) => MapEntry(m, (shipmentCountByMonth[m] ?? 0).toDouble())).toList(),
      };
    } catch (_) {
      return {'revenue_trend': [], 'profit_trend': [], 'shipment_trend': []};
    }
  }

  /// ── Inventory distribution ──

  Future<List<MapEntry<String, double>>> getInventoryDistribution() async {
    try {
      final batches = await _client
          .from('stock_batches')
          .select('product_id, fruit_types!left(name), remaining_quantity, purchase_cost')
          .gt('remaining_quantity', 0)
          .eq('status', 'active');

      final byProduct = <String, double>{};
      for (final b in batches) {
        final fruit = b['fruit_types'] as Map? ?? {};
        final raw = b['raw_materials'] as Map? ?? {};
        final name = (fruit['name'] as String?) ?? (raw['name'] as String?) ?? 'أخرى';
        final qty = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
        final cost = (b['purchase_cost'] as num?)?.toDouble() ?? 0;
        byProduct.update(name, (v) => v + (qty * cost), ifAbsent: () => qty * cost);
      }

      final sorted = byProduct.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  /// ── Top lists ──

  Future<List<Map<String, dynamic>>> getTopCustomers() async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('customer_name, total_revenue_egp')
          .neq('status', 'cancelled');

      final byCustomer = <String, double>{};
      for (final s in shipments) {
        final name = (s['customer_name'] as String?) ?? 'غير معروف';
        byCustomer.update(name, (v) => v + ((s['total_revenue_egp'] as num?)?.toDouble() ?? 0),
            ifAbsent: () => (s['total_revenue_egp'] as num?)?.toDouble() ?? 0);
      }

      return byCustomer.entries
          .map((e) => {'customer_name': e.key, 'total_revenue': e.value})
          .toList()
        ..sort((a, b) => (b['total_revenue'] as double).compareTo(a['total_revenue'] as double));
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopProducts() async {
    try {
      final orders = await _client
          .from('packing_orders')
          .select('fruit_types!left(name), total_net_weight, export_shipment_id');

      final byProduct = <String, double>{};
      for (final o in orders) {
        final p = o['fruit_types'] as Map? ?? {};
        final name = (p['name'] as String?) ?? 'غير معروف';
        final wt = (o['total_net_weight'] as num?)?.toDouble() ?? 0;
        byProduct.update(name, (v) => v + wt, ifAbsent: () => wt);
      }

      return byProduct.entries
          .map((e) => {'product_name': e.key, 'total_weight': e.value})
          .toList()
        ..sort((a, b) => (b['total_weight'] as double).compareTo(a['total_weight'] as double));
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopProfitableShipments() async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('id, shipment_no, net_profit_egp, customer_name')
          .neq('status', 'cancelled')
          .order('net_profit_egp', ascending: false)
          .limit(10);
      return (shipments as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopDestinations() async {
    try {
      final shipments = await _client
          .from('export_shipments')
          .select('country, customer_name, total_revenue_egp')
          .neq('status', 'cancelled');

      final byDest = <String, double>{};
      for (final s in shipments) {
        final dest = (s['country'] as String?) ?? 'غير معروف';
        byDest.update(dest, (v) => v + ((s['total_revenue_egp'] as num?)?.toDouble() ?? 0),
            ifAbsent: () => (s['total_revenue_egp'] as num?)?.toDouble() ?? 0);
      }

      return byDest.entries
          .map((e) => {'destination': e.key, 'total_revenue': e.value})
          .toList()
        ..sort((a, b) => (b['total_revenue'] as double).compareTo(a['total_revenue'] as double));
    } catch (_) {
      return [];
    }
  }
}
