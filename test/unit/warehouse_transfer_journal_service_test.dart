import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/services/warehouse_transfer_journal_service.dart';

void main() {
  group('WarehouseTransferJournalService Tests', () {
    test('Extracts transfer context from stock_transfer entry notes and descriptions', () {
      final entry = {
        'sourceType': 'stock_transfer',
        'notes': 'تحويل مخزني من تاج إلى السادات - مانجو',
      };
      final debitLine = {
        'description': 'إثبات تحويل مخزني وارد إلى السادات من تاج (مانجو - 1000)',
      };
      final creditLine = {
        'description': 'إثبات تحويل مخزني منصرف من تاج إلى السادات (مانجو - 1000)',
      };

      final debitCtx = WarehouseTransferJournalService.extractTransferContext(
        entry: entry,
        line: debitLine,
      );
      expect(debitCtx.isTransfer, isTrue);
      expect(debitCtx.fromWarehouse, equals('تاج'));
      expect(debitCtx.toWarehouse, equals('السادات'));
      expect(debitCtx.receivingWarehouse, equals('السادات'));
      expect(debitCtx.sendingWarehouse, equals('تاج'));
      expect(debitCtx.productName, equals('مانجو'));
      expect(debitCtx.quantity, equals(1000.0));

      // Test debit formatted name
      final debitFormatted = WarehouseTransferJournalService.formatTransferAccountName(
        baseAccountName: 'مخزون المحاصيل الزراعية',
        isDebit: true,
        context: debitCtx,
        includePrefix: true,
      );
      expect(debitFormatted, equals('من حـ/ مخزون المحاصيل - مخزن السادات'));

      // Test credit formatted name
      final creditCtx = WarehouseTransferJournalService.extractTransferContext(
        entry: entry,
        line: creditLine,
      );
      final creditFormatted = WarehouseTransferJournalService.formatTransferAccountName(
        baseAccountName: 'مخزون المحاصيل الزراعية',
        isDebit: false,
        context: creditCtx,
        includePrefix: true,
      );
      expect(creditFormatted, equals('إلى حـ/ مخزون المحاصيل - مخزن تاج'));
    });

    test('generateTransferJournalLines produces balanced double-entry with explicit warehouse names', () {
      final lines = WarehouseTransferJournalService.generateTransferJournalLines(
        transferId: 101,
        fromWarehouse: 'تاج',
        toWarehouse: 'السادات',
        productName: 'عنب كرمسون',
        quantity: 500,
        totalCost: 12500,
        currency: 'USD',
        exchangeRate: 50.0,
      );

      expect(lines.length, equals(2));

      // Debit line
      final debit = lines[0];
      expect(debit['account_name'], equals('مخزون المحاصيل - مخزن السادات'));
      expect(debit['debit'], equals(12500.0));
      expect(debit['credit'], equals(0.0));
      expect(debit['amount_in_base_currency'], equals(625000.0));
      expect(debit['warehouse_name'], equals('السادات'));
      expect(debit['description'], contains('إلى مخزن السادات'));

      // Credit line
      final credit = lines[1];
      expect(credit['account_name'], equals('مخزون المحاصيل - مخزن تاج'));
      expect(credit['debit'], equals(0.0));
      expect(credit['credit'], equals(12500.0));
      expect(credit['amount_in_base_currency'], equals(625000.0));
      expect(credit['warehouse_name'], equals('تاج'));
      expect(credit['description'], contains('من مخزن تاج'));
    });
  });
}
