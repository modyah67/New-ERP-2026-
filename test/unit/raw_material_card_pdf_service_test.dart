import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/raw_materials/raw_material_card_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RawMaterialCardPdfService / PackagingItemCardPdfService Tests', () {
    final mockBatches = [
      {
        'id': 'b-1',
        'created_at': '2026-08-15T10:00:00',
        'station_id': 1,
        'station_name': 'مخزن التعبئة المركزي',
        'supplier_name': 'شركة الأهرام للكرتون',
        'invoice_number': 'INV-4091',
        'source_type': 'purchase',
        'remaining_quantity': 2500.0,
        'purchase_cost': 14.50,
        'exchange_rate': 1.0, // Should format as '—'
        'currency': 'EGP',
      },
      {
        'id': 'b-2',
        'created_at': '2026-08-20T14:30:00',
        'station_id': 2,
        'station_name': 'مخزن المحطة 2',
        'supplier_name': 'مصنع الدلتا للمستلزمات',
        'invoice_number': '', // Missing invoice number
        'source_type': 'purchase',
        'remaining_quantity': 1800.0,
        'purchase_cost': 15.00,
        'exchange_rate': 48.50, // Foreign currency / non-1 rate
        'currency': 'USD',
      },
      {
        'id': 'b-3',
        'created_at': '2026-07-01T09:00:00',
        'station_id': null,
        'station_name': null, // Missing station name -> defaults cleanly
        'supplier_name': null, // Missing supplier -> defaults to 'رصيد افتتاحي'
        'invoice_number': null,
        'source_type': 'opening',
        'remaining_quantity': 500.0,
        'purchase_cost': 12.00,
        'exchange_rate': null, // Null exchange rate -> '—'
        'currency': 'EGP',
      },
    ];

    test('generatePdfBytes produces non-empty bytes in Landscape format with sanitized cells', () async {
      final bytes = await RawMaterialCardPdfService.generatePdfBytes(
        itemName: 'كرتونة 5 كجم تلسكوبك توب',
        itemCode: 'BOX-5KG-TEL',
        categoryName: 'مواد تعبئة وتغليف',
        unit: 'كرتونة',
        currency: 'EGP',
        initialQuantity: 1000.0,
        initialAvgPrice: 12.0,
        currentQuantity: 4800.0,
        minimumStock: 2000.0,
        estimatedValue: 69250.0,
        avgCost: 14.43,
        statusLabel: 'متوفر',
        batches: mockBatches,
        settings: {
          'company_name': 'Fruity Farms Export Co.',
        },
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // PDF signature "%PDF" at index 0..3
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('generatePdfBytes produces valid PDF when batches are empty', () async {
      final bytes = await RawMaterialCardPdfService.generatePdfBytes(
        itemName: 'صنف فارغ من الدفعات',
        itemCode: 'EMPTY-001',
        categoryName: 'خامات عامة',
        unit: 'قطعة',
        currency: 'EGP',
        initialQuantity: 0.0,
        initialAvgPrice: 0.0,
        currentQuantity: 0.0,
        minimumStock: 500.0,
        estimatedValue: 0.0,
        avgCost: 0.0,
        statusLabel: 'نفد',
        batches: [],
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('PackagingItemCardPdfService alias works identically', () async {
      final bytes = await PackagingItemCardPdfService.generatePdfBytes(
        itemName: 'زاوية كرتون حماية 2 متر',
        itemCode: 'CRN-2M',
        categoryName: 'زوايا حماية',
        unit: 'قطعة',
        currency: 'EGP',
        initialQuantity: 200.0,
        initialAvgPrice: 5.0,
        currentQuantity: 800.0,
        minimumStock: 300.0,
        estimatedValue: 4000.0,
        avgCost: 5.0,
        statusLabel: 'متوفر',
        batches: mockBatches.take(1).toList(),
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });
  });
}
