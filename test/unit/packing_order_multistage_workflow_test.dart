import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/packing_order_model.dart';

void main() {
  group('Packing Order Multi-Stage Workflow Model Tests', () {
    test('1. Default draft packing order has stage index 0 and no stages confirmed', () {
      final order = PackingOrderModel(
        id: '101',
        orderNumber: 'PO-2026-001',
        lotId: '1',
        grade: 'Grade A',
        status: 'draft',
      );

      expect(order.isDraft, isTrue);
      expect(order.isCropsConfirmed, isFalse);
      expect(order.isPackagingConfirmed, isFalse);
      expect(order.isCostsConfirmed, isFalse);
      expect(order.isFinalApproved, isFalse);
      expect(order.currentStageIndex, equals(0));
    });

    test('2. Stage 1 (crops_confirmed) sets isCropsConfirmed and currentStageIndex = 1', () {
      final now = DateTime.now();
      final order = PackingOrderModel(
        id: '102',
        orderNumber: 'PO-2026-002',
        lotId: '1',
        grade: 'Grade A',
        status: 'crops_confirmed',
        cropsConfirmedAt: now,
        cropsJournalEntryId: 'JE-CROP-102',
      );

      expect(order.isDraft, isFalse);
      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isFalse);
      expect(order.isCostsConfirmed, isFalse);
      expect(order.isFinalApproved, isFalse);
      expect(order.currentStageIndex, equals(1));
      expect(order.cropsJournalEntryId, equals('JE-CROP-102'));
    });

    test('3. Stage 2 (packaging_confirmed) sets isPackagingConfirmed and currentStageIndex = 2', () {
      final now = DateTime.now();
      final order = PackingOrderModel(
        id: '103',
        orderNumber: 'PO-2026-003',
        lotId: '1',
        grade: 'Grade A',
        status: 'packaging_confirmed',
        cropsConfirmedAt: now.subtract(const Duration(hours: 2)),
        cropsJournalEntryId: 'JE-CROP-103',
        packagingConfirmedAt: now,
        packagingJournalEntryId: 'JE-PKG-103',
      );

      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isTrue);
      expect(order.isCostsConfirmed, isFalse);
      expect(order.isFinalApproved, isFalse);
      expect(order.currentStageIndex, equals(2));
      expect(order.packagingJournalEntryId, equals('JE-PKG-103'));
    });

    test('4. Stage 3 (costs_confirmed) sets isCostsConfirmed and currentStageIndex = 3', () {
      final now = DateTime.now();
      final order = PackingOrderModel(
        id: '104',
        orderNumber: 'PO-2026-004',
        lotId: '1',
        grade: 'Grade A',
        status: 'costs_confirmed',
        cropsConfirmedAt: now.subtract(const Duration(hours: 3)),
        packagingConfirmedAt: now.subtract(const Duration(hours: 1)),
        costsConfirmedAt: now,
        costsJournalEntryId: 'JE-COST-104',
      );

      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isTrue);
      expect(order.isCostsConfirmed, isTrue);
      expect(order.isFinalApproved, isFalse);
      expect(order.currentStageIndex, equals(3));
      expect(order.costsJournalEntryId, equals('JE-COST-104'));
    });

    test('5. Stage 4 (final_approved) sets isFinalApproved and currentStageIndex = 4', () {
      final now = DateTime.now();
      final order = PackingOrderModel(
        id: '105',
        orderNumber: 'PO-2026-005',
        lotId: '1',
        grade: 'Grade A',
        status: 'final_approved',
        cropsConfirmedAt: now.subtract(const Duration(hours: 4)),
        packagingConfirmedAt: now.subtract(const Duration(hours: 2)),
        costsConfirmedAt: now.subtract(const Duration(hours: 1)),
        finalApprovedAt: now,
        journalEntryId: 'JE-FINAL-105',
      );

      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isTrue);
      expect(order.isCostsConfirmed, isTrue);
      expect(order.isFinalApproved, isTrue);
      expect(order.currentStageIndex, equals(4));
    });

    test('6. Backward compatibility: Old completed orders automatically treat all stages as confirmed', () {
      final oldCompletedOrder = PackingOrderModel(
        id: '99',
        orderNumber: 'PO-OLD-099',
        lotId: '1',
        grade: 'Grade A',
        status: 'completed',
        journalEntryId: 'JE-OLD-999',
      );

      expect(oldCompletedOrder.isCropsConfirmed, isTrue);
      expect(oldCompletedOrder.isPackagingConfirmed, isTrue);
      expect(oldCompletedOrder.isCostsConfirmed, isTrue);
      expect(oldCompletedOrder.isFinalApproved, isTrue);
      expect(oldCompletedOrder.currentStageIndex, equals(4));
    });

    test('7. Dual-read from DB columns directly', () {
      final map = {
        'id': 200,
        'order_number': 'PO-200',
        'lot_id': 1,
        'grade': 'Grade A',
        'status': 'crops_confirmed',
        'crops_confirmed_at': '2026-09-29T10:00:00.000Z',
        'crops_journal_entry_id': 'JE-200-1',
        'packaging_confirmed_at': null,
        'packaging_journal_entry_id': null,
        'costs_confirmed_at': null,
        'costs_journal_entry_id': null,
        'final_approved_at': null,
      };

      final order = PackingOrderModel.fromMap(map);
      expect(order.cropsConfirmedAt, isNotNull);
      expect(order.cropsJournalEntryId, equals('JE-200-1'));
      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isFalse);
    });

    test('8. Dual-read fallback from notes[\'workflow_stages\'] when DB columns are absent', () {
      final notesData = {
        'workflow_stages': {
          'crops_confirmed_at': '2026-09-29T11:00:00.000Z',
          'crops_journal_entry_id': 'JE-FALLBACK-CROP',
          'packaging_confirmed_at': '2026-09-29T12:00:00.000Z',
          'packaging_journal_entry_id': 'JE-FALLBACK-PKG',
        },
      };

      final map = {
        'id': 201,
        'order_number': 'PO-201',
        'lot_id': 1,
        'grade': 'Grade A',
        'status': 'packaging_confirmed',
        'notes': jsonEncode(notesData),
      };

      final order = PackingOrderModel.fromMap(map);
      expect(order.cropsConfirmedAt, isNotNull);
      expect(order.cropsJournalEntryId, equals('JE-FALLBACK-CROP'));
      expect(order.packagingConfirmedAt, isNotNull);
      expect(order.packagingJournalEntryId, equals('JE-FALLBACK-PKG'));
      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isTrue);
      expect(order.isCostsConfirmed, isFalse);
    });

    test('9. Serialization toMap preserves stage columns', () {
      final now = DateTime.utc(2026, 9, 29, 13, 0);
      final order = PackingOrderModel(
        id: '202',
        orderNumber: 'PO-202',
        lotId: '1',
        grade: 'Grade A',
        status: 'costs_confirmed',
        cropsConfirmedAt: now,
        cropsJournalEntryId: 'JE-C1',
        packagingConfirmedAt: now,
        packagingJournalEntryId: 'JE-P1',
        costsConfirmedAt: now,
        costsJournalEntryId: 'JE-X1',
      );

      final map = order.toMap();
      expect(map['status'], equals('costs_confirmed'));
      expect(map['crops_confirmed_at'], isNotNull);
      expect(map['crops_journal_entry_id'], equals('JE-C1'));
      expect(map['packaging_confirmed_at'], isNotNull);
      expect(map['packaging_journal_entry_id'], equals('JE-P1'));
      expect(map['costs_confirmed_at'], isNotNull);
      expect(map['costs_journal_entry_id'], equals('JE-X1'));
    });

    test('10. copyWith correctly updates individual stage timestamps and journal entries', () {
      final now = DateTime.now();
      var order = PackingOrderModel(
        id: '203',
        orderNumber: 'PO-203',
        lotId: '1',
        grade: 'Grade A',
        status: 'draft',
      );

      order = order.copyWith(
        status: 'crops_confirmed',
        cropsConfirmedAt: now,
        cropsJournalEntryId: 'JE-C203',
      );
      expect(order.isCropsConfirmed, isTrue);
      expect(order.isPackagingConfirmed, isFalse);

      order = order.copyWith(
        status: 'packaging_confirmed',
        packagingConfirmedAt: now,
        packagingJournalEntryId: 'JE-P203',
      );
      expect(order.isPackagingConfirmed, isTrue);
      expect(order.isCostsConfirmed, isFalse);

      order = order.copyWith(
        status: 'costs_confirmed',
        costsConfirmedAt: now,
        costsJournalEntryId: 'JE-X203',
      );
      expect(order.isCostsConfirmed, isTrue);
      expect(order.isFinalApproved, isFalse);

      order = order.copyWith(
        status: 'final_approved',
        finalApprovedAt: now,
      );
      expect(order.isFinalApproved, isTrue);
      expect(order.currentStageIndex, equals(4));
    });
  });
}
