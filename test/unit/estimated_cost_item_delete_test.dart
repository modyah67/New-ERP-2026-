import 'dart:convert';
import 'package:accounting_system/core/widgets/estimated_cost_delete_helper.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/models/supplier_expected_cost_item_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Estimated Cost Item Delete Eligibility Guards', () {
    test('allows deletion exclusively for unsettled estimated items', () {
      const estimatedItem = SupplierExpectedCostItemModel(
        costItemId: 101,
        packingOrderId: 50,
        orderNumber: '50',
        orderStatus: 'costs_confirmed',
        itemName: 'تبريد محطة',
        category: 'station',
        reportCategoryName: 'محطات',
        costStatus: 'expected',
        expectedAmount: 2500.0,
        actualAmount: null,
        reconciledAt: null,
        varianceJournalEntryId: null,
        isLocked: false,
      );

      expect(
        SupplierDao.canDeleteExpectedCostItemModel(estimatedItem),
        isTrue,
      );
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 102,
          'cost_status': 'expected',
          'actual_amount': null,
          'reconciled_at': null,
          'variance_journal_entry_id': null,
          'is_locked': false,
        }),
        isTrue,
      );
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 103,
          'cost_status': 'pending',
          'actual_amount': 0,
          'reconciled_at': null,
          'variance_journal_entry_id': null,
          'is_locked': null,
        }),
        isTrue,
      );
    });

    test('blocks deletion for items with actual value, settlement status, journal link, or lock', () {
      // 1. Has actual_amount > 0 even without lock/status update
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 201,
          'cost_status': 'expected',
          'actual_amount': 1200.0,
          'reconciled_at': null,
          'variance_journal_entry_id': null,
          'is_locked': false,
        }),
        isFalse,
      );

      // 2. Settled status ('actual', 'settled', 'locked')
      for (final status in ['actual', 'settled', 'locked', 'ACTUAL ']) {
        expect(
          SupplierDao.canDeleteEstimatedCostItemMap({
            'id': 202,
            'cost_status': status,
            'actual_amount': null,
            'is_locked': false,
          }),
          isFalse,
          reason: 'Status $status must forbid deletion',
        );
      }

      // 3. Reconciled timestamp exists
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 203,
          'cost_status': 'expected',
          'reconciled_at': '2026-11-10T12:00:00Z',
          'is_locked': false,
        }),
        isFalse,
      );

      // 4. Posted journal entry exists
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 204,
          'cost_status': 'expected',
          'variance_journal_entry_id': 987,
          'is_locked': false,
        }),
        isFalse,
      );

      // 5. Explicitly locked
      expect(
        SupplierDao.canDeleteExpectedCostItemModel(
          const SupplierExpectedCostItemModel(
            costItemId: 205,
            packingOrderId: 50,
            orderNumber: '50',
            orderStatus: 'final_approved',
            itemName: 'مصاريف إدارية',
            category: 'admin',
            reportCategoryName: 'مصاريف إدارية',
            costStatus: 'actual',
            expectedAmount: 1000.0,
            actualAmount: 1100.0,
            isLocked: true,
          ),
        ),
        isFalse,
      );

      // 6. Soft-deleted or missing id
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 206,
          'cost_status': 'expected',
          'deleted_at': '2026-11-10T12:00:00Z',
        }),
        isFalse,
      );
      expect(
        SupplierDao.canDeleteEstimatedCostItemMap({
          'id': 0,
          'cost_status': 'expected',
        }),
        isFalse,
      );
    });
  });

  group('Order Notes Cost Items Sync on Deletion', () {
    test('removes deleted cost item by id or item_uuid while preserving remaining order notes', () {
      final rawNotes = jsonEncode({
        'workflow_stages': {'costs': {'confirmed_at': '2026-11-10'}},
        'cost_items': [
          {'id': 11, 'item_uuid': 'u-11', 'name': 'بند تقديري محذوف'},
          {'id': 12, 'item_uuid': 'u-12', 'name': 'بند باقي'},
        ],
      });

      final updated = SupplierDao.removeDeletedCostItemFromOrderNotes(
        rawNotes,
        costItemId: 11,
        itemUuid: 'u-11',
      );

      expect(updated, isNotNull);
      final decoded = jsonDecode(updated!) as Map<String, dynamic>;
      expect((decoded['cost_items'] as List).length, 1);
      expect((decoded['cost_items'] as List).first['id'], 12);
      expect(decoded['workflow_stages'], isNotNull);

      // Deleting non-existent item returns null (no-op)
      expect(
        SupplierDao.removeDeletedCostItemFromOrderNotes(
          updated,
          costItemId: 999,
        ),
        isNull,
      );
    });
  });

  group('Estimated Cost Delete UI Helper Widgets', () {
    testWidgets('shows delete icon, opens confirmation dialog with exact Arabic prompt, and returns choice',
        (tester) async {
      bool? dialogOutcome;
      int deleteClicks = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => EstimatedCostDeleteButton(
                isDeleting: false,
                onPressed: () async {
                  deleteClicks++;
                  dialogOutcome = await showDeleteEstimatedCostItemDialog(
                    context,
                    itemName: 'عمولة محطة',
                    orderNumber: '1045',
                    estimatedAmount: 3500.0,
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(deleteClicks, 1);
      expect(
        find.text('هل أنت متأكد من حذف هذا البند التقديري؟'),
        findsOneWidget,
      );
      expect(find.textContaining('عمولة محطة'), findsOneWidget);
      expect(find.textContaining('#1045'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('تأكيد الحذف'));
      await tester.pumpAndSettle();
      expect(dialogOutcome, isTrue);

      // Re-open and cancel
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(dialogOutcome, isFalse);
    });

    testWidgets('shows loading indicator and blocks taps while deleting',
        (tester) async {
      int clicks = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EstimatedCostDeleteButton(
              isDeleting: true,
              onPressed: () => clicks++,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      await tester.tap(find.byType(EstimatedCostDeleteButton));
      await tester.pump();
      expect(clicks, 0);
    });
  });
}

