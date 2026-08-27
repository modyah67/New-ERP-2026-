import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'export_shipment_dao.dart';

class DashboardDao {
  final _client = Supabase.instance.client;
  final _shipmentDao = ExportShipmentDao();

  Future<Map<String, dynamic>> getKpiData() async {
    try {
      final res = await _client.rpc('get_complete_dashboard_data');
      if (res != null) {
        debugPrint('✅ DashboardDao: Successfully fetched aggregated dashboard stats via RPC.');
        final data = _parseRpcResult(res);
        // Override net_profit with same source as profit/loss page
        try {
          final profitSummary = await _shipmentDao.getProfitSummary();
          data['totalProfit'] = {
            'value': (profitSummary['net_profit_egp'] as num?)?.toDouble() ?? 0.0,
            'change': 0.0,
            'label': 'صافي الأرباح',
          };
        } catch (_) {}
        // Always override lowStockCount with local query (RPC may be stale)
        data['lowStockCount'] = await _getLowStockCount();
        data['alerts'] = data['lowStockCount'];
        data['inventoryValue'] = await _getInventoryValue();
        return data;
      }
    } catch (e) {
      debugPrint('⚠️ DashboardDao: RPC get_complete_dashboard_data failed. Falling back to optimized Dart queries: $e');
    }
    // Safe Fallback Mode: executes 11 parallel, optimized REST queries
    return await _getKpiDataFallback();
  }

  Future<Map<String, dynamic>> _getLowStockCount() async {
    try {
      final rows = await _client.from('raw_materials').select('id, quantity, minimum_stock, is_active');
      int count = 0;
      for (final m in rows) {
        if (m['is_active'] != true) continue;
        final minStock = (m['minimum_stock'] is num) ? (m['minimum_stock'] as num).toDouble() : double.tryParse('${m['minimum_stock']}') ?? 0.0;
        final qty = (m['quantity'] is num) ? (m['quantity'] as num).toDouble() : double.tryParse('${m['quantity']}') ?? 0.0;
        if (minStock > 0 && qty <= minStock) count++;
      }
      return {'value': count.toDouble(), 'change': 0.0, 'label': 'أصناف منخفضة المخزون'};
    } catch (e) {
      debugPrint('⚠️ DashboardDao: _getLowStockCount failed: $e');
      return {'value': 0.0, 'change': 0.0, 'label': 'أصناف منخفضة المخزون'};
    }
  }

  Future<Map<String, dynamic>> _getInventoryValue() async {
    try {
      double total = 0.0;
      try {
        final materials = await _client.from('raw_materials').select('quantity, default_purchase_price, is_active');
        for (final m in materials) {
          if (m['is_active'] != true) continue;
          final qty = (m['quantity'] is num) ? (m['quantity'] as num).toDouble() : double.tryParse('${m['quantity']}') ?? 0.0;
          final price = (m['default_purchase_price'] is num) ? (m['default_purchase_price'] as num).toDouble() : double.tryParse('${m['default_purchase_price']}') ?? 0.0;
          total += qty * price;
        }
      } catch (_) {}
      return {'value': total, 'change': 0.0, 'label': 'قيمة المخزون'};
    } catch (e) {
      debugPrint('⚠️ DashboardDao: _getInventoryValue failed: $e');
      return {'value': 0.0, 'change': 0.0, 'label': 'قيمة المخزون'};
    }
  }

