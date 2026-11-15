import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/utils.dart';
import '../../data/services/crop_purchase_calculation_service.dart';

/// State representing the calculated financial and inventory values for a crop purchase.
class CropPurchaseState {
  final String purchaseMethod; // 'weight' or 'carton'
  final double grossWeightKg;
  final double netWeightKg;
  final int cartonCount;
  final int netCartonCount;
  final double weightPerCartonKg;
  final double grossWeightPerCartonKg;
  final double pricePerCarton;
  final double pricePerKg;
  final String currency;
  final double exchangeRate;

  // Derived financial & inventory metrics
  final double supplierGrossTotal;
  final double supplierGrossTotalEgp;
  final double inventoryNetQuantity;
  final double inventoryEffectiveUnitCost;
  final String formulaDescription;
  final String inventoryLineDescription;
  final String supplierCreditDescription;

  const CropPurchaseState({
    this.purchaseMethod = 'weight',
    this.grossWeightKg = 0.0,
    this.netWeightKg = 0.0,
    this.cartonCount = 0,
    this.netCartonCount = 0,
    this.weightPerCartonKg = 0.0,
    this.grossWeightPerCartonKg = 0.0,
    this.pricePerCarton = 0.0,
    this.pricePerKg = 0.0,
    this.currency = 'EGP',
    this.exchangeRate = 1.0,
    this.supplierGrossTotal = 0.0,
    this.supplierGrossTotalEgp = 0.0,
    this.inventoryNetQuantity = 0.0,
    this.inventoryEffectiveUnitCost = 0.0,
    this.formulaDescription = '',
    this.inventoryLineDescription = '',
    this.supplierCreditDescription = '',
  });

  bool get isCarton => CropPurchaseCalculationService.isCartonMethod(purchaseMethod);

  CropPurchaseState copyWith({
    String? purchaseMethod,
    double? grossWeightKg,
    double? netWeightKg,
    int? cartonCount,
    int? netCartonCount,
    double? weightPerCartonKg,
    double? grossWeightPerCartonKg,
    double? pricePerCarton,
    double? pricePerKg,
    String? currency,
    double? exchangeRate,
    double? supplierGrossTotal,
    double? supplierGrossTotalEgp,
    double? inventoryNetQuantity,
    double? inventoryEffectiveUnitCost,
    String? formulaDescription,
    String? inventoryLineDescription,
    String? supplierCreditDescription,
  }) {
    return CropPurchaseState(
      purchaseMethod: purchaseMethod ?? this.purchaseMethod,
      grossWeightKg: grossWeightKg ?? this.grossWeightKg,
      netWeightKg: netWeightKg ?? this.netWeightKg,
      cartonCount: cartonCount ?? this.cartonCount,
      netCartonCount: netCartonCount ?? this.netCartonCount,
      weightPerCartonKg: weightPerCartonKg ?? this.weightPerCartonKg,
      grossWeightPerCartonKg: grossWeightPerCartonKg ?? this.grossWeightPerCartonKg,
      pricePerCarton: pricePerCarton ?? this.pricePerCarton,
      pricePerKg: pricePerKg ?? this.pricePerKg,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      supplierGrossTotal: supplierGrossTotal ?? this.supplierGrossTotal,
      supplierGrossTotalEgp: supplierGrossTotalEgp ?? this.supplierGrossTotalEgp,
      inventoryNetQuantity: inventoryNetQuantity ?? this.inventoryNetQuantity,
      inventoryEffectiveUnitCost: inventoryEffectiveUnitCost ?? this.inventoryEffectiveUnitCost,
      formulaDescription: formulaDescription ?? this.formulaDescription,
      inventoryLineDescription: inventoryLineDescription ?? this.inventoryLineDescription,
      supplierCreditDescription: supplierCreditDescription ?? this.supplierCreditDescription,
    );
  }
}

/// Cubit managing crop purchase calculations, ensuring:
/// 1. The financial liability and amount credited to the supplier uses the **Gross Total**
///    (Total Gross Weight × Price or Total Cartons × Price).
/// 2. Inventory physical storage and stock balances track the **Net Weight**
///    at an absorbed effective unit cost (`gross_total / net_weight`).
class CropPurchaseCubit extends Cubit<CropPurchaseState> {
  CropPurchaseCubit({
    String purchaseMethod = 'weight',
    String currency = 'EGP',
    double exchangeRate = 1.0,
  }) : super(CropPurchaseState(
          purchaseMethod: purchaseMethod,
          currency: currency,
          exchangeRate: exchangeRate,
        ));

  /// Updates weight mode metrics and triggers reactive recalculation
  void updateWeights({
    required double grossWeightKg,
    required double netWeightKg,
    required double pricePerKg,
    String cropName = 'محصول',
    String supplierName = 'المورد',
  }) {
    _recalculate(
      purchaseMethod: 'weight',
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      cropName: cropName,
      supplierName: supplierName,
    );
  }

