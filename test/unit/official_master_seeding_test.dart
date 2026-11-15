// test/unit/official_master_seeding_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for official master seeding data parity with الموردين.pdf
// and code generator rules.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/database_seeder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Official Master Seeding Data Parity (الموردين.pdf)', () {
    test('Group 5: موردين المحاصيل strictly spans 501 to 518 (18 suppliers)', () {
      final list = DatabaseSeeder.cropSuppliers;
      expect(list.length, equals(18));

      // Range check
      for (int i = 0; i < list.length; i++) {
        final expectedCode = (501 + i).toString();
        expect(list[i].code, equals(expectedCode));
        expect(list[i].categoryGroup, equals('موردين المحاصيل'));
        expect(list[i].entityType, equals('crop'));
        expect(list[i].name.startsWith('مورد محاصيل - '), isTrue);
      }

      // Exact name checks
      expect(list[0].name, equals('مورد محاصيل - الحاج ياسر'));
      expect(list[1].name, equals('مورد محاصيل - وليد رزقانه'));
      expect(list[2].name, equals('مورد محاصيل - الحاج اسماعيل'));
      expect(list[3].name, equals('مورد محاصيل - محمد رزق'));
      expect(list[17].name, equals('مورد محاصيل - حماده مصباح مانجو'));
    });

    test('Group 6: موردين النقل strictly spans 601 to 610 (10 transport contractors)', () {
      final list = DatabaseSeeder.transportSuppliers;
      expect(list.length, equals(10));

      for (int i = 0; i < list.length; i++) {
        final expectedCode = (601 + i).toString();
        expect(list[i].code, equals(expectedCode));
        expect(list[i].categoryGroup, equals('موردين النقل'));
        expect(list[i].entityType, equals('transport'));
        expect(list[i].name.startsWith('مورد نقل'), isTrue);
      }

      expect(list[0].name, equals('مورد نقل - محمود ابو حسين'));
      expect(list[1].name, equals('مورد نقل - عزام'));
      expect(list[9].name, equals('مورد نقل برادات - وليد'));
    });

    test('Group 7: موردين مواد التعبئة والتغليف والاستيكر strictly spans 701 to 717 (17 suppliers)', () {
      final list = DatabaseSeeder.packagingSuppliers;
      expect(list.length, equals(17));

      final codes = list.map((e) => int.parse(e.code)).toSet();
      expect(codes.length, equals(17));
      for (int c = 701; c <= 717; c++) {
        expect(codes.contains(c), isTrue, reason: 'Missing code $c in packaging suppliers');
      }

      expect(list.firstWhere((e) => e.code == '701').name, equals('مورد مواد تعبئه وتغليف - يوسف'));
      expect(list.firstWhere((e) => e.code == '702').name, equals('مورد مواد تعبئه وتغليف - مصنع مودرن للكرتون'));
      expect(list.firstWhere((e) => e.code == '706').name, equals('مورد مواد تعبئه وتغليف - جورج استيكر'));
      expect(list.firstWhere((e) => e.code == '716').name, equals('مورد استكير - يوسف'));
      expect(list.firstWhere((e) => e.code == '717').name, equals('مورد استكير - رحاب'));
    });

    test('Group 8: محطات التعبئة والتحاليل strictly spans 801 to 809 (9 stations & test centers)', () {
      final list = DatabaseSeeder.stationsAndTesting;
      expect(list.length, equals(9));

      for (int i = 0; i < list.length; i++) {
        final expectedCode = (801 + i).toString();
        expect(list[i].code, equals(expectedCode));
        expect(list[i].categoryGroup, equals('محطات التعبئة والتحاليل'));
        expect(list[i].entityType, equals('station'));
      }

      expect(list[0].name, equals('محطة - العبور'));
      expect(list[1].name, equals('محطة الصفا - العاشر من رمضان'));
      expect(list[3].name, equals('تحاليل وتخصيم - الشيخ تامر'));
      expect(list[5].name, equals('محطه تاج'));
      expect(list[8].name, equals('محطه دلتا جروب'));
    });

    test('Group 9: شركات الشحن strictly spans 901 to 905 (5 shipping companies)', () {
      final list = DatabaseSeeder.shippingCompanies;
      expect(list.length, equals(5));

      for (int i = 0; i < list.length; i++) {
        final expectedCode = (901 + i).toString();
        expect(list[i].code, equals(expectedCode));
        expect(list[i].categoryGroup, equals('شركات الشحن'));
        expect(list[i].entityType, equals('shipping'));
        expect(list[i].name.startsWith('شركه '), isTrue);
      }

      expect(list[0].name, equals('شركه فالكون للشحن'));
      expect(list[1].name, equals('شركه المصريه للشحن'));
      expect(list[2].name, equals('شركه فينوس للشحن'));
      expect(list[3].name, equals('شركه العربى للشحن'));
      expect(list[4].name, equals('شركه الندى للشحن'));
    });

    test('Total official entities count equals 59 with no duplicates', () {
      final all = DatabaseSeeder.allEntities;
      expect(all.length, equals(59));

      final uniqueCodes = all.map((e) => e.code).toSet();
      expect(uniqueCodes.length, equals(59), reason: 'All entity codes across groups must be distinct');
    });

    test('Code generator rules enforce 500s, 600s, 700s, 800s, 900s and eliminate TR/STA prefixes', () {
      // Simulate TransportSupplier next code logic with 601..610 present
      final sampleTransportRows = DatabaseSeeder.transportSuppliers.map((e) => {'code': e.code}).toList();
      int maxTransport = 600;
      for (var row in sampleTransportRows) {
        final num = int.tryParse(row['code'] ?? '') ?? 0;
        if (num >= 600 && num < 700 && num > maxTransport) maxTransport = num;
      }
      final nextTransportCode = (maxTransport + 1).toString();
      expect(nextTransportCode, equals('611'));
      expect(nextTransportCode.startsWith('TR'), isFalse);

      // Simulate Station next code logic with 801..809 present
      final sampleStationRows = DatabaseSeeder.stationsAndTesting.map((e) => {'code': e.code}).toList();
      int maxStation = 800;
      for (var row in sampleStationRows) {
        final num = int.tryParse(row['code'] ?? '') ?? 0;
        if (num >= 800 && num < 900 && num > maxStation) maxStation = num;
      }
      final nextStationCode = (maxStation + 1).toString();
      expect(nextStationCode, equals('810'));
      expect(nextStationCode.startsWith('STA'), isFalse);

      // Simulate Shipping Company next code logic with 901..905 present
      final sampleShippingRows = DatabaseSeeder.shippingCompanies.map((e) => {'code': e.code}).toList();
      int maxShipping = 900;
      for (var row in sampleShippingRows) {
        final num = int.tryParse(row['code'] ?? '') ?? 0;
        if (num >= 900 && num < 1000 && num > maxShipping) maxShipping = num;
      }
      final nextShippingCode = (maxShipping + 1).toString();
      expect(nextShippingCode, equals('906'));
      expect(nextShippingCode, isNot(equals('00001')));

      // Simulate Crop Supplier next code logic with 501..518 present
      final sampleCropRows = DatabaseSeeder.cropSuppliers.map((e) => {'code': e.code}).toList();
      int maxCrop = 500;
      for (var row in sampleCropRows) {
        final num = int.tryParse(row['code'] ?? '') ?? 0;
        if (num >= 500 && num < 600 && num > maxCrop) maxCrop = num;
      }
      final nextCropCode = (maxCrop + 1).toString();
      expect(nextCropCode, equals('519'));
      expect(nextCropCode, isNot(equals('00001')));

      // Simulate Packaging Supplier next code logic with 701..717 present
      final samplePackagingRows = DatabaseSeeder.packagingSuppliers.map((e) => {'code': e.code}).toList();
      int maxPack = 700;
      for (var row in samplePackagingRows) {
        final num = int.tryParse(row['code'] ?? '') ?? 0;
        if (num >= 700 && num < 800 && num > maxPack) maxPack = num;
      }
      final nextPackCode = (maxPack + 1).toString();
      expect(nextPackCode, equals('718'));
      expect(nextPackCode, isNot(equals('00001')));
    });
  });
}
