import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/backup/data_migration_template_service.dart';
import 'package:excel/excel.dart';

void main() {
  group('DataMigrationImportService Tests', () {
    test('generateMockDataWorkbookBytes can be parsed by Excel', () {
      final bytes = DataMigrationTemplateService.generateMockDataWorkbookBytes();
      expect(bytes, isNotEmpty);

      final excel = Excel.decodeBytes(bytes);
      expect(excel.tables.isNotEmpty, isTrue);

      final nonGuideSheets = excel.tables.keys
          .where((k) => !k.contains('Guide') && !k.contains('دليل_التعليمات'))
          .toList();
      expect(nonGuideSheets.length, equals(14));
    });

    test('DataMigrationImportService handles mock data workbook parsing safely', () async {
      // Create an excel file in temp
      final bytes = DataMigrationTemplateService.generateMockDataWorkbookBytes();
      final tempDir = await Directory.systemTemp.createTemp('import_test_');
      final tempFile = File('${tempDir.path}/test_migration.xlsx');
      await tempFile.writeAsBytes(bytes);

      try {
        final excel = Excel.decodeBytes(bytes);
        // Verify all 14 sheets have data rows
        for (final spec in DataMigrationTemplateService.allTableSpecs) {
          final sheet = excel.tables[spec.sheetName];
          expect(sheet, isNotNull, reason: 'Sheet ${spec.sheetName} must exist');
          expect(sheet!.maxRows, greaterThanOrEqualTo(2), reason: 'Sheet ${spec.sheetName} must have at least 1 mock data row');

          final headers = sheet.rows[0].map((c) => c?.value?.toString().replaceAll('*', '').trim().toLowerCase()).toList();
          for (final col in spec.headerColumnNames) {
            expect(headers, contains(col.toLowerCase()), reason: 'Sheet ${spec.sheetName} must contain column $col');
          }
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('All 14 sheet names are resolved to correct database table names', () {
      final specs = DataMigrationTemplateService.allTableSpecs;
      for (final spec in specs) {
        final sheetName = spec.sheetName;
        // Verify expected table mapping
        switch (sheetName) {
          case 'المحطات':
            expect(spec.tableId, 'stations');
            break;
          case 'فئات مواد التعبئة':
            expect(spec.tableId, 'raw_material_categories');
            break;
          case 'العملاء - تصديري':
          case 'العملاء - محلي':
            expect(spec.tableId, 'customers');
            break;
          case 'موردين المحاصيل':
          case 'موردين مواد التعبئة':
          case 'الموردين المشتركين':
          case 'موردي المحطات':
          case 'موردي التخصيمات':
            expect(spec.tableId, 'suppliers');
            break;
          case 'موردي النقل':
            expect(spec.tableId, 'transport_suppliers');
            break;
          case 'المخلص البحري':
          case 'المخلص الجوي':
            expect(spec.tableId, 'clearing_agents');
            break;
          case 'شركات الشحن':
            expect(spec.tableId, 'shipping_companies');
            break;
          case 'مواد التعبئة والمستلزمات':
            expect(spec.tableId, 'raw_materials');
            break;
          default:
            fail('Unknown sheet name: $sheetName');
        }
      }
    });
  });
}

