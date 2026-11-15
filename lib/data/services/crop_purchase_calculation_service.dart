import '../../core/utils.dart';

/// Service responsible for financial calculations, active formula building,
/// and item-level journal entry / transaction generation for crop purchases.
///
/// Financial Rule:
/// - **Supplier Liability (دائن مستحقات المورد)**: Computed based on **Gross Total**
///   (Total Gross Weight × Price per Kg or Total Cartons × Price per Carton).
/// - **Inventory Accounting (مدين مخزون المحاصيل)**: Physical quantities track the
///   **Net Weight (الوزن الصافي)**, absorbing the gross total financial cost into an
///   effective unit cost per net kg (`gross_total / net_weight`).
class CropPurchaseCalculationService {
  static final CropPurchaseCalculationService instance =
      CropPurchaseCalculationService._();
  CropPurchaseCalculationService._();

  /// Calculates the total financial purchase amount credited to the supplier:
  ///
  /// - **By Cartons (كراتين)**:
  ///   `Total Amount = Number of Cartons (عدد الكراتين الإجمالي) × Price per Carton (سعر الكرتونة)`
  ///
  /// - **By Weight (بالوزن)**:
  ///   `Total Amount = Gross Weight (الوزن الإجمالي/القائم) × Price per Unit/Kg (سعر الكيلو)`
  ///   If gross weight is omitted or zero, falls back to net weight.
  static double calculateTotalAmount({
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
  }) {
    final isCarton = isCartonMethod(purchaseMethod);
    if (isCarton) {
      final count = (cartonCount ?? 0).clamp(0, 999999999);
      final price = (pricePerCarton ?? 0.0).clamp(0.0, double.infinity);
      return AppUtils.roundDouble(count * price);
    } else {
      final gross = (grossWeightKg ?? 0.0).clamp(0.0, double.infinity);
      final net = (netWeightKg ?? 0.0).clamp(0.0, double.infinity);
      final weight = gross > 0 ? gross : net;
      final price = (pricePerKg ?? 0.0).clamp(0.0, double.infinity);
      return AppUtils.roundDouble(weight * price);
    }
  }

  /// Calculates the effective absorbed inventory unit cost per net kg:
  /// The total gross financial liability to the supplier is absorbed across
  /// the actual usable net physical weight received in the warehouse.
  static double calculateEffectiveInventoryUnitCost({
    required double totalGrossAmount,
    required double netWeightKg,
    double? fallbackPrice,
  }) {
    if (netWeightKg > 0) {
      return AppUtils.roundDouble(totalGrossAmount / netWeightKg);
    }
    return (fallbackPrice ?? 0.0).clamp(0.0, double.infinity);
  }

  /// Checks if the purchase method corresponds to carton-based purchasing.
  static bool isCartonMethod(String method) {
    final lower = method.trim().toLowerCase();
    return lower == 'carton' ||
        lower == 'cartons' ||
        lower.contains('كرتون') ||
        lower.contains('طرد');
  }

  /// Builds the active formula string reflecting the supplier's gross settlement:
  ///
  /// - Cartons: `1000 كرتونة (إجمالي) × 2.00 $ = 2,000.00 $`
  /// - Weight:  `500.00 كجم (إجمالي) × 25.00 $ = 12,500.00 $ [صافي المخزن: 480.00 كجم]`
  static String buildFormulaDescription({
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
  }) {
    final currencySymbol = formatCurrencySymbol(currency);
    final isCarton = isCartonMethod(purchaseMethod);

    if (isCarton) {
      final count = cartonCount ?? 0;
      final price = pricePerCarton ?? (count > 0 ? (totalAmount / count) : 0.0);
      return '$count كرتونة (إجمالي) × ${price.toStringAsFixed(2)} $currencySymbol = ${totalAmount.toStringAsFixed(2)} $currencySymbol';
    } else {
      final gross = (grossWeightKg != null && grossWeightKg > 0)
          ? grossWeightKg
          : (netWeightKg ?? 0.0);
      final price = pricePerKg ?? (gross > 0 ? (totalAmount / gross) : 0.0);
      final grossPart =
          '${gross.toStringAsFixed(2)} كجم (إجمالي) × ${price.toStringAsFixed(2)} $currencySymbol = ${totalAmount.toStringAsFixed(2)} $currencySymbol';
      if (netWeightKg != null &&
          netWeightKg > 0 &&
          (netWeightKg - gross).abs() > 0.001) {
        return '$grossPart [صافي المخزن: ${netWeightKg.toStringAsFixed(2)} كجم]';
      }
      return grossPart;
    }
  }

