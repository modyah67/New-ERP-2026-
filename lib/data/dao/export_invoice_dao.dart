import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/export_invoice_model.dart';
import '../services/currency_conversion_service.dart';


class ExportInvoiceDao {
  final _client = Supabase.instance.client;

  Future<List<ExportInvoiceModel>> getAll({
    int page = 0,
    int limit = 50,
    String? customerName,
  }) async {
    final offset = page * limit;
    final data = await _client
        .from('export_invoices')
        .select('*, customers(name)')
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);
    return data.map(ExportInvoiceModel.fromMap).toList();
  }

  Future<ExportInvoiceModel?> getById(String id) async {
    final data = await _client
        .from('export_invoices')
        .select('*, customers(name)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return ExportInvoiceModel.fromMap(data);
  }

  Future<String> insert(ExportInvoiceModel invoice) async {
    final map = invoice.toMap();
    await _resolveFinancials(map);
    map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: (map['currency_code'] as String?) ?? 'EGP',
      amount: (map['total_amount_foreign'] as num?)?.toDouble() ?? 0.0,
      exchangeRate: (map['exchange_rate_used'] as num?)?.toDouble() ?? 1.0,
    ).toJson();
    final result = await _client
        .from('export_invoices')
        .insert(map)
        .select()
        .single();
    return result['id'] as String;
  }

  Future<void> update(ExportInvoiceModel invoice) async {
    final map = invoice.toMap();
    await _resolveFinancials(map);
    map['currency_snapshot'] = CurrencyConversionService.instance.createSnapshot(
      currency: (map['currency_code'] as String?) ?? 'EGP',
      amount: (map['total_amount_foreign'] as num?)?.toDouble() ?? 0.0,
      exchangeRate: (map['exchange_rate_used'] as num?)?.toDouble() ?? 1.0,
    ).toJson();
    await _client
        .from('export_invoices')
        .update(map)
        .eq('id', invoice.id!);
  }

  Future<void> _resolveFinancials(Map<String, dynamic> map) async {
    final code = (map['currency_code'] as String?) ?? 'EGP';
    final cartons = (map['total_cartons'] as int?) ?? 0;
    final exportPrice = (map['export_price_per_carton'] as num?)?.toDouble() ?? 0.0;
    final purchaseCost = (map['purchase_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
    if (exportPrice <= 0 && purchaseCost <= 0) return;

    final rate = await CurrencyConversionService.instance.getRate(code);
    final totalAmountForeign = cartons * exportPrice;
    final totalAmountEgp = CurrencyConversionService.instance.toBase(totalAmountForeign, code, rate);
    final totalCostEgp = cartons * purchaseCost;
    final netProfitEgp = totalAmountEgp - totalCostEgp;

    map['total_amount_foreign'] = totalAmountForeign;
    map['exchange_rate_used'] = rate;
    map['total_amount_egp'] = totalAmountEgp;
    map['total_cost_egp'] = totalCostEgp;
    map['net_profit_egp'] = netProfitEgp;
  }

  Future<void> delete(int id) async {
    await _client.from('export_invoices').delete().eq('id', id);
  }

  Future<int> getCount() async {
    final response = await _client
        .from('export_invoices')
        .select()
        .count(CountOption.exact);
    return response.count;
  }

  Future<String> generateNextInvoiceNo({required int customerId, required int year}) async {
    final shortYear = year.toString().substring(2).padLeft(2, '0');
    final yearStart = DateTime(year, 1, 1).toIso8601String();
    final yearEnd = DateTime(year, 12, 31).toIso8601String();
    final data = await _client
        .from('export_invoices')
        .select('invoice_no')
        .eq('customer_id', customerId.toString())
        .gte('date', yearStart)
        .lte('date', yearEnd)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return '$shortYear/$customerId/001';
    final lastNo = data['invoice_no'] as String;
    final parts = lastNo.split('/');
    if (parts.length == 3) {
      final seq = int.tryParse(parts[2]) ?? 0;
      return '$shortYear/$customerId/${(seq + 1).toString().padLeft(3, '0')}';
    }
    return '$shortYear/$customerId/001';
  }

  Future<List<ExportInvoiceModel>> getAllUnpaginated() async {
    final data = await _client
        .from('export_invoices')
        .select('*, customers(name)')
        .order('date', ascending: false);
    return data.map(ExportInvoiceModel.fromMap).toList();
  }

  Future<List<ExportInvoiceModel>> getRecent(int limit) async {
    final data = await _client
        .from('export_invoices')
        .select('*, customers(name)')
        .order('date', ascending: false)
        .limit(limit);
    return data.map(ExportInvoiceModel.fromMap).toList();
  }

  Future<Map<String, dynamic>> getAggregates() async {
    final data = await _client
        .from('export_invoices')
        .select('id,total_cartons,total_pallets,total_net_weight,total_gross_weight,transport_mode,date');
    int totalCartons = 0;
    int totalPallets = 0;
    double totalNet = 0;
    double totalGross = 0;
    int seaCount = 0;
    int airCount = 0;
    for (final row in data) {
      totalCartons += (row['total_cartons'] as int?) ?? 0;
      totalPallets += (row['total_pallets'] as int?) ?? 0;
      totalNet += (row['total_net_weight'] as num?)?.toDouble() ?? 0;
      totalGross += (row['total_gross_weight'] as num?)?.toDouble() ?? 0;
      if ((row['transport_mode'] as int?) == 0) seaCount++; else airCount++;
    }
    return {
      'totalCartons': totalCartons,
      'totalPallets': totalPallets,
      'totalNetWeight': totalNet,
      'totalGrossWeight': totalGross,
      'seaCount': seaCount,
      'airCount': airCount,
      'totalInvoices': data.length,
    };
  }

  Future<Map<String, dynamic>> getFinancialAggregates() async {
    final data = await _client
        .from('export_invoices')
        .select('total_amount_egp,total_cost_egp,net_profit_egp,date');
    double totalRevenue = 0;
    double totalCost = 0;
    double totalProfit = 0;
    final Map<String, double> monthlyProfit = {};
    for (final row in data) {
      totalRevenue += (row['total_amount_egp'] as num?)?.toDouble() ?? 0;
      totalCost += (row['total_cost_egp'] as num?)?.toDouble() ?? 0;
      totalProfit += (row['net_profit_egp'] as num?)?.toDouble() ?? 0;
      final dt = row['date'] as String?;
      if (dt != null && dt.length >= 7) {
        final monthKey = dt.substring(0, 7);
        monthlyProfit.update(
          monthKey,
          (v) => v + ((row['net_profit_egp'] as num?)?.toDouble() ?? 0),
          ifAbsent: () => (row['net_profit_egp'] as num?)?.toDouble() ?? 0,
        );
      }
    }
    final sortedMonths = monthlyProfit.keys.toList()..sort();
    return {
      'totalRevenue': totalRevenue,
      'totalCost': totalCost,
      'totalProfit': totalProfit,
      'monthlyProfit': monthlyProfit,
      'sortedMonths': sortedMonths,
      'invoiceCount': data.length,
    };
  }

  Future<List<ExportInvoiceModel>> getByCustomerId(int customerId) async {
    final data = await _client
        .from('export_invoices')
        .select('*, customers(name)')
        .eq('customer_id', customerId.toString())
        .order('date', ascending: false);
    return data.map(ExportInvoiceModel.fromMap).toList();
  }
}
