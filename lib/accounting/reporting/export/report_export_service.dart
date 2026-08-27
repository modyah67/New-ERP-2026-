/// ReportExportService — Reusable export engine for financial reports
///
/// Generates Excel, PDF, CSV, and print-ready output for all report types.
/// Uses the existing `excel` and `pdf` packages already in the project.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/report_models.dart';

class ReportExportService {
  ReportExportService._();

  // ─────────────────────────────────────────────
  // ARABIC PDF FONTS (lazy-loaded, cached)
  // ─────────────────────────────────────────────

  static pw.Font? _arabicFont;
  static pw.Font? _arabicBoldFont;
  static pw.MemoryImage? _bgImage;

  static Future<void> _loadFonts() async {
    if (_arabicFont == null) {
      final regular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _arabicFont = pw.Font.ttf(regular);
      _arabicBoldFont = pw.Font.ttf(bold);
    }
    if (_bgImage == null) {
      final bgData = await rootBundle.load('assets/images/statment.png');
      _bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    }
  }

  // ─────────────────────────────────────────────
  // TRIAL BALANCE EXPORT
  // ─────────────────────────────────────────────

  /// Export Trial Balance to Excel
  static Excel exportTrialBalanceToExcel(TrialBalanceReport report) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'ميزانية تجريبية');
    final sheet = excel['ميزانية تجريبية'];

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('الميزانية التجريبية / Trial Balance');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('بتاريخ: ${_formatDate(report.asOfDate)}');

    final headers = ['كود الحساب', 'اسم الحساب', 'مدين', 'دائن'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1B3A5C'),
        fontColorHex: ExcelColor.white,
      );
    }

    for (var i = 0; i < report.rows.length; i++) {
      final row = report.rows[i];
      final rowIndex = 5 + i;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
          TextCellValue(row.accountCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value =
          TextCellValue(row.accountNameAr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value =
          DoubleCellValue(row.debit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value =
          DoubleCellValue(row.credit);
    }

    final totalRow = 5 + report.rows.length;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: totalRow)).value =
        TextCellValue('الإجمالي');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: totalRow)).value =
        DoubleCellValue(report.totalDebit);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow)).value =
        DoubleCellValue(report.totalCredit);

    return excel;
  }

  /// Export Trial Balance to PDF
  static Future<pw.Document> exportTrialBalanceToPdf(TrialBalanceReport report) async {
    await _loadFonts();
    final doc = pw.Document();

    final tableData = <List<String>>[];
    for (final r in report.rows) {
      tableData.add([r.accountCode, r.accountNameAr, _fmt(r.debit), _fmt(r.credit)]);
    }
    tableData.add(['', 'الإجمالي', _fmt(report.totalDebit), _fmt(report.totalCredit)]);

    doc.addPage(pw.Page(
      pageTheme: pw.PageTheme(
        theme: pw.ThemeData.withFont(base: _arabicFont!, bold: _arabicBoldFont!),
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(_bgImage!, fit: pw.BoxFit.cover),
        ),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('الميزانية التجريبية / Trial Balance',
              style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 4),
          pw.Text('بتاريخ: ${_formatDate(report.asOfDate)}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['كود الحساب', 'اسم الحساب', 'مدين', 'دائن'],
            data: tableData,
          ),
        ],
      ),
    ));

    return doc;
  }

  // ─────────────────────────────────────────────
  // GENERAL LEDGER EXPORT
  // ─────────────────────────────────────────────

  /// Export General Ledger to PDF (real Arabic RTL, multi-page)
  static Future<Uint8List> exportLedgerToPdf(
    LedgerReport report, {
    String companyName = 'المؤسسة',
  }) async {
    await _loadFonts();

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _arabicFont!,
      bold: _arabicBoldFont!,
    );

    final pageFormat = PdfPageFormat.a4.landscape;
    final rowsPerPage = 30;
    final totalPages = (report.rows.length / rowsPerPage).ceil();

    for (var pageNum = 0; pageNum < totalPages; pageNum++) {
      final start = pageNum * rowsPerPage;
      final end = (start + rowsPerPage).clamp(0, report.rows.length);
      final pageRows = report.rows.sublist(start, end);
      final isLastPage = pageNum == totalPages - 1;

      final tableData = <List<String>>[];
      for (final row in pageRows) {
        tableData.add([
          _formatDate(row.date),
          row.entryNumber?.toString() ?? '',
          row.description ?? '',
          _fmt(row.debit),
          _fmt(row.credit),
          _fmt(row.balance),
        ]);
      }

      if (isLastPage) {
        tableData.add(['', '', 'الإجمالي', _fmt(report.totalDebit), _fmt(report.totalCredit), '']);
      }

      doc.addPage(pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          theme: theme,
          textDirection: pw.TextDirection.rtl,
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(_bgImage!, fit: pw.BoxFit.cover),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${pageNum + 1} من $totalPages',
            style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(companyName,
                            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 18)),
                        pw.SizedBox(height: 4),
                        pw.Text('دفتر الأستاذ العام',
                            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                            'من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}',
                            style: pw.TextStyle(font: _arabicFont!, fontSize: 11)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                            'تم الإنشاء: ${_formatDate(report.generatedAt)}',
                            style: pw.TextStyle(font: _arabicFont!, fontSize: 9, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text('الرصيد الافتتاحي: ${_fmt(report.openingBalance)}',
                            style: pw.TextStyle(font: _arabicFont!, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: _arabicBoldFont!, fontSize: 9, color: PdfColors.white),
                  cellStyle: pw.TextStyle(font: _arabicFont!, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B3A5C)),
                  headers: ['التاريخ', 'رقم القيد', 'البيان', 'مدين', 'دائن', 'الرصيد'],
                  data: tableData,
                  cellAlignments: {
                    0: pw.Alignment.centerRight,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerLeft,
                    5: pw.Alignment.centerLeft,
                  },
                  headerAlignments: {
                    0: pw.Alignment.centerRight,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerLeft,
                    5: pw.Alignment.centerLeft,
                  },
                ),
                if (isLastPage) ...[
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text('الرصيد الختامي: ${_fmt(report.closingBalance)}',
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ));
    }

    return doc.save();
  }

  /// Export General Ledger to Excel
  static Excel exportLedgerToExcel(LedgerReport report) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'دفتر الأستاذ');
    final sheet = excel['دفتر الأستاذ'];

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('دفتر الأستاذ العام / General Ledger');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}');
    sheet.cell(CellIndex.indexByString('A3')).value =
        TextCellValue('الرصيد الافتتاحي: ${_fmt(report.openingBalance)}');

    final headers = ['التاريخ', 'الرقم', 'الحساب', 'الوصف', 'مدين', 'دائن', 'الرصيد'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1B3A5C'),
        fontColorHex: ExcelColor.white,
      );
    }

    for (var i = 0; i < report.rows.length; i++) {
      final row = report.rows[i];
      final rowIndex = 6 + i;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
          TextCellValue(_formatDate(row.date));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value =
          TextCellValue(row.entryNumber?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value =
          TextCellValue(row.accountCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value =
          TextCellValue(row.description ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value =
          DoubleCellValue(row.debit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value =
          DoubleCellValue(row.credit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value =
          DoubleCellValue(row.balance);
    }

    return excel;
  }

  // ─────────────────────────────────────────────
  // BALANCE SHEET EXPORT
  // ─────────────────────────────────────────────

  /// Export Balance Sheet to PDF
  static Future<Uint8List> exportBalanceSheetToPdf(
    BalanceSheetReport report, {
    String companyName = 'المؤسسة',
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _arabicFont!,
      bold: _arabicBoldFont!,
    );

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(_bgImage!, fit: pw.BoxFit.cover),
        ),
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(companyName,
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 18)),
                      pw.SizedBox(height: 4),
                      pw.Text('الميزانية العامة',
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('بتاريخ: ${_formatDate(report.asOfDate)}',
                          style: pw.TextStyle(font: _arabicFont!, fontSize: 11)),
                      pw.SizedBox(height: 2),
                      pw.Text('تم الإنشاء: ${_formatDate(report.generatedAt)}',
                          style: pw.TextStyle(
                              font: _arabicFont!, fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              _buildPdfSection('الأصول', report.assets),
              pw.SizedBox(height: 12),
              _buildPdfSection('الخصوم', report.liabilities),
              pw.SizedBox(height: 12),
              _buildPdfSection('حقوق الملكية', report.equity),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('إجمالي الأصول: ${_fmt(report.totalAssets)}',
                      style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
                  pw.Text(
                      'إجمالي الخصوم وحقوق الملكية: ${_fmt(report.totalLiabilitiesAndEquity)}',
                      style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                  'الفرق: ${_fmt(report.difference)} ${report.isBalanced ? "(متوازن)" : "(غير متوازن)"}',
                  style: pw.TextStyle(
                      font: _arabicBoldFont!,
                      fontSize: 11,
                      color: report.isBalanced ? PdfColors.green : PdfColors.red)),
            ],
          ),
        ),
      ],
    ));

    return doc.save();
  }

  static pw.Widget _buildPdfSection(String title, BalanceSheetSection section) {
    final tableData = <List<String>>[];
    for (final line in section.lines) {
      tableData.add([line.accountCode, line.accountNameAr, _fmt(line.amount)]);
    }
    tableData.add(['', 'الإجمالي', _fmt(section.total)]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 13)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
              font: _arabicBoldFont!, fontSize: 9, color: PdfColors.white),
          cellStyle: pw.TextStyle(font: _arabicFont!, fontSize: 9),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B3A5C)),
          headers: ['الكود', 'الاسم', 'المبلغ'],
          data: tableData,
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerLeft,
          },
        ),
      ],
    );
  }
  static Excel exportBalanceSheetToExcel(BalanceSheetReport report) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'الميزانية العامة');
    final sheet = excel['الميزانية العامة'];

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('الميزانية العامة / Balance Sheet');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('بتاريخ: ${_formatDate(report.asOfDate)}');

    var row = 4;
    row = _writeSection(sheet, row, report.assets, 'الأصول');
    row += 2;
    row = _writeSection(sheet, row, report.liabilities, 'الخصوم');
    row += 2;
    row = _writeSection(sheet, row, report.equity, 'حقوق الملكية');
    row += 2;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        TextCellValue('إجمالي الأصول');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
        DoubleCellValue(report.totalAssets);

    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        TextCellValue('إجمالي الخصوم وحقوق الملكية');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
        DoubleCellValue(report.totalLiabilitiesAndEquity);

    return excel;
  }

  static int _writeSection(
    Sheet sheet,
    int startRow,
    BalanceSheetSection section,
    String title,
  ) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue(title);
    startRow++;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue('الكود');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
        TextCellValue('الاسم');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: startRow)).value =
        TextCellValue('المبلغ');
    startRow++;

    for (final line in section.lines) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
          TextCellValue(line.accountCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
          TextCellValue(line.accountNameAr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: startRow)).value =
          DoubleCellValue(line.amount);
      startRow++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
        TextCellValue('الإجمالي');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: startRow)).value =
        DoubleCellValue(section.total);

    return startRow + 1;
  }

  // ─────────────────────────────────────────────
  // INCOME STATEMENT EXPORT
  // ─────────────────────────────────────────────

  /// Export Income Statement to Excel
  static Excel exportIncomeStatementToExcel(IncomeStatementReport report) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'قائمة الدخل');
    final sheet = excel['قائمة الدخل'];

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('قائمة الدخل / Income Statement');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}');

    var row = 4;
    row = _writeIncomeSection(sheet, row, report.revenue, 'الإيرادات');
    row++;
    row = _writeIncomeSection(sheet, row, report.costOfGoodsSold, 'تكلفة البضاعة المباعة');
    row++;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        TextCellValue('إجمالي الربح');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
        DoubleCellValue(report.grossProfit);
    row += 2;

    row = _writeIncomeSection(sheet, row, report.operatingExpenses, 'المصروفات التشغيلية');
    row++;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        TextCellValue('صافي الدخل');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
        DoubleCellValue(report.netIncome);

    return excel;
  }

  static int _writeIncomeSection(
    Sheet sheet,
    int startRow,
    IncomeStatementSection section,
    String title,
  ) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue(title);
    startRow++;

    for (final line in section.lines) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
          TextCellValue('  ${line.accountCode} ${line.accountNameAr}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
          DoubleCellValue(line.amount);
      startRow++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue('الإجمالي: ${section.titleAr}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
        DoubleCellValue(section.total);

    return startRow + 1;
  }

  // ─────────────────────────────────────────────
  // CSV EXPORT
  // ─────────────────────────────────────────────

  /// Export Trial Balance as CSV string
  static String exportTrialBalanceToCsv(TrialBalanceReport report) {
    final buffer = StringBuffer();
    buffer.writeln('كود الحساب,اسم الحساب,مدين,دائن');
    for (final row in report.rows) {
      buffer.writeln('${row.accountCode},${row.accountNameAr},${row.debit},${row.credit}');
    }
    buffer.writeln(',الإجمالي,${report.totalDebit},${report.totalCredit}');
    return buffer.toString();
  }

  /// Export General Ledger as CSV string
  static String exportLedgerToCsv(LedgerReport report) {
    final buffer = StringBuffer();
    buffer.writeln('التاريخ,الرقم,الحساب,الوصف,مدين,دائن,الرصيد');
    for (final row in report.rows) {
      buffer.writeln(
          '${_formatDate(row.date)},${row.entryNumber ?? ""},${row.accountCode},"${row.description ?? ""}",${row.debit},${row.credit},${row.balance}');
    }
    return buffer.toString();
  }

  /// Export Balance Sheet as CSV string
  static String exportBalanceSheetToCsv(BalanceSheetReport report) {
    final buffer = StringBuffer();
    buffer.writeln('الميزانية العامة');
    buffer.writeln('بتاريخ,${_formatDate(report.asOfDate)}');
    buffer.writeln();
    buffer.writeln('القسم,كود الحساب,اسم الحساب,المبلغ');
    for (final line in report.assets.lines) {
      buffer.writeln('الأصول,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('الأصول,الإجمالي,,${report.assets.total}');
    for (final line in report.liabilities.lines) {
      buffer.writeln('الخصوم,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('الخصوم,الإجمالي,,${report.liabilities.total}');
    for (final line in report.equity.lines) {
      buffer.writeln('حقوق الملكية,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('حقوق الملكية,الإجمالي,,${report.equity.total}');
    buffer.writeln();
    buffer.writeln('إجمالي الأصول,,${report.totalAssets}');
    buffer.writeln('إجمالي الخصوم وحقوق الملكية,,${report.totalLiabilitiesAndEquity}');
    return buffer.toString();
  }

  /// Export Income Statement as CSV string
  static String exportIncomeStatementToCsv(IncomeStatementReport report) {
    final buffer = StringBuffer();
    buffer.writeln('قائمة الدخل');
    buffer.writeln('من,${_formatDate(report.fromDate)},إلى,${_formatDate(report.toDate)}');
    buffer.writeln();
    buffer.writeln('القسم,كود الحساب,اسم الحساب,المبلغ');
    for (final line in report.revenue.lines) {
      buffer.writeln('الإيرادات,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('الإيرادات,الإجمالي,,${report.revenue.total}');
    for (final line in report.costOfGoodsSold.lines) {
      buffer.writeln('تكلفة البضاعة,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('تكلفة البضاعة,الإجمالي,,${report.costOfGoodsSold.total}');
    buffer.writeln('إجمالي الربح,,,${report.grossProfit}');
    for (final line in report.operatingExpenses.lines) {
      buffer.writeln('المصروفات,${line.accountCode},${line.accountNameAr},${line.amount}');
    }
    buffer.writeln('المصروفات,الإجمالي,,${report.operatingExpenses.total}');
    buffer.writeln('صافي الدخل,,,${report.netIncome}');
    return buffer.toString();
  }

  /// Export Cash Flow as CSV string
  static String exportCashFlowToCsv(CashFlowReport report) {
    final buffer = StringBuffer();
    buffer.writeln('قائمة التدفقات النقدية');
    buffer.writeln('من,${_formatDate(report.fromDate)},إلى,${_formatDate(report.toDate)}');
    buffer.writeln();
    buffer.writeln('القسم,البيان,المبلغ');
    for (final line in report.operating.lines) {
      buffer.writeln('الأنشطة التشغيلية,${line.descriptionAr},${line.amount}');
    }
    buffer.writeln('الأنشطة التشغيلية,الإجمالي,,${report.netCashFromOperating}');
    for (final line in report.investing.lines) {
      buffer.writeln('الأنشطة الاستثمارية,${line.descriptionAr},${line.amount}');
    }
    buffer.writeln('الأنشطة الاستثمارية,الإجمالي,,${report.netCashFromInvesting}');
    for (final line in report.financing.lines) {
      buffer.writeln('الأنشطة التمويلية,${line.descriptionAr},${line.amount}');
    }
    buffer.writeln('الأنشطة التمويلية,الإجمالي,,${report.netCashFromFinancing}');
    buffer.writeln('صافي التدفق,,,${report.netChangeInCash}');
    return buffer.toString();
  }

  // ─────────────────────────────────────────────
  // INCOME STATEMENT PDF EXPORT
  // ─────────────────────────────────────────────

  /// Export Income Statement to PDF
  static Future<Uint8List> exportIncomeStatementToPdf(
    IncomeStatementReport report, {
    String companyName = 'المؤسسة',
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _arabicFont!,
      bold: _arabicBoldFont!,
    );

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(_bgImage!, fit: pw.BoxFit.cover),
        ),
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(companyName,
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 18)),
                      pw.SizedBox(height: 4),
                      pw.Text('قائمة الدخل',
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          'من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}',
                          style: pw.TextStyle(font: _arabicFont!, fontSize: 11)),
                      pw.SizedBox(height: 2),
                      pw.Text('تم الإنشاء: ${_formatDate(report.generatedAt)}',
                          style: pw.TextStyle(
                              font: _arabicFont!, fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              _buildIncomePdfSection('الإيرادات', report.revenue),
              pw.SizedBox(height: 8),
              _buildIncomePdfSection('تكلفة البضاعة المباعة', report.costOfGoodsSold),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFE8F5E9)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي الربح',
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
                    pw.Text(_fmt(report.grossProfit),
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              _buildIncomePdfSection('المصروفات التشغيلية', report.operatingExpenses),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: report.netIncome >= 0
                      ? const PdfColor.fromInt(0xFFE8F5E9)
                      : const PdfColor.fromInt(0xFFFFEBEE),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('صافي الدخل',
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                    pw.Text(_fmt(report.netIncome),
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ));

    return doc.save();
  }

  static pw.Widget _buildIncomePdfSection(
      String title, IncomeStatementSection section) {
    final tableData = <List<String>>[];
    for (final line in section.lines) {
      tableData.add(['${line.accountCode} ${line.accountNameAr}', _fmt(line.amount)]);
    }
    tableData.add(['الإجمالي', _fmt(section.total)]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
              font: _arabicBoldFont!, fontSize: 9, color: PdfColors.white),
          cellStyle: pw.TextStyle(font: _arabicFont!, fontSize: 9),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B3A5C)),
          headers: ['الحساب', 'المبلغ'],
          data: tableData,
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // CASH FLOW EXPORT
  // ─────────────────────────────────────────────

  /// Export Cash Flow to PDF
  static Future<Uint8List> exportCashFlowToPdf(
    CashFlowReport report, {
    String companyName = 'المؤسسة',
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _arabicFont!,
      bold: _arabicBoldFont!,
    );

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(_bgImage!, fit: pw.BoxFit.cover),
        ),
      ),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(companyName,
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 18)),
                      pw.SizedBox(height: 4),
                      pw.Text('قائمة التدفقات النقدية',
                          style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          'من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}',
                          style: pw.TextStyle(font: _arabicFont!, fontSize: 11)),
                      pw.SizedBox(height: 2),
                      pw.Text('تم الإنشاء: ${_formatDate(report.generatedAt)}',
                          style: pw.TextStyle(
                              font: _arabicFont!, fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              _buildCashFlowPdfSection('الأنشطة التشغيلية', report.operating, report.netCashFromOperating),
              pw.SizedBox(height: 8),
              _buildCashFlowPdfSection('الأنشطة الاستثمارية', report.investing, report.netCashFromInvesting),
              pw.SizedBox(height: 8),
              _buildCashFlowPdfSection('الأنشطة التمويلية', report.financing, report.netCashFromFinancing),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: report.netChangeInCash >= 0
                      ? const PdfColor.fromInt(0xFFE8F5E9)
                      : const PdfColor.fromInt(0xFFFFEBEE),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('صافي التغير في النقد',
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                    pw.Text(_fmt(report.netChangeInCash),
                        style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ));

    return doc.save();
  }

  static pw.Widget _buildCashFlowPdfSection(
      String title, CashFlowSection section, double sectionTotal) {
    final tableData = <List<String>>[];
    for (final line in section.lines) {
      tableData.add([line.descriptionAr, _fmt(line.amount)]);
    }
    tableData.add(['الإجمالي', _fmt(sectionTotal)]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(font: _arabicBoldFont!, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
              font: _arabicBoldFont!, fontSize: 9, color: PdfColors.white),
          cellStyle: pw.TextStyle(font: _arabicFont!, fontSize: 9),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B3A5C)),
          headers: ['البيان', 'المبلغ'],
          data: tableData,
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
          },
        ),
      ],
    );
  }

  /// Export Cash Flow to Excel
  static Excel exportCashFlowToExcel(CashFlowReport report) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'التدفقات النقدية');
    final sheet = excel['التدفقات النقدية'];

    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('قائمة التدفقات النقدية / Cash Flow Statement');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('من: ${_formatDate(report.fromDate)} إلى: ${_formatDate(report.toDate)}');

    var row = 4;
    row = _writeCashFlowSection(sheet, row, report.operating, 'الأنشطة التشغيلية', report.netCashFromOperating);
    row++;
    row = _writeCashFlowSection(sheet, row, report.investing, 'الأنشطة الاستثمارية', report.netCashFromInvesting);
    row++;
    row = _writeCashFlowSection(sheet, row, report.financing, 'الأنشطة التمويلية', report.netCashFromFinancing);
    row++;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
        TextCellValue('صافي التغير في النقد');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
        DoubleCellValue(report.netChangeInCash);

    return excel;
  }

  static int _writeCashFlowSection(
    Sheet sheet,
    int startRow,
    CashFlowSection section,
    String title,
    double sectionTotal,
  ) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue(title);
    startRow++;

    for (final line in section.lines) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
          TextCellValue('  ${line.descriptionAr}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
          DoubleCellValue(line.amount);
      startRow++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
        TextCellValue('الإجمالي: $title');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: startRow)).value =
        DoubleCellValue(sectionTotal);

    return startRow + 1;
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  static String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _fmt(double value) {
    return value.toStringAsFixed(2);
  }
}
