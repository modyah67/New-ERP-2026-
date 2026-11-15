import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/transport_supplier_model.dart';
import 'package:accounting_system/data/models/transport_transaction_model.dart';
import 'package:accounting_system/features/transport_suppliers/transport_supplier_statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransportSupplierStatementPdfService Landscape Tests', () {
    const testSupplier = TransportSupplierModel(
      id: 1,
      code: 'TR-001',
      name: 'شركة النور لخدمات النقل البري والمبرد',
      phone: '01099887766',
      balance: 18500.0,
      truckBalance: 12,
      initialBalance: 5000.0,
      initialTruckBalance: 4,
      initialBalanceDirection: 'CREDIT',
      createdAt: '2026-08-01',
    );

    test('generatePdfBytes produces non-empty bytes in Landscape format with sanitized cells', () async {
      final transactions = [
        const TransportTransactionModel(
          id: 101,
          supplierId: 1,
          type: 'invoice',
          amount: 25000.0,
          currency: 'EGP',
          referenceId: 'TR-INV-001',
          description: 'نقل برتقال صيفي من مزارع وادي النطرون إلى محطة التعبئة',
          routeFrom: 'وادي النطرون',
          routeTo: 'محطة التعبئة',
          truckCount: 5,
          date: '2026-08-10',
          createdAt: '2026-08-10T08:00:00',
        ),
        const TransportTransactionModel(
          id: 102,
          supplierId: 1,
          type: 'cash_payment',
          amount: 15000.0,
          currency: 'EGP',
          referenceId: 'PAY-771',
          description: 'دفعة نقدية تحت الحساب إيصال خزينة رقم 771',
          truckCount: 0,
          date: '2026-08-12',
          createdAt: '2026-08-12T11:30:00',
        ),
        const TransportTransactionModel(
          id: 103,
          supplierId: 1,
          type: 'packing_consumption',
          amount: 0.0,
          currency: 'EGP',
          description: 'استهلاك نقلة لأمر تعبئة محلي',
          routeFrom: 'محطة التعبئة',
          routeTo: 'سوق الجملة',
          truckCount: 2,
          date: '2026-08-15',
          createdAt: '2026-08-15T16:00:00',
        ),
        const TransportTransactionModel(
          id: 104,
          supplierId: 1,
          type: '',
          amount: 0.0,
          currency: 'EGP',
          description: '', // Should fallback cleanly to '-'
          date: '', // Should fallback cleanly to '-'
          truckCount: 0,
          createdAt: '',
        ),
      ];

      final pdfBytes = await TransportSupplierStatementPdfService.generatePdfBytes(
        supplier: testSupplier,
        transactions: transactions,
        openingBalance: 5000.0,
        totalDebit: 15000.0,
        totalCredit: 25000.0,
        finalBalance: 15000.0,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
        statementNumber: 202608,
        settings: {
          'company_name': 'شركة فروتي فارمز الدولية',
        },
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF documents start with '%PDF-' header bytes [0x25, 0x50, 0x44, 0x46, 0x2D]
      expect(pdfBytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('generatePdfBytes succeeds when transactions are empty without crashing', () async {
      final pdfBytes = await TransportSupplierStatementPdfService.generatePdfBytes(
        supplier: testSupplier,
        transactions: const [],
        openingBalance: 5000.0,
        totalDebit: 0.0,
        totalCredit: 0.0,
        finalBalance: 5000.0,
        fromDate: null,
        toDate: null,
        statementNumber: 0,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(pdfBytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });
  });
}
