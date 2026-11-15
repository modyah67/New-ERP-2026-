import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/lots/crop_return_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CropReturnPdfService Landscape PDF Tests', () {
    final sampleSingleReturn = {
      'id': 101,
      'lot_receipt_id': 12,
      'supplier_id': 'sup-1',
      'station_id': 2,
      'returned_quantity': 450.5,
      'return_value': 11262.50,
      'notes': 'مرتجع محصول لعدم مطابقة المواصفات القياسية المطلوبة',
      'created_at': '2026-09-04T14:30:00.000Z',
      'journal_entry_id': 25,
      'lot_receipts': {
        'lot_number': 'LOT-2026-008',
        'product_name': 'فراولة فريش نخب أول',
        'purchase_mode': 'weight',
        'currency': 'EGP',
      },
      'suppliers': {
        'name': 'شركة الوادي للحاصلات الزراعية',
        'code': 'SUP-014',
      },
      'stations': {
        'name': 'محطة التبريد والتعبئة المركزية',
      },
      'journal_entries': {
        'entry_number': 'RET-00025',
      },
    };

    final sampleReturnsList = [
      sampleSingleReturn,
      {
        'id': 102,
        'lot_receipt_id': 15,
        'supplier_id': 'sup-2',
        'station_id': 3,
        'returned_quantity': 80.0,
        'return_value': 2400.00,
        'notes': 'كراتين تالفة أثناء النقل',
        'created_at': '2026-09-04T16:00:00.000Z',
        'journal_entry_id': null,
        'lot_receipts': {
          'lot_number': 'LOT-2026-011',
          'product_name': 'برتقال صيفي كراتين',
          'purchase_mode': 'carton',
          'currency': 'USD',
        },
        'suppliers': {
          'name': 'مزرعة الأمل الحديثة',
          'code': 'SUP-022',
        },
        'stations': {
          'name': 'محطة فرز النوبارية',
        },
      },
      {
        'id': 103,
        'lot_receipt_id': 18,
        'supplier_id': 'sup-3',
        'station_id': 1,
        'returned_quantity': 1200.0,
        'return_value': 36000.00,
        'notes': 'زيادة في الوزن المستلم عن أمر الشراء',
        'created_at': '2026-09-04T18:15:00.000Z',
        'journal_entry_id': 30,
        'lot_receipts': {
          'lot_number': 'LOT-2026-015',
          'product_name': 'عنب فليم للتصدير',
          'purchase_mode': 'weight',
          'currency': 'EUR',
        },
        'suppliers': {
          'name': 'مزارع الدلتا الزراعية',
          'code': 'SUP-009',
        },
        'stations': {
          'name': 'محطة سادات الزراعية',
        },
        'journal_entries': {
          'entry_number': 'RET-00030',
        },
      },
    ];

    test('generateSingleReturnReceiptPdf compiles valid landscape A4 PDF bytes with %PDF header', () async {
      final bytes = await CropReturnPdfService.generateSingleReturnReceiptPdf(
        sampleSingleReturn,
        companyName: 'مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generateReturnsReportPdf compiles valid multi-record landscape A4 PDF bytes with %PDF header', () async {
      final bytes = await CropReturnPdfService.generateReturnsReportPdf(
        sampleReturnsList,
        companyName: 'مزارع فروتي فارمز لتصدير الحاصلات الزراعية',
        filterQuery: 'فراولة',
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1500));
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generateReturnsReportPdf handles empty returns gracefully without throwing', () async {
      final bytes = await CropReturnPdfService.generateReturnsReportPdf(
        [],
        companyName: 'مزارع فروتي فارمز',
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(500));
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('computeSummary accurately segregates weight units and packaging/carton units', () {
      final summary = CropReturnPdfService.computeSummary(sampleReturnsList);

      expect(summary.totalCount, equals(3));
      // Weight units: 450.5 kg + 1200.0 kg = 1650.5 kg
      expect(summary.totalWeightQty, equals(1650.5));
      // Packaging / Carton units: 80.0 cartons
      expect(summary.totalCartonQty, equals(80.0));
      // Linked journal entries: items 1 and 3 have journal entries = 2
      expect(summary.linkedJeCount, equals(2));
      // Currencies present: EGP, USD, EUR
      expect(summary.valueByCurrency['EGP'], equals(11262.50));
      expect(summary.valueByCurrency['USD'], equals(2400.00));
      expect(summary.valueByCurrency['EUR'], equals(36000.00));
    });

    test('alias LotReturnPdfService points to CropReturnPdfService seamlessly', () {
      expect(LotReturnPdfService, equals(CropReturnPdfService));
    });
  });
}
