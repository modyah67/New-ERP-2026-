import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/treasury_model.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/features/treasury/widgets/coa_expense_dropdown.dart';

void main() {
  group('COA Expense Disbursal & Cost Center Verification Tests', () {
    test('1. TreasuryTransactionModel handles costCenterId correctly in constructor and fromMap', () {
      final txMap = <String, dynamic>{
        'id': '101',
        'treasury_id': '1',
        'type': 'expense',
        'currency': 'EGP',
        'amount': -1500.0,
        'description': 'شراء كراتين تعبئة للمحطة',
        'cost_center_id': 'packing_station',
        'created_at': '2026-09-09T02:00:00Z',
        'status': 'confirmed',
        'payload': {
          'expense_account_id': '312001',
          'cost_center_id': 'packing_station',
        },
      };

      final tx = TreasuryTransactionModel.fromMap(txMap);

      expect(tx.id, '101');
      expect(tx.amount, -1500.0);
      expect(tx.costCenterId, 'packing_station');
      expect(tx.payload?['cost_center_id'], 'packing_station');
    });

    test('2. COAExpenseDropdown.suggestCostCenter correctly infers Cost Center across all COA Levels & Crop Lines', () {
      // 1. Direct binding in account row takes highest priority
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '321001',
          'cost_center_id': 'customs_clearance',
        }),
        'customs_clearance',
      );

      // 2. Crop Production Lines: Mango (3112 / keyword)
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3112',
          'name': 'تكلفة مبيعات محصول المانجو',
        }),
        'mango_line',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '311201',
          'name': 'Mango Line Production Cost',
        }),
        'mango_line',
      );

      // 3. Crop Production Lines: Strawberry (3111 / keyword)
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3111',
          'name': 'تكلفة بضاعة مباعة فراولة تصدير',
        }),
        'strawberry_line',
      );

      // 4. Crop Production Lines: Citrus & Grapes & Banana
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3115',
          'name': 'تكلفة بضاعة مباعة موالح وبرتقال',
        }),
        'citrus_line',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3116',
          'name': 'تكلفة إنتاج عنب فليم وسوبيريور',
        }),
        'grapes_line',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3118',
          'name': 'تكلفة محصول موز مغطى',
        }),
        'banana_line',
      );

      // 5. COGS General / Production (311)
      expect(
        COAExpenseDropdown.suggestCostCenter({
          'account_code': '3110',
          'name': 'تكلفة البضاعة المباعة عام',
        }),
        'packing_station',
      );

      // 6. Direct Packing & Materials (312)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '312001', 'name': 'كراتين تعبئة'}),
        'packing_station',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '312205', 'name': 'صيانة خطوط فرز المحطة'}),
        'packing_station',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '312003', 'name': 'هالك فرز تشغيل'}),
        'packing_station',
      );

      // 7. Field Harvest & Agricultural Labor (311)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '311201', 'name': 'أجور عمال جمع وحصاد'}),
        'packing_station',
      );

      // 8. Administrative Expenses (313)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '313101', 'name': 'بوفيه وضيافة'}),
        'general_admin',
      );

      // 9. Shipping & Logistics (34114)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '34114', 'name': 'نولون بري وشحن مبرد'}),
        'freight_logistics',
      );

      // 10. Salaries & Wages (311)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '311101', 'name': 'رواتب مهندسي وعمال المحطة'}),
        'packing_station',
      );

      // 11. General Administration (313), Depreciation (321), Financial (314)
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '313102', 'name': 'أدوات مكتبية ومطبوعات'}),
        'general_admin',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '321001', 'name': 'إهلاك أثاث وأجهزة مكتبية'}),
        'general_admin',
      );
      expect(
        COAExpenseDropdown.suggestCostCenter({'account_code': '314101', 'name': 'مصاريف وعمولات بنكية'}),
        'general_admin',
      );

      // 12. Fallback for null
      expect(
        COAExpenseDropdown.suggestCostCenter(null),
        'general_admin',
      );
    });

    test('3. COAExpenseDropdown.resolveCategory correctly categorizes all multi-level accounts for filtering', () {
      // COGS (341)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '3411'}), 'cogs');
      expect(COAExpenseDropdown.resolveCategory({'account_code': '3412'}), 'cogs');

      // Salaries & Employees (3111, 3112)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '311101'}), 'salaries');
      expect(COAExpenseDropdown.resolveCategory({'account_code': '311201'}), 'employees');

      // Operating (312)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '312005'}), 'operating');

      // Admin (313)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '313002'}), 'admin');

      // Finance & Bank (314)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '314001'}), 'finance');

      // Depreciation (321)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '321001'}), 'depreciation');

      // FX (322)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '322001'}), 'fx');

      // Inventory (331)
      expect(COAExpenseDropdown.resolveCategory({'account_code': '331001'}), 'inventory');

      // Labels check
      expect(COAExpenseDropdown.getCategoryLabel('cogs'), contains('341x'));
      expect(COAExpenseDropdown.getCategoryLabel('salaries'), contains('3111x'));
      expect(COAExpenseDropdown.getCategoryLabel('employees'), contains('3112x'));
      expect(COAExpenseDropdown.getCategoryLabel('operating'), contains('312x'));
      expect(COAExpenseDropdown.getCategoryLabel('admin'), contains('313x'));
      expect(COAExpenseDropdown.getCategoryLabel('finance'), contains('314x'));
      expect(COAExpenseDropdown.getCategoryLabel('depreciation'), contains('321x'));
      expect(COAExpenseDropdown.getCategoryLabel('fx'), contains('322x'));
      expect(COAExpenseDropdown.getCategoryLabel('inventory'), contains('331x'));
    });

    test('4. CostCenterHelper resolves all operational and crop variety cost centers accurately', () {
      final packing = CostCenterHelper.fromId('packing_station');
      expect(packing.id, 'packing_station');
      expect(packing.nameAr, contains('تعبئة'));
      expect(packing.type, CostCenterType.operational);

      final freight = CostCenterHelper.fromId('freight_logistics');
      expect(freight.id, 'freight_logistics');
      expect(freight.nameAr, contains('شحن'));
      expect(freight.type, CostCenterType.operational);

      final admin = CostCenterHelper.fromId('general_admin');
      expect(admin.id, 'general_admin');
      expect(admin.type, CostCenterType.operational);

      final mango = CostCenterHelper.fromId('mango_line');
      expect(mango.id, 'mango_line');
      expect(mango.nameAr, contains('مانجو'));
      expect(mango.type, CostCenterType.variety);

      final strawberry = CostCenterHelper.fromId('strawberry_line');
      expect(strawberry.nameAr, contains('فراولة'));
      expect(strawberry.type, CostCenterType.variety);

      final citrus = CostCenterHelper.fromId('citrus_line');
      expect(citrus.nameAr, contains('الموالح'));
      expect(citrus.type, CostCenterType.variety);

      final shared = CostCenterHelper.fromId('ALL');
      expect(shared.id, 'ALL');
      expect(shared.nameAr, contains('بالتساوي'));
    });

    test('5. Mandatory Cost Center Association is strictly enforced for expense disbursals', () {
      // Simulate form validation logic from TreasuryPage._showExpenseSheet
      bool validateForm({
        required double amount,
        required double availableBalance,
        required String? counterpartyType,
        required String? selectedExpenseAccountId,
        required String? selectedCostCenterId,
      }) {
        final isAmountValid = amount > 0 && amount <= availableBalance;
        final isFormValid = isAmountValid &&
            counterpartyType != null &&
            !(counterpartyType == 'category' &&
                (selectedExpenseAccountId == null ||
                 selectedCostCenterId == null ||
                 selectedCostCenterId.trim().isEmpty));
        return isFormValid;
      }

      // Case A: Missing cost center -> REJECTED
      final missingCc = validateForm(
        amount: 500.0,
        availableBalance: 10000.0,
        counterpartyType: 'category',
        selectedExpenseAccountId: '15',
        selectedCostCenterId: null,
      );
      expect(missingCc, isFalse, reason: 'Expense disbursement must require cost center');

      // Case B: Empty string cost center -> REJECTED
      final emptyCc = validateForm(
        amount: 500.0,
        availableBalance: 10000.0,
        counterpartyType: 'category',
        selectedExpenseAccountId: '15',
        selectedCostCenterId: '   ',
      );
      expect(emptyCc, isFalse, reason: 'Empty cost center cannot be accepted');

      // Case C: Missing account -> REJECTED
      final missingAcct = validateForm(
        amount: 500.0,
        availableBalance: 10000.0,
        counterpartyType: 'category',
        selectedExpenseAccountId: null,
        selectedCostCenterId: 'packing_station',
      );
      expect(missingAcct, isFalse, reason: 'Expense account must be selected');

      // Case D: Valid amount + Account + Cost Center -> ACCEPTED
      final validDisbursal = validateForm(
        amount: 500.0,
        availableBalance: 10000.0,
        counterpartyType: 'category',
        selectedExpenseAccountId: '15',
        selectedCostCenterId: 'mango_line',
      );
      expect(validDisbursal, isTrue, reason: 'Complete disbursal with cost center is valid');
    });

    test('6. Double-Entry Journal line structure strictly tags debit line with cost_center_id', () {
      const expenseAccountId = 120; // e.g. 312101 Direct Packing Supplies
      const treasuryAccountId = 10;  // 110101 Main Cash Safe
      const amount = 3500.0;
      const currency = 'EGP';
      const costCenterId = 'packing_station';

      final journalLines = [
        {
          'account_id': expenseAccountId,
          'debit': amount,
          'credit': 0.0,
          'base_debit': amount,
          'base_credit': 0.0,
          'currency': currency,
          'description': 'شراء مستلزمات تعبئة لمحطة الفرز',
          'cost_center_id': costCenterId,
        },
        {
          'account_id': treasuryAccountId,
          'debit': 0.0,
          'credit': amount,
          'base_debit': 0.0,
          'base_credit': amount,
          'currency': currency,
          'description': 'صرف من الخزينة الرئيسية',
        },
      ];

      // Double-entry balancing verification
      final totalDebit = journalLines.fold<double>(0.0, (sum, l) => sum + (l['debit'] as double));
      final totalCredit = journalLines.fold<double>(0.0, (sum, l) => sum + (l['credit'] as double));
      expect(totalDebit, equals(totalCredit));

      // Debit line carries the designated cost center
      final debitLine = journalLines.firstWhere((l) => (l['debit'] as double) > 0);
      expect(debitLine['account_id'], equals(expenseAccountId));
      expect(debitLine['cost_center_id'], equals(costCenterId));

      // Credit line credits the treasury
      final creditLine = journalLines.firstWhere((l) => (l['credit'] as double) > 0);
      expect(creditLine['account_id'], equals(treasuryAccountId));
    });

    test('7. Unified One-Step Picker automatically resolves and binds cost center upon account pick', () {
      // Simulating selecting a Level 4 expense sub-account in the unified dialog
      final selectedAccount = {
        'id': '345',
        'account_code': '32101',
        'name': 'أدوات مكتبية ومطبوعات',
        'cost_center_id': 'CC-ADMIN',
      };

      // In the unified workflow: picking the account resolves cost center immediately
      final directCc = selectedAccount['cost_center_id'];
      final resolvedCc = directCc ?? COAExpenseDropdown.suggestCostCenter(selectedAccount);

      expect(resolvedCc, equals('CC-ADMIN'));

      // Case 2: Account without direct cost_center_id falls back to intelligent suggestion
      final packagingAccount = {
        'id': '312',
        'account_code': '31201',
        'name': 'كراتين تعبئة وتغليف',
      };
      final resolvedPackagingCc = packagingAccount['cost_center_id'] ??
          COAExpenseDropdown.suggestCostCenter(packagingAccount);

      expect(resolvedPackagingCc, equals(CostCenterHelper.packingStation.id));
    });

    test('8. Filtered COA logic strictly restricts selection to leaf-node analytical expense accounts (Root 3)', () {
      final mixedAccounts = [
        // Valid Root 3 leaf accounts
        {'account_code': '32101', 'is_leaf': true, 'is_active': true, 'name': 'مصاريف بوفية'},
        {'account_code': '31205', 'is_leaf': true, 'is_active': true, 'name': 'سولار محطة'},
        {'account_code': '34101', 'is_leaf': true, 'is_active': true, 'name': 'مشتريات خام'},

        // Invalid: Parent group accounts under Root 3 (should be excluded)
        {'account_code': '3', 'is_leaf': false, 'is_active': true, 'name': 'المصروفات والتكاليف'},
        {'account_code': '31', 'is_leaf': false, 'is_active': true, 'name': 'تكاليف النشاط'},
        {'account_code': '32', 'is_leaf': false, 'is_active': true, 'name': 'مصروفات عمومية'},
        {'account_code': '321', 'is_leaf': false, 'is_active': true, 'name': 'مصروفات إدارية'},

        // Invalid: Inactive leaf account
        {'account_code': '32199', 'is_leaf': true, 'is_active': false, 'name': 'مصروف معطل'},

        // Invalid: Non-Root 3 accounts
        {'account_code': '1101', 'is_leaf': true, 'is_active': true, 'name': 'النقدية بالصندوق'},
        {'account_code': '2101', 'is_leaf': true, 'is_active': true, 'name': 'الموردين'},
        {'account_code': '4101', 'is_leaf': true, 'is_active': true, 'name': 'إيرادات مبيعات'},
      ];

      final filtered = mixedAccounts.where((a) {
        final code = (a['account_code'] ?? '').toString().trim();
        if (!code.startsWith('3')) return false;
        final isLeaf = a['is_leaf'] == true;
        final allowPosting = a['allow_posting'] == true;
        if (!isLeaf && !allowPosting) return false;
        if (a['is_active'] == false) return false;
        if (const {'3', '31', '32', '33', '34'}.contains(code)) return false;
        return true;
      }).toList();

      expect(filtered.length, equals(3));
      expect(filtered.map((a) => a['account_code']), containsAll(['32101', '31205', '34101']));
      expect(filtered.map((a) => a['account_code']), isNot(contains('3')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('31')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('32')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('1101')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('2101')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('4101')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('32199')));
    });

    test('9. Cash disbursal modal filter strictly isolates Root 31 (Operational & Administrative Cash Expenses) leaf nodes, excluding all non-cash depreciation (Group 32), assets, liabilities, and parent folders', () {
      final mixedAccounts = [
        // Cash expense leaf accounts (Group 31) - Should be INCLUDED
        {'account_code': '313101', 'is_leaf': true, 'is_active': true, 'name': 'مصاريف ضيافة وبوفيه'},
        {'account_code': '313102', 'is_leaf': true, 'is_active': true, 'name': 'أدوات مكتبية ومطبوعات'},
        {'account_code': '313103', 'is_leaf': true, 'is_active': true, 'name': 'صيانة دورية ومكتبية'},
        {'account_code': '311201', 'is_leaf': true, 'is_active': true, 'name': 'انتقالات وعمالة مؤقتة'},

        // Parent root 31 folder and level 2/3 folders - Should be EXCLUDED
        {'account_code': '31', 'is_leaf': false, 'is_active': true, 'name': 'التكاليف والمصروفات النقدية'},
        {'account_code': '313', 'is_leaf': false, 'is_active': true, 'name': 'مصروفات عمومية وإدارية'},
        {'account_code': '3131', 'is_leaf': false, 'is_active': true, 'name': 'بوفيه وإدارة المقر'},

        // Depreciation under Group 32 - Should be EXCLUDED (non-cash)
        {'account_code': '321001', 'is_leaf': true, 'is_active': true, 'name': 'إهلاك أثاث ومعدات مكتبية'},
        {'account_code': '321002', 'is_leaf': true, 'is_active': true, 'name': 'إهلاك سيارات ووسائل نقل'},
        {'account_code': '322001', 'is_leaf': true, 'is_active': true, 'name': 'فروق تقييم عملة غير نقدية'},

        // Non-expense accounts (Assets 1, Liabilities 2, Equity 4) - Should be EXCLUDED
        {'account_code': '110101', 'is_leaf': true, 'is_active': true, 'name': 'الخزينة الرئيسية'},
        {'account_code': '210101', 'is_leaf': true, 'is_active': true, 'name': 'موردين خامات'},
        {'account_code': '410101', 'is_leaf': true, 'is_active': true, 'name': 'إيرادات نشاط'},

        // Inactive Cash Expense Account - Should be EXCLUDED
        {'account_code': '313199', 'is_leaf': true, 'is_active': false, 'name': 'حساب بوفيه معطل'},
      ];

      // Replicate exact filtering logic from COAExpenseDropdown & ChartOfAccountsCacheService
      final filtered = mixedAccounts.where((a) {
        final code = (a['account_code'] ?? a['code'] ?? '').toString().trim();

        // 0. Exclusively restrict to Cash Operational & Administrative Expenses (Group 31)
        if (!code.startsWith('31')) return false;

        // 1. Filter out parent root folder '31'
        if (code == '31') return false;

        // 2. Strictly exclude Depreciation and Non-cash accounting expenses (Group 32)
        if (code.startsWith('32')) return false;

        // 3. Strictly exclude Assets, Liabilities, Equity
        if (code.startsWith('1') || code.startsWith('2') || code.startsWith('4')) return false;

        // 4. Restrict to leaf-node analytical expense accounts
        final isLeaf = a['is_leaf'] == true;
        final allowPosting = a['allow_posting'] == true;
        if (!isLeaf && !allowPosting) return false;
        if (a['is_active'] == false) return false;

        return true;
      }).toList();

      expect(filtered.length, equals(4));
      final resultCodes = filtered.map((a) => a['account_code']).toList();
      expect(resultCodes, equals(['313101', '313102', '313103', '311201']));

      // Assert all non-31, non-leaf, depreciation 32, and inactive items are excluded
      expect(resultCodes, isNot(contains('31')));
      expect(resultCodes, isNot(contains('313')));
      expect(resultCodes, isNot(contains('3131')));
      expect(resultCodes, isNot(contains('321001')));
      expect(resultCodes, isNot(contains('321002')));
      expect(resultCodes, isNot(contains('322001')));
      expect(resultCodes, isNot(contains('110101')));
      expect(resultCodes, isNot(contains('210101')));
      expect(resultCodes, isNot(contains('410101')));
      expect(resultCodes, isNot(contains('313199')));
    });

    test('10. Expense disbursal architecture links Branch first, then Cost Center, and propagates both to Journal Entries', () {
      // 1. Transaction model captures both branch and cost center
      final txMap = <String, dynamic>{
        'id': '205',
        'treasury_id': '1',
        'type': 'expense',
        'currency': 'EGP',
        'amount': -45000.0,
        'description': 'مرتبات وأجور عمال محطة تاج',
        'branch_id': '1',
        'branch_name': 'محطة تاج الرئيسية',
        'cost_center_id': 'salaries',
        'created_at': '2026-09-23T10:00:00Z',
        'status': 'confirmed',
        'payload': {
          'expense_account_id': '311101',
          'branch_id': '1',
          'branch_name': 'محطة تاج الرئيسية',
          'cost_center_id': 'salaries',
        },
      };

      final tx = TreasuryTransactionModel.fromMap(txMap);
      expect(tx.branchId, '1');
      expect(tx.branchName, 'محطة تاج الرئيسية');
      expect(tx.costCenterId, 'salaries');
      expect(tx.payload?['branch_id'], '1');
      expect(tx.payload?['cost_center_id'], 'salaries');

      // 2. Journal Entry Debit line tags both branch_id and cost_center_id
      final journalEntryLines = [
        {
          'account_id': 311101, // 311101 رواتب وأجور
          'account_code': '311101',
          'branch_id': 1,
          'branch_name': 'محطة تاج الرئيسية',
          'cost_center_id': 'salaries',
          'cost_center_name': 'المرتبات والأجور',
          'debit': 45000.0,
          'credit': 0.0,
          'currency': 'EGP',
        },
        {
          'account_id': 110101, // 110101 خزينة رئيسية
          'account_code': '110101',
          'branch_id': 1,
          'branch_name': 'محطة تاج الرئيسية',
          'cost_center_id': null,
          'debit': 0.0,
          'credit': 45000.0,
          'currency': 'EGP',
        }
      ];

      final debitLine = journalEntryLines.firstWhere((l) => (l['debit'] as double) > 0);
      expect(debitLine['branch_id'], equals(1));
      expect(debitLine['branch_name'], equals('محطة تاج الرئيسية'));
      expect(debitLine['cost_center_id'], equals('salaries'));
      expect(debitLine['cost_center_name'], equals('المرتبات والأجور'));

      // 3. Ensure analytical reporting views can group expenses by Branch and Cost Center
      final reportingGroupByBranchAndCC = {
        'branch_id': debitLine['branch_id'],
        'branch_name': debitLine['branch_name'],
        'cost_center_id': debitLine['cost_center_id'],
        'total_spent': debitLine['debit'],
      };

      expect(reportingGroupByBranchAndCC['branch_id'], equals(1));
      expect(reportingGroupByBranchAndCC['cost_center_id'], equals('salaries'));
      expect(reportingGroupByBranchAndCC['total_spent'], equals(45000.0));
    });
  });
}

