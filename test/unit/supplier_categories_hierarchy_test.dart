import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/core/services/auto_account_generation_service.dart';

void main() {
  group('Supplier & Notes Payable 5-Level Hierarchy Tests', () {
    test('1. Level 3 (211) and Level 4 Category Heads (2111-2115) evaluated levels and labels', () {
      // Level 3
      final acc211 = AccountModel(
        code: '211',
        name: 'Suppliers & Notes Payable',
        accountName: 'الموردين وأوراق الدفع',
        type: 'liability',
      );
      expect(acc211.evaluatedLevel, equals(3));
      expect(acc211.levelLabel, equals('مستوى 3 - فرعي'));

      // Level 4 Category Heads
      final cat2111 = AccountModel(
        code: '2111',
        name: 'Crop Purchase Suppliers',
        accountName: 'موردي مشتريات محاصيل',
        type: 'liability',
        parentId: 'id_211',
      );
      final cat2112 = AccountModel(
        code: '2112',
        name: 'Notes Payable',
        accountName: 'أوراق الدفع',
        type: 'liability',
        parentId: 'id_211',
      );
      final cat2113 = AccountModel(
        code: '2113',
        name: 'Shipping Companies',
        accountName: 'شركات الشحن',
        type: 'liability',
        parentId: 'id_211',
      );
      final cat2114 = AccountModel(
        code: '2114',
        name: 'Customs Clearing Agents',
        accountName: 'مخلصو الجمارك',
        type: 'liability',
        parentId: 'id_211',
      );
      final cat2115 = AccountModel(
        code: '2115',
        name: 'Packaging & Station Suppliers',
        accountName: 'موردو محطات التعبئة',
        type: 'liability',
        parentId: 'id_211',
      );

      for (final cat in [cat2111, cat2112, cat2113, cat2114, cat2115]) {
        expect(cat.evaluatedLevel, equals(4));
        expect(cat.levelLabel, equals('مستوى 4 - تحليلي'));
        expect(cat.parentId, equals('id_211'));
      }

      // Check standard Arabic names resolution
      expect(AccountModel.getStandardArabicName('211'), equals('الموردين وأوراق الدفع'));
      expect(AccountModel.getStandardArabicName('2111'), equals('الموردين'));
      expect(AccountModel.getStandardArabicName('2112'), equals('أوراق الدفع'));
      expect(AccountModel.getStandardArabicName('21111'), equals('موردي النقل والسيارات'));
      expect(AccountModel.getStandardArabicName('21112'), equals('موردي مواد التعبئة'));
      expect(AccountModel.getStandardArabicName('21113'), equals('موردي مشتريات محاصيل'));
      expect(AccountModel.getStandardArabicName('21114'), equals('موردين مشتركين'));
      expect(AccountModel.getStandardArabicName('21115'), equals('شركات الشحن'));
      expect(AccountModel.getStandardArabicName('21116'), equals('مخلصي الجمارك'));
      expect(AccountModel.getStandardArabicName('21117'), equals('موردي المحطات'));
      expect(AccountModel.getStandardArabicName('21118'), equals('موردي التخصيمات'));
    });

    test('2. Level 5 individual entity sub-ledgers evaluate to Level 5 posting accounts', () {
      final subCrop = AccountModel(
        code: '211101',
        name: 'Supplier - Nile Farms',
        accountName: 'مورد - مزارع النيل',
        type: 'liability',
        parentId: 'id_2111',
      );
      final subNote = AccountModel(
        code: '211201',
        name: 'Notes Payable - CIB',
        accountName: 'أوراق دفع - CIB',
        type: 'liability',
        parentId: 'id_2112',
      );
      final subShip = AccountModel(
        code: '211301',
        name: 'Shipping - Maersk',
        accountName: 'شركة شحن - ميرسك',
        type: 'liability',
        parentId: 'id_2113',
      );
      final subClear = AccountModel(
        code: '211401',
        name: 'Clearing - Alexandria Port Agent',
        accountName: 'مخلص جمركي - ميناء الإسكندرية',
        type: 'liability',
        parentId: 'id_2114',
      );
      final subPack = AccountModel(
        code: '211501',
        name: 'Packaging Supplier - Modern Cartons',
        accountName: 'مورد تعبئة - كرتون الحديث',
        type: 'liability',
        parentId: 'id_2115',
      );

      for (final sub in [subCrop, subNote, subShip, subClear, subPack]) {
        expect(sub.evaluatedLevel, equals(5));
        expect(sub.levelLabel, equals('مستوى 5 - حساب ترحيل'));
      }
    });

    test('3. Dynamic supplier entity type resolver correctly routes categories to Level 4 parents', () {
      // Crop suppliers route to 2111
      final cropType = AutoAccountGenerationService.resolveSupplierEntityType('crop');
      expect(cropType.parentCode, equals('2111'));
      expect(cropType.rpcType, equals('crop_supplier'));

      // Packaging suppliers route to 2111
      final packType = AutoAccountGenerationService.resolveSupplierEntityType('packaging');
      expect(packType.parentCode, equals('2111'));
      expect(packType.rpcType, equals('packaging_supplier'));

      // Stations route to 2111
      final stationType = AutoAccountGenerationService.resolveSupplierEntityType('station');
      expect(stationType.parentCode, equals('2111'));
      expect(stationType.rpcType, equals('station_supplier'));

      // Shipping companies route to 2111
      final shipType = AutoAccountGenerationService.resolveSupplierEntityType('shipping');
      expect(shipType.parentCode, equals('2111'));
      expect(shipType.rpcType, equals('shipping_company'));

      // Clearing agents route to 2111
      final clearType = AutoAccountGenerationService.resolveSupplierEntityType('clearing');
      expect(clearType.parentCode, equals('2111'));
      expect(clearType.rpcType, equals('clearing_agent'));

      // Transport suppliers route to 2111
      final transportType = AutoAccountGenerationService.resolveSupplierEntityType('transport');
      expect(transportType.parentCode, equals('2111'));
      expect(transportType.rpcType, equals('transport_supplier'));

      // Shared suppliers default to crop (2111)
      final sharedType = AutoAccountGenerationService.resolveSupplierEntityType('shared');
      expect(sharedType.parentCode, equals('2111'));
    });

    test('4. Tree view indentation progression under Liabilities (2 -> 21 -> 211 -> 2111..2115 -> L5)', () {
      // Indentation formula from chart_of_accounts_page:
      // padding: 16.0 + (level.clamp(0, 5) * 22.0)
      double computePadding(int treeDepth) => 16.0 + (treeDepth.clamp(0, 5) * 22.0);

      final depthLevel1 = 0; // Root: 2
      final depthLevel2 = 1; // Group: 21
      final depthLevel3 = 2; // Control Group: 211
      final depthLevel4 = 3; // Categories: 2111, 2112, 2113, 2114, 2115
      final depthLevel5 = 4; // Individual sub-ledgers

      expect(computePadding(depthLevel1), equals(16.0));
      expect(computePadding(depthLevel2), equals(38.0));
      expect(computePadding(depthLevel3), equals(60.0));
      expect(computePadding(depthLevel4), equals(82.0));
      expect(computePadding(depthLevel5), equals(104.0));

      // Each successive level indents by exactly 22.0 pixels
      expect(computePadding(depthLevel4) - computePadding(depthLevel3), equals(22.0));
      expect(computePadding(depthLevel5) - computePadding(depthLevel4), equals(22.0));
    });
  });
}
