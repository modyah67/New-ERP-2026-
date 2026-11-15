import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/backup/data_audit_service.dart';

void main() {
  group('DataAuditService & Report Models Verification', () {
    test('DataAuditCategoryResult correctly calculates status and counts', () {
      final passedCategory = DataAuditCategoryResult(
        categoryKey: 'crop',
        categoryName: 'موردين المحاصيل',
        tableName: 'suppliers',
        codeRangeDisplay: '50000 - 59999',
        minCode: 50000,
        maxCode: 59999,
        totalCount: 25,
        totalInitialBalance: 150000.0,
        issues: const [],
      );

      expect(passedCategory.isPassed, isTrue);
      expect(passedCategory.warningCount, 0);
      expect(passedCategory.validCount, 25);

      final warningCategory = DataAuditCategoryResult(
        categoryKey: 'transport',
        categoryName: 'موردي النقل',
        tableName: 'suppliers',
        codeRangeDisplay: '60000 - 69999',
        minCode: 60000,
        maxCode: 69999,
        totalCount: 10,
        totalInitialBalance: 45000.0,
        issues: const [
          DataAuditItemIssue(
            categoryName: 'موردي النقل',
            tableName: 'suppliers',
            recordId: '1',
            code: '105',
            name: 'سائق غير معتمد',
            issueType: 'كود خارج النطاق',
            details: 'الكود 105 خارج النطاق المعتمد (60000 - 69999)',
          ),
        ],
      );

      expect(warningCategory.isPassed, isFalse);
      expect(warningCategory.warningCount, 1);
      expect(warningCategory.validCount, 9);
    });

    test('DataAuditReport correctly aggregates multiple categories', () {
      final cat1 = DataAuditCategoryResult(
        categoryKey: 'crop',
        categoryName: 'موردين المحاصيل',
        tableName: 'suppliers',
        codeRangeDisplay: '50000 - 59999',
        totalCount: 30,
        totalInitialBalance: 200000.0,
        issues: const [],
      );

      final cat2 = DataAuditCategoryResult(
        categoryKey: 'packaging',
        categoryName: 'موردين مواد التعبئة',
        tableName: 'suppliers',
        codeRangeDisplay: '70000 - 74999',
        totalCount: 15,
        totalInitialBalance: 80000.0,
        issues: const [
          DataAuditItemIssue(
            categoryName: 'موردين مواد التعبئة',
            tableName: 'suppliers',
            recordId: '2',
            code: '',
            name: 'شركة تعبئة بلاستيك',
            issueType: 'كود مفقود',
            details: 'المورد بدون كود',
          ),
        ],
      );

      final report = DataAuditReport(
        generatedAt: DateTime.now(),
        categories: [cat1, cat2],
        totalRecords: cat1.totalCount + cat2.totalCount,
        totalInitialBalance: cat1.totalInitialBalance + cat2.totalInitialBalance,
        totalPassedCategories: 1,
        totalWarningCategories: 1,
        totalIssues: 1,
      );

      expect(report.totalRecords, 45);
      expect(report.totalInitialBalance, 280000.0);
      expect(report.totalPassedCategories, 1);
      expect(report.totalWarningCategories, 1);
      expect(report.totalIssues, 1);
      expect(report.isAllPassed, isFalse);
    });

    test('Excel generation produces valid bytes with two sheets', () {
      final cat1 = DataAuditCategoryResult(
        categoryKey: 'crop',
        categoryName: 'موردين المحاصيل',
        tableName: 'suppliers',
        codeRangeDisplay: '50000 - 59999',
        totalCount: 10,
        totalInitialBalance: 50000.0,
        issues: const [],
      );

      final report = DataAuditReport(
        generatedAt: DateTime.now(),
        categories: [cat1],
        totalRecords: 10,
        totalInitialBalance: 50000.0,
        totalPassedCategories: 1,
        totalWarningCategories: 0,
        totalIssues: 0,
      );

      final excelBytes = DataAuditService.generateExcelBytes(report);
      expect(excelBytes, isNotEmpty);
      expect(excelBytes.length, greaterThan(100));
    });

    test('PDF generation produces valid Landscape document bytes', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cat1 = DataAuditCategoryResult(
        categoryKey: 'crop',
        categoryName: 'موردين المحاصيل',
        tableName: 'suppliers',
        codeRangeDisplay: '50000 - 59999',
        totalCount: 10,
        totalInitialBalance: 50000.0,
        issues: const [
          DataAuditItemIssue(
            categoryName: 'موردين المحاصيل',
            tableName: 'suppliers',
            recordId: '1',
            code: '999',
            name: 'مورد تجريبي',
            issueType: 'كود خارج النطاق',
            details: 'كود غير مطابق للنطاق',
          ),
        ],
      );

      final report = DataAuditReport(
        generatedAt: DateTime.now(),
        categories: [cat1],
        totalRecords: 10,
        totalInitialBalance: 50000.0,
        totalPassedCategories: 0,
        totalWarningCategories: 1,
        totalIssues: 1,
      );

      final doc = await DataAuditService.buildPdfDocument(report);
      final pdfBytes = await doc.save();
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(500));
    });
  });
}

