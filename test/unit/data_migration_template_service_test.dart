import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:accounting_system/features/backup/data_migration_template_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsPath') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  group('DataMigrationTemplateService 14-Sheets Exclusive Tests', () {
    test('defines EXCLUSIVELY the 14 expected sheets without duplicates or excluded tables', () {
      final specs = DataMigrationTemplateService.allTableSpecs;
      expect(specs.length, 14);

      final sheetNames = specs.map((s) => s.sheetName).toList();
      expect(sheetNames, [
        'العملاء - تصديري',
        'العملاء - محلي',
        'موردين المحاصيل',
        'موردين مواد التعبئة',
        'الموردين المشتركين',
        'موردي المحطات',
        'موردي النقل',
        'موردي التخصيمات',
        'المخلص البحري',
        'المخلص الجوي',
        'شركات الشحن',
        'المحطات',
        'فئات مواد التعبئة',
        'مواد التعبئة والمستلزمات',
      ]);

      // Verify excluded tables are NOT present
      final tableIds = specs.map((s) => s.tableId).toList();
      expect(tableIds, isNot(contains('fruit_types')));
      expect(tableIds, isNot(contains('accounts')));
      expect(tableIds, isNot(contains('warehouses')));
      expect(sheetNames, isNot(contains('أصناف_الفاكهة (Fruits)')));
      expect(sheetNames, isNot(contains('دليل_الحسابات (Accounts)')));
      expect(sheetNames, isNot(contains('المخازن (Warehouses)')));
    });

    test('1. Export Customers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[0];
      expect(spec.sheetName, 'العملاء - تصديري');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'currency',
        'phone',
        'email',
        'city',
        'country',
        'address',
        'contact_person',
        'contact_phone',
        'contact_email',
        'vat_number',
        'eori_number',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('2. Local Customers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[1];
      expect(spec.sheetName, 'العملاء - محلي');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'currency',
        'phone',
        'email',
        'city',
        'country',
        'address',
        'contact_person',
        'contact_phone',
        'contact_email',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('3. Crop Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[2];
      expect(spec.sheetName, 'موردين المحاصيل');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'address',
        'currency',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('4. Packing Materials Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[3];
      expect(spec.sheetName, 'موردين مواد التعبئة');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'address',
        'currency',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('5. Shared Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[4];
      expect(spec.sheetName, 'الموردين المشتركين');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'address',
        'currency',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('6. Station Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[5];
      expect(spec.sheetName, 'موردي المحطات');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'address',
        'services_mapping',
        'currency',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('7. Transport Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[6];
      expect(spec.sheetName, 'موردي النقل');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'currency',
        'phone',
        'email',
        'opening_balance',
        'balance_direction',
        'available_trips_count',
        'notes',
      ]);
    });

    test('8. Deduction Suppliers sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[7];
      expect(spec.sheetName, 'موردي التخصيمات');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'address',
        'deductions_mapping',
        'currency',
        'opening_balance',
        'balance_direction',
      ]);
    });

    test('9. Sea Clearing Agents sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[8];
      expect(spec.sheetName, 'المخلص البحري');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'email',
        'city',
        'country',
        'address',
        'contact_person',
        'opening_balance',
        'currency',
      ]);
    });

    test('10. Air Clearing Agents sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[9];
      expect(spec.sheetName, 'المخلص الجوي');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'email',
        'city',
        'country',
        'address',
        'contact_person',
        'opening_balance',
        'currency',
      ]);
    });

    test('11. Shipping Companies sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[10];
      expect(spec.sheetName, 'شركات الشحن');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'phone',
        'email',
        'opening_balance',
        'currency',
      ]);
    });

    test('12. Stations sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[11];
      expect(spec.sheetName, 'المحطات');
      expect(spec.headerColumnNames, [
        'code',
        'name',
      ]);
    });

    test('13. Packing Material Categories sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[12];
      expect(spec.sheetName, 'فئات مواد التعبئة');
      expect(spec.headerColumnNames, [
        'category_name',
      ]);
    });

    test('14. Packing Materials & Items sheet columns match exact requirements', () {
      final spec = DataMigrationTemplateService.allTableSpecs[13];
      expect(spec.sheetName, 'مواد التعبئة والمستلزمات');
      expect(spec.headerColumnNames, [
        'code',
        'name',
        'currency',
        'unit',
        'category',
        'opening_quantity',
        'opening_cost_price',
        'station_id',
      ]);
    });

    test('Unified workbook contains all 14 sheets + Guide with Row 0 headers only and 0 data rows', () {
      final bytes = DataMigrationTemplateService.generateUnifiedWorkbookBytes();
      expect(bytes, isNotEmpty);

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.keys, contains('دليل_التعليمات (Guide)'));

      for (final spec in DataMigrationTemplateService.allTableSpecs) {
        expect(excel.tables.keys, contains(spec.sheetName));

        final sheet = excel.tables[spec.sheetName]!;
        // Exactly 1 row (Row 0 Headers)
        expect(sheet.maxRows, 1);

        final headerRow = sheet.rows[0];
        final headerStrings = headerRow.map((cell) => cell?.value?.toString()).toList();
        expect(headerStrings, equals(spec.excelHeaderColumnNames));
      }
    });

    test('Individual template files export with exact headers and 0 data rows', () {
      for (final spec in DataMigrationTemplateService.allTableSpecs) {
        final bytes = DataMigrationTemplateService.generateSingleTemplateBytes(spec);
        expect(bytes, isNotEmpty);

        final excel = Excel.decodeBytes(bytes);
        expect(excel.tables.keys, contains(spec.sheetName));

        final sheet = excel.tables[spec.sheetName]!;
        expect(sheet.maxRows, 1);
        final headerStrings = sheet.rows[0].map((cell) => cell?.value?.toString()).toList();
        expect(headerStrings, equals(spec.excelHeaderColumnNames));
      }
    });

    test('exportUnifiedWorkbook saves safely to disk without crashing', () async {
      final tempDir = await Directory.systemTemp.createTemp('migration_14_test_');
      try {
        final path = await DataMigrationTemplateService.exportUnifiedWorkbook(
          customDirectory: tempDir.path,
          openAfterSave: false,
        );
        expect(File(path).existsSync(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('generateMockDataWorkbookBytes populates realistic mock data in all 14 sheets with foreign key relations', () {
      final bytes = DataMigrationTemplateService.generateMockDataWorkbookBytes();
      expect(bytes, isNotEmpty);

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.keys, contains('دليل_التعليمات (Guide)'));

      for (final spec in DataMigrationTemplateService.allTableSpecs) {
        expect(excel.tables.keys, contains(spec.sheetName));

        final sheet = excel.tables[spec.sheetName]!;
        // Must contain Row 0 (Headers) + At least 1-2 data rows
        expect(sheet.maxRows, greaterThanOrEqualTo(2));

        // Header check
        final headerRow = sheet.rows[0];
        final headerStrings = headerRow.map((cell) => cell?.value?.toString()).toList();
        expect(headerStrings, equals(spec.excelHeaderColumnNames));

        // Data row check (Must not be empty)
        final firstDataRow = sheet.rows[1];
        expect(firstDataRow.length, equals(spec.columns.length));
        expect(firstDataRow[0]?.value, isNotNull);
      }

      // Check Foreign Key consistency between sheets
      // 1. Station code in stations sheet (80000 - 89999)
      final stationsSheet = excel.tables['المحطات']!;
      final stationCodes = stationsSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(stationCodes, contains('80001'));
      expect(stationCodes, contains('80002'));

      // 2. Packing Material Categories in category sheet
      final catSheet = excel.tables['فئات مواد التعبئة']!;
      final categories = catSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(categories, contains('مواد تعبئة وكراتين'));
      expect(categories, contains('أطباق فوم وبلاستيك'));
      expect(categories, contains('طبالي وزوايا خشبية'));

      // 3. Materials sheet uses matching station_id and category
      final matSheet = excel.tables['مواد التعبئة والمستلزمات']!;
      final matRows = matSheet.rows.skip(1).toList();
      for (final row in matRows) {
        final catValue = row[4]?.value?.toString(); // category
        final stationValue = row[7]?.value?.toString(); // station_id
        expect(categories, contains(catValue));
        expect(stationCodes, contains(stationValue));
      }

      // 4. Code range checks for other sheets
      final expCustSheet = excel.tables['العملاء - تصديري']!;
      final expCodes = expCustSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(expCodes, contains('12001'));

      final locCustSheet = excel.tables['العملاء - محلي']!;
      final locCodes = locCustSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(locCodes, contains('12501'));

      final seaClearingSheet = excel.tables['المخلص البحري']!;
      final seaCodes = seaClearingSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(seaCodes, contains('20001'));

      final airClearingSheet = excel.tables['المخلص الجوي']!;
      final airCodes = airClearingSheet.rows.skip(1).map((r) => r[0]?.value?.toString()).toList();
      expect(airCodes, contains('25001'));
    });

    test('exportMockDataWorkbook creates valid Excel file on disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('mock_data_test_');
      try {
        final path = await DataMigrationTemplateService.exportMockDataWorkbook(
          customDirectory: tempDir.path,
          openAfterSave: false,
        );
        expect(File(path).existsSync(), isTrue);
        expect(File(path).lengthSync(), greaterThan(1000));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('exportMockDataWorkbook generates real file in user migration templates folder', () async {
      final userDocDir = Directory(r'C:\Users\mahmooud\OneDrive\Dokumente\Fruity_ERP_Migration_Templates');
      final targetDir = userDocDir.existsSync() ? userDocDir.path : Directory.systemTemp.path;
      final path = await DataMigrationTemplateService.exportMockDataWorkbook(
        customDirectory: targetDir,
        openAfterSave: false,
      );
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), greaterThan(1000));
    });

    test('exportUnifiedWorkbook generates fresh empty templates in user migration templates folder', () async {
      final userDocDir = Directory(r'C:\Users\mahmooud\OneDrive\Dokumente\Fruity_ERP_Migration_Templates');
      final targetDir = userDocDir.existsSync() ? userDocDir.path : Directory.systemTemp.path;
      final path = await DataMigrationTemplateService.exportUnifiedWorkbook(
        customDirectory: targetDir,
        openAfterSave: false,
      );
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), greaterThan(1000));
    });

    test('Required columns are formatted with asterisk * and match exact ERP rules', () {
      final specs = {for (final s in DataMigrationTemplateService.allTableSpecs) s.sheetName: s};

      // 1. Export Customers: code*, name*, currency*, city*, country*, opening_balance*
      final expReq = specs['العملاء - تصديري']!.columns.where((c) => c.isRequired).map((c) => c.columnName).toList();
      expect(expReq, containsAll(['code', 'name', 'currency', 'city', 'country', 'opening_balance']));
      expect(specs['العملاء - تصديري']!.excelHeaderColumnNames, containsAll(['code*', 'name*', 'currency*', 'city*', 'country*', 'opening_balance*']));

      // 2. Local Customers: code*, name*, currency*, opening_balance*
      final locReq = specs['العملاء - محلي']!.columns.where((c) => c.isRequired).map((c) => c.columnName).toList();
      expect(locReq, containsAll(['code', 'name', 'currency', 'opening_balance']));
      expect(specs['العملاء - محلي']!.excelHeaderColumnNames, containsAll(['code*', 'name*', 'currency*', 'opening_balance*']));

      // 2. Suppliers (all types): code*, name*, currency*, opening_balance*
      final supplierSheets = [
        'موردين المحاصيل',
        'موردين مواد التعبئة',
        'الموردين المشتركين',
        'موردي المحطات',
        'موردي النقل',
        'موردي التخصيمات',
      ];
      for (final sheet in supplierSheets) {
        final reqCols = specs[sheet]!.columns.where((c) => c.isRequired).map((c) => c.columnName).toList();
        expect(reqCols, containsAll(['code', 'name', 'currency', 'opening_balance']), reason: 'Failed for sheet: $sheet');
        expect(specs[sheet]!.excelHeaderColumnNames, containsAll(['code*', 'name*', 'currency*', 'opening_balance*']), reason: 'Header failed for sheet: $sheet');
      }

      // 3. Stations: code*, name*
      expect(specs['المحطات']!.excelHeaderColumnNames, containsAll(['code*', 'name*']));

      // 4. Clearing Agents & Shipping: code*, name*, currency*
      for (final sheet in ['المخلص البحري', 'المخلص الجوي', 'شركات الشحن']) {
        expect(specs[sheet]!.excelHeaderColumnNames, containsAll(['code*', 'name*', 'currency*']), reason: 'Failed for sheet: $sheet');
      }

      // 5. Packing Materials: code*, name*, currency*, unit*, category*
      expect(specs['مواد التعبئة والمستلزمات']!.excelHeaderColumnNames, containsAll(['code*', 'name*', 'currency*', 'unit*', 'category*']));

      // 6. Packing Categories: category_name*
      expect(specs['فئات مواد التعبئة']!.excelHeaderColumnNames, contains('category_name*'));
    });
  });
}
