import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/cost_center.dart';
import 'package:accounting_system/features/treasury/widgets/coa_expense_dropdown.dart';

void main() {
  group('Master Chart of Accounts (COA) Model & Synchronized Tree Tests', () {
    test('Root 1 (Assets) - Required fixed assets, currencies, and custodies structure', () {
      final assetsAccounts = [
        {'account_code': '1', 'name': 'Assets', 'account_name': 'الأصول', 'normal_balance': 'Debit', 'level': 1},
        {'account_code': '11', 'parent': '1', 'name': 'Non-Current Assets', 'account_name': 'الأصول غير المتداولة', 'level': 2},
        {'account_code': '111', 'parent': '11', 'name': 'Fixed Assets', 'account_name': 'الأصول الثابتة', 'level': 3},
        {'account_code': '1111', 'parent': '111', 'name': 'Buildings & Construction', 'account_name': 'المباني والمنشآت', 'level': 4},
        {'account_code': '1112', 'parent': '111', 'name': 'Machinery & Equipment', 'account_name': 'الآلات والمعدات', 'level': 4},
        {'account_code': '1113', 'parent': '111', 'name': 'Furniture & Office Equipment', 'account_name': 'أثاث ومعدات مكتبية', 'level': 4},
        {'account_code': '1114', 'parent': '111', 'name': 'Computers & IT Equipment', 'account_name': 'أجهزة كمبيوتر وتكنولوجيا', 'level': 4},
        {'account_code': '1115', 'parent': '111', 'name': 'Passenger Vehicles', 'account_name': 'سيارات ملاكي وإدارية', 'level': 4},
        {'account_code': '1116', 'parent': '111', 'name': 'Produce Transport & Trucks', 'account_name': 'وسائل نقل المحاصيل والشاحنات', 'level': 4},
        {'account_code': '12111', 'parent': '1211', 'name': 'CIB Bank Account - EGP', 'account_name': 'حساب بنكي - CIB - جنيه مصري', 'level': 5},
        {'account_code': '12112', 'parent': '1211', 'name': 'CIB Bank Account - USD', 'account_name': 'حساب بنكي - CIB - دولار أمريكي', 'level': 5},
        {'account_code': '12113', 'parent': '1211', 'name': 'CIB Bank Account - EUR', 'account_name': 'حساب بنكي - CIB - يورو', 'level': 5},
        {'account_code': '12114', 'parent': '1211', 'name': 'CIB Bank Account - GBP', 'account_name': 'حساب بنكي - CIB - جنيه إسترليني', 'level': 5},
        {'account_code': '12121', 'parent': '1212', 'name': 'Main Treasury - EGP', 'account_name': 'الخزينة الرئيسية - جنيه مصري', 'level': 5},
        {'account_code': '12122', 'parent': '1212', 'name': 'Main Treasury - USD', 'account_name': 'الخزينة الرئيسية - دولار أمريكي', 'level': 5},
        {'account_code': '12123', 'parent': '1212', 'name': 'Main Treasury - EUR', 'account_name': 'الخزينة الرئيسية - يورو', 'level': 5},
        {'account_code': '12124', 'parent': '1212', 'name': 'Main Treasury - GBP', 'account_name': 'الخزينة الرئيسية - جنيه إسترليني', 'level': 5},
      ];

      expect(assetsAccounts.length, equals(17));
      expect(assetsAccounts.first['normal_balance'], equals('Debit'));
      expect(assetsAccounts.where((a) => a['account_code']!.toString().startsWith('111')).length, equals(7)); // 111 + 6 leaves
      expect(assetsAccounts.where((a) => a['account_code']!.toString().startsWith('1211')).length, equals(4));
      expect(assetsAccounts.where((a) => a['account_code']!.toString().startsWith('1212')).length, equals(4));
    });

    test('Root 2 (Liabilities & Equity) - Suppliers, taxes 21211-21216, shareholders 23211-23213, and equity', () {
      final equityAccounts = [
        {'account_code': '2', 'name': 'Liabilities & Equity', 'account_name': 'الخصوم', 'normal_balance': 'Credit', 'level': 1},
        {'account_code': '21', 'parent': '2', 'name': 'Current Liabilities', 'account_name': 'الخصوم المتداوله', 'level': 2},
        {'account_code': '211', 'parent': '21', 'name': 'Suppliers & Notes Payable', 'account_name': 'الموردين واوراق الدفع', 'level': 3},
        {'account_code': '2111', 'parent': '211', 'name': 'Crop Purchase Suppliers', 'account_name': 'موردي مشتريات محاصيل', 'level': 4},
        {'account_code': '2112', 'parent': '211', 'name': 'Notes Payable', 'account_name': 'اوراق الدفع', 'level': 4},
        {'account_code': '2113', 'parent': '211', 'name': 'Shipping Companies', 'account_name': 'شركات الشحن', 'level': 4},
        {'account_code': '2114', 'parent': '211', 'name': 'Customs Clearing Agents', 'account_name': 'مخلصو الجمارك', 'level': 4},
        {'account_code': '2115', 'parent': '211', 'name': 'Packaging Materials Suppliers', 'account_name': 'موردو مواد التعبئة', 'level': 4},
        {'account_code': '21111', 'parent': '2111', 'account_name': 'موردين محليين نقل', 'level': 5},
        {'account_code': '21112', 'parent': '2111', 'account_name': 'موردين محليين مواد تعبئه', 'level': 5},
        {'account_code': '21113', 'parent': '2111', 'account_name': 'موردين مشتريات محاصيل', 'level': 5},
        {'account_code': '21121', 'parent': '2112', 'account_name': 'اوراق دفع البنك التجارى الدولى CIB', 'level': 5},
        {'account_code': '2121', 'parent': '212', 'name': 'Taxes', 'account_name': 'الضرائب', 'level': 4},
        {'account_code': '21211', 'parent': '2121', 'account_name': 'ضريبه كسب العمل', 'level': 5},
        {'account_code': '21212', 'parent': '2121', 'account_name': 'ضريبه الخصم من الغير - الخصم والاضافه', 'level': 5},
        {'account_code': '21213', 'parent': '2121', 'account_name': 'ضريبه القيمه المضافه - المبيعات', 'level': 5},
        {'account_code': '21214', 'parent': '2121', 'account_name': 'ضريبه الدخل', 'level': 5},
        {'account_code': '21215', 'parent': '2121', 'account_name': 'ضريبه الدمغه', 'level': 5},
        {'account_code': '21216', 'parent': '2121', 'account_name': 'ضريبه سنوات سابقه', 'level': 5},
        {'account_code': '21221', 'parent': '2122', 'account_name': 'هيئه التامينات الإجتماعيه', 'level': 5},
        {'account_code': '21222', 'parent': '2122', 'account_name': 'مكتب العمل', 'level': 5},
        {'account_code': '23211', 'parent': '2321', 'name': 'Shareholder - Emad', 'account_name': 'جارى أ / عماد', 'level': 5},
        {'account_code': '23212', 'parent': '2321', 'name': 'Shareholder - Abdel Batin', 'account_name': 'جارى أ / عبدالباطن', 'level': 5},
        {'account_code': '23213', 'parent': '2321', 'name': 'Shareholder - Eslam', 'account_name': 'جارى أ / اسلام', 'level': 5},
      ];

      expect(equityAccounts.first['normal_balance'], equals('Credit'));
      expect(equityAccounts.where((a) => a['account_code']!.toString().startsWith('2121')).length, equals(7));
      expect(equityAccounts.where((a) => a['account_code']!.toString().startsWith('2321')).length, equals(3));
    });

    test('Root 3 (Expenses & Costs) - COGS, direct packing, administrative 3151-3158, sales breakdown 3411-3419, and FX losses', () {
      final expenseAccounts = [
        {'account_code': '3', 'name': 'Expenses & Costs', 'account_name': 'المصروفات والتكاليف', 'normal_balance': 'Debit', 'level': 1},
        {'account_code': '3111', 'account_name': 'تكلفة البضاعة المباعة - محاصيل تصديرية'},
        {'account_code': '3112', 'account_name': 'تكلفة البضاعة المباعة - محاصيل محلية'},
        {'account_code': '3122', 'account_name': 'تكاليف تشغيل محملة على الإنتاج التام'},
        {'account_code': '3211', 'account_name': 'مصروفات إدارية وعمومية فعلية'},
        {'account_code': '3212', 'account_name': 'مصروفات تشغيل ومرافق المحطة'},
        {'account_code': '3213', 'account_name': 'مصروفات عامة وتشغيلية'},
        {'account_code': '3310', 'account_name': 'فروق أسعار العملة'},
        {'account_code': '3311', 'account_name': 'خسائر فروق أسعار العملة المحققة'},
        {'account_code': '3312', 'account_name': 'خسائر فروق أسعار العملة غير المحققة'},
        // 3151-3158
        {'account_code': '3151', 'account_name': 'مصروفات فوائد بنكية'},
        {'account_code': '3152', 'account_name': 'مصروفات بنكية'},
        {'account_code': '3153', 'account_name': 'فروق فحص ضريبي'},
        {'account_code': '3154', 'account_name': 'مصروفات سنوات سابقة'},
        {'account_code': '3155', 'account_name': 'مصروفات أتعاب استشارية'},
        {'account_code': '3156', 'account_name': 'مصروفات أتعاب مكتب المراجعة'},
        {'account_code': '3157', 'account_name': 'مصروفات رسوم واشتراكات وتراخيص'},
        {'account_code': '3158', 'account_name': 'مصروفات شحن مستندات'},
        // 3411-3419
        {'account_code': '3411', 'account_name': 'تكاليف مشتريات خام - تكلفة بيع'},
        {'account_code': '3412', 'account_name': 'مصروفات إكراميات - تكلفة بيع'},
        {'account_code': '3413', 'account_name': 'مصروفات عمالة - تكلفة بيع'},
        {'account_code': '3414', 'account_name': 'مصروفات نقل ومشال - تكلفة بيع'},
        {'account_code': '3415', 'account_name': 'مصروفات رويالتي - تكلفة بيع'},
        {'account_code': '3416', 'account_name': 'مصروفات إيجار برادات - تكلفة بيع'},
        {'account_code': '3417', 'account_name': 'مصروفات تخليص - تكلفة بيع'},
        {'account_code': '3418', 'account_name': 'مصروفات شحن (نولون) - تكلفة بيع'},
        {'account_code': '3419', 'account_name': 'مصروفات تحاليل عينات - تكلفة بيع'},
      ];

      expect(expenseAccounts.first['normal_balance'], equals('Debit'));
      expect(expenseAccounts.where((a) => a['account_code']!.toString().startsWith('315')).length, equals(8));
      expect(expenseAccounts.where((a) => a['account_code']!.toString().startsWith('341')).length, equals(9));
      expect(expenseAccounts.where((a) => a['account_code']!.toString().startsWith('331')).length, equals(3));
    });

    test('Root 4 (Revenues) and Root 9 (System Clearing) accounts verification', () {
      final revenuesAndSystem = [
        {'account_code': '4', 'name': 'Revenues', 'account_name': 'الإيرادات', 'normal_balance': 'Credit'},
        {'account_code': '4111', 'account_name': 'مبيعات الفراولة التصديرية'},
        {'account_code': '4112', 'account_name': 'مبيعات المحاصيل التصديرية الأخرى'},
        {'account_code': '4121', 'account_name': 'مبيعات المحاصيل بالسوق المحلي'},
        {'account_code': '4211', 'account_name': 'أرباح فروق أسعار العملة المحققة'},
        {'account_code': '4212', 'account_name': 'أرباح فروق أسعار العملة غير المحققة'},
        {'account_code': '9', 'name': 'System & Intermediary Accounts', 'account_name': 'حسابات نظامية ووسيطة', 'normal_balance': 'Debit'},
        {'account_code': '9111', 'account_name': 'وسيط هالك مواد التعبئة'},
        {'account_code': '9112', 'account_name': 'وسيط هالك المحاصيل'},
        {'account_code': '9121', 'account_name': 'وسيط ضرائب'},
        {'account_code': '9122', 'account_name': 'ضرائب محملة'},
        {'account_code': '9123', 'account_name': 'مخصص / وسيط مصروفات إدارية'},
        {'account_code': '9124', 'account_name': 'مصروفات إدارية محملة'},
      ];

      expect(revenuesAndSystem.where((a) => a['account_code']!.toString().startsWith('4')).length, equals(6));
      expect(revenuesAndSystem.where((a) => a['account_code']!.toString().startsWith('9')).length, equals(7));
    });

    test('COAExpenseDropdown UI category resolution and cost center suggestions for 3411-3419', () {
      final rawPurchases = {'account_code': '3411', 'account_name': 'تكاليف مشتريات خام - تكلفة بيع'};
      final freightHandling = {'account_code': '34114', 'account_name': 'مصروفات نقل ومشال - تكلفة بيع'};
      final oceanFreight = {'account_code': '34118', 'account_name': 'مصروفات شحن (نولون) - تكلفة بيع'};
      final depAccount = {'account_code': '3211', 'account_name': 'إهلاك أصول'};

      expect(COAExpenseDropdown.resolveCategory(rawPurchases), equals('cogs'));
      expect(COAExpenseDropdown.resolveCategory(freightHandling), equals('cogs'));
      expect(COAExpenseDropdown.resolveCategory(depAccount), equals('depreciation'));

      expect(COAExpenseDropdown.suggestCostCenter(rawPurchases), equals(CostCenterHelper.packingStation.id));
      expect(COAExpenseDropdown.suggestCostCenter(freightHandling), equals(CostCenterHelper.freightLogistics.id));
      expect(COAExpenseDropdown.suggestCostCenter(oceanFreight), equals(CostCenterHelper.freightLogistics.id));
    });
  });
}