  /// Updates carton mode metrics and triggers reactive recalculation
  void updateCartons({
    required int cartonCount,
    required int netCartonCount,
    required double weightPerCartonKg,
    double? grossWeightPerCartonKg,
    required double pricePerCarton,
    String cropName = 'محصول',
    String supplierName = 'المورد',
  }) {
    final grossPerCarton = grossWeightPerCartonKg ?? weightPerCartonKg;
    final grossWeight = cartonCount * grossPerCarton;
    final netWeight = netCartonCount * weightPerCartonKg;

    _recalculate(
      purchaseMethod: 'carton',
      cartonCount: cartonCount,
      netCartonCount: netCartonCount,
      weightPerCartonKg: weightPerCartonKg,
      grossWeightPerCartonKg: grossPerCarton,
      grossWeightKg: grossWeight,
      netWeightKg: netWeight,
      pricePerCarton: pricePerCarton,
      cropName: cropName,
      supplierName: supplierName,
    );
  }

  /// Updates currency and spot exchange rate
  void updateCurrency({
    required String currency,
    required double exchangeRate,
    String cropName = 'محصول',
    String supplierName = 'المورد',
  }) {
    _recalculate(
      currency: currency,
      exchangeRate: exchangeRate > 0 ? exchangeRate : 1.0,
      cropName: cropName,
      supplierName: supplierName,
    );
  }

  /// Internal recalculation engine adhering strictly to gross financial vs net inventory segregation
  void _recalculate({
    String? purchaseMethod,
    double? grossWeightKg,
    double? netWeightKg,
    int? cartonCount,
    int? netCartonCount,
    double? weightPerCartonKg,
    double? grossWeightPerCartonKg,
    double? pricePerCarton,
    double? pricePerKg,
    String? currency,
    double? exchangeRate,
    String cropName = 'محصول',
    String supplierName = 'المورد',
  }) {
    final method = purchaseMethod ?? state.purchaseMethod;
    final cur = currency ?? state.currency;
    final rate = exchangeRate ?? state.exchangeRate;
    final grossWt = grossWeightKg ?? state.grossWeightKg;
    final netWt = netWeightKg ?? state.netWeightKg;
    final cartons = cartonCount ?? state.cartonCount;
    final netCartons = netCartonCount ?? state.netCartonCount;
    final wtPerCarton = weightPerCartonKg ?? state.weightPerCartonKg;
    final grossWtPerCarton = grossWeightPerCartonKg ?? state.grossWeightPerCartonKg;
    final pCarton = pricePerCarton ?? state.pricePerCarton;
    final pKg = pricePerKg ?? state.pricePerKg;

    final isCarton = CropPurchaseCalculationService.isCartonMethod(method);

    // 1. Supplier Financial Liability: Gross Total
    final grossTotal = CropPurchaseCalculationService.calculateTotalAmount(
      purchaseMethod: method,
      cartonCount: cartons,
      pricePerCarton: pCarton,
      grossWeightKg: grossWt,
      netWeightKg: netWt,
      pricePerKg: pKg,
    );
    final grossTotalEgp = AppUtils.roundDouble(grossTotal * rate);

    // 2. Physical Inventory Tracking: Net Weight / Net Cartons
    final inventoryQty = isCarton
        ? (netCartons > 0 ? netCartons.toDouble() : cartons.toDouble())
        : (netWt > 0 ? netWt : grossWt);

    // 3. Effective Unit Cost Absorbed into Inventory
    final effectiveUnitCost = CropPurchaseCalculationService.calculateEffectiveInventoryUnitCost(
      totalGrossAmount: grossTotal,
      netWeightKg: isCarton ? netWt : inventoryQty,
      fallbackPrice: isCarton ? pCarton : pKg,
    );

    // 4. Descriptions & Formula Previews
    final formula = CropPurchaseCalculationService.buildFormulaDescription(
      purchaseMethod: method,
      cartonCount: cartons,
      pricePerCarton: pCarton,
      grossWeightKg: grossWt,
      netWeightKg: netWt,
      pricePerKg: pKg,
      totalAmount: grossTotal,
      currency: cur,
    );

    final invDesc = CropPurchaseCalculationService.buildInventoryLineDescription(
      cropName: cropName,
      purchaseMethod: method,
      cartonCount: cartons,
      pricePerCarton: pCarton,
      grossWeightKg: grossWt,
      netWeightKg: netWt,
      pricePerKg: pKg,
      totalAmount: grossTotal,
      currency: cur,
    );

    final suppDesc = CropPurchaseCalculationService.buildSupplierCreditDescription(
      supplierName: supplierName,
      cropName: cropName,
      purchaseMethod: method,
      cartonCount: cartons,
      pricePerCarton: pCarton,
      grossWeightKg: grossWt,
      netWeightKg: netWt,
      pricePerKg: pKg,
      totalAmount: grossTotal,
      currency: cur,
      exchangeRate: rate,
    );

    emit(state.copyWith(
      purchaseMethod: method,
      grossWeightKg: grossWt,
      netWeightKg: netWt,
      cartonCount: cartons,
      netCartonCount: netCartons,
      weightPerCartonKg: wtPerCarton,
      grossWeightPerCartonKg: grossWtPerCarton,
      pricePerCarton: pCarton,
      pricePerKg: pKg,
      currency: cur,
      exchangeRate: rate,
      supplierGrossTotal: grossTotal,
      supplierGrossTotalEgp: grossTotalEgp,
      inventoryNetQuantity: inventoryQty,
      inventoryEffectiveUnitCost: effectiveUnitCost,
      formulaDescription: formula,
      inventoryLineDescription: invDesc,
      supplierCreditDescription: suppDesc,
    ));
  }
}
