import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import 'report_state.dart';

class ReportCubit extends Cubit<ReportState> {
  final _client = Supabase.instance.client;

  ReportCubit() : super(const ReportInitial()) {
    refreshReports();
  }

  Future<void> refreshReports() async {
    emit(const ReportLoading());
    try {
      final now = DateTime.now();
      final fromDate = DateTime(now.year, now.month, 1);
      final toDate = now;

      final data = await _calcForRange(_fmtDate(fromDate), _fmtDate(toDate));
      final income = data['income']!;
      await _loadAdvancedStats(income, fromDate, toDate);
    } catch (e) {
      emit(ReportError(message: 'حدث خطأ: $e'));
    }
  }

  Future<void> runFilter() async {
    final currentState = state;
    if (currentState is! ReportLoaded) return;

    try {
      final data = await _calcForRange(
        _fmtDate(currentState.fromDate),
        _fmtDate(currentState.toDate),
      );
      emit(currentState.copyWith(filteredIncome: data['income']!));
    } catch (e) {
      emit(ReportError(message: 'حدث خطأ: $e'));
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! ReportLoaded) return;

    final d = await showDatePicker(
      context: context,
      initialDate: currentState.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      emit(currentState.copyWith(fromDate: d));
      await runFilter();
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! ReportLoaded) return;

    final d = await showDatePicker(
      context: context,
      initialDate: currentState.toDate,
      firstDate: currentState.fromDate,
      lastDate: DateTime.now(),
    );
    if (d != null) {
      emit(currentState.copyWith(toDate: d));
      await runFilter();
    }
  }

  Future<Map<String, double>> _calcForRange(String from, String to) async {
    final data = await _client
        .from('invoices')
        .select('total_amount, discount_amount')
        .eq('type', 'sale')
        .eq('status', 'confirmed')
        .gte('invoice_date', from)
        .lte('invoice_date', to);

    double income = 0.0;
    for (final row in data as List) {
      final total = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
      final discount = (row['discount_amount'] as num?)?.toDouble() ?? 0.0;
      income += total - discount;
    }

    return {'income': income};
  }

