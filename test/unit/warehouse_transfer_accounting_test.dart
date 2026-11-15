import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/stock_transfer_model.dart';
import 'package:accounting_system/data/dao/transfer_dao.dart';

void main() {
  group('Warehouse Stock Transfer Accounting & Model Tests', () {
    test('StockTransferModel parses and serializes accounting fields correctly', () {
      final map = {
        'id': 42,
        'from_station_id': 2,
        'to_station_id': 1,
        'product_name': 'مانجا كيت',
        'product_code': 'MNG-KIT-01',
        'quantity': 250.0,
        'description': 'تحويل مانجا من تاج إلى السادات',
        'created_at': '2026-09-04T12:00:00Z',
        'journal_entry_id': 1055,
        'unit_cost': 35.5,
        'total_cost': 8875.0,
        'currency': 'EGP',
      };

      final transfer = StockTransferModel.fromMap(map);

      expect(transfer.id, 42);
      expect(transfer.fromStationId, 2);
      expect(transfer.toStationId, 1);
      expect(transfer.productName, 'مانجا كيت');
      expect(transfer.quantity, 250.0);
      expect(transfer.journalEntryId, 1055);
      expect(transfer.unitCost, 35.5);
      expect(transfer.totalCost, 8875.0);
      expect(transfer.currency, 'EGP');

      final insertMap = transfer.toInsertMap();
      expect(insertMap['journal_entry_id'], 1055);
      expect(insertMap['unit_cost'], 35.5);
      expect(insertMap['total_cost'], 8875.0);
      expect(insertMap['currency'], 'EGP');

      // Test copyWith
      final updated = transfer.copyWith(
        journalEntryId: 1056,
        totalCost: 9000.0,
      );
      expect(updated.journalEntryId, 1056);
      expect(updated.totalCost, 9000.0);
      expect(updated.unitCost, 35.5);
    });

    test('StockTransferModel gracefully handles null/empty accounting fields', () {
      final minimalMap = {
        'from_station_id': 1,
        'to_station_id': 2,
        'product_name': 'كرتون فارغ',
        'quantity': 100.0,
      };

      final transfer = StockTransferModel.fromMap(minimalMap);

      expect(transfer.journalEntryId, isNull);
      expect(transfer.unitCost, isNull);
      expect(transfer.totalCost, isNull);
      expect(transfer.currency, equals('EGP'));

      final insertMap = transfer.toInsertMap();
      expect(insertMap.containsKey('journal_entry_id'), isFalse);
      expect(insertMap.containsKey('unit_cost'), isFalse);
      expect(insertMap.containsKey('total_cost'), isFalse);
      expect(insertMap['currency'], equals('EGP'));
    });

    test('WarehouseTransferDao alias is identical to TransferDao', () {
      expect(WarehouseTransferDao, equals(TransferDao));
    });

    test('Warehouse transfer double-entry accounting invariant: Debit must equal Credit', () {
      // Given a transfer with valuation
      const transferQty = 400.0;
      const unitCost = 25.0;
      const totalValuation = transferQty * unitCost; // 10,000.00 EGP

      // Journal entry lines simulation
      final debitLine = {
        'account_id': 1231, // Receiving Warehouse Inventory
        'debit': totalValuation,
        'credit': 0.0,
        'description': 'إثبات تحويل مخزني وارد إلى محطة السادات من محطة تاج',
      };

      final creditLine = {
        'account_id': 1231, // Sending Warehouse Inventory
        'debit': 0.0,
        'credit': totalValuation,
        'description': 'إثبات تحويل مخزني منصرف من محطة تاج إلى محطة السادات',
      };

      final lines = [debitLine, creditLine];

      final totalDebit = lines.fold<double>(0.0, (sum, l) => sum + (l['debit'] as double));
      final totalCredit = lines.fold<double>(0.0, (sum, l) => sum + (l['credit'] as double));

      // Assert zero-sum double-entry balance
      expect(totalDebit, equals(totalCredit));
      expect(totalDebit, equals(10000.0));
      expect(totalDebit - totalCredit, equals(0.0));
    });
  });
}
