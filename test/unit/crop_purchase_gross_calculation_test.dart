import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/crop_purchase_calculation_service.dart';
import 'package:accounting_system/features/lots/crop_purchase_cubit.dart';
import 'package:accounting_system/data/models/purchase_model.dart';

void main() {
  group('Crop Purchase Gross Financial Liability vs Net Inventory Segregation Tests', () {
    test('Weight mode: financial liability is based on gross weight, not net weight', () {
      const grossWeight = 500.0;
      const netWeight = 480.0;
      const pricePerKg = 25.0;

      final supplierAmount = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'weight',
        grossWeightKg: grossWeight,
        netWeightKg: netWeight,
        pricePerKg: pricePerKg,
      );

      // Must be 500 * 25 = 12500, NOT 480 * 25 = 12000
      expect(supplierAmount, equals(12500.0));

      final effectiveUnitCost = CropPurchaseCalculationService.calculateEffectiveInventoryUnitCost(
        totalGrossAmount: supplierAmount,
        netWeightKg: netWeight,
      );

      // Effective inventory cost absorbs gross total across net usable weight: 12500 / 480 = 26.04
      expect(effectiveUnitCost, equals(26.04));
    });

    test('Weight mode: fallback to net weight when gross weight is null or zero', () {
      const netWeight = 400.0;
      const pricePerKg = 30.0;

      final totalWithZeroGross = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'weight',
        grossWeightKg: 0.0,
        netWeightKg: netWeight,
        pricePerKg: pricePerKg,
      );
      expect(totalWithZeroGross, equals(12000.0));

      final totalWithNullGross = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'weight',
        grossWeightKg: null,
        netWeightKg: netWeight,
        pricePerKg: pricePerKg,
      );
      expect(totalWithNullGross, equals(12000.0));
    });

    test('Carton mode: financial liability is based on total cartons', () {
      const cartonCount = 1000;
      const pricePerCarton = 2.50;

      final supplierAmount = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'carton',
        cartonCount: cartonCount,
        pricePerCarton: pricePerCarton,
      );

      expect(supplierAmount, equals(2500.0));
    });

    test('Formula description distinguishes gross weight from net storage weight', () {
      final formula = CropPurchaseCalculationService.buildFormulaDescription(
        purchaseMethod: 'weight',
        grossWeightKg: 500.0,
        netWeightKg: 480.0,
        pricePerKg: 25.0,
        totalAmount: 12500.0,
        currency: 'USD',
      );

      expect(formula, contains('500.00 كجم (إجمالي)'));
      expect(formula, contains('25.00 \$'));
      expect(formula, contains('12500.00 \$'));
      expect(formula, contains('[صافي المخزن: 480.00 كجم]'));
    });

    test('Inventory line description explicitly states net weight and absorbed cost', () {
      final invDesc = CropPurchaseCalculationService.buildInventoryLineDescription(
        cropName: 'مانجو كيت',
        purchaseMethod: 'weight',
        grossWeightKg: 500.0,
        netWeightKg: 480.0,
        pricePerKg: 25.0,
        totalAmount: 12500.0,
        currency: 'USD',
        lotNumber: 'LOT-101',
      );

      expect(invDesc, contains('مخزون المحاصيل - مانجو كيت'));
      expect(invDesc, contains('480.00 كجم (صافي)'));
      expect(invDesc, contains('تكلفة مستوعبة'));
      expect(invDesc, contains('لوط: LOT-101'));
    });

    test('Supplier credit description explicitly states gross calculation basis', () {
      final suppDesc = CropPurchaseCalculationService.buildSupplierCreditDescription(
        supplierName: 'مزرعة النيل',
        cropName: 'مانجو كيت',
        purchaseMethod: 'weight',
        grossWeightKg: 500.0,
        netWeightKg: 480.0,
        pricePerKg: 25.0,
        totalAmount: 12500.0,
        currency: 'USD',
        exchangeRate: 50.0,
        lotNumber: 'LOT-101',
      );

      expect(suppDesc, contains('مستحقات مورد (إجمالي) - مزرعة النيل'));
      expect(suppDesc, contains('500.00 كجم (إجمالي)'));
      expect(suppDesc, contains('[سعر صرف 50.00 ج.م]'));
    });

    test('generateCropJournalLines balances exactly: Total Debit == Total Credit == Gross Total', () {
      final lines = CropPurchaseCalculationService.generateCropJournalLines(
        cropName: 'برتقال فالنسيا',
        purchaseMethod: 'weight',
        grossWeightKg: 1000.0,
        netWeightKg: 950.0,
        pricePerKg: 15.0,
        totalAmount: 15000.0,
        currency: 'USD',
        exchangeRate: 48.0,
        supplierAccountId: 211105,
        supplierAccountCode: '211105',
        supplierName: 'مزارع الوادي',
        lotNumber: 'LOT-0099',
      );

      expect(lines.length, equals(2));
      final debitLine = lines[0];
      final creditLine = lines[1];

      // Debit line: Inventory
      expect(debitLine['account_code'], equals('12412'));
      expect(debitLine['quantity'], equals(950.0)); // Physical net quantity
      expect(debitLine['unit'], equals('كجم (صافي)'));
      expect(debitLine['debit'], equals(15000.0)); // Absorbed gross amount
      expect(debitLine['base_debit'], equals(15000.0 * 48.0));

      // Credit line: Supplier
      expect(creditLine['account_code'], equals('211105'));
      expect(creditLine['credit'], equals(15000.0)); // Gross liability
      expect(creditLine['base_credit'], equals(15000.0 * 48.0));

      // Double entry equilibrium
      expect(debitLine['base_debit'], equals(creditLine['base_credit']));
    });

    test('CropPurchaseCubit updates state reactively with gross financial total and net inventory quantity', () {
      final cubit = CropPurchaseCubit(currency: 'USD', exchangeRate: 50.0);

      cubit.updateWeights(
        grossWeightKg: 2000.0,
        netWeightKg: 1900.0,
        pricePerKg: 10.0,
        cropName: 'فراولة',
        supplierName: 'مورد الفراولة',
      );

      expect(cubit.state.supplierGrossTotal, equals(20000.0));
      expect(cubit.state.supplierGrossTotalEgp, equals(1000000.0));
      expect(cubit.state.inventoryNetQuantity, equals(1900.0));
      expect(cubit.state.inventoryEffectiveUnitCost, equals(10.53));
      expect(cubit.state.formulaDescription, contains('2000.00 كجم (إجمالي)'));
      expect(cubit.state.formulaDescription, contains('[صافي المخزن: 1900.00 كجم]'));

      cubit.close();
    });

    test('PurchaseLineData calculates gross total price while quantity tracks net weight', () {
      final line = PurchaseLineData(
        name: 'رمان',
        purchaseMethod: 'weight',
        grossWeightKg: 800.0,
        netWeightKg: 750.0,
        quantity: 750.0,
        purchasePrice: 12.0,
        exchangeRate: 1.0,
      );

      // Total price based on gross weight
      expect(line.totalPrice, equals(9600.0));
      // Inventory quantity remains net weight
      expect(line.netWeightKg, equals(750.0));
      expect(line.quantity, equals(750.0));
    });
  });
}
