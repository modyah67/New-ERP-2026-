import 'currency_conversion_service.dart';

/// Lightweight currency amount used by CostLineItem/CostBreakdown.
class CurrencyAmount {
  final double originalAmount;
  final String originalCurrency;
  final double exchangeRate;
  final double baseAmount;

  const CurrencyAmount({
    required this.originalAmount,
    required this.originalCurrency,
    required this.exchangeRate,
    required this.baseAmount,
  });

  static const CurrencyAmount zero = CurrencyAmount(
    originalAmount: 0,
    originalCurrency: 'EGP',
    exchangeRate: 1.0,
    baseAmount: 0,
  );

  bool get isEGP => originalCurrency == 'EGP';
}

/// Represents a single cost line item with full currency context.
class CostLineItem {
  final String name;
  final CurrencyAmount amount;
  final String category;
  final int? reportCategoryId;
  final String? reportCategoryName;

  const CostLineItem({
    required this.name,
    required this.amount,
    required this.category,
    this.reportCategoryId,
    this.reportCategoryName,
  });

  double get baseAmount => amount.baseAmount;
  String get currency => amount.originalCurrency;
}

/// Aggregated cost breakdown for display and calculation.
class CostBreakdown {
  final List<CostLineItem> items;
  final String displayCurrency;
  final double displayExchangeRate;

  const CostBreakdown({
    required this.items,
    required this.displayCurrency,
    required this.displayExchangeRate,
  });

  double get totalBase => items.fold(0.0, (sum, i) => sum + i.baseAmount);

  double get totalDisplay {
    if (displayCurrency == CurrencyConversionService.baseCurrency) return totalBase;
    return CurrencyConversionService.instance.fromBase(totalBase, displayCurrency, displayExchangeRate);
  }

  List<CostLineItem> get fruitItems => items.where((i) => i.category == 'fruit').toList();
  List<CostLineItem> get materialItems => items.where((i) => i.category == 'material').toList();
  List<CostLineItem> get logisticsItems => items.where((i) => i.category == 'logistics').toList();
  List<CostLineItem> get otherItems => items.where((i) => i.category == 'other').toList();

  double get totalFruitBase => fruitItems.fold(0.0, (sum, i) => sum + i.baseAmount);
  double get totalMaterialBase => materialItems.fold(0.0, (sum, i) => sum + i.baseAmount);
  double get totalLogisticsBase => logisticsItems.fold(0.0, (sum, i) => sum + i.baseAmount);
  double get totalOtherBase => otherItems.fold(0.0, (sum, i) => sum + i.baseAmount);

  double costPerCarton(int cartons) => cartons > 0 ? totalBase / cartons : 0;
  double costPerKg(double totalKg) => totalKg > 0 ? totalBase / totalKg : 0;

  double costPerCartonDisplay(int cartons) {
    if (displayCurrency == CurrencyConversionService.baseCurrency) return costPerCarton(cartons);
    return CurrencyConversionService.instance.fromBase(costPerCarton(cartons), displayCurrency, displayExchangeRate);
  }

  double costPerKgDisplay(double totalKg) {
    if (displayCurrency == CurrencyConversionService.baseCurrency) return costPerKg(totalKg);
    return CurrencyConversionService.instance.fromBase(costPerKg(totalKg), displayCurrency, displayExchangeRate);
  }
}

/// Unified cost calculation engine — single source of truth.
///
/// ALL cost calculations MUST go through this engine.
/// NEVER calculate costs directly in widgets/pages/DAOs.
class CostCalculationEngine {
  CostCalculationEngine._();
  static final CostCalculationEngine instance = CostCalculationEngine._();
  factory CostCalculationEngine() => instance;

  final CurrencyConversionService _currencyService = CurrencyConversionService.instance;

  /// Build a CostLineItem from raw values — the ONLY way to create one.
  CostLineItem createLineItem({
    required String name,
    required double originalAmount,
    required String originalCurrency,
    required double exchangeRate,
    required String category,
  }) {
    final baseAmount = _currencyService.toBase(originalAmount, originalCurrency, exchangeRate);
    return CostLineItem(
      name: name,
      amount: CurrencyAmount(
        originalAmount: originalAmount,
        originalCurrency: originalCurrency,
        exchangeRate: originalCurrency == 'EGP' ? 1.0 : exchangeRate,
        baseAmount: baseAmount,
      ),
      category: category,
    );
  }

  /// Build a CostLineItem already in base currency (EGP).
  CostLineItem createBaseLineItem({
    required String name,
    required double baseAmount,
    required String category,
  }) {
    return CostLineItem(
      name: name,
      amount: CurrencyAmount(
        originalAmount: baseAmount,
        originalCurrency: CurrencyConversionService.baseCurrency,
        exchangeRate: 1.0,
        baseAmount: baseAmount,
      ),
      category: category,
    );
  }