  Map<String, dynamic> _parseRpcResult(dynamic res) {
    final map = Map<String, dynamic>.from(res as Map);
    return {
      'totalSales': {'value': (map['total_sales_val'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'إجمالي المبيعات'},
      'todaySales': {'value': (map['today_sales'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'مبيعات اليوم'},
      'totalProfit': {'value': (map['net_profit'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'صافي الأرباح'},
      'totalExpenses': {'value': (map['total_expenses'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'إجمالي المصروفات'},
      'totalPurchases': {'value': (map['total_purchases'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'إجمالي المشتريات'},
      'activeShipments': {'value': (map['active_shipments_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'الشحنات النشطة'},
      'customerCount': {'value': (map['customer_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'العملاء'},
      'supplierCount': {'value': (map['supplier_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'الموردين'},
      'productCount': {'value': (map['product_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'الأصناف'},
      'lowStockCount': {'value': (map['low_stock_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'أصناف منخفضة المخزون'},
      'inventoryValue': {'value': (map['inventory_value'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'قيمة المخزون'},
      'alerts': {'value': (map['low_stock_count'] as num?)?.toDouble() ?? 0.0, 'change': 0.0, 'label': 'التنبيهات'},
      'monthlySales': (map['monthly_sales'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'expenseDistribution': (map['expense_distribution'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'exportDestinations': (map['export_destinations'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'topCustomers': (map['top_customers'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'topProducts': (map['top_products'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'upcomingShipments': (map['upcoming_shipments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'treasuryBalances': (map['treasury_balances'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'bankBalances': (map['bank_balances'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'recentActivities': (map['recent_activities'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      'quickAnalytics': Map<String, dynamic>.from(map['quick_analytics'] as Map? ?? {}),
    };
  }

  Future<Map<String, dynamic>> _getKpiDataFallback() async {
    Future<T?> _safe<T>(Future<T> Function() fn, String name) async {
      try {
        final result = await fn();
        return result;
      } catch (e) {
        debugPrint('⚠️ DashboardDao.fallback.$name failed: $e');
        return null;
      }
    }

    final results = await Future.wait([
      _safe(() => _client.from('export_shipments').select('total_revenue_egp, net_profit_egp, status, shipment_date, destination_country, customer_name, total_fruit_cost, port_of_destination, shipment_no, created_at, gross_weight').limit(500), 'export_shipments'),
      _safe(() => _client.from('sales_invoices').select('total_amount, paid_amount, invoice_date, customer_id, created_at, invoice_number').limit(500), 'sales_invoices'),
      _safe(() => _client.from('purchase_invoices').select('total_amount, status, created_at, invoice_number').limit(500), 'purchase_invoices'),
      _safe(() => _client.from('treasury_transactions').select('amount, type, description, category_id, customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id').limit(500), 'treasury_transactions'),
      _safe(() => _client.from('cashbox_transactions').select('amount, transaction_type, description, customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id').limit(500), 'cashbox_transactions'),
      _safe(() => _client.from('fruit_types').select('id, name').limit(100), 'fruit_types'),
      _safe(() => _client.from('treasuries').select('name, balance:treasury_balances(balance, currency)').limit(20), 'treasuries'),
      _safe(() => _client.from('bank_accounts').select('name, balance, currency').limit(20), 'bank_accounts'),
      _safe(() => _client.from('customers').select('id, name, created_at').limit(500), 'customers'),
      _safe(() => _client.from('suppliers').select('id, name, created_at').limit(500), 'suppliers'),
      _safe(() => _client.from('export_shipment_items').select('product_name, quantity, amount, export_price_per_carton').limit(1000), 'export_shipment_items'),
      _safe(() => _client.from('raw_materials').select('id, quantity, minimum_stock, is_active').limit(200), 'raw_materials'),
    ]);

    final List shipments = results[0] as List? ?? [];
    final List localSales = results[1] as List? ?? [];
    final List purchases = results[2] as List? ?? [];
    final List treasuryTxs = results[3] as List? ?? [];
    final List cashboxTxs = results[4] as List? ?? [];
    final List productsList = results[5] as List? ?? [];
    final List treasuriesList = results[6] as List? ?? [];
    final List bankList = results[7] as List? ?? [];
    final List customerList = results[8] as List? ?? [];
    final List supplierList = results[9] as List? ?? [];
    final List shipmentItems = results[10] as List? ?? [];
    final List rawMaterials = results[11] as List? ?? [];

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final monthStartStr = DateTime.now().toIso8601String().substring(0, 7) + '-01';

    double numVal(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0.0);

    // 1. Sales
    double totalSales = 0.0;
    double todaySales = 0.0;
    double monthlySales = 0.0;

    for (final s in shipments) {
      if (s['status'] == 'cancelled') continue;
      final val = numVal(s['total_revenue_egp']);
      final date = s['shipment_date']?.toString() ?? '';
      totalSales += val;
      if (date == todayStr) todaySales += val;
      if (date.compareTo(monthStartStr) >= 0) monthlySales += val;
    }

    for (final s in localSales) {
      if (s['status'] == 'cancelled') continue;
      final val = numVal(s['total_amount']);
      final date = s['invoice_date']?.toString() ?? '';
      totalSales += val;
      if (date == todayStr) todaySales += val;
      if (date.compareTo(monthStartStr) >= 0) monthlySales += val;
    }

    // 2. Purchases
    double totalPurchases = 0.0;
    for (final p in purchases) {
      if (p['status'] == 'cancelled') continue;
      totalPurchases += numVal(p['total_amount']);
    }

    // 3. Expenses
    double totalExpenses = 0.0;
    
    bool isOperatingExpense(Map<String, dynamic> tx) {
      return tx['customer_id'] == null &&
             tx['supplier_id'] == null &&
             tx['clearing_agent_id'] == null &&
             tx['shipping_company_id'] == null &&
             tx['shareholder_id'] == null;
    }

    for (final tx in treasuryTxs) {
      if ((tx['type'] == 'expense' || tx['type'] == 'supplier_payment') && isOperatingExpense(tx)) {
        totalExpenses += numVal(tx['amount']);
      }
    }
    for (final tx in cashboxTxs) {
      if (tx['transaction_type'] == 'expense' && isOperatingExpense(tx)) {
        totalExpenses += numVal(tx['amount']);
      }
    }

    // 4. Net Profit — use same source as profit/loss page
    double netProfit = 0.0;
    try {
      final profitSummary = await _shipmentDao.getProfitSummary();
      netProfit = (profitSummary['net_profit_egp'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      for (final s in shipments) {
        if (s['status'] == 'cancelled') continue;
        netProfit += numVal(s['net_profit_egp']);
      }
    }

    // 5. Counts
    int activeShipments = shipments.where((s) => ['preparing', 'ready', 'shipped', 'in_transit', 'active'].contains(s['status'])).length;
    int customerCount = customerList.length;
    int supplierCount = supplierList.length;
    int productCount = productsList.length;

    // 6. Low stock: count raw_materials where quantity <= minimum_stock
    int lowStockCount = 0;
    for (final m in rawMaterials) {
      if (m['is_active'] != true) continue;
      final minStock = numVal(m['minimum_stock']);
      final qty = numVal(m['quantity']);
      if (minStock > 0 && qty <= minStock) lowStockCount++;
    }

    // 6b. Inventory value: raw materials only
    double inventoryValue = 0.0;
    for (final m in rawMaterials) {
      if (m['is_active'] != true) continue;
      inventoryValue += numVal(m['quantity']) * numVal(m['default_purchase_price']);
    }

    // 7. Sales Trend (last 30 days)
    final trendList = <Map<String, dynamic>>[];
    for (int i = 29; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      final label = '${date.month}/${date.day}';
      double dailySales = 0.0;
      for (final s in shipments) {
        if (s['status'] != 'cancelled' && s['shipment_date'] == dateStr) {
          dailySales += numVal(s['total_revenue_egp']);
        }
      }
      for (final s in localSales) {
        if (s['status'] != 'cancelled' && s['invoice_date'] == dateStr) {
          dailySales += numVal(s['total_amount']);
        }
      }
      trendList.add({'date': label, 'sales': dailySales});
    }

    // 8. Expense Distribution
    final expenseMap = <String, double>{};
    for (final tx in treasuryTxs) {
      if (tx['type'] != 'expense') continue;
      final cat = tx['description']?.toString() ?? 'أخرى';
      expenseMap[cat] = (expenseMap[cat] ?? 0) + numVal(tx['amount']);
    }
    for (final tx in cashboxTxs) {
      if (tx['transaction_type'] != 'expense') continue;
      final cat = tx['description']?.toString() ?? 'أخرى';
      expenseMap[cat] = (expenseMap[cat] ?? 0) + numVal(tx['amount']);
    }
    final expenseDistList = expenseMap.entries.map((e) => {'name': e.key, 'value': e.value}).toList()
      ..sort((a, b) => (b['value'] as num).toDouble().compareTo((a['value'] as num).toDouble()));

    // 9. Export Destinations (ranked by total revenue EGP + total weight)
    final destMap = <String, double>{}; // normalized → total value
    final destWeight = <String, double>{}; // normalized → total weight
    final destDisplay = <String, String>{}; // normalized → original case
    for (final s in shipments) {
      if (s['status'] == 'cancelled') continue;
      final raw = s['destination_country']?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final norm = raw.toLowerCase();
      destMap[norm] = (destMap[norm] ?? 0) + numVal(s['total_revenue_egp']);
      destWeight[norm] = (destWeight[norm] ?? 0) + numVal(s['gross_weight']);
      destDisplay[norm] = raw;
    }
    final destList = destMap.entries
        .map((e) => {'name': destDisplay[e.key] ?? e.key, 'total_value': e.value, 'total_weight': destWeight[e.key] ?? 0.0})
        .toList()
      ..sort((a, b) => (b['total_value'] as num).toDouble().compareTo((a['total_value'] as num).toDouble()));

    // 10. Top Customers
    final custMap = <String, double>{};
    for (final s in shipments) {
      if (s['status'] == 'cancelled') continue;
      final name = s['customer_name']?.toString() ?? 'أخرى';
      custMap[name] = (custMap[name] ?? 0) + numVal(s['total_revenue_egp']);
    }
    final topCustomersList = custMap.entries.map((e) => {'name': e.key, 'total': e.value}).toList()
      ..sort((a, b) => (b['total'] as num).toDouble().compareTo((a['total'] as num).toDouble()));

    // 11. Top Products
    final prodQty = <String, double>{};
    final prodVal = <String, double>{};
    for (final item in shipmentItems) {
      final name = item['product_name']?.toString() ?? '—';
      final qty = numVal(item['quantity']);
      final ep = numVal(item['export_price_per_carton']);
      final amount = numVal(item['amount']);
      final value = amount > 0 ? amount : qty * ep;
      prodQty[name] = (prodQty[name] ?? 0) + qty;
      prodVal[name] = (prodVal[name] ?? 0) + value;
    }
    final topProductsList = prodQty.keys.map((name) => {
      'name': name,
      'quantity': prodQty[name]!,
      'value': prodVal[name]!,
    }).toList()
      ..sort((a, b) => (b['quantity'] as num).toDouble().compareTo((a['quantity'] as num).toDouble()));

    // 12. Upcoming Shipments
    final upcomingList = shipments
        .where((s) => ['pending', 'preparing', 'ready', 'active'].contains(s['status']) && s['shipment_date'] != null && s['shipment_date'].toString().compareTo(todayStr) >= 0)
        .map((s) => {
          'id': s['id'],
          'shipment_no': s['shipment_no'],
          'destination': s['port_of_destination'] ?? s['destination_country'] ?? '—',
          'date': s['shipment_date'],
          'status': s['status'],
        }).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    // 13. Treasury Balances
    final treasuryBalances = <Map<String, dynamic>>[];
    for (final row in treasuriesList) {
      final name = row['name'] as String? ?? '';
      final bals = row['balance'] as List? ?? [];
      for (final b in bals) {
        if (b is Map) {
          treasuryBalances.add({
            'name': name,
            'balance': (b['balance'] as num?)?.toDouble() ?? 0.0,
            'currency': b['currency'] as String? ?? 'EGP',
          });
        }
      }
    }

    // 14. Bank Balances
    final bankBalances = bankList.map((row) => {
      'name': row['name'] as String? ?? '',
      'balance': numVal(row['balance']),
      'currency': row['currency'] as String? ?? 'EGP',
    }).toList();

    // 15. Recent Activities
    final activitiesList = <Map<String, dynamic>>[];
    for (final s in shipments.take(5)) {
      activitiesList.add({
        'type': 'shipment',
        'title': 'تم إنشاء شحنة ${s['shipment_no']}',
        'time': s['created_at'],
      });
    }
    for (final c in customerList.take(5)) {
      activitiesList.add({
        'type': 'customer',
        'title': 'تم إضافة عميل ${c['name']}',
        'time': c['created_at'],
      });
    }
    for (final s in supplierList.take(5)) {
      activitiesList.add({
        'type': 'supplier',
        'title': 'تم إضافة مورد ${s['name']}',
        'time': s['created_at'],
      });
    }
    for (final p in purchases.take(5)) {
      activitiesList.add({
        'type': 'purchase',
        'title': 'تم تسجيل فاتورة شراء ${p['invoice_number']}',
        'time': p['created_at'],
      });
    }
    activitiesList.sort((a, b) {
      final tA = (a['time'] as String?) ?? '';
      final tB = (b['time'] as String?) ?? '';
      return tB.compareTo(tA);
    });

    // 16. Quick Analytics
    final totalInvoices = shipments.length + localSales.length;
    final avgInvoice = totalInvoices > 0 ? totalSales / totalInvoices : 0.0;
    final profitMargin = totalSales > 0 ? (netProfit / totalSales) * 100 : 0.0;
    final collectionRate = 100.0;
    final inventoryTurnover = inventoryValue > 0 ? totalPurchases / inventoryValue : 1.0;

    return {
      'totalSales': {'value': totalSales, 'change': 0.0, 'label': 'إجمالي المبيعات'},
      'todaySales': {'value': todaySales, 'change': 0.0, 'label': 'مبيعات اليوم'},
      'totalProfit': {'value': netProfit, 'change': 0.0, 'label': 'صافي الأرباح'},
      'totalExpenses': {'value': totalExpenses, 'change': 0.0, 'label': 'إجمالي المصروفات'},
      'totalPurchases': {'value': totalPurchases, 'change': 0.0, 'label': 'إجمالي المشتريات'},
      'activeShipments': {'value': activeShipments.toDouble(), 'change': 0.0, 'label': 'الشحنات النشطة'},
      'customerCount': {'value': customerCount.toDouble(), 'change': 0.0, 'label': 'العملاء'},
      'supplierCount': {'value': supplierCount.toDouble(), 'change': 0.0, 'label': 'الموردين'},
      'productCount': {'value': productCount.toDouble(), 'change': 0.0, 'label': 'الأصناف'},
      'lowStockCount': {'value': lowStockCount.toDouble(), 'change': 0.0, 'label': 'أصناف منخفضة المخزون'},
      'inventoryValue': {'value': inventoryValue, 'change': 0.0, 'label': 'قيمة المخزون'},
      'alerts': {'value': lowStockCount.toDouble(), 'change': 0.0, 'label': 'التنبيهات'},
      'monthlySales': trendList,
      'expenseDistribution': expenseDistList,
      'exportDestinations': destList,
      'topCustomers': topCustomersList,
      'topProducts': topProductsList,
      'upcomingShipments': upcomingList.take(10).toList(),
      'treasuryBalances': treasuryBalances,
      'bankBalances': bankBalances,
      'recentActivities': activitiesList.take(10).toList(),
      'quickAnalytics': {
        'avgInvoice': avgInvoice,
        'profitMargin': profitMargin,
        'collectionRate': collectionRate,
        'inventoryTurnover': inventoryTurnover,
      },
    };
  }

  Future<List<Map<String, dynamic>>> globalSearch(String query) async {
    if (query.trim().isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    final pattern = '%$query%';
    try {
      final customers = await _client.from('customers')
          .select('id, name, code')
          .or('name.ilike.$pattern,code.ilike.$pattern')
          .limit(5);
      for (final c in customers) {
        results.add({'type': 'customer', 'title': c['name'], 'subtitle': c['code'], 'id': c['id']});
      }
    } catch (_) {}
    try {
      final items = await _client.from('fruit_types')
          .select('id, name, code')
          .or('name.ilike.$pattern,code.ilike.$pattern')
          .limit(5);
      for (final p in items) {
        results.add({'type': 'product', 'title': p['name'], 'subtitle': p['code'], 'id': p['id']});
      }
    } catch (e) { debugPrint('⚠️ globalSearch fruit_types: $e'); }
    try {
      final shipments = await _client.from('export_shipments')
          .select('id, shipment_no')
          .or('shipment_no.ilike.$pattern,port_of_destination.ilike.$pattern')
          .limit(5);
      for (final s in shipments) {
        results.add({'type': 'shipment', 'title': s['shipment_no'], 'subtitle': 'شحنة', 'id': s['id']});
      }
    } catch (e) { debugPrint('⚠️ globalSearch shipments: $e'); }
    try {
      final invoices = await _client.from('sales_invoices')
          .select('id, invoice_number')
          .or('invoice_number.ilike.$pattern')
          .limit(5);
      for (final inv in invoices) {
        results.add({'type': 'invoice', 'title': 'فاتورة #${inv['invoice_number']}', 'subtitle': '', 'id': inv['id']});
      }
    } catch (e) { debugPrint('⚠️ globalSearch invoices: $e'); }
    try {
      final suppliers = await _client.from('suppliers')
          .select('id, name, supplier_code')
          .or('name.ilike.$pattern,supplier_code.ilike.$pattern')
          .limit(5);
      for (final s in suppliers) {
        results.add({'type': 'supplier', 'title': s['name'], 'subtitle': s['supplier_code'], 'id': s['id']});
      }
    } catch (e) { debugPrint('⚠️ globalSearch suppliers: $e'); }
    return results;
  }

  Future<Map<String, dynamic>> getBadgeCounts() async {
    int activeShipments = 0;
    int alerts = 0;
    int unpaidInvoices = 0;
    try {
      final s = await _client.from('export_shipments').select('id').eq('status', 'active');
      activeShipments = s.length;
    } catch (e) { debugPrint('⚠️ getBadgeCounts shipments: $e'); }
    try {
      final u = await _client.from('sales_invoices').select('id').eq('payment_status', 'unpaid');
      unpaidInvoices = u.length;
    } catch (e) { debugPrint('⚠️ getBadgeCounts invoices: $e'); }
    try {
      final p = await _client.from('cheques').select('id').eq('status', 'pending');
      alerts = p.length;
    } catch (e) { debugPrint('⚠️ getBadgeCounts cheques: $e'); }
    return {
      'activeShipments': activeShipments,
      'alerts': alerts,
      'unpaidInvoices': unpaidInvoices,
    };
  }
}
