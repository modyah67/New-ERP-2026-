import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/features/statements/supplier_consolidated_statement_pdf_service.dart';
import 'package:accounting_system/core/consolidated_statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupplierConsolidatedStatementPdfService Multi-Currency & Landscape Tests', () {
    const sampleSuppliers = [
      SupplierModel(
        id: '1',
        supplierCode: 'SUP0001',
        name: 'مزارع الصالحية لتصدير الفواكه',
        phone: '01012345678',
        currency: 'EGP',
        initialBalance: 50000.0,
        outstandingBalance: 120000.0,
        supplierType: 'crop',
      ),
      SupplierModel(
        id: '2',
        supplierCode: 'SUP0002',
        name: 'شركة الأهرام لمواد التعبئة والتغليف',
        phone: '01198765432',
        currency: 'USD',
        initialBalance: 2000.0,
        outstandingBalance: 4500.0,
        supplierType: 'packaging',
      ),
      SupplierModel(
        id: '3',
        supplierCode: 'SUP0003',
        name: 'مؤسسة الدلتا المشتركة للتوريدات',
        phone: '01234567890',
        currency: 'EUR',
        initialBalance: 1500.0,
        outstandingBalance: -800.0,
        supplierType: 'shared',
      ),
      SupplierModel(
        id: '4',
        supplierCode: 'SUP0004',
        name: 'مجموعة النيل الزراعية',
        phone: '01500001111',
        currency: 'GBP',
        initialBalance: 1000.0,
        outstandingBalance: 3200.0,
        supplierType: 'crop',
      ),
    ];

    test('generatePdf compiles and returns non-empty PDF bytes for multi-currency suppliers', () async {
      final pdfBytes = await SupplierConsolidatedStatementPdfService.generatePdf(
        suppliers: sampleSuppliers,
        cropCount: 2,
        packagingCount: 1,
        sharedCount: 1,
        exchangeRates: const {
          'EGP': 1.0,
          'USD': 50.0,
          'EUR': 55.0,
          'GBP': 65.0,
        },
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(2000));
      // PDF documents start with %PDF header
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generatePdf works with empty suppliers list without crashing', () async {
      final pdfBytes = await SupplierConsolidatedStatementPdfService.generatePdf(
        suppliers: [],
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('ConsolidatedStatementPdfService.build produces valid landscape PDF bytes', () async {
      final rows = sampleSuppliers.map((s) => {
        'code': s.supplierCode,
        'name': s.name,
        'currency': s.currency,
        'balance': s.outstandingBalance.toStringAsFixed(2),
      }).toList();

      final pdfBytes = await ConsolidatedStatementPdfService.build(
        title: 'كشف حساب مجمع - الموردون',
        rows: rows,
        totalBalance: 150000.0,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(2000));
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });
  });
}
