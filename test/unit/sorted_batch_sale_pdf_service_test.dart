// test/unit/sorted_batch_sale_pdf_service_test.dart
// Unit tests for SortedBatchSalePdfService (Landscape A4 Produce Sorting Sales & Segregated Unit Metrics)

import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_sorting_model.dart';
import 'package:accounting_system/features/packing/sorted_batch_sale_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SortedBatchSalePdfService Landscape PDF & Unit Segregation Tests', () {
    final sampleSorting = PackingOrderSortingModel(
      id: 42,
      packingOrderId: 10,
      productName: 'برتقال أبو سرة - نخب فرزة أولى',
      lotNumber: 'LOT-2026-088',
      weightKg: 1250.0,
      remainingWeightKg: 250.0,
      costPerKg: 8.50,
      totalCost: 10625.0,
      totalSaleAmount: 11000.0,
      status: 'pending',
      soldAt: DateTime(2026, 9, 4, 11, 30),
      treasuryNames: 'خزينة محطة التعبئة المركزية',
      createdAt: DateTime(2026, 9, 3, 9, 0),
    );

    final sampleDetails = SortedBatchSaleDetails(
      sorting: sampleSorting,
      customerName: 'مؤسسة النور لتجارة الخضار والفاكهة',
      journalEntryNumber: 'JE-00482',
      journalEntryId: '482',
      treasuryName: 'خزينة محطة التعبئة المركزية',
      saleDate: DateTime(2026, 9, 4),
      notes: 'تم بيع كمية 1000 كجم فرزة برتقال بسعر 11 ج.م للكيلو نقداً.',
      currency: 'EGP',
    );

    test('SortedBatchSaleDetails correctly computes sold weight, unit price, and unit label', () {
      // 1250 - 250 = 1000 kg sold
      expect(sampleDetails.soldWeightKg, 1000.0);
      expect(sampleDetails.totalSaleValue, 11000.0);
      // 11000 / 1000 = 11.00 EGP/kg
      expect(sampleDetails.unitSalePrice, 11.0);
      expect(sampleDetails.effectiveUnit, 'كجم');
      expect(sampleDetails.isCarton, isFalse);
    });

    test('SortedBatchSaleDetails correctly handles packaging carton unit overrides', () {
      final cartonSorting = PackingOrderSortingModel(
        id: 77,
        packingOrderId: 20,
        productName: 'طماطم شيري فرزة كراتين',
        lotNumber: 'LOT-2026-110',
        weightKg: 300.0,
        remainingWeightKg: 50.0,
        costPerKg: 25.0,
        totalCost: 7500.0,
        totalSaleAmount: 8750.0,
        status: 'pending',
        soldAt: DateTime(2026, 9, 4),
      );

      final cartonDetails = SortedBatchSaleDetails(
        sorting: cartonSorting,
        unit: 'كرتونة',
      );

      expect(cartonDetails.soldWeightKg, 250.0);
      expect(cartonDetails.effectiveUnit, 'كرتونة');
      expect(cartonDetails.isCarton, isTrue);
      // 8750 / 250 = 35.00 EGP/carton
      expect(cartonDetails.unitSalePrice, 35.0);
    });

    test('computeSummary strictly segregates weight metrics from count/packaging carton metrics', () {
      final mixedItems = [
        // Weight batch: 1000 kg total, 800 kg sold, 200 kg remaining
        PackingOrderSortingModel(
          id: 1,
          packingOrderId: 10,
          productName: 'برتقال فالنسيا وزن',
          lotNumber: 'LOT-01',
          weightKg: 1000.0,
          remainingWeightKg: 200.0,
          totalSaleAmount: 9600.0,
        ),
        // Weight batch: 500 kg total, 500 kg sold, 0 kg remaining (sold out)
        PackingOrderSortingModel(
          id: 2,
          packingOrderId: 10,
          productName: 'عنب كريمسون كجم',
          lotNumber: 'LOT-02',
          weightKg: 500.0,
          remainingWeightKg: 0.0,
          totalSaleAmount: 7500.0,
        ),
        // Carton batch: 120 cartons total, 100 cartons sold, 20 cartons remaining
        PackingOrderSortingModel(
          id: 3,
          packingOrderId: 10,
          productName: 'فراولة فريش فرزة كراتين',
          lotNumber: 'LOT-03',
          weightKg: 120.0,
          remainingWeightKg: 20.0,
          totalSaleAmount: 5000.0,
        ),
        // Carton batch: 50 cartons total, 0 cartons sold, 50 cartons remaining
        PackingOrderSortingModel(
          id: 4,
          packingOrderId: 10,
          productName: 'برقوق أحمر فرزة صندوق',
          lotNumber: 'LOT-04',
          weightKg: 50.0,
          remainingWeightKg: 50.0,
          totalSaleAmount: 0.0,
        ),
      ];

      final summary = SortedBatchSalePdfService.computeSummary(mixedItems);

      // Counts
      expect(summary.totalCount, 4);
      expect(summary.soldCount, 3);

      // Weight metrics: only lots 1 and 2
      expect(summary.totalOriginalWeight, 1500.0); // 1000 + 500
      expect(summary.totalSoldWeight, 1300.0);     // 800 + 500
      expect(summary.totalRemainingWeight, 200.0);  // 200 + 0

      // Carton metrics: only lots 3 and 4
      expect(summary.totalOriginalCartons, 170.0); // 120 + 50
      expect(summary.totalSoldCartons, 100.0);     // 100 + 0
      expect(summary.totalRemainingCartons, 70.0); // 20 + 50

      // Financials
      expect(summary.totalSalesRevenue, 22100.0);  // 9600 + 7500 + 5000 + 0
      expect(summary.hasCartons, isTrue);
      expect(summary.hasWeights, isTrue);
    });

    test('generateSaleVoucherPdf generates valid non-empty Landscape A4 PDF bytes', () async {
      final pdfBytes = await SortedBatchSalePdfService.generateSaleVoucherPdf(
        sampleDetails,
        companyName: 'شركة مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      final headerStr = String.fromCharCodes(pdfBytes.take(5));
      expect(headerStr, equals('%PDF-'));
    });

    test('generateSaleVoucherPdf handles fully sold carton batches', () async {
      final soldOutCartonSorting = PackingOrderSortingModel(
        id: 43,
        packingOrderId: 11,
        productName: 'فراولة تصنيع ومربى فرزة كراتين',
        lotNumber: 'LOT-2026-095',
        weightKg: 80.0,
        remainingWeightKg: 0.0,
        costPerKg: 40.0,
        totalCost: 3200.0,
        totalSaleAmount: 4800.0,
        status: 'sold',
        soldAt: DateTime(2026, 9, 5, 10, 0),
        treasuryNames: null,
      );

      final cartonDetails = SortedBatchSaleDetails(
        sorting: soldOutCartonSorting,
        unit: 'كرتونة',
      );

      expect(soldOutCartonSorting.isSoldOut, isTrue);
      expect(cartonDetails.isCarton, isTrue);
      expect(cartonDetails.soldWeightKg, 80.0);
      expect(cartonDetails.unitSalePrice, 60.0);

      final pdfBytes = await SortedBatchSalePdfService.generateSaleVoucherPdf(
        cartonDetails,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      final headerStr = String.fromCharCodes(pdfBytes.take(5));
      expect(headerStr, equals('%PDF-'));
    });

    test('generateSalesRegisterPdf generates multi-batch consolidated register PDF with segregated cards', () async {
      final items = [
        sampleSorting,
        PackingOrderSortingModel(
          id: 44,
          packingOrderId: 12,
          productName: 'مانجو كيت فرزة كراتين',
          lotNumber: 'LOT-2026-102',
          weightKg: 150.0,
          remainingWeightKg: 50.0,
          costPerKg: 50.0,
          totalCost: 7500.0,
          totalSaleAmount: 6000.0,
          status: 'pending',
          soldAt: DateTime(2026, 9, 4),
          treasuryNames: 'خزينة رئيسية',
        ),
        PackingOrderSortingModel(
          id: 45,
          packingOrderId: 12,
          productName: 'عنب كريمسون فرزة وزن',
          lotNumber: 'LOT-2026-103',
          weightKg: 300.0,
          remainingWeightKg: 300.0,
          costPerKg: 15.0,
          totalCost: 4500.0,
          totalSaleAmount: 0.0,
          status: 'pending',
        ),
      ];

      final pdfBytes = await SortedBatchSalePdfService.generateSalesRegisterPdf(
        items,
        companyName: 'شركة مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
        filterQuery: 'فرزة',
        dateLabel: 'من 2026-09-01 إلى 2026-09-05',
        currency: 'EGP',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      final headerStr = String.fromCharCodes(pdfBytes.take(5));
      expect(headerStr, equals('%PDF-'));
    });
  });
}