  Future<void> _loadAdvancedStats(
      double income, DateTime fromDate, DateTime toDate) async {
    // 1. Top Supplier
    String topSupplier = 'لا يوجد';
    try {
      final topSuppRes = await _client
          .from('suppliers')
          .select('name, balance')
          .order('balance', ascending: false)
          .limit(1);
      if (topSuppRes.isNotEmpty &&
          (topSuppRes.first['balance'] as num).toDouble() > 0) {
        topSupplier =
            "${topSuppRes.first['name']} (${AppUtils.formatCurrency((topSuppRes.first['balance'] as num).toDouble())})";
      }
    } catch (_) {}

    // 2. Top Customer
    String topCustomer = 'لا يوجد';
    try {
      final topCustRes = await _client
          .from('customers')
          .select('name, balance')
          .order('balance', ascending: false)
          .limit(1);
      if (topCustRes.isNotEmpty &&
          (topCustRes.first['balance'] as num).toDouble() > 0) {
        topCustomer =
            "${topCustRes.first['name']} (${AppUtils.formatCurrency((topCustRes.first['balance'] as num).toDouble())})";
      }
    } catch (_) {}

    // 3. Most Consumed Item
    String topItem = 'لا يوجد';
    try {
      final topItemRes = await _client
          .from('invoice_items')
          .select('item_id, quantity, unit, items(name)')
          .limit(10000);
      // Group by item_id and sum quantities
      final Map<String, double> itemQty = {};
      final Map<String, String> itemNames = {};
      final Map<String, String> itemUnits = {};
      for (final row in topItemRes as List) {
        final itemId = row['item_id']?.toString() ?? '';
        final qty = (row['quantity'] as num).toDouble();
        itemQty[itemId] = (itemQty[itemId] ?? 0) + qty;
        final item = AppUtils.asMap(row['items']);
        itemNames[itemId] = item?['name'] as String? ?? '';
        itemUnits[itemId] = row['unit'] as String? ?? '';
      }
      if (itemQty.isNotEmpty) {
        final sorted = itemQty.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top = sorted.first;
        topItem =
            "${itemNames[top.key]} (${AppUtils.formatNumber(top.value)} ${itemUnits[top.key]})";
      }
    } catch (_) {}

    // 4. Biggest Debtor
    String biggestDebtor = 'لا يوجد مديونيات';
    try {
      final biggestDebtorRes = await _client
          .from('customers')
          .select('name, balance')
          .order('balance', ascending: true)
          .limit(1);
      if (biggestDebtorRes.isNotEmpty &&
          (biggestDebtorRes.first['balance'] as num).toDouble() < 0) {
        biggestDebtor =
            "${biggestDebtorRes.first['name']} (${AppUtils.formatCurrency((biggestDebtorRes.first['balance'] as num).toDouble().abs())})";
      }
    } catch (_) {}

    // 5. Biggest Creditor
    String biggestCreditor = 'لا يوجد';
    try {
      final biggestCredRes = await _client
          .from('suppliers')
          .select('name, balance')
          .order('balance', ascending: false)
          .limit(1);
      if (biggestCredRes.isNotEmpty &&
          (biggestCredRes.first['balance'] as num).toDouble() > 0) {
        biggestCreditor =
            "${biggestCredRes.first['name']} (${AppUtils.formatCurrency((biggestCredRes.first['balance'] as num).toDouble())})";
      }
    } catch (_) {}

    // 6. Price Monitoring - simplified for Supabase
    final List<Map<String, dynamic>> priceAlerts = [];
    try {
      final purchasesData = await _client
          .from('purchase_items')
          .select('item_id, purchase_price, purchases(purchase_date), items(name)')
          .limit(5000);

      // Group by item_id and get last two purchases
      final Map<String, List<Map<String, dynamic>>> itemPurchases = {};
      for (final row in purchasesData as List) {
        final itemId = row['item_id']?.toString() ?? '';
        if (!itemPurchases.containsKey(itemId)) {
          itemPurchases[itemId] = [];
        }
        final purchases = AppUtils.asMap(row['purchases']);
        final items = AppUtils.asMap(row['items']);
        itemPurchases[itemId]!.add({
          'purchase_price': (row['purchase_price'] as num).toDouble(),
          'purchase_date': purchases?['purchase_date'] as String?,
          'item_name': items?['name'] as String? ?? '',
        });
      }

      for (final entry in itemPurchases.entries) {
        final purchases = entry.value;
        if (purchases.length < 2) continue;
        purchases.sort((a, b) =>
            (b['purchase_date'] as String? ?? '').compareTo(a['purchase_date'] as String? ?? ''));
        final latest = purchases[0];
        final prev = purchases[1];
        if (prev['purchase_price'] > 0 &&
            latest['purchase_price'] > prev['purchase_price'] * 1.1) {
          final prevPrice = prev['purchase_price'] as double;
          final newPrice = latest['purchase_price'] as double;
          final increase = ((newPrice - prevPrice) / prevPrice) * 100;
          priceAlerts.add({
            'item_name': latest['item_name'],
            'supplier': '',
            'prev_price': prevPrice,
            'new_price': newPrice,
            'increase': increase,
          });
        }
      }
    } catch (_) {}

    emit(ReportLoaded(
      filteredIncome: income,
      topSupplier: topSupplier,
      topCustomer: topCustomer,
      topItem: topItem,
      biggestDebtor: biggestDebtor,
      biggestCreditor: biggestCreditor,
      priceAlerts: priceAlerts,
      fromDate: fromDate,
      toDate: toDate,
    ));
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  void onChange(Change<ReportState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    return super.close();
  }
}
