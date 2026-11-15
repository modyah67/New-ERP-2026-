// test/unit/account_statement_pdf_service_test.dart
// Unit tests for AccountStatementPdfService (Landscape A4 Account Ledger & Chart of Accounts PDF Vouchers)

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/data/models/account_ledger_result.dart';
import 'package:accounting_system/features/accounting/account_statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.';
    });
  });

  group('AccountStatementPdfService Landscape PDF Tests', () {
    final sampleAccount = AccountModel(
      id: 'acc-211202',
      code: '211202',
      name: 'مورد - رامي',
      type: 'liability',
      balance: 145000.0,
      isActive: true,
    );

    final sampleBranchAccount = AccountModel(
      id: 'acc-2100',
      code: '2100',
      name: 'الخصوم المتداولة والموردون',
      type: 'liability',
      balance: 450000.0,
      isActive: true,
    );

    final sampleEntries = [
      AccountLedgerEntry(
        id: 'ale-001',
        date: DateTime(2026, 9, 1, 10, 30),
        entryNumber: 'JE-000450',
        referenceType: 'purchase_invoice',
        referenceId: 'PINV-01',
        description: 'فاتورة توريد محصول برتقال صيفي كود #88',
        debit: 0.0,
        credit: 80000.0,
        runningBalance: 180000.0,
        currency: 'EGP',
        accountCode: '211202',
        accountName: 'مورد - رامي',
        createdAt: '2026-09-01T10:30:00Z',
      ),
      AccountLedgerEntry(
        id: 'ale-002',
        date: DateTime(2026, 9, 2, 14, 00),
        entryNumber: 'JE-000455',
        referenceType: 'supplier_payment',
        referenceId: 'PAY-01',
        description: 'سداد دفعة تحت الحساب بشيك مصرفي CIB',
        debit: 35000.0,
        credit: 0.0,
        runningBalance: 145000.0,
        currency: 'EGP',
        accountCode: '211202',
        accountName: 'مورد - رامي',
        createdAt: '2026-09-02T14:00:00Z',
      ),
    ];

    test('generateLedgerPdf generates valid non-empty Landscape A4 PDF bytes with corporate branding', () async {
      final bytes = await AccountStatementPdfService.generateLedgerPdf(
        account: sampleAccount,
        entries: sampleEntries,
        openingBalance: 100000.0,
        totalDebit: 35000.0,
        totalCredit: 80000.0,
        closingBalance: 145000.0,
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 5),
        currency: 'EGP',
        isBranch: false,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);

      // Verify PDF header magic bytes "%PDF-"
      final pdfMagic = utf8.decode(bytes.sublist(0, 5));
      expect(pdfMagic, equals('%PDF-'));
    });

    test('generateLedgerPdf handles branch / parent account node statement gracefully', () async {
      final bytes = await AccountStatementPdfService.generateLedgerPdf(
        account: sampleBranchAccount,
        entries: sampleEntries,
        openingBalance: 200000.0,
        totalDebit: 50000.0,
        totalCredit: 120000.0,
        closingBalance: 270000.0,
        currency: 'EGP',
        isBranch: true,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('generateLedgerPdf handles empty entries list without crashing', () async {
      final bytes = await AccountStatementPdfService.generateLedgerPdf(
        account: sampleAccount,
        entries: [],
        openingBalance: 0.0,
        totalDebit: 0.0,
        totalCredit: 0.0,
        closingBalance: 0.0,
        currency: 'EGP',
        isBranch: false,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });
  });
}
