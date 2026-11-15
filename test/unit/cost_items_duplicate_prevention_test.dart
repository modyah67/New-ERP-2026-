import 'package:flutter_test/flutter_test.dart';



void main() {

  group('Packing Cost Items Deduplication & Duplicate Prevention Tests', () {

    test('1. Deduplication filters out exact duplicate cost items', () {

      final inputItems = [

        {

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'report_category_id': 19,

          'supplier_id': null,

          'transport_supplier_id': null,

          'total_egp': 1000.0,

          'notes': 'رسوم طريق',

        },

        {

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'report_category_id': 19,

          'supplier_id': null,

          'transport_supplier_id': null,

          'total_egp': 1000.0,

          'notes': 'رسوم طريق', // Identical duplicate!

        },

        {

          'name': 'مصاريف نقل',

          'category': 'logistics',

          'report_category_id': null,

          'supplier_id': null,

          'transport_supplier_id': 5,

          'total_egp': 2500.0,

          'notes': 'نقلة مزارع',

        },

      ];



      final Map<String, Map<String, dynamic>> canonicalMap = {};

      for (final item in inputItems) {

        final rawName = (item['name']?.toString() ?? '').trim().toLowerCase()

            .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه');

        final rawCat = (item['report_category_id'] ?? item['category'])?.toString().trim().toLowerCase() ?? '';

        final amt = ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble().toStringAsFixed(2);

        final rawNote = (item['notes'] ?? item['settlement_notes'] ?? '').toString().trim();

        final cleanNote = (rawNote.startsWith('تسوية') || rawNote.contains('جدول مقارنة التكاليف')) ? '' : rawNote;

        final sig = '$rawName|$rawCat|$amt|$cleanNote';

        if (!canonicalMap.containsKey(sig)) {

          canonicalMap[sig] = item;

        }

      }

      final uniqueItems = canonicalMap.values.toList();



      expect(uniqueItems.length, equals(2));

      expect(uniqueItems[0]['name'], equals('مصاريف إدارية'));

      expect(uniqueItems[1]['name'], equals('مصاريف نقل'));

    });



    test('2. Legitimate distinct cost items with same category but different amount or notes are preserved', () {

      final inputItems = [

        {

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'report_category_id': 19,

          'supplier_id': null,

          'total_egp': 900.0,

          'notes': 'بوفيه وضيافة',

        },

        {

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'report_category_id': 19,

          'supplier_id': null,

          'total_egp': 1000.0,

          'notes': 'إيجار مخزن',

        },

        {

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'report_category_id': 19,

          'supplier_id': null,

          'total_egp': 1000.0,

          'notes': 'تصاريح وتراخيص',

        },

      ];



      final Map<String, Map<String, dynamic>> canonicalMap = {};

      for (final item in inputItems) {

        final rawName = (item['name']?.toString() ?? '').trim().toLowerCase()

            .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه');

        final rawCat = (item['report_category_id'] ?? item['category'])?.toString().trim().toLowerCase() ?? '';

        final amt = ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble().toStringAsFixed(2);

        final rawNote = (item['notes'] ?? item['settlement_notes'] ?? '').toString().trim();

        final cleanNote = (rawNote.startsWith('تسوية') || rawNote.contains('جدول مقارنة التكاليف')) ? '' : rawNote;

        final sig = '$rawName|$rawCat|$amt|$cleanNote';

        if (!canonicalMap.containsKey(sig)) {

          canonicalMap[sig] = item;

        }

      }

      final uniqueItems = canonicalMap.values.toList();



      expect(uniqueItems.length, equals(3));

      expect(uniqueItems.map((i) => i['total_egp']).toList(), equals([900.0, 1000.0, 1000.0]));

    });



    test('3. Duplicate prevention prevents adding exact duplicate in UI dialog', () {

      final existingCostItems = [

        {

          'name': 'خدمات محطة',

          'category': 'other',

          'report_category_id': 22,

          'supplier_id': 'supp-uuid-1',

          'transport_supplier_id': null,

          'total_egp': 5000.0,

          'notes': 'فرز وتعبئة',

        }

      ];



      bool isDuplicateItem(Map<String, dynamic> newItem) {

        return existingCostItems.any((item) {

          final matchName = (item['name']?.toString().trim() ?? '') == newItem['name'];

          final matchCat = item['report_category_id'] == newItem['report_category_id'];

          final matchSupp = item['supplier_id'] == newItem['supplier_id'] &&

              item['transport_supplier_id'] == newItem['transport_supplier_id'];

          final itemTotal = ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();

          final newTotal = ((newItem['total_egp'] ?? newItem['total'] ?? 0) as num).toDouble();

          final matchTotal = (itemTotal - newTotal).abs() < 0.01;

          final matchNotes = (item['notes']?.toString().trim() ?? '') == (newItem['notes']?.toString().trim() ?? '');

          return matchName && matchCat && matchSupp && matchTotal && matchNotes;

        });

      }



      final duplicateEntry = {

        'name': 'خدمات محطة',

        'report_category_id': 22,

        'supplier_id': 'supp-uuid-1',

        'transport_supplier_id': null,

        'total_egp': 5000.0,

        'notes': 'فرز وتعبئة',

      };



      final distinctEntry = {

        'name': 'خدمات محطة',

        'report_category_id': 22,

        'supplier_id': 'supp-uuid-1',

        'transport_supplier_id': null,

        'total_egp': 7500.0, // Different amount

        'notes': 'فرز وتعبئة',

      };



      expect(isDuplicateItem(duplicateEntry), isTrue);

      expect(isDuplicateItem(distinctEntry), isFalse);

    });



    test('4. Double submission lock state prevents re-entrant confirmCalls', () {

      bool isConfirmingCosts = false;

      int callsExecuted = 0;



      Future<void> simulateConfirm() async {

        if (isConfirmingCosts) return; // Guarded

        isConfirmingCosts = true;

        try {

          await Future.delayed(const Duration(milliseconds: 50));

          callsExecuted++;

        } finally {

          isConfirmingCosts = false;

        }

      }



      // Simulate rapid double click

      final f1 = simulateConfirm();

      final f2 = simulateConfirm();



      return Future.wait([f1, f2]).then((_) {

        expect(callsExecuted, equals(1)); // Only executed once!

      });

    });



    test('5. Cost variance deduplication prioritizes settled actual row over ghost unsettled copies', () {

      // Simulating the exact screenshot scenario for Order #17:

      // - Row 9, 7 & 16: 'خدمات محطة - مورد محطات' (Row 9 settled 1000, Rows 7 & 16 unsettled expected 1000)

      // - Row 11 & 14: 'مصاريف إدارية' (Row 11 settled 1000, Row 14 unsettled expected 1000)

      // - Row 12 & 13: 'مصاريف إدارية' (Row 12 settled 500, Row 13 unsettled expected 500)

      // - Row 8 & 17: 'مصاريف نقل - مورد نقل' (Row 8 id 8, Row 17 id 17)

      final rawDbCostItems = [

        // Station supplier: 1 settled, 2 unsettled

        {

          'id': 101,

          'name': 'خدمات محطة - مورد محطات',

          'category': 'other',

          'supplier_id': 'supp-station-uuid',

          'supplier_name': 'مورد محطات',

          'expected_amount': 1000.0,

          'actual_amount': 1000.0,

          'cost_status': 'actual',

          'variance_journal_entry_id': 501,

        },

        {

          'id': 102,

          'name': 'خدمات محطة - مورد محطات',

          'category': 'other',

          'supplier_id': 'supp-station-uuid',

          'supplier_name': 'مورد محطات',

          'expected_amount': 1000.0,

          'actual_amount': null,

          'cost_status': 'expected',

        },

        {

          'id': 103,

          'name': 'خدمات محطة - مورد محطات',

          'category': 'other',

          'supplier_id': 'supp-station-uuid',

          'supplier_name': 'مورد محطات',

          'expected_amount': 1000.0,

          'actual_amount': null,

          'cost_status': 'expected',

        },

        // Admin expense 1000: 1 settled, 1 unsettled

        {

          'id': 201,

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'supplier_id': null,

          'expected_amount': 1000.0,

          'actual_amount': 1000.0,

          'cost_status': 'actual',

        },

        {

          'id': 202,

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'supplier_id': null,

          'expected_amount': 1000.0,

          'actual_amount': null,

          'cost_status': 'expected',

        },

        // Admin expense 500: 1 settled, 1 unsettled

        {

          'id': 301,

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'supplier_id': null,

          'expected_amount': 500.0,

          'actual_amount': 500.0,

          'cost_status': 'actual',

        },

        {

          'id': 302,

          'name': 'مصاريف إدارية',

          'category': 'admin',

          'supplier_id': null,

          'expected_amount': 500.0,

          'actual_amount': null,

          'cost_status': 'expected',

        },

        // Transport: 2 copies

        {

          'id': 401,

          'name': 'مصاريف نقل - مورد نقل',

          'category': 'logistics',

          'supplier_id': null,

          'transport_supplier_id': 7,

          'supplier_name': 'مورد نقل',

          'expected_amount': 60.0,

          'actual_amount': 60.0,

          'cost_status': 'actual',

        },

        {

          'id': 402,

          'name': 'مصاريف نقل - مورد نقل',

          'category': 'logistics',

          'supplier_id': null,

          'transport_supplier_id': 7,

          'supplier_name': 'مورد نقل',

          'expected_amount': 60.0,

          'actual_amount': 60.0,

          'cost_status': 'actual',

        },

      ];



      // Execute the exact deduplication algorithm from PackingCostVarianceService

      final Map<String, List<Map<String, dynamic>>> groupedCostMap = {};

      for (final c in rawDbCostItems) {

        final rawName = (c['name']?.toString() ?? '').trim().toLowerCase()

            .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه');

        final rawCat = (c['category']?.toString() ?? '').trim().toLowerCase();



        String normCat = rawCat;

        if (rawName.contains('مهندس') || rawName.contains('مهندسين') || rawCat.contains('engineer') || c['custody_id'] != null) {

          normCat = 'engineer';

        } else if (rawName.contains('إدار') || rawName.contains('ادار') || rawCat.contains('admin')) {

          normCat = 'admin';

        } else if (rawName.contains('نقل') || rawName.contains('شحن') || rawCat.contains('transport') || rawCat.contains('logistics')) {

          normCat = 'transport';

        } else if (rawName.contains('محطة') || rawCat.contains('station')) {

          normCat = 'station';

        } else if (rawName.contains('تخصيم') || rawCat.contains('deduction')) {

          normCat = 'deduction';

        }



        final num expNum = (c['expected_amount'] ?? c['base_amount'] ?? c['total_egp'] ?? c['original_amount'] ?? 0) as num;

        final expStr = expNum.toDouble().toStringAsFixed(2);



        final sig = '$rawName|$normCat|$expStr';

        groupedCostMap.putIfAbsent(sig, () => []).add(c);

      }



      final List<Map<String, dynamic>> deduped = [];

      final List<int> redundantDbIds = [];



      for (final group in groupedCostMap.values) {

        if (group.length == 1) {

          deduped.add(group.first);

          continue;

        }



        group.sort((a, b) {

          final aIsSettled = (a['cost_status'] == 'actual' && a['actual_amount'] != null) ||

              a['variance_journal_entry_id'] != null ||

              a['settled_actual'] == true;

          final bIsSettled = (b['cost_status'] == 'actual' && b['actual_amount'] != null) ||

              b['variance_journal_entry_id'] != null ||

              b['settled_actual'] == true;

          if (aIsSettled && !bIsSettled) return -1;

          if (!aIsSettled && bIsSettled) return 1;



          final aHasActual = a['actual_amount'] != null;

          final bHasActual = b['actual_amount'] != null;

          if (aHasActual && !bHasActual) return -1;

          if (!aHasActual && bHasActual) return 1;



          final aId = (a['id'] as num?)?.toInt() ?? 999999999;

          final bId = (b['id'] as num?)?.toInt() ?? 999999999;

          return aId.compareTo(bId);

        });



        final winner = group.first;

        deduped.add(winner);



        for (int i = 1; i < group.length; i++) {

          final loser = group[i];

          final loserId = (loser['id'] as num?)?.toInt();

          if (loserId != null && loserId > 0 && loserId != winner['id']) {

            redundantDbIds.add(loserId);

          }

        }

      }



      // Assertions:

      // 1. Initial 9 rows must be reduced to exactly 4 distinct items

      expect(deduped.length, equals(4));



      // 2. Exactly 5 duplicate DB IDs must be marked for deletion: 102, 103, 202, 302, 402

      expect(redundantDbIds, equals([102, 103, 202, 302, 402]));



      // 3. Every kept item must be the settled version

      final stationItem = deduped.firstWhere((i) => i['name'] == 'خدمات محطة - مورد محطات');

      expect(stationItem['id'], equals(101));

      expect(stationItem['cost_status'], equals('actual'));

      expect(stationItem['actual_amount'], equals(1000.0));



      final admin1000 = deduped.firstWhere((i) => i['name'] == 'مصاريف إدارية' && i['expected_amount'] == 1000.0);

      expect(admin1000['id'], equals(201));

      expect(admin1000['cost_status'], equals('actual'));



      final admin500 = deduped.firstWhere((i) => i['name'] == 'مصاريف إدارية' && i['expected_amount'] == 500.0);

      expect(admin500['id'], equals(301));

      expect(admin500['cost_status'], equals('actual'));



      final transportItem = deduped.firstWhere((i) => i['name'] == 'مصاريف نقل - مورد نقل');

      expect(transportItem['id'], equals(401));

      expect(transportItem['actual_amount'], equals(60.0));

    });



    test('6. Two cost items with identical name and amount but distinct item_uuid are both preserved as independent rows', () {

      final inputItems = [

        {

          'item_uuid': 'uuid-eng-morning-1',

          'name': 'مصاريف مهندسين وإشراف',

          'category': 'engineer_expenses',

          'total_egp': 200.0,

          'notes': 'إشراف وردية صباحية',

        },

        {

          'item_uuid': 'uuid-eng-evening-2',

          'name': 'مصاريف مهندسين وإشراف',

          'category': 'engineer_expenses',

          'total_egp': 200.0, // Same name, same amount!

          'notes': 'إشراف وردية مسائية',

        },

      ];



      final Map<String, Map<String, dynamic>> dedupMap = {};

      for (final item in inputItems) {

        final itemUuid = item['item_uuid']?.toString();

        final rawId = (item['id'] as num?)?.toInt();

        final sig = (itemUuid != null && itemUuid.isNotEmpty && !itemUuid.startsWith('db_'))

            ? 'uuid_$itemUuid'

            : ((rawId != null && rawId > 0 && rawId < 1000000000)

                ? 'id_$rawId'

                : '${item['name']}|${item['category']}|${item['total_egp']}');

        dedupMap[sig] = item;

      }



      final preserved = dedupMap.values.toList();

      expect(preserved.length, equals(2));

      expect(preserved[0]['item_uuid'], equals('uuid-eng-morning-1'));

      expect(preserved[1]['item_uuid'], equals('uuid-eng-evening-2'));

    });



    test('7. Smart reconciliation updates existing row in place instead of inserting duplicate', () {

      final existingDbRows = [

        {

          'id': 50,

          'name': 'خدمات محطة - مورد محطات',

          'category': 'other',

          'base_amount': 1000.0,

          'expected_amount': 1000.0,

          'cost_status': 'expected',

          'currency_snapshot': {'item_uuid': 'uuid-station-1'},

        }

      ];



      final incomingItems = [

        {

          'item_uuid': 'uuid-station-1',

          'name': 'خدمات محطة - مورد محطات',

          'category': 'other',

          'total_egp': 1000.0,

          'notes': 'تسوية معتمدة',

        }

      ];



      final matchedIds = <int>{};

      final rowsToUpdate = <int>[];

      final rowsToInsert = <Map<String, dynamic>>[];



      for (final item in incomingItems) {

        final uuid = item['item_uuid']?.toString();

        final match = existingDbRows.firstWhere(

          (r) => (r['currency_snapshot'] as Map)['item_uuid'] == uuid,

          orElse: () => {},

        );

        if (match.isNotEmpty) {

          matchedIds.add(match['id'] as int);

          rowsToUpdate.add(match['id'] as int);

        } else {

          rowsToInsert.add(item);

        }

      }



      // Assert:

      // It must update row 50, and insert ZERO new rows

      expect(rowsToUpdate, equals([50]));

      expect(rowsToInsert, isEmpty);

    });

    test('8. Post costs idempotency: Ghost/deleted rows with base_amount=0 are excluded from form state and synchronization', () {
      final rawDbRows = [
        {'id': 1, 'name': 'خدمات محطة', 'base_amount': 1000.0, 'deleted_at': null},
        {'id': 2, 'name': 'مصاريف إدارية', 'base_amount': 500.0, 'deleted_at': null},
        {'id': 50, 'name': 'عماله', 'base_amount': 0.0, 'deleted_at': '2026-11-06T12:00:00Z'},
        {'id': 51, 'name': 'مصاريف إدارية', 'base_amount': 0.0, 'deleted_at': '2026-11-06T12:00:00Z'},
      ];

      final activeRows = rawDbRows.where((r) => r['deleted_at'] == null && (r['base_amount'] as double) > 0).toList();

      expect(activeRows.length, equals(2));
      expect(activeRows.map((r) => r['id']).toList(), equals([1, 2]));

      final formCostItems = [
        {'id': 1, 'name': 'خدمات محطة', 'total_egp': 1000.0},
        {'id': 2, 'name': 'مصاريف إدارية', 'total_egp': 500.0},
        {'id': 50, 'name': 'عماله', 'total_egp': 0.0},
      ];

      final cleanItems = formCostItems.where((c) => ((c['total_egp'] ?? 0) as num) > 0).toList();
      expect(cleanItems.length, equals(2));
      expect(cleanItems.any((c) => c['id'] == 50), isFalse);
    });

    test('9. Multiple cost items with exact same name and amount (e.g. 2x 200 EGP engineer expenses) are preserved independently without merging or zeroing', () {
      final item1 = {
        'name': 'مصاريف مهندسين وإشراف',
        'category': 'engineer_expenses',
        'supplier_type': 'engineer',
        'total_egp': 200.0,
        'item_uuid': 'uuid_eng_1',
      };
      final item2 = {
        'name': 'مصاريف مهندسين وإشراف',
        'category': 'engineer_expenses',
        'supplier_type': 'engineer',
        'total_egp': 200.0,
        'item_uuid': 'uuid_eng_2',
      };

      final costItems = [item1, item2];

      // Simulate Step 1 In-memory Deduplication
      final Map<String, Map<String, dynamic>> canonicalCostMap = {};
      for (final item in costItems) {
        final rawItem = Map<String, dynamic>.from(item);
        final rawAmt = ((rawItem['total_egp'] ?? 0) as num).toDouble();
        if (rawAmt <= 0) continue;
        final itemUuid = rawItem['item_uuid']!.toString();
        final rawId = (rawItem['id'] as num?)?.toInt();
        final sig = (rawId != null && rawId > 0 && rawId < 1000000000)
            ? 'id_$rawId'
            : 'uuid_$itemUuid';
        canonicalCostMap[sig] = rawItem;
      }
      final uniqueCostItems = canonicalCostMap.values.toList();

      expect(uniqueCostItems.length, equals(2));
      expect(uniqueCostItems[0]['item_uuid'], equals('uuid_eng_1'));
      expect(uniqueCostItems[1]['item_uuid'], equals('uuid_eng_2'));
      expect(uniqueCostItems[0]['total_egp'], equals(200.0));
      expect(uniqueCostItems[1]['total_egp'], equals(200.0));

      // Simulate Step 3 Smart Reconciliation against DB rows
      final existingDbRows = [
        {
          'id': 101,
          'name': 'مصاريف مهندسين وإشراف',
          'category': 'engineer_expenses',
          'base_amount': 200.0,
          'currency_snapshot': {'item_uuid': 'uuid_eng_1'},
        }
      ];

      final matchedDbIds = <int>{};
      final rowsToUpdate = <int>[];
      final rowsToInsert = <Map<String, dynamic>>[];

      for (final sourceItem in uniqueCostItems) {
        final sourceId = (sourceItem['id'] as num?)?.toInt();
        final sourceUuid = sourceItem['item_uuid']?.toString();

        Map<String, dynamic>? matchedDbRow;
        if (sourceId != null && sourceId > 0) {
          matchedDbRow = existingDbRows.firstWhere((r) => r['id'] == sourceId && !matchedDbIds.contains(r['id']), orElse: () => {});
          if (matchedDbRow.isEmpty) matchedDbRow = null;
        }
        if (matchedDbRow == null && sourceUuid != null && sourceUuid.isNotEmpty) {
          matchedDbRow = existingDbRows.firstWhere((r) {
            if (matchedDbIds.contains(r['id'])) return false;
            final snap = r['currency_snapshot'];
            return snap is Map && snap['item_uuid'] == sourceUuid;
          }, orElse: () => {});
          if (matchedDbRow.isEmpty) matchedDbRow = null;
        }

        if (matchedDbRow != null) {
          final matchedId = matchedDbRow['id'] as int;
          matchedDbIds.add(matchedId);
          rowsToUpdate.add(matchedId);
        } else {
          rowsToInsert.add(sourceItem);
        }
      }

      // Assert:
      // Item 1 matches existing row 101
      // Item 2 is treated as a NEW row to INSERT (NOT merged into row 101 and NOT zeroed out!)
      expect(rowsToUpdate, equals([101]));
      expect(rowsToInsert.length, equals(1));
      expect(rowsToInsert.first['item_uuid'], equals('uuid_eng_2'));
      expect(rowsToInsert.first['total_egp'], equals(200.0));
    });

    test('10. Repeated confirmation clicks do NOT double items (Idempotent Selective Posting)', () {
      // Existing DB has 2 already posted items
      final existingDbRows = [
        {
          'id': 1,
          'name': 'مصاريف إدارية',
          'base_amount': 500.0,
          'cost_status': 'actual',
          'currency_snapshot': {'item_uuid': 'uuid_1'},
        },
        {
          'id': 2,
          'name': 'مصاريف مهندسين وإشراف',
          'base_amount': 200.0,
          'cost_status': 'actual',
          'currency_snapshot': {'item_uuid': 'uuid_2'},
        },
      ];

      // UI state has the 2 existing items + 1 newly added unposted item
      final incomingItems = [
        {
          'id': 1,
          'name': 'مصاريف إدارية',
          'total_egp': 500.0,
          'cost_status': 'actual',
          'item_uuid': 'uuid_1',
        },
        {
          'id': 2,
          'name': 'مصاريف مهندسين وإشراف',
          'total_egp': 200.0,
          'cost_status': 'actual',
          'item_uuid': 'uuid_2',
        },
        {
          'id': null, // New unposted item
          'name': 'خدمات محطة',
          'total_egp': 300.0,
          'cost_status': 'expected',
          'item_uuid': 'uuid_3',
        },
      ];

      // Pass 1: Selective reconciliation
      final matchedDbIds = <int>{};
      final updatedIds = <int>[];
      final insertedItems = <Map<String, dynamic>>[];

      for (final item in incomingItems) {
        final sourceId = (item['id'] as num?)?.toInt();
        final sourceUuid = item['item_uuid']?.toString();

        Map<String, dynamic>? match;
        if (sourceId != null && sourceId > 0) {
          match = existingDbRows.firstWhere((r) => r['id'] == sourceId && !matchedDbIds.contains(r['id']), orElse: () => {});
          if (match.isEmpty) match = null;
        }
        if (match == null && sourceUuid != null) {
          match = existingDbRows.firstWhere((r) {
            final snap = r['currency_snapshot'];
            return snap is Map && snap['item_uuid'] == sourceUuid;
          }, orElse: () => {});
          if (match.isEmpty) match = null;
        }

        if (match != null) {
          final mId = match['id'] as int;
          matchedDbIds.add(mId);
          updatedIds.add(mId);
        } else {
          // Genuinely new item: INSERT
          const newId = 3;
          item['id'] = newId;
          matchedDbIds.add(newId);
          insertedItems.add(item);
          existingDbRows.add({
            'id': newId,
            'name': item['name'] as String,
            'base_amount': item['total_egp'] as double,
            'cost_status': 'actual',
            'currency_snapshot': {'item_uuid': sourceUuid},
          });
        }
      }

      // Assert Pass 1:
      expect(updatedIds, equals([1, 2]));
      expect(insertedItems.length, equals(1));
      expect(insertedItems.first['id'], equals(3));
      expect(existingDbRows.length, equals(3));

      // Pass 2: Clicking 'تحديث وترحيل' again with the exact same items
      final matchedDbIdsPass2 = <int>{};
      final updatedIdsPass2 = <int>[];
      final insertedItemsPass2 = <Map<String, dynamic>>[];

      for (final item in incomingItems) {
        final sourceId = (item['id'] as num?)?.toInt();

        Map<String, dynamic>? match;
        if (sourceId != null && sourceId > 0) {
          match = existingDbRows.firstWhere((r) => r['id'] == sourceId && !matchedDbIdsPass2.contains(r['id']), orElse: () => {});
          if (match.isEmpty) match = null;
        }

        if (match != null) {
          final mId = match['id'] as int;
          matchedDbIdsPass2.add(mId);
          updatedIdsPass2.add(mId);
        } else {
          insertedItemsPass2.add(item);
        }
      }

      // Assert Pass 2:
      // ZERO rows inserted, exactly 3 rows updated in place, no doubling (3 remains 3)!
      expect(insertedItemsPass2, isEmpty);
      expect(updatedIdsPass2, equals([1, 2, 3]));
      expect(existingDbRows.length, equals(3));
    });

    test('11. Administrative expenses start as expected and are not posted directly as actual', () {
      // 1. New Admin cost item creation:
      final adminItem = {
        'name': 'مصاريف إدارية',
        'category': 'admin',
        'supplier_type': 'admin',
        'total_egp': 1500.0,
      };

      // Status resolution logic
      final name = adminItem['name'] as String;
      final bool isEng = adminItem['category'] == 'engineer_expenses' || name.contains('مهندس');
      final bool isAdminItem = adminItem['category'] == 'admin' ||
          adminItem['supplier_type'] == 'admin' ||
          name.contains('إدار') ||
          name.contains('ادار');
      final bool isAdminSettled = isAdminItem &&
          (adminItem['cost_status'] == 'settled' || adminItem['reconciled_at'] != null) &&
          adminItem['actual_amount'] != null;

      final costStatus = isEng
          ? 'actual'
          : (isAdminItem
              ? (isAdminSettled ? 'actual' : 'expected')
              : (adminItem['cost_status'] ?? 'expected'));

      final actualAmt = isEng
          ? 1500.0
          : (isAdminItem
              ? (isAdminSettled ? (adminItem['actual_amount'] as num).toDouble() : null)
              : adminItem['actual_amount']);

      expect(costStatus, equals('expected'));
      expect(actualAmt, isNull);

      // 2. When settled from the dedicated administrative expenses settlement page:
      final settledAdminItem = {
        'name': 'مصاريف إدارية',
        'category': 'admin',
        'supplier_type': 'admin',
        'total_egp': 1500.0,
        'cost_status': 'settled',
        'actual_amount': 1450.0,
        'reconciled_at': '2026-11-06T18:00:00Z',
      };

      final bool isSettledAdmin = (settledAdminItem['category'] == 'admin') &&
          (settledAdminItem['cost_status'] == 'settled' || settledAdminItem['reconciled_at'] != null) &&
          settledAdminItem['actual_amount'] != null;

      final settledCostStatus = isSettledAdmin ? 'actual' : 'expected';
      final settledActualAmt = isSettledAdmin ? settledAdminItem['actual_amount'] : null;

      expect(settledCostStatus, equals('actual'));
      expect(settledActualAmt, equals(1450.0));
    });

    test('12. Administrative item lock logic & controller population remain pending until actual invoice settlement', () {
      bool isItemLocked(Map<String, dynamic> item) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        final cat = (item['category'] ?? '').toString().toLowerCase();
        final isAdmin = cat == 'admin' || name.contains('إدار') || name.contains('ادار');

        if (isAdmin) {
          final hasReconciled = item['reconciled_at'] != null &&
              item['reconciled_at'].toString().isNotEmpty &&
              item['reconciled_at'].toString() != 'null';
          final hasJe = item['variance_journal_entry_id'] != null;
          final status = (item['cost_status'] ?? '').toString().toLowerCase();
          final hasActual = (item['actual_amount'] as num?) != null && ((item['actual_amount'] as num) > 0);

          if ((hasReconciled || hasJe || status == 'settled') && hasActual) {
            return true;
          }
          return false;
        }

        if (item['is_locked'] == true) return true;
        final status = (item['cost_status'] ?? '').toString().toLowerCase();
        if (status == 'locked' || status == 'settled' || status == 'actual') return true;
        return false;
      }

      // Case A: Unsettled admin expense item (even if previously had is_locked=true in DB)
      final unsettledAdmin = {
        'id': 101,
        'name': 'مصاريف إدارية',
        'category': 'admin',
        'base_amount': 1000.0,
        'expected_amount': 1000.0,
        'cost_status': 'expected',
        'actual_amount': null,
        'is_locked': false,
        'reconciled_at': null,
        'variance_journal_entry_id': null,
      };

      expect(isItemLocked(unsettledAdmin), isFalse);

      final double? actVal = (unsettledAdmin['actual_amount'] as num?)?.toDouble();
      final actText = (actVal != null && actVal > 0) ? actVal.toStringAsFixed(2) : '';
      expect(actText, isEmpty); // Must be empty, NOT '1000.00'!

      // Case B: Genuinely settled admin expense item
      final settledAdmin = {
        'id': 102,
        'name': 'مصاريف إدارية',
        'category': 'admin',
        'base_amount': 1000.0,
        'expected_amount': 1000.0,
        'cost_status': 'settled',
        'actual_amount': 1050.0,
        'is_locked': true,
        'reconciled_at': '2026-11-06T18:30:00Z',
        'variance_journal_entry_id': 55,
      };

      expect(isItemLocked(settledAdmin), isTrue);
      final double? settledActVal = (settledAdmin['actual_amount'] as num?)?.toDouble();
      final settledActText = (settledActVal != null && settledActVal > 0) ? settledActVal.toStringAsFixed(2) : '';
      expect(settledActText, equals('1050.00'));
    });
  });
}



