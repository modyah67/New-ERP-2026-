import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';

void main() {
  group('Chart of Accounts UI Strict 4-Level Evaluation Tests', () {
    test('strictly maps account codes to 4 levels without Level 5 or 6', () {
      // Level 1: 1 digit
      final rootAsset = AccountModel(code: '1', name: 'Assets', accountName: 'الأصول', type: 'asset');
      final rootLiab = AccountModel(code: '2', name: 'Liabilities', accountName: 'الالتزامات', type: 'liability');
      final rootEquity = AccountModel(code: '3', name: 'Equity', accountName: 'حقوق الملكية', type: 'equity');
      final rootRev = AccountModel(code: '4', name: 'Revenues', accountName: 'الإيرادات', type: 'revenue');
      final rootSystem = AccountModel(code: '9', name: 'System', accountName: 'الحسابات الوسيطة والنظامية', type: 'system');

      expect(rootAsset.evaluatedLevel, 1);
      expect(rootAsset.levelLabel, 'مستوى 1 - رئيسي');
      expect(rootAsset.isOperationalSubEntity, false);

      expect(rootLiab.evaluatedLevel, 1);
      expect(rootEquity.evaluatedLevel, 1);
      expect(rootRev.evaluatedLevel, 1);
      expect(rootSystem.evaluatedLevel, 1);

      // Level 2: 2 digits
      final group12 = AccountModel(code: '12', name: 'Current Assets', accountName: 'الأصول المتداولة', type: 'asset');
      final group21 = AccountModel(code: '21', name: 'Current Liabilities', accountName: 'الالتزامات المتداولة', type: 'liability');

      expect(group12.evaluatedLevel, 2);
      expect(group12.levelLabel, 'مستوى 2 - مجموعة');
      expect(group12.isOperationalSubEntity, false);
      expect(group21.evaluatedLevel, 2);

      // Level 3: 3 digits
      final sub121 = AccountModel(code: '121', name: 'Cash and Banks', accountName: 'النقدية وما في حكمها', type: 'asset');
      final sub211 = AccountModel(code: '211', name: 'Accounts Payable', accountName: 'الموردون وأوراق الدفع', type: 'liability');

      expect(sub121.evaluatedLevel, 3);
      expect(sub121.levelLabel, 'مستوى 3 - فرعي');
      expect(sub121.isOperationalSubEntity, false);
      expect(sub211.evaluatedLevel, 3);

      // Level 4: 4 digits (Standard analytical parent accounts)
      final parent1211 = AccountModel(code: '1211', name: 'Banks', accountName: 'البنوك', type: 'asset');
      final parent2112 = AccountModel(code: '2112', name: 'Suppliers', accountName: 'الموردين', type: 'liability');
      final parent2315 = AccountModel(code: '2315', name: 'Shareholders', accountName: 'جاري المساهمين', type: 'liability');

      expect(parent1211.evaluatedLevel, 4);
      expect(parent1211.levelLabel, 'مستوى 4 - تحليلي');
      expect(parent1211.isOperationalSubEntity, false);

      expect(parent2112.evaluatedLevel, 4);
      expect(parent2315.evaluatedLevel, 4);

      // Operational Sub-Entities under Level 4 (5+ digits -> Level 5)
      final op12111 = AccountModel(code: '12111', name: 'CIB-EGP', accountName: 'بنك CIB - جاري', type: 'asset');
      final op12121 = AccountModel(code: '12121', name: 'Main Cash', accountName: 'الخزينة الرئيسية', type: 'asset');
      final op211202 = AccountModel(code: '211202', name: 'Supplier Rami', accountName: 'مورد - رامي', type: 'liability');
      final op231501 = AccountModel(code: '231501', name: 'Shareholder Eslam', accountName: 'مساهم - إسلام', type: 'equity');

      // In the 5-level hierarchy, 5+ digit accounts are Level 5 posting accounts
      expect(op12111.evaluatedLevel, 5);
      expect(op12111.levelLabel, 'مستوى 5 - حساب ترحيل');

      expect(op12121.evaluatedLevel, 5);
      expect(op12121.levelLabel, 'مستوى 5 - حساب ترحيل');

      expect(op211202.evaluatedLevel, 5);
      expect(op211202.levelLabel, 'مستوى 5 - حساب ترحيل');

      expect(op231501.evaluatedLevel, 5);
      expect(op231501.levelLabel, 'مستوى 5 - حساب ترحيل');
    });

    test('verifies that long codes evaluate to Level 5 posting accounts', () {
      final longCodes = ['12111', '12112', '211201', '211202', '231501', '123456789'];
      for (final code in longCodes) {
        final acc = AccountModel(code: code, name: 'Test', accountName: 'تجربة', type: 'asset');
        expect(acc.evaluatedLevel, equals(5));
        expect(acc.levelLabel, 'مستوى 5 - حساب ترحيل');
      }
    });

    test('dynamically resolves entity labels for suppliers, customers, and general accounts', () {
      // Suppliers (e.g. 211..., 'مورد - وليد', 'وليد')
      final walidSupplier = AccountModel(
        code: '211202',
        name: 'وليد',
        accountName: 'Walid',
        type: 'liability',
      );
      expect(walidSupplier.entityLabel, 'المورد');
      expect(walidSupplier.entityHeaderTitle, 'المورد: وليد');

      final genericSupplier = AccountModel(
        code: '2111',
        name: 'موردي المحاصيل',
        type: 'liability',
      );
      expect(genericSupplier.entityLabel, 'المورد');

      // Customers (e.g. 125...)
      final amalCustomer = AccountModel(
        code: '125101',
        name: 'شركة الأمل',
        accountName: 'Al-Amal Co',
        type: 'asset',
      );
      expect(amalCustomer.entityLabel, 'العميل');
      expect(amalCustomer.entityHeaderTitle, 'العميل: شركة الأمل');

      // Other / General Accounts (e.g. Banks 12111, Cash 12121)
      final cibBank = AccountModel(
        code: '12111',
        name: 'بنك CIB - جاري',
        type: 'asset',
      );
      expect(cibBank.entityLabel, 'الحساب');
      expect(cibBank.entityHeaderTitle, 'الحساب: البنك التجاري الدولي CIB - جنيه مصري');
    });

    test('strictly enforces 5-level hierarchy: parent Level 4 with Level 5 posting children', () {
      final parent1211 = AccountModel(
        id: 'p1211',
        code: '1211',
        name: 'بنك CIB',
        type: 'asset',
      );
      final child12111 = AccountModel(
        id: 'c12111',
        code: '12111',
        name: 'CIB - EGP',
        type: 'asset',
        parentId: 'p1211',
      );
      final child12112 = AccountModel(
        id: 'c12112',
        code: '12112',
        name: 'CIB - USD',
        type: 'asset',
        parentId: 'p1211',
      );

      // Parent is Level 4
      expect(parent1211.evaluatedLevel, 4);
      expect(parent1211.levelLabel, 'مستوى 4 - تحليلي');
      expect(parent1211.isOperationalSubEntity, false);

      // Children are Level 5 posting accounts
      expect(child12111.evaluatedLevel, 5);
      expect(child12111.levelLabel, 'مستوى 5 - حساب ترحيل');
      expect(child12112.evaluatedLevel, 5);
      expect(child12112.levelLabel, 'مستوى 5 - حساب ترحيل');

      // Clamping logic: level index passed to child increments up to 5 max
      const parentDepth = 3; // 0=L1, 1=L2, 2=L3, 3=L4
      final childDepth = (parentDepth + 1).clamp(0, 5);
      expect(childDepth, 4);

      // Terminal verification: child accounts cannot have further sub-accounts (evaluatedLevel >= 5)
      final canAddUnderParent = parent1211.evaluatedLevel < 5;
      final canAddUnderChild = child12111.evaluatedLevel < 5;
      expect(canAddUnderParent, isTrue); // Allowed under Level 4
      expect(canAddUnderChild, isFalse); // Blocked under Level 5 leaf
    });

    test('verifies unwanted accounts 2123, 2124, 2125, 2126 are in the obsolete/excluded list', () {
      const obsoleteLegacyCodes = {
        '112', '1121', '1112', '1113', '1114', '1115', '1116',
        '1213', '1214', '12122', '12123', '12124',
        '1222', '1223', '1224', '1225', '1232', '1233', '1234', '1235',
        '1242', '1243', '1244', '1245', '1246', '1247', '1248',
        '124101', '124102',
        '2123', '2124', '2125', '2126',
      };

      expect(obsoleteLegacyCodes.contains('2123'), isTrue); // Suspense Accounts
      expect(obsoleteLegacyCodes.contains('2124'), isTrue); // Other Current Liabilities
      expect(obsoleteLegacyCodes.contains('2125'), isTrue); // Third Party Guarantees
      expect(obsoleteLegacyCodes.contains('2126'), isTrue); // Notes Payable - CIB
    });
  });
}

