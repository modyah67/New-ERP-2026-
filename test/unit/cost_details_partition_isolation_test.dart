import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';

void main() {
  group('Cost Details Partition & Historical Isolation Logic', () {
    const activeCenterP2 = CostCenter(
      id: 'CC-MANGO-2026-2027',
      code: 'CC-MANGO-2026-2027',
      nameAr: 'مانجو (موسم 2026-2027)',
      nameEn: 'Mango (Season 2026-2027)',
      type: CostCenterType.variety,
      color: Colors.green,
      icon: Icons.eco,
      seasonStatus: 'active',
      closureCount: 1, // Stage 1 closed
      seasonNumber: 2, // Period 2
      isActive: true,
    );

    const permanentlyClosedCenter = CostCenter(
      id: 'CC-MANGO-2025-2026',
      code: 'CC-MANGO-2025-2026',
      nameAr: 'مانجو (موسم 2025-2026)',
      nameEn: 'Mango (Season 2025-2026)',
      type: CostCenterType.variety,
      color: Colors.grey,
      icon: Icons.eco,
      seasonStatus: 'permanently_closed',
      closureCount: 2,
      seasonNumber: 2,
      isActive: false,
    );

    final allCenters = [activeCenterP2, permanentlyClosedCenter];

    final rolloverRow = {
      'cost_center_id': 'CC-MANGO-2026-2027',
      'source_type': 'season_rollover',
      'source_id': 'rollover_1_to_1',
      'item_name': 'رصيد مرحل من الفترة الأولى إلى الفترة الثانية',
      'amount': 200000.0,
      'created_at': '2026-06-01T12:00:00Z',
    };

    final p1Transaction = {
      'cost_center_id': 'CC-MANGO-2026-2027',
      'source_type': 'packing_operational',
      'item_name': 'خدمات محطة تشغيل',
      'amount': 50000.0,
      'created_at': '2026-05-15T10:00:00Z',
    };

    final p2Transaction = {
      'cost_center_id': 'CC-MANGO-2026-2027',
      'source_type': 'packing_operational',
      'item_name': 'خدمات فرز وتعبئة فترة ثانية',
      'amount': 25000.0,
      'created_at': '2026-07-20T14:00:00Z',
    };

    final closedCenterRow = {
      'cost_center_id': 'CC-MANGO-2025-2026',
      'source_type': 'crop_purchase',
      'item_name': 'شراء محصول مانجو موسم سابق',
      'amount': 150000.0,
      'created_at': '2025-08-10T09:00:00Z',
    };

    final allRows = [rolloverRow, p1Transaction, p2Transaction, closedCenterRow];

    bool isRolloverRow(Map<String, dynamic> r) {
      final sType = r['source_type']?.toString() ?? '';
      final sId = r['source_id']?.toString() ?? '';
      final itemName = r['item_name']?.toString() ?? '';
      final notes = r['notes']?.toString() ?? '';
      final cat = r['category']?.toString() ?? '';
      return sType == 'season_rollover' ||
          r['is_rollover'] == true ||
          sId.startsWith('rollover_') ||
          itemName.contains('رصيد مرحل') ||
          itemName.contains('رصيد افتتاحي مرحل') ||
          cat.contains('رصيد مرحل') ||
          cat.contains('رصيد افتتاحي منقول') ||
          notes.contains('ترحيل محاسبي');
    }

    bool isRowClosed(Map<String, dynamic> r) {
      final ccId = (r['cost_center_id']?.toString() ?? '').trim();
      final ccName = (r['cost_center_name']?.toString() ?? '').trim();
      final sId = (r['source_id']?.toString() ?? '').trim();

      CostCenter? matchingCenter;
      for (final c in allCenters) {
        if ((ccId.isNotEmpty && (c.id == ccId || c.code == ccId)) ||
            (ccId.isEmpty && (c.nameAr == ccName || c.nameEn == ccName))) {
          matchingCenter = c;
          break;
        }
      }

      if (matchingCenter != null && (matchingCenter.isClosed || matchingCenter.isPermanentlyClosed)) {
        return true;
      }

      if (r['is_closed'] == true ||
          r['is_closed'] == 1 ||
          r['is_closed'] == 'true' ||
          r['season_status'] == 'closed' ||
          r['season_status'] == 'permanently_closed') {
        return true;
      }

      if (matchingCenter != null && (matchingCenter.closureCount >= 1 || matchingCenter.seasonNumber >= 2)) {
        Map<String, dynamic>? intraRollover;
        for (final row in allRows) {
          final rowCc = (row['cost_center_id']?.toString() ?? '').trim();
          final rowSid = (row['source_id']?.toString() ?? '').trim();
          final matchesCc = rowCc.isEmpty || rowCc == ccId || rowCc == matchingCenter.id || rowCc == matchingCenter.code;
          if (matchesCc &&
              row['source_type'] == 'season_rollover' &&
              RegExp(r'^rollover_(\d+)_to_\1').hasMatch(rowSid)) {
            intraRollover = row;
            break;
          }
        }

        if (intraRollover != null) {
          final intraSid = (intraRollover['source_id']?.toString() ?? '').trim();
          if (sId == intraSid) {
            return false;
          }

          final rolloverDateStr = intraRollover['created_at']?.toString() ??
              intraRollover['date']?.toString();
          final rDateStr = r['created_at']?.toString() ??
              r['date']?.toString();
          if (rolloverDateStr != null && rDateStr != null) {
            final rolloverTime = DateTime.tryParse(rolloverDateStr);
            final rTime = DateTime.tryParse(rDateStr);
            if (rolloverTime != null && rTime != null) {
              if (rTime.isBefore(rolloverTime)) {
                return true;
              }
              return false;
            }
          }

          if (isRolloverRow(r) && !RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId)) {
            return true;
          }
        }
      }

      if (isRolloverRow(r)) return false;
      return false;
    }

    test('Forward rollover transaction is ALWAYS active opening baseline and not classified as closed', () {
      expect(isRolloverRow(rolloverRow), isTrue);
      expect(isRowClosed(rolloverRow), isFalse);
    });

    test('Period 1 transactions before rollover are classified as closed (historical)', () {
      expect(isRowClosed(p1Transaction), isTrue);
    });

    test('Period 2 transactions after rollover are classified as active', () {
      expect(isRowClosed(p2Transaction), isFalse);
    });

    test('Transactions of permanently closed cost centers are classified as closed (historical)', () {
      expect(isRowClosed(closedCenterRow), isTrue);
    });

    test('Partitions strictly isolate active from historical transactions', () {
      final activeRows = allRows.where((r) => !isRowClosed(r)).toList();
      final historicalRows = allRows.where((r) => isRowClosed(r)).toList();

      expect(activeRows, contains(rolloverRow));
      expect(activeRows, contains(p2Transaction));
      expect(activeRows, isNot(contains(p1Transaction)));
      expect(activeRows, isNot(contains(closedCenterRow)));

      expect(historicalRows, contains(p1Transaction));
      expect(historicalRows, contains(closedCenterRow));
      expect(historicalRows, isNot(contains(rolloverRow)));
      expect(historicalRows, isNot(contains(p2Transaction)));
    });

    test('Cross-year card scoping strictly isolates agricultural years', () {
      // Simulate Card 2027-2028 scoping
      const target2027 = CostCenter(
        id: 'CC-MANGO-2027-2028',
        code: 'CC-MANGO-2027-2028',
        nameAr: 'مانجو (موسم 2027-2028)',
        nameEn: 'Mango (Season 2027-2028)',
        type: CostCenterType.variety,
        color: Colors.green,
        icon: Icons.eco,
        season: '2027-2028',
        seasonStatus: 'active',
        status: 'active',
        closureCount: 0,
        seasonNumber: 1,
        isActive: true,
      );

      final row2027 = {
        'cost_center_id': 'CC-MANGO-2027-2028',
        'source_type': 'lot_receipt',
        'item_name': 'مانجو عويسي - وزن',
        'amount': 100000.0,
        'created_at': '2026-11-13T02:13:50Z',
      };

      final allMultiYearRows = [
        row2027,
        rolloverRow, // 2026-2027
        p1Transaction, // 2026-2027
        p2Transaction, // 2026-2027
        closedCenterRow, // 2025-2026
      ];

      String? extractSeason(String? text) {
        if (text == null || text.isEmpty) return null;
        final m = RegExp(r'(\d{4})[-/–](\d{4})').firstMatch(text);
        if (m != null) return '${m.group(1)}-${m.group(2)}';
        return null;
      }

      final scopedFor2027 = allMultiYearRows.where((r) {
        final id = r['cost_center_id']?.toString();
        final targetSeason = target2027.season ?? extractSeason(target2027.code);
        if (targetSeason != null) {
          final rowSeason = extractSeason(id) ?? extractSeason(r['item_name']?.toString());
          if (rowSeason != null && rowSeason != targetSeason) return false;
        }
        return id == target2027.id || id == target2027.code;
      }).toList();

      expect(scopedFor2027, contains(row2027));
      expect(scopedFor2027, isNot(contains(rolloverRow)));
      expect(scopedFor2027, isNot(contains(p1Transaction)));
      expect(scopedFor2027, isNot(contains(p2Transaction)));
      expect(scopedFor2027, isNot(contains(closedCenterRow)));
    });

    test('Season rollover balance computation and variety grouping integrity', () {
      // 1. Simulating 2026-2027 transactions
      final p1Row1 = {'cost_center_id': 'CC-MANGO-2026-2027', 'source_type': 'lot_receipt', 'item_name': 'مانجو عويسي - وزن', 'amount': 100000.0};
      final p1Row2 = {'cost_center_id': 'CC-MANGO-2026-2027', 'source_type': 'lot_receipt', 'item_name': 'مانجو عويسي - كراتين', 'amount': 100000.0};
      final p1Rollover = {'cost_center_id': 'CC-MANGO-2026-2027', 'source_type': 'season_rollover', 'source_id': 'rollover_1_to_1', 'item_name': 'رصيد مرحل من الفترة الأولى', 'amount': 200000.0, 'is_redundant_rollover': true};
      final p2Row1 = {'cost_center_id': 'CC-MANGO-2026-2027', 'source_type': 'lot_receipt', 'item_name': 'مانجو عويسي - وزن', 'amount': 100000.0};
      final p2Row2 = {'cost_center_id': 'CC-MANGO-2026-2027', 'source_type': 'lot_receipt', 'item_name': 'مانجو عويسي - وزن', 'amount': 150000.0};

      final all2026Rows = [p1Row1, p1Row2, p1Rollover, p2Row1, p2Row2];

      bool isRollover(Map<String, dynamic> r) =>
          r['source_type'] == 'season_rollover' ||
          r['is_rollover'] == true ||
          (r['source_id']?.toString().startsWith('rollover_') ?? false);

      // Authentic total for Stage 2 rollover MUST equal 450,000 (excluding intra-card rollover)
      double closingBalance = 0.0;
      for (final r in all2026Rows) {
        if (r['is_redundant_rollover'] == true) continue;
        if (isRollover(r)) continue;
        closingBalance += ((r['amount'] as num?)?.toDouble() ?? 0.0);
      }
      expect(closingBalance, 450000.0);

      // 2. Rollover to 2027-2028: variety breakdown
      final r27VarietyWeight = {
        'cost_center_id': 'CC-MANGO-2027-2028',
        'source_type': 'season_rollover',
        'source_id': 'rollover_1_to_2_weight',
        'item_name': 'مانجو عويسي - وزن',
        'amount': 350000.0,
      };
      final r27VarietyBoxes = {
        'cost_center_id': 'CC-MANGO-2027-2028',
        'source_type': 'season_rollover',
        'source_id': 'rollover_1_to_2_boxes',
        'item_name': 'مانجو عويسي - كراتين',
        'amount': 100000.0,
      };
      // Bogus negative remainder (should be filtered)
      final r27BogusRemainder = {
        'cost_center_id': 'CC-MANGO-2027-2028',
        'source_type': 'season_rollover',
        'source_id': 'rollover_1_to_2_remainder',
        'item_name': 'مانجو (رصيد عام غير مخصص)',
        'amount': -200000.0,
      };
      final r27NewOp = {
        'cost_center_id': 'CC-MANGO-2027-2028',
        'source_type': 'lot_receipt',
        'item_name': 'مانجو عويسي - وزن',
        'amount': 100000.0,
      };

      final raw2027Rows = [r27VarietyWeight, r27VarietyBoxes, r27BogusRemainder, r27NewOp];

      // Defensive filtering in DAO and UI
      final clean2027Rows = raw2027Rows.where((r) {
        final sType = r['source_type']?.toString() ?? '';
        final sId = r['source_id']?.toString() ?? '';
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final item = r['item_name']?.toString() ?? '';
        if (sType == 'season_rollover' && (sId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
          return false;
        }
        return true;
      }).toList();

      expect(clean2027Rows.length, 3);
      expect(clean2027Rows.any((r) => r['item_name'] == 'مانجو (رصيد عام غير مخصص)'), isFalse);

      // Summary Bar calculations
      double openingTotal = 0.0;
      double operationalTotal = 0.0;
      for (final r in clean2027Rows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        if (isRollover(r)) {
          openingTotal += amt;
        } else {
          operationalTotal += amt;
        }
      }

      expect(openingTotal, 450000.0); // Exact match with 2026-2027 closing balance!
      expect(operationalTotal, 100000.0);
      expect(openingTotal + operationalTotal, 550000.0);
    });

    test('Bottom Summary Bar carry-forward indicator matches table opening items and Net Closing Balance', () {
      // Simulating a closed cost center from previous season
      const closedSeasonCenter = CostCenter(
        id: 'CC-MANGO-2026-2027',
        code: 'CC-MANGO-2026-2027',
        nameAr: 'مانجو (موسم 2026-2027)',
        nameEn: 'Mango (Season 2026-2027)',
        type: CostCenterType.variety,
        color: Colors.grey,
        icon: Icons.eco,
        currentBalance: 450000.0, // Authentic Net Closing Balance
        seasonStatus: 'permanently_closed',
      );

      // Simulating the new active cost center
      const newSeasonCenter = CostCenter(
        id: 'CC-MANGO-2027-2028',
        code: 'CC-MANGO-2027-2028',
        nameAr: 'مانجو (موسم 2027-2028)',
        nameEn: 'Mango (Season 2027-2028)',
        type: CostCenterType.variety,
        color: Colors.green,
        icon: Icons.eco,
        openingBalance: 450000.0, // Matches previous closing balance exactly
        currentBalance: 550000.0, // 450k opening + 100k new operations
        seasonStatus: 'active',
        isActive: true,
      );

      // Active operations partition rows
      final activeTableRows = [
        {
          'id': 'cct_22',
          'cost_center_id': 'CC-MANGO-2027-2028',
          'source_type': 'season_rollover',
          'source_id': 'rollover_1_to_2_weight',
          'item_name': 'مانجو عويسي - وزن',
          'amount': 350000.0,
          'is_opening_balance': true,
          'is_rollover': true,
        },
        {
          'id': 'cct_23',
          'cost_center_id': 'CC-MANGO-2027-2028',
          'source_type': 'season_rollover',
          'source_id': 'rollover_1_to_2_boxes',
          'item_name': 'مانجو عويسي - كراتين',
          'amount': 100000.0,
          'is_opening_balance': true,
          'is_rollover': true,
        },
        {
          'id': 'cct_25',
          'cost_center_id': 'CC-MANGO-2027-2028',
          'source_type': 'lot_receipt',
          'source_id': '5',
          'item_name': 'مانجو عويسي - وزن',
          'amount': 100000.0,
          'is_opening_balance': false,
          'is_rollover': false,
        },
      ];

      // 1. Calculate sum of opening items shown as rows in the table
      final tableOpeningItemsSum = activeTableRows
          .where((r) => r['is_opening_balance'] == true || r['source_type'] == 'season_rollover' || r['is_rollover'] == true)
          .fold<double>(0.0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0.0));

      // 2. Summary Bar calculation logic
      double baselineOpening = 0.0;
      double operational = 0.0;
      double redundantRollover = 0.0;

      for (final r in activeTableRows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final isRedundant = r['is_redundant_rollover'] == true;
        final isRollover = r['is_rollover'] == true || r['source_type'] == 'season_rollover';
        final isOpening = r['is_opening_balance'] == true || isRollover;

        if (isRedundant) {
          redundantRollover += amt;
        } else if (isOpening) {
          baselineOpening += amt;
        } else {
          operational += amt;
        }
      }

      double displayOpening = redundantRollover > 0 ? redundantRollover : baselineOpening;
      if (displayOpening == 0.0 && newSeasonCenter.openingBalance > 0) {
        displayOpening = newSeasonCenter.openingBalance;
      }
      final totalLedgerBalance = displayOpening + operational;

      // Assertions:
      // A. "رصيد مرحل / أساس" matches Net Closing Balance of the previous season
      expect(displayOpening, equals(closedSeasonCenter.currentBalance));
      expect(displayOpening, equals(450000.0));

      // B. "رصيد مرحل / أساس" matches the sum of opening items in the table
      expect(displayOpening, equals(tableOpeningItemsSum));

      // C. Net operational movements
      expect(operational, equals(100000.0));

      // D. Total Ledger Balance equation: opening + operational = ledger balance
      expect(totalLedgerBalance, equals(550000.0));
      expect(totalLedgerBalance, equals(newSeasonCenter.currentBalance));
    });
  });
}

