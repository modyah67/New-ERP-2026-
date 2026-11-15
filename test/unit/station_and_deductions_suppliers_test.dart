import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/constants/entity_code_ranges.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/services/cost_category_service.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';

void main() {
  group('Station and Deductions Suppliers Unit Tests', () {
    test('Chart of Accounts mapping includes station and deductions control accounts', () {
      expect(AccountModel.getStandardArabicName('21117'), equals('موردي المحطات'));
      expect(AccountModel.getStandardArabicName('21118'), equals('موردي التخصيمات'));
    });

    test('AppEntityCodeRanges defines correct ranges for station and deduction suppliers', () {
      expect(AppEntityCodeRanges.warehouseStationRange.minCode, equals(80000));
      expect(AppEntityCodeRanges.warehouseStationRange.maxCode, equals(84999));
      expect(AppEntityCodeRanges.stationRange.minCode, equals(85000));
      expect(AppEntityCodeRanges.stationRange.maxCode, equals(89999));
      expect(AppEntityCodeRanges.deductionsSupplierRange.minCode, equals(40000));
      expect(AppEntityCodeRanges.deductionsSupplierRange.maxCode, equals(49999));

      expect(AppEntityCodeRanges.deductionsSupplierRange.contains(40001), isTrue);
      expect(AppEntityCodeRanges.deductionsSupplierRange.contains(49999), isTrue);
      expect(AppEntityCodeRanges.deductionsSupplierRange.contains(50000), isFalse);

      expect(AppEntityCodeRanges.warehouseStationRange.contains(80001), isTrue);
      expect(AppEntityCodeRanges.warehouseStationRange.contains(84999), isTrue);
      expect(AppEntityCodeRanges.warehouseStationRange.contains(85000), isFalse);

      expect(AppEntityCodeRanges.stationRange.contains(85001), isTrue);
      expect(AppEntityCodeRanges.stationRange.contains(89999), isTrue);
      expect(AppEntityCodeRanges.stationRange.contains(90000), isFalse);
    });

    test('SupplierModel handles station suppliers correctly', () {
      const s = SupplierModel(
        id: 'station-1',
        supplierCode: '85001',
        name: 'محطة السلام للتبريد والتعبئة',
        supplierType: 'station',
        categories: ['تشغيل', 'تبريد', 'حفظ مبرد'],
      );

      expect(s.isStationSupplier, isTrue);
      expect(s.isDeductionSupplier, isFalse);
      expect(s.supplierTypeLabel, equals('مورد محطة'));
      expect(s.categories.length, equals(3));
      expect(s.categories, contains('تبريد'));

      final map = s.toInsertMap();
      expect(map['supplier_type'], equals('station'));
      expect(map['categories'], equals(['تشغيل', 'تبريد', 'حفظ مبرد']));

      final fromMap = SupplierModel.fromMap(map);
      expect(fromMap.isStationSupplier, isTrue);
      expect(fromMap.categories, equals(['تشغيل', 'تبريد', 'حفظ مبرد']));
    });

    test('SupplierModel handles deductions suppliers correctly', () {
      const s = SupplierModel(
        id: 'ded-1',
        supplierCode: '40001',
        name: 'معمل الفحص المركزي',
        supplierType: 'deduction',
        categories: ['رسوم فحص', 'تحليل خاص', 'دفتر حجر زراعي'],
      );

      expect(s.isDeductionSupplier, isTrue);
      expect(s.isStationSupplier, isFalse);
      expect(s.supplierTypeLabel, equals('مورد تخصيمات'));
      expect(s.categories.length, equals(3));
      expect(s.categories, contains('رسوم فحص'));

      final map = s.toInsertMap();
      expect(map['supplier_type'], equals('deduction'));
      expect(map['categories'], equals(['رسوم فحص', 'تحليل خاص', 'دفتر حجر زراعي']));

      final fromMap = SupplierModel.fromMap(map);
      expect(fromMap.isDeductionSupplier, isTrue);
      expect(fromMap.categories, equals(['رسوم فحص', 'تحليل خاص', 'دفتر حجر زراعي']));
    });

    test('SupplierDao resolves correct master account code', () {
      final dao = SupplierDao();
      expect(SupplierDao.resolveMasterAccountCode('station'), equals('21117'));
      expect(SupplierDao.resolveMasterAccountCode('deduction'), equals('21118'));
      expect(SupplierDao.resolveMasterAccountCode('deductions'), equals('21118'));
      expect(SupplierDao.resolveMasterAccountCode('transport'), equals('21111'));
      expect(SupplierDao.resolveMasterAccountCode('packaging'), equals('21112'));
      expect(SupplierDao.resolveMasterAccountCode('crop'), equals('21113'));
      expect(dao.resolveAccountCode('station'), equals('21117'));
      expect(dao.resolveAccountCode('deduction'), equals('21118'));
    });

    test('CostCategoryService defines 9 station categories and 9 deduction categories', () {
      expect(CostCategoryService.defaultStationCategories.length, equals(9));
      expect(CostCategoryService.defaultStationCategories, containsAll([
        'تشغيل',
        'تبريد',
        'حفظ مبرد',
        'تقفيل كرتون',
        'تعتيق صادر',
        'اعادة تدوير',
        'عماله',
        'تبخير',
        'تدوير خام',
      ]));

      expect(CostCategoryService.defaultDeductionCategories.length, equals(9));
      expect(CostCategoryService.defaultDeductionCategories, containsAll([
        'رسوم فحص',
        'تخصيم عربي',
        'تخصيم اوروبي',
        'تحليل خاص',
        'تحليل هيئه',
        'سحب عينه عربي',
        'تعديل وجات',
        'دفتر حجر زراعي',
        'دفتر حجر سلامه غذاء',
      ]));
    });

    test('CostCategoryService supplier type labels map accurately', () {
      expect(CostCategoryService.getSupplierTypeLabel('station'), equals('موردي المحطات 🏭'));
      expect(CostCategoryService.getSupplierTypeLabel('deduction'), equals('موردي التخصيمات 📋'));
      expect(CostCategoryService.getSupplierTypeLabel('transport'), equals('موردي النقل 🚛'));
      expect(CostCategoryService.getSupplierTypeLabel('packaging'), equals('موردي مواد التعبئة 📦'));
      expect(CostCategoryService.getSupplierTypeLabel('crop'), equals('موردي المحاصيل 🌾'));
      expect(CostCategoryService.getSupplierTypeLabel('general'), equals('عام / أخرى 🌐'));
    });

    test('CostCategoryService.resolveParentAccountCode maps categories to correct COA parent accounts', () {
      // 1. Station Suppliers / Operations -> 3124
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'تشغيل', supplierType: 'station'), equals('3124'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'تبريد', supplierType: 'station'), equals('3124'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'حفظ مبرد'), equals('3124'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'محطة الفرز'), equals('3124'));

      // 2. Deduction Suppliers / Quality & Inspection -> 3126
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'رسوم فحص', supplierType: 'deduction'), equals('3126'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'تخصيم عربي', supplierType: 'deduction'), equals('3126'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing', name: 'تحليل خاص'), equals('3126'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'all', name: 'دفتر حجر زراعي'), equals('3126'));

      // 3. Packaging waste / scrap -> 3124
      expect(CostCategoryService.resolveParentAccountCode(scope: 'packing_waste', name: 'هالك كراتين'), equals('3124'));

      // 4. Crop & Raw Materials -> 3411
      expect(CostCategoryService.resolveParentAccountCode(scope: 'all', name: 'شراء خام فراولة'), equals('3411'));

      // 5. Shipment & Logistics -> 3411
      expect(CostCategoryService.resolveParentAccountCode(scope: 'shipment', name: 'نولون بحري'), equals('3411'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'shipment', name: 'تخليص جمركي'), equals('3411'));

      // 6. General & Admin -> 3133 / 3132
      expect(CostCategoryService.resolveParentAccountCode(scope: 'general_admin', name: 'أدوات كتابية وبوفيه'), equals('3133'));
      expect(CostCategoryService.resolveParentAccountCode(scope: 'general_admin', name: 'استشارات قانونية'), equals('3132'));
    });

    test('AccountModel includes standard Arabic names for 3124, 3126 and their sub-accounts', () {
      expect(AccountModel.getStandardArabicName('3124'), equals('تكاليف ومصروفات تشغيل المحطات'));
      expect(AccountModel.getStandardArabicName('3126'), equals('رسوم فحص وتخصيمات التشغيل'));
      expect(AccountModel.getStandardArabicName('31241'), equals('تشغيل'));
      expect(AccountModel.getStandardArabicName('31242'), equals('تبريد'));
      expect(AccountModel.getStandardArabicName('31261'), equals('رسوم فحص'));
      expect(AccountModel.getStandardArabicName('31262'), equals('تخصيم عربي'));
    });
  });
}
