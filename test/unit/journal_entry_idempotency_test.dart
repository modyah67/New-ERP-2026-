import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/lot_model.dart';
import 'package:accounting_system/data/models/stock_transfer_model.dart';

void main() {
  group('Journal Entry Universal Idempotency & Single Source of Truth Tests', () {
    test('LotReceiptModel preserves and respects journal_entry_id across updates', () {
      final json = {
        'id': 101,
        'lot_number': 'LOT-2026-001',
        'supplier_id': 'supp-uuid-1',
        'fruit_type': 'مانجو تومي',
        'is_confirmed': true,
        'journal_entry_id': 5001,
        'total_fruit_cost': 150000.0,
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'created_at': '2026-09-04T10:00:00Z',
      };

      final lot = LotReceiptModel.fromMap(json);

      expect(lot.id, '101');
      expect(lot.journalEntryId, 5001);
      expect(lot.isConfirmed, isTrue);

      // Verify that copyWith maintains idempotency by preserving the journal_entry_id
      final updatedLot = lot.copyWith(
        notes: 'Updated notes after verification',
      );

      expect(updatedLot.journalEntryId, 5001);
      expect(updatedLot.id, '101');

      // Verify that unconfirmed or newly initialized lot can have null journal_entry_id
      final draftJson = {
        'id': 102,
        'lot_number': 'LOT-2026-002',
        'supplier_id': 'supp-uuid-1',
        'fruit_type': 'مانجو عويس',
        'is_confirmed': false,
        'total_fruit_cost': 75000.0,
      };

      final draftLot = LotReceiptModel.fromMap(draftJson);
      expect(draftLot.journalEntryId, isNull);
      expect(draftLot.isConfirmed, isFalse);

      // Once linked via single source of truth, journalEntryId is populated
      final linkedDraft = draftLot.copyWith(journalEntryId: 5002);
      expect(linkedDraft.journalEntryId, 5002);
    });

    test('StockTransferModel enforces journal entry tracking idempotency', () {
      final transferMap = {
        'id': 77,
        'from_station_id': 1,
        'to_station_id': 2,
        'product_name': 'كرتون مانجو فائق',
        'quantity': 500.0,
        'journal_entry_id': 9001,
        'unit_cost': 40.0,
        'total_cost': 20000.0,
        'currency': 'EGP',
      };

      final transfer = StockTransferModel.fromMap(transferMap);
      expect(transfer.id, 77);
      expect(transfer.journalEntryId, 9001);

      // Verify that toInsertMap includes the established journal_entry_id
      final insertMap = transfer.toInsertMap();
      expect(insertMap['journal_entry_id'], 9001);

      // Re-invoking or updating with same or modified attributes does not erase journal reference
      final reTransfer = transfer.copyWith(quantity: 520.0);
      expect(reTransfer.journalEntryId, 9001);
    });

    test('Idempotency source_type and source_id composite key validation', () {
      final validSourceTypes = ['lot_receipt', 'stock_transfer', 'purchase', 'waste', 'sorting_sale'];

      for (final type in validSourceTypes) {
        expect(type.isNotEmpty, isTrue);
      }

      String makeSourceKey(String type, dynamic id) => '$type#$id';

      expect(makeSourceKey('lot_receipt', 101), 'lot_receipt#101');
      expect(makeSourceKey('stock_transfer', 77), 'stock_transfer#77');
      expect(makeSourceKey('purchase', 'INV-001'), 'purchase#INV-001');
    });
  });
}
