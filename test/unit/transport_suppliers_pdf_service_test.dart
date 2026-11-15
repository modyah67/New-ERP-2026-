import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/transport_supplier_model.dart';
import 'package:accounting_system/features/transport_suppliers/transport_suppliers_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransportSuppliersPdfService Landscape & KPI Tests', () {
    final sampleTransportSuppliers = [
      const TransportSupplierModel(
        id: 1,
        code: 'TRP-001',
        name: 'أسطول النيل للنقل الثقيل',
        phone: '01012345678',
        truckBalance: 14,
        balance: 85000.0,
        initialBalance: 20000.0,
        initialTruckBalance: 2,
        notes: 'مورد معتمد لنقل الحاصلات الزراعية',
        createdAt: '2026-01-01',
      ),
      const TransportSupplierModel(
        id: 2,
        code: 'TRP-002',
        name: 'شركة الصفا للشحن والتبريد',
        phone: '01123456789',
        truckBalance: 8,
        balance: -15000.0,
        initialBalance: 0.0,
        initialTruckBalance: 0,
        notes: 'سداد دفعات مقدمة',
        createdAt: '2026-01-01',
      ),
      const TransportSupplierModel(
        id: 3,
        code: 'TRP-003',
        name: 'مؤسسة الدلتا لخدمات التريلات',
        phone: '01234567890',
        truckBalance: 22,
        balance: 142500.0,
        initialBalance: 50000.0,
        initialTruckBalance: 5,
        notes: 'نقل بري سريع إلى موانئ التصدير',
        createdAt: '2026-01-01',
      ),
      const TransportSupplierModel(
        id: 4,
        code: 'TRP-004',
        name: 'الحاج محمود للنقل الداخلي',
        phone: '01511223344',
        truckBalance: 0,
        balance: 0.0,
        initialBalance: 0.0,
        initialTruckBalance: 0,
        createdAt: '2026-01-01',
      ),
    ];

    test('generatePdf compiles and returns non-empty landscape PDF bytes for transport suppliers', () async {
      final pdfBytes = await TransportSuppliersPdfService.generatePdf(
        suppliers: sampleTransportSuppliers,
        companyName: 'مزارع فروتي فارمز',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(2000));
      // PDF documents start with %PDF header
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generatePdf works gracefully with empty transport suppliers list without crashing', () async {
      final pdfBytes = await TransportSuppliersPdfService.generatePdf(
        suppliers: [],
        companyName: 'مزارع فروتي فارمز',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      final header = String.fromCharCodes(pdfBytes.take(4));
      expect(header, equals('%PDF'));
    });
  });
}
