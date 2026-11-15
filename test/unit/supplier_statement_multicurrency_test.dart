import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:accounting_system/features/statements/supplier_statement_pdf_service.dart';
import 'package:accounting_system/core/statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StatementRow Multi-Currency Model Tests', () {
    test('EGP row is not foreign', () {
      const row = StatementRow(
        transactionNumber: 'TRX-101',
        date: '2026-11-01',
        accountName: 'توريد كراتين',
        description: 'شراء كراتين تعبئة محلي',
        piecesCount: 100,
        quantity: 100,
        unitPrice: 50.0,
        debit: 0.0,
        credit: 5000.0,
        balance: 5000.0,
        type: 'purchase',
        createdAt: '2026-11-01T10:00:00',
        currency: 'EGP',
      );

      expect(row.isForeignCurrency, isFalse);
      expect(row.foreignAmount, equals(0.0));
      expect(row.foreignDisplay, equals('—'));
      expect(row.foreignDisplayCompact, equals('-'));
    });

    test('USD foreign row formats amount and exchange rate correctly', () {
      const row = StatementRow(
        transactionNumber: 'LOT-99',
        date: '2026-11-02',
        accountName: 'شراء محصول مانجو',
        description: 'شراء محصول مانجو بالدولار',
        piecesCount: 500,
        quantity: 1000,
        unitPrice: 1.5,
        debit: 0.0,
        credit: 75000.0, // 1500 USD * 50 rate = 75000 EGP
        balance: 75000.0,
        type: 'lot_receipt',
        createdAt: '2026-11-02T11:00:00',
        currency: 'EGP',
        foreignCredit: 1500.0,
        foreignCurrency: 'USD',
        exchangeRate: 50.0,
      );

      expect(row.isForeignCurrency, isTrue);
      expect(row.foreignAmount, equals(1500.0));
      expect(row.foreignDisplay, contains('1500 USD'));
      expect(row.foreignDisplay, contains('50'));
      expect(row.foreignDisplayCompact, contains('1500 USD @ 50'));
      expect(row.credit, equals(75000.0)); // Unified base currency amount in EGP
    });

    test('Foreign debit row (payment in USD) formats correctly', () {
      const row = StatementRow(
        transactionNumber: 'PAY-USD-1',
        date: '2026-11-03',
        accountName: 'سداد نقدي للمورد',
        description: 'سداد دفعة من الحساب بالدولار',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 25000.0, // 500 USD * 50 = 25000 EGP
        credit: 0.0,
        balance: 50000.0,
        type: 'payment',
        createdAt: '2026-11-03T12:00:00',
        currency: 'EGP',
        foreignDebit: 500.0,
        foreignCurrency: 'USD',
        exchangeRate: 50.0,
      );

      expect(row.isForeignCurrency, isTrue);
      expect(row.foreignAmount, equals(500.0));
      expect(row.debit, equals(25000.0));
      expect(row.foreignDisplayCompact, contains('500 USD @ 50'));
    });
  });

  group('Supplier Statement Multi-Currency PDF & Excel Generation Tests', () {
    const testSupplier = SupplierModel(
      id: 'sup-multi-1',
      supplierCode: 'SUP-USD-01',
      name: 'مورد دولي متعدد العملات',
      currency: 'MULTI',
      initialBalance: 0,
      outstandingBalance: 50000.0,
      supplierType: 'crop',
    );

    final rows = [
      const StatementRow(
        transactionNumber: 'LOT-1',
        date: '2026-11-01',
        accountName: 'شراء محصول',
        description: 'شحنة فاكهة بالدولار',
        piecesCount: 100,
        quantity: 200,
        unitPrice: 10.0,
        debit: 0.0,
        credit: 100000.0, // $2,000 USD * 50 = 100,000 EGP
        balance: 100000.0,
        type: 'lot_receipt',
        createdAt: '2026-11-01T10:00:00',
        currency: 'EGP',
        foreignCredit: 2000.0,
        foreignCurrency: 'USD',
        exchangeRate: 50.0,
      ),
      const StatementRow(
        transactionNumber: 'INV-EGP-1',
        date: '2026-11-02',
        accountName: 'توريد كراتين',
        description: 'توريد كراتين محلي بالجنيه',
        piecesCount: 500,
        quantity: 500,
        unitPrice: 30.0,
        debit: 0.0,
        credit: 15000.0, // 15,000 EGP
        balance: 115000.0,
        type: 'purchase',
        createdAt: '2026-11-02T11:00:00',
        currency: 'EGP',
      ),
      const StatementRow(
        transactionNumber: 'PAY-USD-1',
        date: '2026-11-03',
        accountName: 'سند صرف للمورد',
        description: 'دفعة بنكية بالدولار',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 50000.0, // $1,000 USD * 50 = 50,000 EGP
        credit: 0.0,
        balance: 65000.0,
        type: 'payment',
        createdAt: '2026-11-03T12:00:00',
        currency: 'EGP',
        foreignDebit: 1000.0,
        foreignCurrency: 'USD',
        exchangeRate: 50.0,
      ),
    ];

    test('SupplierStatementPdfService generates PDF with 9-column multicurrency layout', () async {
      final bytes = await SupplierStatementPdfService.generatePdfBytes(
        supplier: testSupplier,
        rows: rows,
        totalDebit: 50000.0,
        totalCredit: 115000.0,
        finalBalance: 65000.0,
        fromDate: DateTime(2026, 11, 1),
        toDate: DateTime(2026, 11, 30),
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // Valid PDF magic bytes
      expect(bytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });

    test('StatementPdfService generates PDF with foreign currency column', () async {
      final bytes = await StatementPdfService.build(
        title: 'كشف حساب الموردين',
        vendorName: testSupplier.name,
        vendorCode: testSupplier.supplierCode,
        currency: 'EGP',
        rows: rows,
        totalDebit: 50000.0,
        totalCredit: 115000.0,
        finalBalance: 65000.0,
        statementNumber: 555,
        locale: 'ar',
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.take(5).toList(), equals([0x25, 0x50, 0x44, 0x46, 0x2D]));
    });
  });
}
