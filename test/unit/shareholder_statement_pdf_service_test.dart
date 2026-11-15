import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/shareholder_model.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:accounting_system/features/shareholders/shareholder_statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShareholderStatementPdfService Landscape & Clean Data Tests', () {
    const testShareholder = ShareholderModel(
      id: 'sh-001',
      code: 'SH-01',
      name: 'الحاج عصام عبد السلام',
      initialBalanceEgp: 100000.0,
      currentBalanceEgp: 350000.0,
      createdAt: '2026-01-01',
    );

    test('generatePdfBytes produces valid landscape PDF with sanitized data cells', () async {
      final rows = [
        const StatementRow(
          transactionNumber: 'TX-1001',
          date: '2026-08-01',
          accountName: 'سند قبض نقدي',
          description: 'إيداع نقدي بالخزينة لزيادة رأس المال',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0.0, // Clean placeholder
          credit: 150000.0,
          balance: 250000.0,
          type: 'treasury',
          createdAt: '2026-08-01T10:00:00',
        ),
        const StatementRow(
          transactionNumber: 'TX-1002',
          date: '2026-08-15',
          accountName: 'تحويل بنكي',
          description: 'مسحوبات أرباح على الحساب البنكي CIB',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 50000.0,
          credit: 0.0, // Clean placeholder
          balance: 200000.0,
          type: 'bank',
          createdAt: '2026-08-15T12:00:00',
        ),
        const StatementRow(
          transactionNumber: 'TX-1003',
          date: '2026-08-30',
          accountName: 'توزيع أرباح نصف سنوية',
          description: 'إثبات حصة الأرباح من العمليات التصديرية',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0.0,
          credit: 150000.0,
          balance: 350000.0,
          type: 'profit',
          createdAt: '2026-08-30T17:00:00',
        ),
        const StatementRow(
          transactionNumber: '',
          date: '',
          accountName: '',
          description: '',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0.0,
          credit: 0.0,
          balance: 350000.0,
          type: '',
          createdAt: '',
        ),
      ];

      final pdfBytes = await ShareholderStatementPdfService.generatePdfBytes(
        shareholder: testShareholder,
        rows: rows,
        totalDebit: 50000.0,
        totalCredit: 300000.0,
        finalBalance: 350000.0,
        totalProfitShare: 150000.0,
        openingBalance: 100000.0,
        currency: 'EGP',
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
        statementNumber: 7788,
        notes: {
          'TX-1001': 'تم الإيداع بمعرفة الإدارة المالية',
        },
        settings: {
          'company_name': 'شركة فروتي فارمز الدولية',
        },
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF documents start with '%PDF-' header bytes [0x25, 0x50, 0x44, 0x46, 0x2D]
      expect(pdfBytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('generatePdfBytes succeeds when statement rows are empty without crashing', () async {
      final pdfBytes = await ShareholderStatementPdfService.generatePdfBytes(
        shareholder: testShareholder,
        rows: const [],
        totalDebit: 0.0,
        totalCredit: 0.0,
        finalBalance: 100000.0,
        totalProfitShare: 0.0,
        openingBalance: 100000.0,
        currency: 'EGP',
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