  /// Builds a detailed item-level description for the inventory debit line:
  /// Explicitly demonstrates that physical stock is tracked by Net Weight,
  /// while absorbing the agreed gross total supplier cost.
  static String buildInventoryLineDescription({
    required String cropName,
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
    String? lotNumber,
  }) {
    final isCarton = isCartonMethod(purchaseMethod);
    final currencySymbol = formatCurrencySymbol(currency);
    final formula = buildFormulaDescription(
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalAmount,
      currency: currency,
    );

    final String qtyDesc;
    final String priceDesc;
    if (isCarton) {
      final count = cartonCount ?? 0;
      final price = pricePerCarton ?? (count > 0 ? (totalAmount / count) : 0.0);
      qtyDesc = '$count كرتونة';
      priceDesc = '${price.toStringAsFixed(2)} $currencySymbol/كرتونة';
    } else {
      final net = (netWeightKg != null && netWeightKg > 0)
          ? netWeightKg
          : (grossWeightKg ?? 0.0);
      final effectivePrice =
          net > 0 ? (totalAmount / net) : (pricePerKg ?? 0.0);
      qtyDesc = '${net.toStringAsFixed(2)} كجم (صافي)';
      priceDesc =
          '${effectivePrice.toStringAsFixed(2)} $currencySymbol/كجم (تكلفة مستوعبة)';
    }

    final lotSuffix = (lotNumber != null && lotNumber.trim().isNotEmpty)
        ? ' - لوط: ${lotNumber.trim()}'
        : '';

    return 'مخزون المحاصيل - $cropName - كمية: $qtyDesc - تكلفة: $priceDesc ($formula)$lotSuffix';
  }

  /// Builds the supplier credit line description for accounts payable / ledger:
  /// Explicitly states that the supplier is credited based on the Gross Total.
  static String buildSupplierCreditDescription({
    required String supplierName,
    required String cropName,
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
    double exchangeRate = 1.0,
    String? lotNumber,
  }) {
    final formula = buildFormulaDescription(
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalAmount,
      currency: currency,
    );

    final lotSuffix = (lotNumber != null && lotNumber.trim().isNotEmpty)
        ? ' - لوط: ${lotNumber.trim()}'
        : '';
    final fxSuffix = (currency.toUpperCase() != 'EGP' && exchangeRate > 1.0)
        ? ' [سعر صرف ${exchangeRate.toStringAsFixed(2)} ج.م]'
        : '';

    return 'مستحقات مورد (إجمالي) - $supplierName - $cropName ($formula)$fxSuffix$lotSuffix';
  }

  /// Builds the journal entry header description:
  static String buildHeaderDescription({
    required String supplierName,
    required String cropName,
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
    String? lotNumber,
  }) {
    final formula = buildFormulaDescription(
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalAmount,
      currency: currency,
    );
    final lotSuffix = (lotNumber != null && lotNumber.trim().isNotEmpty)
        ? ' - لوط: ${lotNumber.trim()}'
        : '';
    return 'شراء $cropName من $supplierName (حساب إجمالي) - $formula$lotSuffix';
  }

  /// Formats currency symbols gracefully for Arabized accounting displays.
  static String formatCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'EGP':
        return 'ج.م';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      default:
        return currency;
    }
  }

  /// Generates full double-entry journal entry lines for crop purchase transactions.
  ///
  /// Double-entry bookkeeping principle:
  /// - Total debit == Total credit == Gross financial supplier liability.
  /// - Inventory account receives Net physical weight at the effective absorbed unit cost.
  /// - Supplier account is credited with the full Gross Total amount.
  static List<Map<String, dynamic>> generateCropJournalLines({
    required String cropName,
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
    double exchangeRate = 1.0,
    required int supplierAccountId,
    required String supplierName,
    String? supplierAccountCode,
    int? cropInventoryAccountId,
    String? lotNumber,
  }) {
    final rate = exchangeRate > 0 ? exchangeRate : 1.0;
    final totalForeign = AppUtils.roundDouble(totalAmount);
    final totalEgp = AppUtils.roundDouble(totalForeign * rate);

    final isCarton = isCartonMethod(purchaseMethod);
    final double netQty = (netWeightKg != null && netWeightKg > 0)
        ? netWeightKg
        : (grossWeightKg ?? 0.0);
    final double quantity = isCarton ? (cartonCount ?? 0).toDouble() : netQty;
    final double unitPrice = isCarton
        ? (pricePerCarton ?? 0.0)
        : (quantity > 0
            ? AppUtils.roundDouble(totalForeign / quantity)
            : (pricePerKg ?? 0.0));
    final String unit = isCarton ? 'كرتونة' : 'كجم (صافي)';

    final debitDesc = buildInventoryLineDescription(
      cropName: cropName,
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalForeign,
      currency: currency,
      lotNumber: lotNumber,
    );

    final creditDesc = buildSupplierCreditDescription(
      supplierName: supplierName,
      cropName: cropName,
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalForeign,
      currency: currency,
      exchangeRate: rate,
      lotNumber: lotNumber,
    );

    return [
      // 1. Debit Line: Raw Crop Inventory Account (12412 - مخزن مشتريات خام) - absorbs gross cost into net weight
      {
        'account_id': cropInventoryAccountId ?? 12412,
        'account_code': '12412',
        'account_name': 'مخزن مشتريات خام',
        'item_name': cropName,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'debit': totalForeign,
        'base_debit': totalEgp,
        'credit': 0.0,
        'base_credit': 0.0,
        'currency': currency,
        'amount_in_base_currency': totalEgp,
        'description': debitDesc,
      },
      // 2. Credit Line: Supplier Account (2111 / 211101) - credited based on Gross Total
      {
        'account_id': supplierAccountId,
        'account_code': supplierAccountCode ?? '2111',
        'account_name': 'مستحقات مورد: $supplierName',
        'debit': 0.0,
        'base_debit': 0.0,
        'credit': totalForeign,
        'base_credit': totalEgp,
        'currency': currency,
        'amount_in_base_currency': totalEgp,
        'description': creditDesc,
      },
    ];
  }
}