  /// Aggregate a list of cost line items into a CostBreakdown.
  CostBreakdown aggregate({
    required List<CostLineItem> items,
    required String displayCurrency,
    required double displayExchangeRate,
  }) {
    return CostBreakdown(
      items: items,
      displayCurrency: displayCurrency,
      displayExchangeRate: displayExchangeRate,
    );
  }

  /// Calculate fruit cost from lot receipt data.
  /// [quantityKg] total kg received
  /// [costPerKg] original currency cost per kg
  /// [currency] original currency code
  /// [exchangeRate] rate to EGP
  CostLineItem calculateFruitCost({
    required String name,
    required double quantityKg,
    required double costPerKg,
    required String currency,
    required double exchangeRate,
  }) {
    final originalTotal = quantityKg * costPerKg;
    return createLineItem(
      name: name,
      originalAmount: originalTotal,
      originalCurrency: currency,
      exchangeRate: exchangeRate,
      category: 'fruit',
    );
  }

  /// Calculate packing material cost.
  CostLineItem calculateMaterialCost({
    required String name,
    required double quantity,
    required double unitCost,
    required String currency,
    required double exchangeRate,
  }) {
    final originalTotal = quantity * unitCost;
    return createLineItem(
      name: name,
      originalAmount: originalTotal,
      originalCurrency: currency,
      exchangeRate: exchangeRate,
      category: 'material',
    );
  }

  /// Calculate a cost item that's already in EGP.
  CostLineItem calculateEgpCost({
    required String name,
    required double amount,
    required String category,
  }) {
    return createBaseLineItem(name: name, baseAmount: amount, category: category);
  }

  /// Calculate total cost for a packing order — NEVER mixes currencies.
  CostBreakdown calculatePackingOrderCost({
    required double fruitCostBase,
    required double materialCostBase,
    required double otherCostBase,
    required String displayCurrency,
    required double displayExchangeRate,
  }) {
    final items = <CostLineItem>[
      if (fruitCostBase > 0) createBaseLineItem(name: 'تكلفة المنتج', baseAmount: fruitCostBase, category: 'fruit'),
      if (materialCostBase > 0) createBaseLineItem(name: 'مواد التعبئة', baseAmount: materialCostBase, category: 'material'),
      if (otherCostBase > 0) createBaseLineItem(name: 'بنود أخرى', baseAmount: otherCostBase, category: 'other'),
    ];
    return aggregate(items: items, displayCurrency: displayCurrency, displayExchangeRate: displayExchangeRate);
  }

  /// Calculate profit — all inputs MUST be in base currency.
  ({
    double grossProfit,
    double netProfit,
    double grossMargin,
    double netMargin,
    double revenueBase,
    double totalCostBase,
  }) calculateProfit({
    required double revenueBase,
    required double totalCostBase,
  }) {
    final grossProfit = revenueBase - totalCostBase;
    final netProfit = grossProfit;
    final grossMargin = revenueBase > 0 ? (grossProfit / revenueBase) * 100 : 0.0;
    final netMargin = revenueBase > 0 ? (netProfit / revenueBase) * 100 : 0.0;
    return (
      grossProfit: grossProfit,
      netProfit: netProfit,
      grossMargin: grossMargin,
      netMargin: netMargin,
      revenueBase: revenueBase,
      totalCostBase: totalCostBase,
    );
  }

  /// Convert a CostBreakdown to display currency values for UI.
  ({
    double fruitDisplay,
    double materialDisplay,
    double logisticsDisplay,
    double otherDisplay,
    double totalDisplay,
    double costPerCartonDisplay,
    double costPerKgDisplay,
  }) toDisplay(CostBreakdown breakdown, {int cartons = 0, double totalKg = 0}) {
    final cs = _currencyService;
    final rate = breakdown.displayExchangeRate;
    final cur = breakdown.displayCurrency;

    double conv(double baseVal) {
      if (cur == CurrencyConversionService.baseCurrency) return baseVal;
      return cs.fromBase(baseVal, cur, rate);
    }

    return (
      fruitDisplay: conv(breakdown.totalFruitBase),
      materialDisplay: conv(breakdown.totalMaterialBase),
      logisticsDisplay: conv(breakdown.totalLogisticsBase),
      otherDisplay: conv(breakdown.totalOtherBase),
      totalDisplay: conv(breakdown.totalBase),
      costPerCartonDisplay: breakdown.costPerCartonDisplay(cartons),
      costPerKgDisplay: breakdown.costPerKgDisplay(totalKg),
    );
  }
}
