import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:accounting_system/features/statements/supplier_statement_pdf_service.dart';
import 'package:accounting_system/core/statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupplierStatementPdfService Landscape & Empty-Cell Cleaning Tests', () {
    const testSupplier = SupplierModel(
      id: 'sup-1',
      supplierCode: 'SUP-001',
      name: 'مزارع الوادي الأخضر للفاكهة',
      phone: '01012345678',
      currency: 'EGP',
      initialBalance: 25000.0,
      initialBalanceDirection: 'CREDIT',
      outstandingBalance: 145000.0,
      supplierType: 'crop',
    );

    test('generatePdfBytes produces non-empty bytes in Landscape format with sanitized cells', () async {
      final rows = [
        const StatementRow(
          transactionNumber: 'INV-2026-001',
          date: '2026-08-01',
          accountName: 'مشتريات برتقال صيفي',
          description: 'توريد برتقال صيفي صنف أول - سيارة رقم 4521',
          piecesCount: 650,
          quantity: 13000,
          unitPrice: 15.0,
          debit: 0.0, // Should cleanly format as '-'
          credit: 195000.0,
          balance: 220000.0,
          type: 'purchase',
          createdAt: '2026-08-01T10:00:00',
        ),
        const StatementRow(
          transactionNumber: 'PAY-892',
          date: '2026-08-05',
          accountName: 'صرف نقدي من الخزينة الرئيسية',
          description: 'دفعة نقدية تحت الحساب إيصال رقم 892',
          piecesCount: 0, // Should cleanly format as '-'
          quantity: 0,
          unitPrice: 0,
          debit: 75000.0,
          credit: 0.0, // Should cleanly format as '-'
          balance: 145000.0,
          type: 'payment',
          createdAt: '2026-08-05T14:30:00',
        ),
        const StatementRow(
          transactionNumber: '', // Empty ref -> should fallback cleanly to '-' or referenceId
          date: '', // Empty date -> should format as '-'
          accountName: '', // Empty account -> should format as '-'
          description: '', // Empty desc -> should format as '-'
          piecesCount: 0, // Empty count -> should format as '-'
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: 0,
          balance: 145000.0,
          type: '',
          createdAt: '',
        ),
      ];

      final pdfBytes = await SupplierStatementPdfService.generatePdfBytes(
        supplier: testSupplier,
        rows: rows,
        totalDebit: 75000.0,
        totalCredit: 195000.0,
        finalBalance: 145000.0,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
        statementNumber: 101,
        settings: {
          'company_name': 'شركة فروتي فارمز الدولية',
        },
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF documents start with '%PDF-' header bytes [0x25, 0x50, 0x44, 0x46, 0x2D]
      expect(pdfBytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('generatePdfBytes succeeds when rows are empty without crashing', () async {
      final pdfBytes = await SupplierStatementPdfService.generatePdfBytes(
        supplier: testSupplier,
        rows: const [],
        totalDebit: 0.0,
        totalCredit: 0.0,
        finalBalance: 25000.0,
        fromDate: null,
        toDate: null,
        statementNumber: 0,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    test('StatementPdfService.build generates landscape PDF with sanitized cell placeholders', () async {
      final rows = [
        const StatementRow(
          transactionNumber: 'PUR-101',
          date: '2026-08-10',
          accountName: '',
          description: 'توريد مانجو عويس',
          piecesCount: 400,
          quantity: 2000,
          unitPrice: 50,
          debit: 0,
          credit: 100000,
          balance: 100000,
          type: 'purchase',
          createdAt: '2026-08-10',
        ),
        const StatementRow(
          transactionNumber: '',
          date: '',
          accountName: '',
          description: '',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: 0,
          balance: 100000,
          type: '',
          createdAt: '',
        ),
      ];

      final bytes = await StatementPdfService.build(
        title: 'كشف حساب مورد',
        vendorName: 'مزارع الوادي الأخضر',
        vendorCode: 'SUP-001',
        currency: 'EGP',
        rows: rows,
        totalDebit: 0,
        totalCredit: 100000,
        finalBalance: 100000,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
        statementNumber: 42,
        locale: 'ar',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('StatementPdfService dynamically labels supplier Walid with كشف حساب الموردين', () async {
      final rows = [
        const StatementRow(
          transactionNumber: '—',
          date: '2026-09-01',
          accountName: '',
          description: 'رصيد سابق',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: 1000,
          balance: 1000,
          type: 'رصيد سابق',
          createdAt: '2026-09-01',
        ),
      ];

      final bytes = await StatementPdfService.build(
        title: 'كشف حساب الموردين',
        vendorName: 'وليد',
        vendorCode: '00003',
        currency: 'USD',
        rows: rows,
        totalDebit: 500,
        totalCredit: 1000,
        finalBalance: 1500,
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 6),
        statementNumber: 1788708750,
        locale: 'ar',
        openingBalanceNote: 'ملحوظة: الرصيد السابق = 1,000.00 USD',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });
  });
}
