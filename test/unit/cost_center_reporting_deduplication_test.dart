import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/dao/cost_report_dao.dart';

void main() {
  group('Cost Center Reporting Deduplication & Returns Reconcilation', () {
    test('CostReportDao.extractBaseItemName normalizes return and purchase prefixes', () {
      expect(CostReportDao.extractBaseItemName('مرتجع مانجو عويسي - وزن'), 'مانجو عويسي - وزن');
      expect(CostReportDao.extractBaseItemName('مرتجع شراء محصول خام مانجو كيت'), 'مانجو كيت');
      expect(CostReportDao.extractBaseItemName('شراء محصول فراولة فريش'), 'فراوله فريش');
      expect(CostReportDao.extractBaseItemName('فاتورة مشتريات - كراتين فراولة 2 كجم'), 'كراتين فراوله 2 كجم');
      expect(CostReportDao.extractBaseItemName('مانجو عويسي - وزن'), 'مانجو عويسي - وزن');
    });

    test('Deduplicates duplicate live view rows when matching dedicated CCT row exists', () {
      // 1. CCT rows representing confirmed physical transactions
      final cctRows = [
        {
          'id': 'cct_1',
          'source_type': 'lot_receipt',
          'source_id': '1',
          'shipment_no': 'استلام لوط',
          'shipment_date': '2026-09-13',
          'customer_name': 'مورد محصول',
          'category': 'تكلفة المحاصيل',
          'item_name': 'مانجو عويسي - وزن',
          'quantity': 1000.0,
          'unit_price': 150.0,
          'amount': 150000.0,
          'is_lot_receipt': true,
          'is_lot_return': false,
          'is_purchase': false,
          'cost_center_id': 'CC-MANGO-2026-2027',
        },
        {
          'id': 'cct_7',
          'source_type': 'lot_return',
          'source_id': '1',
          'shipment_no': 'مرتجع شراء محصول',
          'shipment_date': '2026-09-13',
          'customer_name': 'مورد محصول (مرتجع)',
          'category': 'تكلفة المحاصيل',
          'item_name': 'مانجو عويسي - وزن',
          'quantity': -400.0,
          'unit_price': 166.5,
          'amount': -66600.0,
          'is_lot_receipt': false,
          'is_lot_return': true,
          'is_purchase': false,
          'cost_center_id': 'CC-MANGO-2026-2027',
        },
      ];

      // 2. Unfiltered live view rows (naive view union from lot_receipts & lot_returns)
      final liveViewRows = [
        {
          'shipment_date': '2026-09-13',
          'category': 'crop',
          'item_name': 'مانجو عويسي - وزن',
          'quantity': 1000.0,
          'unit_price': 150.0,
          'amount': 150000.0,
          'is_lot_receipt': true,
          'is_lot_return': false,
        },
        {
          'shipment_date': '2026-09-13',
          'category': 'crop',
          'item_name': 'مرتجع مانجو عويسي - وزن',
          'quantity': -400.0,
          'unit_price': 166.5,
          'amount': -66600.0,
          'is_lot_receipt': false,
          'is_lot_return': true,
        },
      ];

      // Build CCT signatures
      final Set<String> existingSignatures = {};
      for (final c in cctRows) {
        final sType = c['source_type']?.toString();
        final sId = c['source_id']?.toString();
        if (sType != null && sId != null) existingSignatures.add('$sType:$sId');

        final date = (c['shipment_date']?.toString() ?? '').split('T').first;
        final rawItem = c['item_name']?.toString() ?? '';
        final baseItem = CostReportDao.extractBaseItemName(rawItem);
        final amtAbs = ((c['amount'] as num?)?.toDouble() ?? 0.0).abs().toStringAsFixed(0);

        if (date.isNotEmpty) existingSignatures.add('$date:$baseItem:$amtAbs');
        if (baseItem.isNotEmpty) existingSignatures.add('$baseItem:$amtAbs');
      }

      // Filter live view rows
      final filteredLiveView = liveViewRows.where((row) {
        final cat = row['category']?.toString() ?? '';
        final isCropCat = cat == 'crop' ||
            cat == 'fruit' ||
            cat == 'manual_crop' ||
            cat == 'تكلفة المحاصيل' ||
            row['is_lot_receipt'] == true ||
            row['is_lot_return'] == true;

        if (isCropCat && cctRows.isNotEmpty) {
          final date = (row['shipment_date']?.toString() ?? '').split('T').first;
          final rawItem = row['item_name']?.toString() ?? '';
          final baseItem = CostReportDao.extractBaseItemName(rawItem);
          final amtAbs = ((row['amount'] as num?)?.toDouble() ?? 0.0).abs().toStringAsFixed(0);

          final sigWithDate = '$date:$baseItem:$amtAbs';
          final sigWithoutDate = '$baseItem:$amtAbs';

          if (existingSignatures.contains(sigWithDate) || existingSignatures.contains(sigWithoutDate)) {
            return false;
          }
        }
        return true;
      }).toList();

      // Assert both live view duplicates are suppressed
      expect(filteredLiveView.isEmpty, isTrue);

      // Combined list contains strictly the 2 dedicated CCT rows
      final combined = [...cctRows, ...filteredLiveView];
      expect(combined.length, 2);

      // Verify grand total reconciles to 83,400.00 EGP (150,000 - 66,600) and NOT 233,400.00
      final grandTotal = combined.fold<double>(0.0, (sum, r) => sum + (r['amount'] as double));
      expect(grandTotal, 83400.0);
    });

    test('Eliminates redundant preliminary purchase order entries when detailed lot receipt exists', () {
      final cctRowsWithDuplicatePurchase = [
        {
          'id': 'cct_po_101',
          'source_type': 'crop_purchase',
          'source_id': 'po_101',
          'shipment_no': 'فاتورة مشتريات',
          'shipment_date': '2026-09-13',
          'item_name': 'شراء محصول مانجو عويسي - وزن',
          'quantity': 1000.0,
          'amount': 150000.0,
          'is_purchase': true,
          'is_lot_receipt': false,
          'is_lot_return': false,
        },
        {
          'id': 'cct_lot_1',
          'source_type': 'lot_receipt',
          'source_id': 'po_101',
          'shipment_no': 'استلام لوط',
          'shipment_date': '2026-09-13',
          'item_name': 'مانجو عويسي - وزن',
          'quantity': 1000.0,
          'amount': 150000.0,
          'is_purchase': false,
          'is_lot_receipt': true,
          'is_lot_return': false,
        },
        {
          'id': 'cct_ret_1',
          'source_type': 'lot_return',
          'source_id': '1',
          'shipment_no': 'مرتجع شراء محصول',
          'shipment_date': '2026-09-13',
          'item_name': 'مانجو عويسي - وزن',
          'quantity': -400.0,
          'amount': -66600.0,
          'is_purchase': false,
          'is_lot_receipt': false,
          'is_lot_return': true,
        },
      ];

      final lotReceiptsInCct = cctRowsWithDuplicatePurchase.where((r) => r['is_lot_receipt'] == true).toList();
      final cctDeduplicated = cctRowsWithDuplicatePurchase.where((r) {
        if (r['is_purchase'] == true) {
          final rBaseItem = CostReportDao.extractBaseItemName(r['item_name']?.toString() ?? '');
          final rAmt = ((r['amount'] as num?)?.toDouble() ?? 0.0).abs();
          final rQty = ((r['quantity'] as num?)?.toDouble() ?? 0.0).abs();

          final hasMatchingLot = lotReceiptsInCct.any((lot) {
            final lotBaseItem = CostReportDao.extractBaseItemName(lot['item_name']?.toString() ?? '');
            final lotAmt = ((lot['amount'] as num?)?.toDouble() ?? 0.0).abs();
            final lotQty = ((lot['quantity'] as num?)?.toDouble() ?? 0.0).abs();

            final sameRef = (lot['source_id'] != null && r['source_id'] != null && lot['source_id'] == r['source_id']);
            final sameItem = rBaseItem.isEmpty ||
                lotBaseItem.isEmpty ||
                rBaseItem == lotBaseItem ||
                lotBaseItem.contains(rBaseItem) ||
                rBaseItem.contains(lotBaseItem);
            final sameAmt = (rAmt - lotAmt).abs() < 1.0;
            final sameQty = (rQty > 0 && lotQty > 0) && (rQty - lotQty).abs() < 1.0;

            return sameRef || (sameItem && (sameAmt || sameQty));
          });

          if (hasMatchingLot) {
            return false;
          }
        }
        return true;
      }).toList();

      // Only the detailed lot receipt and return remain
      expect(cctDeduplicated.length, 2);
      expect(cctDeduplicated.any((r) => r['source_type'] == 'crop_purchase'), isFalse);
      expect(cctDeduplicated.any((r) => r['source_type'] == 'lot_receipt'), isTrue);
      expect(cctDeduplicated.any((r) => r['source_type'] == 'lot_return'), isTrue);

      final total = cctDeduplicated.fold<double>(0.0, (s, r) => s + (r['amount'] as double));
      expect(total, 83400.0);
    });

    test('Clean transaction sorting order: Purchase/Receipt -> Lot Receipt -> Operations -> Returns', () {
      final rows = [
        {'id': '1', 'shipment_date': '2026-09-13', 'is_lot_return': true, 'amount': -66600.0},
        {'id': '2', 'shipment_date': '2026-09-13', 'is_purchase': true, 'amount': 20000.0},
        {'id': '3', 'shipment_date': '2026-09-13', 'is_lot_receipt': true, 'amount': 150000.0},
        {'id': '4', 'shipment_date': '2026-09-13', 'is_packing_operational': true, 'amount': 5000.0},
      ];

      rows.sort((a, b) {
        final dateA = a['shipment_date']?.toString() ?? '';
        final dateB = b['shipment_date']?.toString() ?? '';
        final dateComp = dateB.compareTo(dateA);
        if (dateComp != 0) return dateComp;

        int orderPriority(Map<String, dynamic> r) {
          if (r['is_opening_balance'] == true) return 0;
          if (r['is_purchase'] == true) return 1;
          if (r['is_lot_receipt'] == true) return 2;
          if (r['is_packing_operational'] == true) return 3;
          if (r['is_lot_return'] == true || ((r['amount'] as num?)?.toDouble() ?? 0) < 0) return 5;
          if (r['is_sorting_sale'] == true) return 6;
          return 4;
        }

        return orderPriority(a).compareTo(orderPriority(b));
      });

      expect(rows[0]['id'], '2'); // Purchase
      expect(rows[1]['id'], '3'); // Lot receipt
      expect(rows[2]['id'], '4'); // Operations
      expect(rows[3]['id'], '1'); // Return
    });

    test('Mango Cost Center CC-MANGO-2026-2027: Season rollover does NOT double-count operational transactions (55,600 EGP, not 111,200 EGP)', () {
      final rows = [
        {
          'id': 'cct_1',
          'source_type': 'lot_receipt',
          'source_id': '1',
          'shipment_no': 'استلام لوط',
          'shipment_date': '2026-09-13',
          'item_name': 'مانجو عويسي - وزن',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'cost_center_name': 'مانجو (موسم 2026-2027)',
          'amount': 100000.0,
          'is_lot_receipt': true,
          'is_lot_return': false,
          'is_purchase': false,
        },
        {
          'id': 'cct_6',
          'source_type': 'lot_return',
          'source_id': '1',
          'shipment_no': 'مرتجع شراء محصول',
          'shipment_date': '2026-09-13',
          'item_name': 'مانجو عويسي - وزن',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'cost_center_name': 'مانجو (موسم 2026-2027)',
          'amount': -44400.0,
          'is_lot_receipt': false,
          'is_lot_return': true,
          'is_purchase': false,
        },
        {
          'id': 'cct_7',
          'source_type': 'season_rollover',
          'source_id': 'rollover_16_to_16',
          'shipment_no': 'رصيد مرحل',
          'shipment_date': '2026-09-13',
          'item_name': 'رصيد مرحل من الموسم 2026-2027 (الفترة 1)',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'cost_center_name': 'مانجو (موسم 2026-2027)',
          'amount': 55600.0,
          'is_opening_balance': true,
          'is_rollover': true,
          'is_lot_receipt': false,
          'is_lot_return': false,
          'is_purchase': false,
        },
      ];

      // Detect redundant seasonal rollovers
      for (final row in rows) {
        if (row['is_rollover'] == true || row['source_type'] == 'season_rollover') {
          final ccId = row['cost_center_id']?.toString();
          final sId = row['source_id']?.toString() ?? '';
          final amt = ((row['amount'] as num?)?.toDouble() ?? 0.0);

          final isIntraCenter = sId.isNotEmpty && RegExp(r'^rollover_(\d+)_to_\1$').hasMatch(sId);

          final otherOps = rows.where((o) {
            if (identical(o, row)) return false;
            final oCc = o['cost_center_id']?.toString();
            if (oCc == null || (oCc != ccId && o['cost_center_name'] != row['cost_center_name'])) return false;
            final oIsRollover = o['is_rollover'] == true || o['source_type'] == 'season_rollover';
            return !oIsRollover;
          }).toList();

          final otherOpsSum = otherOps.fold<double>(0.0, (s, o) => s + ((o['amount'] as num?)?.toDouble() ?? 0.0));
          final matchesOpsSum = otherOps.isNotEmpty && (otherOpsSum - amt).abs() < 1.0;

          if (isIntraCenter && otherOps.isNotEmpty) {
            row['is_redundant_rollover'] = true;
          } else if (matchesOpsSum) {
            row['is_redundant_rollover'] = true;
          } else {
            row['is_redundant_rollover'] = false;
          }
        }
      }

      // Verify the rollover row is marked redundant because underlying operational rows (100k - 44.4k = 55.6k) are present
      expect(rows[2]['is_redundant_rollover'], isTrue);

      // Verify net total calculation
      double baselineOpeningBalance = 0.0;
      double operationalExpenses = 0.0;
      double redundantRolloverTotal = 0.0;

      for (final r in rows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final isRedundant = r['is_redundant_rollover'] == true;
        final isRollover = r['is_rollover'] == true || r['source_type'] == 'season_rollover';
        final isOpening = r['is_opening_balance'] == true || r['source_type'] == 'opening_balance';

        if (isRedundant) {
          redundantRolloverTotal += amt;
        } else if (isOpening || isRollover) {
          baselineOpeningBalance += amt;
        } else {
          operationalExpenses += amt;
        }
      }

      final netTotalCost = baselineOpeningBalance + operationalExpenses;

      // Assertions:
      expect(operationalExpenses, 55600.0); // 100,000 - 44,400
      expect(redundantRolloverTotal, 55600.0); // Captured for informational display
      expect(netTotalCost, 55600.0); // Exact 55,600.00 EGP, NOT 111,200.00 EGP!
    });

    test('Inter-center rollover: Acts as baseline opening balance when previous operations are not present', () {
      final rows = [
        {
          'id': 'cct_10',
          'source_type': 'season_rollover',
          'source_id': 'rollover_15_to_16',
          'shipment_no': 'رصيد مرحل',
          'shipment_date': '2026-09-13',
          'item_name': 'رصيد مرحل من الموسم 2025-2026 (الفترة 2)',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'cost_center_name': 'مانجو (موسم 2026-2027)',
          'amount': 55600.0,
          'is_opening_balance': true,
          'is_rollover': true,
        },
      ];

      // Detect redundant seasonal rollovers
      for (final row in rows) {
        if (row['is_rollover'] == true || row['source_type'] == 'season_rollover') {
          final ccId = row['cost_center_id']?.toString();
          final sId = row['source_id']?.toString() ?? '';
          final amt = ((row['amount'] as num?)?.toDouble() ?? 0.0);

          final isIntraCenter = sId.isNotEmpty && RegExp(r'^rollover_(\d+)_to_\1$').hasMatch(sId);

          final otherOps = rows.where((o) {
            if (identical(o, row)) return false;
            final oCc = o['cost_center_id']?.toString();
            if (oCc == null || (oCc != ccId && o['cost_center_name'] != row['cost_center_name'])) return false;
            final oIsRollover = o['is_rollover'] == true || o['source_type'] == 'season_rollover';
            return !oIsRollover;
          }).toList();

          final otherOpsSum = otherOps.fold<double>(0.0, (s, o) => s + ((o['amount'] as num?)?.toDouble() ?? 0.0));
          final matchesOpsSum = otherOps.isNotEmpty && (otherOpsSum - amt).abs() < 1.0;

          if (isIntraCenter && otherOps.isNotEmpty) {
            row['is_redundant_rollover'] = true;
          } else if (matchesOpsSum) {
            row['is_redundant_rollover'] = true;
          } else {
            row['is_redundant_rollover'] = false;
          }
        }
      }

      // Assert NOT redundant because no other operations exist in this center
      expect(rows[0]['is_redundant_rollover'], isFalse);

      double baselineOpening = 0.0;
      double operational = 0.0;
      for (final r in rows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        if (r['is_redundant_rollover'] == true) continue;
        if (r['is_opening_balance'] == true || r['is_rollover'] == true) {
          baselineOpening += amt;
        } else {
          operational += amt;
        }
      }

      expect(baselineOpening, 55600.0);
      expect(operational, 0.0);
      expect(baselineOpening + operational, 55600.0);
    });

    test('Inter-center rollover + new operational transaction adds to baseline correctly', () {
      final rows = [
        {
          'id': 'cct_10',
          'source_type': 'season_rollover',
          'source_id': 'rollover_15_to_16',
          'shipment_no': 'رصيد مرحل',
          'shipment_date': '2026-09-13',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'amount': 55600.0,
          'is_opening_balance': true,
          'is_rollover': true,
        },
        {
          'id': 'cct_20',
          'source_type': 'lot_receipt',
          'source_id': '20',
          'shipment_no': 'استلام لوط',
          'shipment_date': '2026-09-14',
          'cost_center_id': 'CC-MANGO-2026-2027',
          'amount': 10000.0,
          'is_lot_receipt': true,
        },
      ];

      for (final row in rows) {
        if (row['is_rollover'] == true || row['source_type'] == 'season_rollover') {
          final ccId = row['cost_center_id']?.toString();
          final sId = row['source_id']?.toString() ?? '';
          final amt = ((row['amount'] as num?)?.toDouble() ?? 0.0);

          final isIntraCenter = sId.isNotEmpty && RegExp(r'^rollover_(\d+)_to_\1$').hasMatch(sId);

          final otherOps = rows.where((o) {
            if (identical(o, row)) return false;
            final oCc = o['cost_center_id']?.toString();
            if (oCc == null || (oCc != ccId && o['cost_center_name'] != row['cost_center_name'])) return false;
            final oIsRollover = o['is_rollover'] == true || o['source_type'] == 'season_rollover';
            return !oIsRollover;
          }).toList();

          final otherOpsSum = otherOps.fold<double>(0.0, (s, o) => s + ((o['amount'] as num?)?.toDouble() ?? 0.0));
          final matchesOpsSum = otherOps.isNotEmpty && (otherOpsSum - amt).abs() < 1.0;

          if (isIntraCenter && otherOps.isNotEmpty) {
            row['is_redundant_rollover'] = true;
          } else if (matchesOpsSum) {
            row['is_redundant_rollover'] = true;
          } else {
            row['is_redundant_rollover'] = false;
          }
        }
      }

      expect(rows[0]['is_redundant_rollover'], isFalse);

      double total = 0.0;
      for (final r in rows) {
        if (r['is_redundant_rollover'] == true) continue;
        total += ((r['amount'] as num?)?.toDouble() ?? 0.0);
      }

      expect(total, 65600.0); // 55,600 baseline + 10,000 new movement
    });
  });
}

