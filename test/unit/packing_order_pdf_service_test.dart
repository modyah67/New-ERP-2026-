// test/unit/packing_order_pdf_service_test.dart
// Unit tests for PackingOrderPdfService (Landscape A4 Packing Orders & Segregated Unit/Weight Metrics)

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_model.dart';
import 'package:accounting_system/data/models/packing_order_line_model.dart';
import 'package:accounting_system/features/packing/packing_order_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.';
    });
  });

  group('PackingOrderPdfService Landscape PDF & Unit Segregation Tests', () {
    final sampleOrder1 = PackingOrderModel(
      id: '101',
      orderNumber: 'PO-2026-001',
      lotId: '12',
      lotNumber: 'LOT-2026-088',
      grade: 'A',
      productName: 'برتقال أبو سرة فاخر',
      supplierName: 'مزارع الوادي الأخضر',
      cartonCount: 500,
      netWeightPerCarton: 15.0,
      grossWeightPerCarton: 16.2,
      totalNetWeight: 7500.0,
      totalGrossWeight: 8100.0,
      status: 'completed',
      packedAt: DateTime(2026, 9, 4, 10, 0),
      stationId: '1',
      fruitCostAllocated: 60000.0,
      actualMaterialCost: 12500.0,
      totalPackingCost: 80000.0,
      displayCurrency: 'EGP',
      journalEntryId: '0488',
      notes: jsonEncode({
        'total_raw_weight_kg': 8200.0,
        'waste_weight_kg': 400.0,
        'grade_a_kg': 300.0,
        'materials': [
          {
            'product_name': 'كرتونة مطبوعة 15 كجم',
            'used_qty': 500.0,
            'unit': 'كرتونة',
            'unit_cost': 20.0,
          },
          {
            'product_name': 'زوايا كرتون مقوى',
            'used_qty': 2000.0,
            'unit': 'قطعة',
            'unit_cost': 1.25,
          },
        ],
        'cost_items': [
          {
            'name': 'أجور عمالة التعبئة والتغليف',
            'supplier_name': 'مقاول عمالة اليومية',
            'quantity': 500.0,
            'unit_price': 15.0,
            'total': 7500.0,
          },
        ],
      }),
      lines: const [
        PackingOrderLineModel(
          id: '1',
          packingOrderId: 101,
          productName: 'برتقال أبو سرة نخب أول',
          cartonCount: 500,
          netWeightPerCarton: 15.0,
          grossWeightPerCarton: 16.2,
          quantity: 8200.0,
          rawMaterialCost: 60000.0,
          wasteCost: 2900.0,
          sortingCost: 2200.0,
        ),
      ],
    );

    final sampleOrder2 = PackingOrderModel(
      id: '102',
      orderNumber: 'PO-2026-002',
      lotId: '15',
      lotNumber: 'LOT-2026-092',
      grade: 'A',
      productName: 'عنب كريمسون سوبر',
      supplierName: 'شركة النيل للتنمية الزراعية',
      cartonCount: 300,
      netWeightPerCarton: 5.0,
      grossWeightPerCarton: 5.6,
      totalNetWeight: 1500.0,
      totalGrossWeight: 1680.0,
      status: 'completed',
      packedAt: DateTime(2026, 9, 4, 14, 0),
      stationId: '2',
      fruitCostAllocated: 37500.0,
      actualMaterialCost: 7500.0,
      totalPackingCost: 49500.0,
      displayCurrency: 'EGP',
      journalEntryId: '0491',
      notes: jsonEncode({
        'total_raw_weight_kg': 1650.0,
        'waste_weight_kg': 50.0,
        'grade_a_kg': 100.0,
      }),
    );

    test('computeSummary strictly segregates raw input weight (kg) from packed count (cartons)', () {
      final summary = PackingOrderPdfService.computeSummary([sampleOrder1, sampleOrder2]);

      expect(summary.totalOrders, 2);

      // Raw Input Weights (كجم): 8200.0 + 1650.0 = 9850.0 kg
      expect(summary.totalRawInputWeightKg, 9850.0);

      // Output Finished Cartons (كرتونة): 500 + 300 = 800 cartons
      expect(summary.totalCartonCount, 800);

      // Net Output Weight (كجم): 7500.0 + 1500.0 = 9000.0 kg
      expect(summary.totalNetWeightKg, 9000.0);

      // Gross Output Weight (كجم): 8100.0 + 1680.0 = 9780.0 kg
      expect(summary.totalGrossWeightKg, 9780.0);

      // Waste & Sorting Weights (كجم): (400 + 300) + (50 + 100) = 850 kg
      expect(summary.totalWasteWeightKg, 450.0);
      expect(summary.totalSortedWeightKg, 400.0);

      // Total Cost: order 1 (60000 + 12500 + 7500 = 80000) + order 2 (37500 + 7500 + 4500 = 49500) = 129500 EGP
      expect(summary.totalFruitCost, 97500.0);
      expect(summary.totalMaterialCost, 20000.0);
      expect(summary.totalAllCost, 129500.0);

      // Average cost per carton: 129500 / 800 = 161.875 EGP/carton
      expect(summary.averageCostPerCarton, closeTo(161.875, 0.01));
    });

    test('generateOrderVoucherPdf produces valid Landscape A4 PDF bytes with corporate branding', () async {
      final bytes = await PackingOrderPdfService.generateOrderVoucherPdf(
        sampleOrder1,
        warehouseName: 'محطة تعبئة وتغليف كفر الدوار',
        companyName: 'شركة مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);

      // Verify PDF file magic header (%PDF-)
      final pdfMagic = String.fromCharCodes(bytes.take(5));
      expect(pdfMagic, '%PDF-');
    });

    test('generateOrdersRegisterPdf produces valid Landscape A4 consolidated multi-order register', () async {
      final bytes = await PackingOrderPdfService.generateOrdersRegisterPdf(
        orders: [sampleOrder1, sampleOrder2],
        dateFrom: DateTime(2026, 9, 1),
        dateTo: DateTime(2026, 9, 4),
        filterQuery: 'برتقال',
        companyName: 'شركة مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);

      final pdfMagic = String.fromCharCodes(bytes.take(5));
      expect(pdfMagic, '%PDF-');
    });

    test('savePdf backward-compatible method works correctly without throwing', () async {
      final path = await PackingOrderPdfService.savePdf(
        warehouseName: 'محطة النوبارية',
        lotEntries: [
          {
            'product_name': 'برتقال صيفي',
            'lot_number': 'LOT-SUM-01',
            'carton_count': 200,
            'effective_weight': 3200.0,
            'total_net_weight': 3000.0,
            'total_gross_weight': 3240.0,
            'fruit_cost': 24000.0,
          }
        ],
        materialItems: [
          {
            'product_name': 'كرتونة 15 كجم',
            'used_qty': 200.0,
            'unit_cost': 18.0,
          }
        ],
        costItems: [
          {
            'name': 'مصاريف نقل وتعتيق',
            'total': 1500.0,
          }
        ],
        totalFruitCostBeforeWaste: 24000.0,
        totalWasteCost: 0.0,
        totalFruitCostAfterWaste: 24000.0,
        totalMaterialCost: 3600.0,
        totalMaterialWasteCost: 0.0,
        totalCostItems: 1500.0,
        totalAll: 29100.0,
        packingCostPerCarton: 145.5,
      );

      expect(path, isNotEmpty);
      expect(path.endsWith('.pdf'), isTrue);
    });
    test('generateOrderVoucherPdf handles draft orders without lines gracefully', () async {
      const draftOrder = PackingOrderModel(
        id: '205',
        orderNumber: 'PO-DRAFT-99',
        lotId: '20',
        lotNumber: 'LOT-DR-01',
        grade: 'B',
        productName: 'ليمون بنزهير',
        status: 'draft',
        cartonCount: 150,
        netWeightPerCarton: 10.0,
        totalNetWeight: 1500.0,
        fruitCostAllocated: 15000.0,
        totalPackingCost: 18000.0,
      );

      final bytes = await PackingOrderPdfService.generateOrderVoucherPdf(draftOrder);
      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('generateOrdersRegisterPdf handles empty orders list cleanly', () async {
      final bytes = await PackingOrderPdfService.generateOrdersRegisterPdf(
        orders: const [],
        filterQuery: 'لا يوجد',
      );
      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
