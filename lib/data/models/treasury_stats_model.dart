import 'package:equatable/equatable.dart';

class TreasuryStatsModel extends Equatable {
  final double totalExpenses;
  final double totalDisbursements;
  final double totalReturns;
  final double totalTransfers;
  final double totalDeposits;
  final int totalTransactions;
  final List<CategoryBreakdown> categoryBreakdown;
  final List<CategoryBreakdown> revenueBreakdown;
  final List<CurrencyTotal> currencyTotals;
  final double totalEmployeeCustody;
  final List<CurrencyTotal> employeeCustodyBreakdown;
  final List<CurrencyTotal> expensesByCurrency;
  final List<CurrencyTotal> disbursementsByCurrency;
  final List<CurrencyTotal> depositsByCurrency;

  const TreasuryStatsModel({
    this.totalExpenses = 0.0,
    this.totalDisbursements = 0.0,
    this.totalReturns = 0.0,
    this.totalTransfers = 0.0,
    this.totalDeposits = 0.0,
    this.totalTransactions = 0,
    this.categoryBreakdown = const [],
    this.revenueBreakdown = const [],
    this.currencyTotals = const [],
    this.totalEmployeeCustody = 0.0,
    this.employeeCustodyBreakdown = const [],
    this.expensesByCurrency = const [],
    this.disbursementsByCurrency = const [],
    this.depositsByCurrency = const [],
  });

  factory TreasuryStatsModel.fromJson(Map<String, dynamic> json) {
    num n(dynamic v) => (v as num?) ?? 0;

    return TreasuryStatsModel(
      totalExpenses: n(json['total_expenses']).toDouble(),
      totalDisbursements: n(json['total_disbursements']).toDouble(),
      totalReturns: n(json['total_returns']).toDouble(),
      totalTransfers: n(json['total_transfers']).toDouble(),
      totalDeposits: n(json['total_deposits']).toDouble(),
      totalTransactions: n(json['total_transactions']).toInt(),
      categoryBreakdown: (json['category_breakdown'] as List?)
              ?.map((e) => CategoryBreakdown.fromMap(Map.from(e)))
              .toList() ??
          [],
      revenueBreakdown: (json['revenue_breakdown'] as List?)
              ?.map((e) => CategoryBreakdown.fromMap(Map.from(e)))
              .toList() ??
          [],
      currencyTotals: (json['currency_totals'] as List?)
              ?.map((e) => CurrencyTotal.fromMap(Map.from(e)))
              .toList() ??
          [],
      totalEmployeeCustody: n(json['total_employee_custody']).toDouble(),
      employeeCustodyBreakdown: (json['employee_custody_breakdown'] as List?)
              ?.map((e) => CurrencyTotal.fromMap(Map.from(e)))
              .toList() ??
          [],
      expensesByCurrency: (json['expenses_by_currency'] as List?)
              ?.map((e) => CurrencyTotal.fromMap(Map.from(e)))
              .toList() ??
          [],
      disbursementsByCurrency: (json['disbursements_by_currency'] as List?)
              ?.map((e) => CurrencyTotal.fromMap(Map.from(e)))
              .toList() ??
          [],
      depositsByCurrency: (json['deposits_by_currency'] as List?)
              ?.map((e) => CurrencyTotal.fromMap(Map.from(e)))
              .toList() ??
          [],
    );
  }

  @override
  List<Object?> get props => [
        totalExpenses,
        totalDisbursements,
        totalReturns,
        totalTransfers,
        totalDeposits,
        totalTransactions,
        categoryBreakdown,
        revenueBreakdown,
        currencyTotals,
        totalEmployeeCustody,
        employeeCustodyBreakdown,
        expensesByCurrency,
        disbursementsByCurrency,
        depositsByCurrency,
      ];
}

class CategoryBreakdown extends Equatable {
  final int id;
  final String name;
  final String code;
  final String color;
  final double total;

  const CategoryBreakdown({
    required this.id,
    required this.name,
    this.code = '',
    required this.color,
    this.total = 0.0,
  });

  factory CategoryBreakdown.fromMap(Map<String, dynamic> map) {
    return CategoryBreakdown(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: map['name']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      color: map['color']?.toString() ?? '#10B981',
      total: ((map['total'] as num?) ?? 0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [id, name, code, color, total];
}

class CurrencyTotal extends Equatable {
  final String currency;
  final double total;

  const CurrencyTotal({required this.currency, this.total = 0.0});

  factory CurrencyTotal.fromMap(Map<String, dynamic> map) {
    return CurrencyTotal(
      currency: map['currency']?.toString() ?? '',
      total: ((map['total'] as num?) ?? 0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [currency, total];
}
