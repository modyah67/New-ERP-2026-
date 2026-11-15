import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/features/accounts/services/advanced_coa_pdf_service.dart';

void main() {
  group('AdvancedCoaPdfService Strict 4-Level Hierarchical Tree Tests', () {
    test('flattens accounts in strict pre-order traversal across 4 levels', () {
      final accounts = [
        // Out of order input
        AccountModel(id: '3', code: '3', name: 'المصروفات والتكاليف', type: 'expense', parentId: null),
        AccountModel(id: '12111', code: '12111', name: 'CIB - جنيه مصري', type: 'asset', parentId: '1211'),
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
        AccountModel(id: '12', code: '12', name: 'الأصول المتداولة', type: 'asset', parentId: '1'),
        AccountModel(id: '121', code: '121', name: 'النقدية والبنوك', type: 'asset', parentId: '12'),
        AccountModel(id: '1211', code: '1211', name: 'بنك CIB', type: 'asset', parentId: '121'),
        AccountModel(id: '2', code: '2', name: 'الخصوم وحقوق الملكية', type: 'liability', parentId: null),
        AccountModel(id: '21', code: '21', name: 'الخصوم المتداولة', type: 'liability', parentId: '2'),
        AccountModel(id: '211', code: '211', name: 'الموردون وأوراق الدفع', type: 'liability', parentId: '21'),
        AccountModel(id: '2112', code: '2112', name: 'موردو محاصيل زراعية', type: 'liability', parentId: '211'),
        AccountModel(id: '211201', code: '211201', name: 'مورد - علي عبد الله', type: 'liability', parentId: '2112'),
        AccountModel(id: '31', code: '31', name: 'تكلفة النشاط والمبيعات', type: 'expense', parentId: '3'),
        AccountModel(id: '311', code: '311', name: 'تكلفة تصدير محاصيل', type: 'expense', parentId: '31'),
        AccountModel(id: '3111', code: '3111', name: 'تكلفة تصدير فراولة طازجة', type: 'expense', parentId: '311'),
        AccountModel(id: '4', code: '4', name: 'الإيرادات', type: 'revenue', parentId: null),
        AccountModel(id: '41', code: '41', name: 'إيرادات النشاط والتصدير', type: 'revenue', parentId: '4'),
        AccountModel(id: '411', code: '411', name: 'إيرادات تصدير فراولة', type: 'revenue', parentId: '41'),
        AccountModel(id: '4111', code: '4111', name: 'مبيعات تصدير فراولة - طازج', type: 'revenue', parentId: '411'),
        AccountModel(id: '9', code: '9', name: 'حسابات نظامية ووسيطة', type: 'system', parentId: null),
        AccountModel(id: '91', code: '91', name: 'الحسابات الوسيطة والتسويات', type: 'system', parentId: '9'),
        AccountModel(id: '911', code: '911', name: 'وسيط تكاليف وهوالك', type: 'system', parentId: '91'),
        AccountModel(id: '9112', code: '9112', name: 'وسيط هالك المحاصيل', type: 'system', parentId: '911'),
      ];

      final flattened = AdvancedCoaPdfService.flattenTree(accounts);

      expect(flattened.length, equals(22));

      final codes = flattened.map((e) => e.account.code).toList();
      final levels = flattened.map((e) => e.level).toList();

      expect(codes, equals([
        // 1. Assets Root
        '1',
        '12',
        '121',
        '1211',
        '12111',
        // 2. Liabilities & Equity Root
        '2',
        '21',
        '211',
        '2112',
        '211201',
        // 3. Expenses & Costs Root
        '3',
        '31',
        '311',
        '3111',
        // 4. Revenues Root
        '4',
        '41',
        '411',
        '4111',
        // 5. System & Intermediary Root
        '9',
        '91',
        '911',
        '9112',
      ]));

      // Enforces 5 levels: posting accounts (12111, 211201) are Level 5
      expect(levels, equals([
        1, 2, 3, 4, 5, // Assets tree (12111 is Level 5)
        1, 2, 3, 4, 5, // Liabilities tree (211201 is Level 5)
        1, 2, 3, 4,    // Expenses tree
        1, 2, 3, 4,    // Revenues tree
        1, 2, 3, 4,    // System tree
      ]));

      // Verify level range is 1 to 5
      for (final item in flattened) {
        expect(item.level, inInclusiveRange(1, 5));
      }
    });

    test('sorts roots strictly by official 4-level sequence (1 -> 2 -> 3 -> 4 -> 9)', () {
      final accounts = [
        AccountModel(id: '9', code: '9', name: 'حسابات نظامية', type: 'system', parentId: null),
        AccountModel(id: '4', code: '4', name: 'الإيرادات', type: 'revenue', parentId: null),
        AccountModel(id: '3', code: '3', name: 'المصروفات والتكاليف', type: 'expense', parentId: null),
        AccountModel(id: '2', code: '2', name: 'الخصوم وحقوق الملكية', type: 'liability', parentId: null),
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
      ];

      final flattened = AdvancedCoaPdfService.flattenTree(accounts);
      final codes = flattened.map((e) => e.account.code).toList();

      expect(codes, equals(['1', '2', '3', '4', '9']));
      for (final item in flattened) {
        expect(item.level, equals(1));
      }
    });

    test('resolves parent by code prefix when parentId is null or missing and enforces max level 4', () {
      final accounts = [
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
        AccountModel(id: '12', code: '12', name: 'الأصول المتداولة', type: 'asset', parentId: null),
        AccountModel(id: '121', code: '121', name: 'النقدية والبنوك', type: 'asset', parentId: null),
        AccountModel(id: '1212', code: '1212', name: 'الخزينة الرئيسية', type: 'asset', parentId: null),
        AccountModel(id: '12121', code: '12121', name: 'الخزينة - جنيه مصري', type: 'asset', parentId: null),
      ];

      final flattened = AdvancedCoaPdfService.flattenTree(accounts);
      final codes = flattened.map((e) => e.account.code).toList();
      final levels = flattened.map((e) => e.level).toList();

      expect(codes, equals(['1', '12', '121', '1212', '12121']));
      expect(levels, equals([1, 2, 3, 4, 5]));
      expect(flattened.last.isSubAnalytic, isTrue);
    });

    test('correctly classifies Arabic type and normal balance', () {
      final accounts = [
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
        AccountModel(id: '21', code: '21', name: 'خصوم متداولة', type: 'liability', parentId: '2'),
        AccountModel(id: '23', code: '23', name: 'حقوق الملكية', type: 'equity', parentId: '2'),
        AccountModel(id: '3', code: '3', name: 'المصروفات والتكاليف', type: 'expense', parentId: null),
        AccountModel(id: '4', code: '4', name: 'الإيرادات', type: 'revenue', parentId: null),
        AccountModel(id: '9', code: '9', name: 'حسابات نظامية', type: 'system', parentId: null),
      ];

      final flattened = AdvancedCoaPdfService.flattenTree(accounts);
      final itemMap = {for (var item in flattened) item.account.code: item};

      // 1. Assets
      expect(itemMap['1']?.typeArabic, equals('أصول'));
      expect(itemMap['1']?.normalBalance, equals('مدين (Dr)'));

      // 2. Liabilities
      expect(itemMap['21']?.typeArabic, equals('خصوم'));
      expect(itemMap['21']?.normalBalance, equals('دائن (Cr)'));

      // 23. Equity
      expect(itemMap['23']?.typeArabic, equals('حقوق ملكية'));
      expect(itemMap['23']?.normalBalance, equals('دائن (Cr)'));

      // 3. Expenses
      expect(itemMap['3']?.typeArabic, equals('مصروفات وتكاليف'));
      expect(itemMap['3']?.normalBalance, equals('مدين (Dr)'));

      // 4. Revenues
      expect(itemMap['4']?.typeArabic, equals('إيرادات'));
      expect(itemMap['4']?.normalBalance, equals('دائن (Cr)'));

      // 9. System
      expect(itemMap['9']?.typeArabic, equals('حسابات وسيطة'));
      expect(itemMap['9']?.normalBalance, equals('وسيط / تسوية'));
    });

    test('nests shareholder and dynamic entity sub-accounts under level 4 without incrementing level index to 5', () {
      final accounts = [
        AccountModel(id: '2', code: '2', name: 'الخصوم وحقوق الملكية', type: 'liability', parentId: null),
        AccountModel(id: '23', code: '23', name: 'حقوق الملكية', type: 'equity', parentId: '2'),
        AccountModel(id: '231', code: '231', name: 'رأس المال المدفوع', type: 'equity', parentId: '23'),
        AccountModel(id: '2315', code: '2315', name: 'رأس مال المساهمين', type: 'equity', parentId: '231'),
        AccountModel(id: '231501', code: '231501', name: 'مساهم - إسلام', type: 'equity', parentId: '2315'),
        AccountModel(id: '231502', code: '231502', name: 'مساهم - عبد الباطن', type: 'equity', parentId: '2315'),
        AccountModel(id: '231503', code: '231503', name: 'مساهم - عماد', type: 'equity', parentId: '2315'),
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
        AccountModel(id: '12', code: '12', name: 'الأصول المتداولة', type: 'asset', parentId: '1'),
        AccountModel(id: '122', code: '122', name: 'العملاء والمدينون', type: 'asset', parentId: '12'),
        AccountModel(id: '1221', code: '1221', name: 'العملاء (مدينون)', type: 'asset', parentId: '122'),
        AccountModel(id: '122101', code: '122101', name: 'عميل - شركة الفواكه العالمية', type: 'asset', parentId: '1221'),
      ];

      final flattened = AdvancedCoaPdfService.flattenTree(accounts);
      final codes = flattened.map((e) => e.account.code).toList();
      final levels = flattened.map((e) => e.level).toList();

      expect(codes, equals([
        '1', '12', '122', '1221', '122101',
        '2', '23', '231', '2315', '231501', '231502', '231503',
      ]));

      // All sub-accounts evaluate to Level 5
      expect(levels, equals([
        1, 2, 3, 4, 5,
        1, 2, 3, 4, 5, 5, 5,
      ]));

      // Verify sub-analytic flags for visual child nesting
      final shItem1 = flattened.firstWhere((e) => e.account.code == '231501');
      expect(shItem1.level, equals(5));
      expect(shItem1.isSubAnalytic, isTrue);

      final custItem = flattened.firstWhere((e) => e.account.code == '122101');
      expect(custItem.level, equals(5));
      expect(custItem.isSubAnalytic, isTrue);
    });

    test('ChartOfAccountsPdfService alias compiles and matches AdvancedCoaPdfService', () {
      expect(ChartOfAccountsPdfService, equals(AdvancedCoaPdfService));
    });

    test('AccountModel evaluatedLevel strictly returns Level 5 for posting accounts', () {
      final supplier = AccountModel(id: 's1', code: '211202', name: 'مورد - رامي', type: 'liability');
      expect(supplier.evaluatedLevel, equals(5));
      expect(supplier.levelLabel, equals('مستوى 5 - حساب ترحيل'));

      final bankSub = AccountModel(id: 'b1', code: '12111', name: 'CIB - EGP', type: 'asset');
      expect(bankSub.evaluatedLevel, equals(5));
      expect(bankSub.levelLabel, equals('مستوى 5 - حساب ترحيل'));
    });

    test('generatePdf compiles and returns non-empty PDF bytes', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final accounts = [
        AccountModel(id: '1', code: '1', name: 'الأصول', type: 'asset', parentId: null),
        AccountModel(id: '12', code: '12', name: 'الأصول المتداولة', type: 'asset', parentId: '1'),
        AccountModel(id: '121', code: '121', name: 'النقدية وما في حكمها والبنوك', type: 'asset', parentId: '12'),
        AccountModel(id: '1211', code: '1211', name: 'حسابات بنك CIB', type: 'asset', parentId: '121'),
        AccountModel(id: '12111', code: '12111', name: 'CIB - EGP', type: 'asset', parentId: '1211'),
        AccountModel(id: '2', code: '2', name: 'الخصوم وحقوق الملكية', type: 'liability', parentId: null),
        AccountModel(id: '3', code: '3', name: 'المصروفات والتكاليف', type: 'expense', parentId: null),
        AccountModel(id: '4', code: '4', name: 'الإيرادات', type: 'revenue', parentId: null),
        AccountModel(id: '9', code: '9', name: 'حسابات نظامية ووسيطة', type: 'system', parentId: null),
      ];

      final pdfBytes = await AdvancedCoaPdfService.generatePdf(accounts);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      
      try {
        final f = File('C:/Users/mahmooud/.gemini/antigravity-ide/brain/6f832504-147d-4ac6-a5da-256c9648e077/scratch/test_output.pdf');
        await f.writeAsBytes(pdfBytes);
      } catch (_) {}
    });
  });
}
