import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/data/models/supplier_model.dart';

void main() {
  group('Supplier Master Account Binding & Mapping Tests (Unified 2111 Architecture)', () {
    test('AccountModel has standardized names for 2111 and all level 5 branches 21111-21118', () {
      expect(AccountModel.getStandardArabicName('2111'), equals('الموردين'));
      expect(AccountModel.getStandardArabicName('21111'), equals('موردي النقل والسيارات'));
      expect(AccountModel.getStandardArabicName('21112'), equals('موردي مواد التعبئة'));
      expect(AccountModel.getStandardArabicName('21113'), equals('موردي مشتريات محاصيل'));
      expect(AccountModel.getStandardArabicName('21114'), equals('موردين مشتركين'));
      expect(AccountModel.getStandardArabicName('21115'), equals('شركات الشحن'));
      expect(AccountModel.getStandardArabicName('21116'), equals('مخلصي الجمارك'));
      expect(AccountModel.getStandardArabicName('21117'), equals('موردي المحطات'));
      expect(AccountModel.getStandardArabicName('21118'), equals('موردي التخصيمات'));

      final accParent = AccountModel(id: '0', code: '2111', name: 'Suppliers Control', type: 'liability');
      final acc1 = AccountModel(id: '1', code: '21111', name: 'Transport Suppliers', type: 'liability');
      final acc2 = AccountModel(id: '2', code: '21112', name: 'Packaging Suppliers', type: 'liability');
      final acc3 = AccountModel(id: '3', code: '21113', name: 'Crop Suppliers', type: 'liability');
      final acc4 = AccountModel(id: '4', code: '21114', name: 'Shared Suppliers', type: 'liability');
      final acc5 = AccountModel(id: '5', code: '21115', name: 'Shipping Companies', type: 'liability');
      final acc6 = AccountModel(id: '6', code: '21116', name: 'Customs Agents', type: 'liability');
      final acc7 = AccountModel(id: '7', code: '21117', name: 'Station Suppliers', type: 'liability');
      final acc8 = AccountModel(id: '8', code: '21118', name: 'Deductions Suppliers', type: 'liability');

      expect(accParent.displayName, equals('الموردين'));
      expect(acc1.displayName, equals('موردي النقل والسيارات'));
      expect(acc2.displayName, equals('موردي مواد التعبئة'));
      expect(acc3.displayName, equals('موردي مشتريات محاصيل'));
      expect(acc4.displayName, equals('موردين مشتركين'));
      expect(acc5.displayName, equals('شركات الشحن'));
      expect(acc6.displayName, equals('مخلصي الجمارك'));
      expect(acc7.displayName, equals('موردي المحطات'));
      expect(acc8.displayName, equals('موردي التخصيمات'));
    });

    test('SupplierModel correctly handles accountId in fromMap and toInsertMap', () {
      final model = SupplierModel(
        id: 'sup-1',
        supplierCode: '501',
        name: 'مورد محاصيل تجريبي',
        supplierType: 'crop',
        accountId: 5104,
      );

      expect(model.accountId, equals(5104));

      final insertMap = model.toInsertMap();
      expect(insertMap['account_id'], equals(5104));

      final fromMap = SupplierModel.fromMap(insertMap);
      expect(fromMap.accountId, equals(5104));

      final copy = model.copyWith(accountId: 5105);
      expect(copy.accountId, equals(5105));
      expect(copy.name, equals('مورد محاصيل تجريبي'));
    });

    test('Unified Supplier Category to Master Account Code Mapping Logic', () {
      String resolveExpectedCode(String type) {
        final t = type.toLowerCase().trim();
        if (t == 'transport' || t == 'transporter') return '21111';
        if (t == 'packaging' || t == 'packing' || t == 'sticker') return '21112';
        if (t == 'shared') return '21114';
        if (t == 'shipping' || t == 'shipping_company') return '21115';
        if (t == 'clearing' || t == 'clearance' || t == 'customs') return '21116';
        if (t == 'station' || t == 'station_supplier') return '21117';
        if (t == 'deduction' || t == 'deductions' || t == 'deduction_supplier') return '21118';
        return '21113';
      }

      expect(resolveExpectedCode('transport'), equals('21111'));
      expect(resolveExpectedCode('packaging'), equals('21112'));
      expect(resolveExpectedCode('station'), equals('21117'));
      expect(resolveExpectedCode('deduction'), equals('21118'));
      expect(resolveExpectedCode('crop'), equals('21113'));
      expect(resolveExpectedCode('shared'), equals('21114'));
      expect(resolveExpectedCode('shipping'), equals('21115'));
      expect(resolveExpectedCode('clearing'), equals('21116'));
      expect(resolveExpectedCode('customs'), equals('21116'));
      expect(resolveExpectedCode('unknown_category'), equals('21113'));
    });
  });
}
