import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/data/services/cost_category_service.dart';
import 'package:accounting_system/features/treasury/widgets/coa_expense_dropdown.dart';

void main() {
  group('Cost Category COA & Cost Center Sync Tests', () {
    test('resolveParentAccountCode maps packing waste keywords to Root 313', () {
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'packing_waste',
          name: 'هالك تعبئة المحطة',
        ),
        equals('313'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'all',
          name: 'توالف وكسر كراتين',
        ),
        equals('313'),
      );
    });

    test('resolveParentAccountCode maps crops and raw materials to Root 341', () {
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'all',
          name: 'تكلفة المحاصيل',
        ),
        equals('341'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'packing',
          name: 'شراء خام فراولة تصدير',
        ),
        equals('341'),
      );
    });

    test('resolveParentAccountCode maps freight, customs, and shipping to Root 322', () {
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'shipment',
          name: 'تكلفة شركات الشحن',
        ),
        equals('322'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'shipment',
          name: 'تكلفة المخلصين الجمركيين',
        ),
        equals('322'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'both',
          name: 'لوجستيك ونقل شحنات',
        ),
        equals('322'),
      );
    });

    test('resolveParentAccountCode maps packing materials and labor to Root 312', () {
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'packing',
          name: 'مواد التعبئة والتغليف',
        ),
        equals('312'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'packing',
          name: 'عمالة تشغيل المحطة',
        ),
        equals('312'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'packing',
          name: 'ديزل مولدات المحطة',
        ),
        equals('312'),
      );
    });

    test('resolveParentAccountCode maps administrative items to Root 321', () {
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'all',
          name: 'مصاريف إدارية وعمومية',
        ),
        equals('321'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'all',
          name: 'أتعاب استشارية ومراجعة قانونية',
        ),
        equals('321'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'all',
          name: 'أخرى',
        ),
        equals('321'),
      );
    });

    test('resolveParentAccountCode under general_admin scope strictly binds to Root 321', () {
      // General & Administrative scope exclusively maps to Root 321 regardless of name keywords
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'general_admin',
          name: 'صيانة مباني ومكاتب إدارية',
        ),
        equals('321'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'general_admin',
          name: 'شحن أوراق ومستندات رسمية',
        ),
        equals('321'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(
          scope: 'admin',
          name: 'بوفيه وضيافة وعمالة نظافة',
        ),
        equals('321'),
      );
    });

    test('CostCategoryScope enum exclusively features General & Administrative in creation scopes', () {
      final creationScopes = CostCategoryScope.generalExpenseCreationScopes;
      expect(creationScopes.length, equals(1));
      expect(creationScopes.first, equals(CostCategoryScope.generalAdmin));
      expect(creationScopes.first.parentAccountCode, equals('321'));
      expect(creationScopes.first.defaultCostCenterCode, equals('CC-ADMIN'));
      expect(CostCategoryScope.fromCode('general_admin'), equals(CostCategoryScope.generalAdmin));
      expect(CostCategoryScope.fromCode('admin'), equals(CostCategoryScope.generalAdmin));
      expect(CostCategoryScope.fromCode(null), equals(CostCategoryScope.generalAdmin));
    });

    test('COAExpenseDropdown.suggestCostCenter respects direct cost_center_id binding', () {
      final accountWithDirectCc = {
        'id': 99,
        'account_code': '3129',
        'account_name': 'كراتين مخصصة',
        'cost_center_id': 'CC-CAT-99',
      };

      expect(
        COAExpenseDropdown.suggestCostCenter(accountWithDirectCc),
        equals('CC-CAT-99'),
      );
    });

    test('COAExpenseDropdown.suggestCostCenter derives correct standard cost centers', () {
      // 1. Packing Station (Root 312)
      final packingAccount = {
        'id': 101,
        'account_code': '3122',
        'account_name': 'تكاليف تشغيل محملة على الإنتاج التام',
      };
      expect(
        COAExpenseDropdown.suggestCostCenter(packingAccount),
        equals(CostCenterHelper.packingStation.id),
      );

      // 2. Freight & Logistics (Root 34114)
      final shippingAccount = {
        'id': 102,
        'account_code': '34114',
        'account_name': 'مصروفات الشحن البحري والجوي',
      };
      expect(
        COAExpenseDropdown.suggestCostCenter(shippingAccount),
        equals(CostCenterHelper.freightLogistics.id),
      );

      // 3. Customs Clearance
      final customsAccount = {
        'id': 103,
        'account_code': '34117',
        'account_name': 'تخليص جمركي وشهادات زراعية',
        'cost_center_id': CostCenterHelper.customsClearance.id,
      };
      expect(
        COAExpenseDropdown.suggestCostCenter(customsAccount),
        equals(CostCenterHelper.customsClearance.id),
      );

      // 4. Admin (Root 321)
      final adminAccount = {
        'id': 104,
        'account_code': '3211',
        'account_name': 'مصروفات عمومية وإدارية',
      };
      expect(
        COAExpenseDropdown.suggestCostCenter(adminAccount),
        equals(CostCenterHelper.generalAdmin.id),
      );
    });

    test('CostCenter.fromMap creates dynamic category cost center correctly', () {
      final dbRecord = {
        'id': 15,
        'code': 'CC-CAT-15',
        'name': 'كراتين جامبو تصدير',
        'name_ar': 'كراتين جامبو تصدير',
        'name_en': 'Jumbo Export Cartons',
        'cost_center_type': 'operational',
        'color': '#10B981',
        'icon': 'inventory_2_rounded',
        'is_active': true,
      };

      final cc = CostCenter.fromMap(dbRecord);
      expect(cc.id, equals('CC-CAT-15'));
      expect(cc.nameAr, equals('كراتين جامبو تصدير'));
      expect(cc.type, equals(CostCenterType.operational));
      expect(cc.code, equals('CC-CAT-15'));
    });

    test('Cleaned-up scope options automatically resolve to 312 and 321 without redundant user configuration', () {
      // 1. Packing scope automatically maps to 312
      expect(
        CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'سولار محطة'),
        equals('312'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'صيانة سيور'),
        equals('312'),
      );

      // 2. All / Admin scope automatically maps to 321
      expect(
        CostCategoryService.resolveParentAccountCode(scope: 'all', name: 'أدوات مكتبية ومطبوعات'),
        equals('321'),
      );
      expect(
        CostCategoryService.resolveParentAccountCode(scope: 'all', name: 'مصاريف ضيافة وانتقالات'),
        equals('321'),
      );
    });

    test('Cash disbursal tree strictly isolates G&A and operational leaf accounts, eliminating non-cash depreciation and inventory COGS', () {
      final accounts = [
        {'account_code': '32101', 'is_leaf': true, 'is_active': true, 'name': 'أدوات مكتبية'},
        {'account_code': '31201', 'is_leaf': true, 'is_active': true, 'name': 'سولار مولدات'},
        {'account_code': '32201', 'is_leaf': true, 'is_active': true, 'name': 'نولون بري'},
        {'account_code': '32401', 'is_leaf': true, 'is_active': true, 'name': 'أجور عمالة مؤقتة'},
        {'account_code': '33201', 'is_leaf': true, 'is_active': true, 'name': 'عمولات بنكية'},
        // Non-cash depreciation accounts (must be excluded from cash treasury disbursals)
        {'account_code': '31501', 'is_leaf': true, 'is_active': true, 'name': 'إهلاك سيور المحطة'},
        {'account_code': '32501', 'is_leaf': true, 'is_active': true, 'name': 'إهلاك أثاث مكتبي'},
        // Non-cash inventory COGS (must be excluded from cash safe disbursals)
        {'account_code': '31101', 'is_leaf': true, 'is_active': true, 'name': 'تكلفة بضاعة مباعة فراولة'},
        {'account_code': '34101', 'is_leaf': true, 'is_active': true, 'name': 'مشتريات خام'},
      ];

      final filtered = accounts.where((a) {
        final code = (a['account_code'] ?? '').toString().trim();
        if (!code.startsWith('3')) return false;
        if (code.startsWith('315') ||
            code.startsWith('325') ||
            code.startsWith('311') ||
            code.startsWith('314') ||
            code.startsWith('341')) {
          return false;
        }
        if (a['is_leaf'] != true && a['allow_posting'] != true) return false;
        if (a['is_active'] == false) return false;
        return true;
      }).toList();

      expect(filtered.length, equals(5));
      expect(filtered.map((a) => a['account_code']), containsAll(['32101', '31201', '32201', '32401', '33201']));
      expect(filtered.map((a) => a['account_code']), isNot(contains('31501')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('32501')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('31101')));
      expect(filtered.map((a) => a['account_code']), isNot(contains('34101')));
    });
  });
}
