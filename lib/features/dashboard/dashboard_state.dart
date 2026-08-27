import 'package:flutter/foundation.dart';

@immutable
class DashboardState {
  final bool loading;
  final String? error;

  final Map<String, dynamic>? totalSales;
  final Map<String, dynamic>? todaySales;
  final Map<String, dynamic>? totalProfit;
  final Map<String, dynamic>? totalExpenses;
  final Map<String, dynamic>? totalPurchases;
  final Map<String, dynamic>? activeShipments;
  final Map<String, dynamic>? customerCount;
  final Map<String, dynamic>? supplierCount;
  final Map<String, dynamic>? productCount;
  final Map<String, dynamic>? lowStockCount;
  final Map<String, dynamic>? inventoryValue;
  final Map<String, dynamic>? alerts;
  final List<Map<String, dynamic>> monthlySales;
  final List<Map<String, dynamic>> expenseDistribution;
  final List<Map<String, dynamic>> exportDestinations;
  final List<Map<String, dynamic>> topCustomers;
  final List<Map<String, dynamic>> recentActivities;
  final List<Map<String, dynamic>> treasuryBalances;
  final List<Map<String, dynamic>> bankBalances;
  final List<Map<String, dynamic>> upcomingShipments;
  final List<Map<String, dynamic>> topProducts;
  final Map<String, dynamic> quickAnalytics;
  final List<Map<String, dynamic>> searchResults;
  final Map<String, dynamic> badgeCounts;
  final String currentTime;

  const DashboardState({
    this.loading = true,
    this.error,
    this.totalSales,
    this.todaySales,
    this.totalProfit,
    this.totalExpenses,
    this.totalPurchases,
    this.activeShipments,
    this.customerCount,
    this.supplierCount,
    this.productCount,
    this.lowStockCount,
    this.inventoryValue,
    this.alerts,
    this.monthlySales = const [],
    this.expenseDistribution = const [],
    this.exportDestinations = const [],
    this.topCustomers = const [],
    this.recentActivities = const [],
    this.treasuryBalances = const [],
    this.bankBalances = const [],
    this.upcomingShipments = const [],
    this.topProducts = const [],
    this.quickAnalytics = const {},
    this.searchResults = const [],
    this.badgeCounts = const {},
    this.currentTime = '',
  });

  DashboardState copyWith({
    bool? loading,
    String? error,
    Map<String, dynamic>? totalSales,
    Map<String, dynamic>? todaySales,
    Map<String, dynamic>? totalProfit,
    Map<String, dynamic>? totalExpenses,
    Map<String, dynamic>? totalPurchases,
    Map<String, dynamic>? activeShipments,
    Map<String, dynamic>? customerCount,
    Map<String, dynamic>? supplierCount,
    Map<String, dynamic>? productCount,
    Map<String, dynamic>? lowStockCount,
    Map<String, dynamic>? inventoryValue,
    Map<String, dynamic>? alerts,
    List<Map<String, dynamic>>? monthlySales,
    List<Map<String, dynamic>>? expenseDistribution,
    List<Map<String, dynamic>>? exportDestinations,
    List<Map<String, dynamic>>? topCustomers,
    List<Map<String, dynamic>>? recentActivities,
    List<Map<String, dynamic>>? treasuryBalances,
    List<Map<String, dynamic>>? bankBalances,
    List<Map<String, dynamic>>? upcomingShipments,
    List<Map<String, dynamic>>? topProducts,
    Map<String, dynamic>? quickAnalytics,
    List<Map<String, dynamic>>? searchResults,
    Map<String, dynamic>? badgeCounts,
    String? currentTime,
  }) {
    return DashboardState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      totalSales: totalSales ?? this.totalSales,
      todaySales: todaySales ?? this.todaySales,
      totalProfit: totalProfit ?? this.totalProfit,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      activeShipments: activeShipments ?? this.activeShipments,
      customerCount: customerCount ?? this.customerCount,
      supplierCount: supplierCount ?? this.supplierCount,
      productCount: productCount ?? this.productCount,
      lowStockCount: lowStockCount ?? this.lowStockCount,
      inventoryValue: inventoryValue ?? this.inventoryValue,
      alerts: alerts ?? this.alerts,
      monthlySales: monthlySales ?? this.monthlySales,
      expenseDistribution: expenseDistribution ?? this.expenseDistribution,
      exportDestinations: exportDestinations ?? this.exportDestinations,
      topCustomers: topCustomers ?? this.topCustomers,
      recentActivities: recentActivities ?? this.recentActivities,
      treasuryBalances: treasuryBalances ?? this.treasuryBalances,
      bankBalances: bankBalances ?? this.bankBalances,
      upcomingShipments: upcomingShipments ?? this.upcomingShipments,
      topProducts: topProducts ?? this.topProducts,
      quickAnalytics: quickAnalytics ?? this.quickAnalytics,
      searchResults: searchResults ?? this.searchResults,
      badgeCounts: badgeCounts ?? this.badgeCounts,
      currentTime: currentTime ?? this.currentTime,
    );
  }
}
