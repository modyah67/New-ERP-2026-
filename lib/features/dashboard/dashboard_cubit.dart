import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/dashboard_dao.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  final DashboardDao _dao;
  Timer? _timeTimer;

  DashboardCubit(this._dao) : super(const DashboardState()) {
    _startTimeUpdater();
  }

  void _startTimeUpdater() {
    _updateTime();
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    if (!isClosed) emit(state.copyWith(currentTime: timeStr));
  }

  Future<void> loadAll() async {
    emit(state.copyWith(loading: true, error: null));
    try {
      final data = await _dao.getKpiData();
      if (isClosed) return;
      emit(state.copyWith(
        loading: false,
        totalSales: data['totalSales'] as Map<String, dynamic>?,
        todaySales: data['todaySales'] as Map<String, dynamic>?,
        totalProfit: data['totalProfit'] as Map<String, dynamic>?,
        totalExpenses: data['totalExpenses'] as Map<String, dynamic>?,
        totalPurchases: data['totalPurchases'] as Map<String, dynamic>?,
        activeShipments: data['activeShipments'] as Map<String, dynamic>?,
        customerCount: data['customerCount'] as Map<String, dynamic>?,
        supplierCount: data['supplierCount'] as Map<String, dynamic>?,
        productCount: data['productCount'] as Map<String, dynamic>?,
        lowStockCount: data['lowStockCount'] as Map<String, dynamic>?,
        inventoryValue: data['inventoryValue'] as Map<String, dynamic>?,
        alerts: data['alerts'] as Map<String, dynamic>?,
        monthlySales: (data['monthlySales'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        expenseDistribution: (data['expenseDistribution'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        exportDestinations: (data['exportDestinations'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        topCustomers: (data['topCustomers'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        recentActivities: (data['recentActivities'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        treasuryBalances: (data['treasuryBalances'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        bankBalances: (data['bankBalances'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        upcomingShipments: (data['upcomingShipments'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        topProducts: (data['topProducts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        quickAnalytics: (data['quickAnalytics'] as Map<String, dynamic>?) ?? {},
      ));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> loadBadgeCounts() async {
    try {
      final counts = await _dao.getBadgeCounts();
      if (!isClosed) emit(state.copyWith(badgeCounts: counts));
    } catch (_) {}
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      emit(state.copyWith(searchResults: []));
      return;
    }
    try {
      final results = await _dao.globalSearch(query);
      if (!isClosed) emit(state.copyWith(searchResults: results));
    } catch (_) {}
  }

  void clearSearch() {
    emit(state.copyWith(searchResults: []));
  }


  @override
  Future<void> close() {
    _timeTimer?.cancel();
    return super.close();
  }
}
