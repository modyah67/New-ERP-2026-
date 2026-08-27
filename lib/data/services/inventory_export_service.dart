import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class InventoryExportService {
  /// Build Excel bytes without saving (for headless/backup use)
  static List<int>? buildExcelBytes({
    required String title,
    required List<Map<String, dynamic>> items,
    bool includeZeroValues = false,
  }) {
    final now = DateTime.now();
    final filtered = includeZeroValues
        ? items
        : items.where((e) {
            final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
            final value = (e['totalValue'] as num?)?.toDouble() ?? 0.0;
            return qty > 0 || value > 0;
          }).toList();

    final categories = <String>{};
    final currencyTotals = <String, double>{};
    final categoryGroups = <String, List<Map<String, dynamic>>>{};

    for (final item in filtered) {
      final cat = (item['categoryName']?.toString() ?? '').isEmpty
          ? 'بدون فئة'
          : item['categoryName'].toString();
      categories.add(cat);
      categoryGroups.putIfAbsent(cat, () => []).add(item);

      final currency = (item['currency']?.toString() ?? 'EGP').toUpperCase();
      final value = (item['totalValue'] as num?)?.toDouble() ?? 0.0;
      currencyTotals[currency] = (currencyTotals[currency] ?? 0) + value;
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final mainSheet = excel[title];
    _buildMainSheet(mainSheet, title, now, filtered, categories, categoryGroups,
        currencyTotals);

    final summarySheet = excel['Summary'];
    _buildSummarySheet(summarySheet, title, now, filtered, categories,
        categoryGroups, currencyTotals);

    return excel.save();
  }

  static Future<void> exportItemsWithBatches({
    required String title,
    required List<Map<String, dynamic>> items,
    bool includeZeroValues = false,
  }) async {
    final now = DateTime.now();
    final filtered = includeZeroValues
        ? items
        : items.where((e) {
            final qty = (e['quantity'] as num?)?.toDouble() ?? 0.0;
            final value = (e['totalValue'] as num?)?.toDouble() ?? 0.0;
            return qty > 0 || value > 0;
          }).toList();

    final categories = <String>{};
    final currencyTotals = <String, double>{};
    final categoryGroups = <String, List<Map<String, dynamic>>>{};

    for (final item in filtered) {
      final cat = (item['categoryName']?.toString() ?? '').isEmpty
          ? 'بدون فئة'
          : item['categoryName'].toString();
      categories.add(cat);
      categoryGroups.putIfAbsent(cat, () => []).add(item);

      final currency = (item['currency']?.toString() ?? 'EGP').toUpperCase();
      final value = (item['totalValue'] as num?)?.toDouble() ?? 0.0;
      currencyTotals[currency] = (currencyTotals[currency] ?? 0) + value;
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final mainSheet = excel[title];
    _buildMainSheet(mainSheet, title, now, filtered, categories, categoryGroups,
        currencyTotals);

    final summarySheet = excel['Summary'];
    _buildSummarySheet(summarySheet, title, now, filtered, categories,
        categoryGroups, currencyTotals);

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = '${title}_${now.millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }

  static Border _thinBorder(ExcelColor color) => Border(
        borderStyle: BorderStyle.Thin,
        borderColorHex: color,
      );

  static void _buildMainSheet(
    Sheet sheet,
    String title,
    DateTime now,
    List<Map<String, dynamic>> items,
    Set<String> categories,
    Map<String, List<Map<String, dynamic>>> categoryGroups,
    Map<String, double> currencyTotals,
  ) {
    const headerBg = '#FF1A237E';
    const headerFg = '#FFFFFFFF';
    const categoryBg = '#FFE8F5E9';
    const categoryFg = '#FF1B5E20';
    const subtotalBg = '#FFC8E6C9';
    const subtotalFg = '#FF1B5E20';
    const grandTotalBg = '#FF37474F';
    const grandTotalFg = '#FFFFFFFF';
    const borderColor = '#FFB0BEC5';

    const headers = [
      'الكود',
      'الصنف',
      'الفئة',
      'الوحدة',
      'الكمية المتبقية',
      'العملة',
      'قيمة الصنف',
    ];

    final border = ExcelColor.fromHexString(borderColor);
    int r = 0;

    // --- Report Title (merged) ---
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue(title);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: ExcelColor.fromHexString(headerBg),
      horizontalAlign: HorizontalAlign.Center,
    );
    r++;

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue('Inventory Report');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString('#FF546E7A'),
      horizontalAlign: HorizontalAlign.Center,
    );
    r++;

    // --- Report Info ---
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr = _formatTime(now);

    final infoLabels = [
      ('تاريخ التقرير', 'Report Date', dateStr),
      ('وقت التقرير', 'Report Time', timeStr),
      ('عدد الأصناف', 'Total Items', '${items.length}'),
      ('عدد الفئات', 'Total Categories', '${categories.length}'),
    ];

    for (final (arLabel, enLabel, value) in infoLabels) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r),
      );
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue('$arLabel : $value');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#FF37474F'),
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .value = TextCellValue('$enLabel: $value');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
          .cellStyle = CellStyle(
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#FF78909C'),
      );
      r++;
    }

    r++; // blank row

    // --- Column Headers ---
    for (var c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value = TextCellValue(headers[c]);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        backgroundColorHex: ExcelColor.fromHexString(headerBg),
        fontColorHex: ExcelColor.fromHexString(headerFg),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        topBorder: _thinBorder(border),
        bottomBorder: _thinBorder(border),
        leftBorder: _thinBorder(border),
        rightBorder: _thinBorder(border),
      );
    }
    sheet.setRowHeight(r, 28);
    r++;

    // --- Data Rows ---
    final sortedCats = categoryGroups.keys.toList()..sort();
    int totalItems = 0;

    for (final catName in sortedCats) {
      final catItems = categoryGroups[catName]!;

      // Category header row
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
              .value =
          TextCellValue('═══ فئة $catName (${catItems.length} صنف) ═══');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        backgroundColorHex: ExcelColor.fromHexString(categoryBg),
        fontColorHex: ExcelColor.fromHexString(categoryFg),
        horizontalAlign: HorizontalAlign.Center,
      );
      sheet.setRowHeight(r, 24);
      r++;

      final catCurrTotals = <String, double>{};
      final catCurrQty = <String, double>{};

      for (final item in catItems) {
        final name = item['name']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        final unit = item['unit']?.toString() ?? '';
        final currency = (item['currency']?.toString() ?? 'EGP').toUpperCase();
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final value = (item['totalValue'] as num?)?.toDouble() ?? 0.0;

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
            .value = TextCellValue(code);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
            .value = TextCellValue(name);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
            .value = TextCellValue(catName);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
            .value = TextCellValue(unit);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
            .value = DoubleCellValue(qty);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
            .value = TextCellValue(currency);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r))
            .value = DoubleCellValue(value);

        for (var c = 0; c < headers.length; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .cellStyle = CellStyle(
            fontSize: 10,
            topBorder: _thinBorder(border),
            bottomBorder: _thinBorder(border),
            leftBorder: _thinBorder(border),
            rightBorder: _thinBorder(border),
            horizontalAlign:
                c <= 3 ? HorizontalAlign.Right : HorizontalAlign.Center,
          );
        }

        totalItems++;
        r++;
      }

      r++; // blank row between categories
    }

    // --- Grand Total ---
    r++;
    final sortedGrand = currencyTotals.keys.toList()..sort();

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue('═══════════ الاجمالي الكلي ═══════════');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      backgroundColorHex: ExcelColor.fromHexString(grandTotalBg),
      fontColorHex: ExcelColor.fromHexString(grandTotalFg),
      horizontalAlign: HorizontalAlign.Center,
    );
    sheet.setRowHeight(r, 30);
    r++;

    // Info rows in grand total
    final gtInfo = [
      ('عدد الأصناف', '$totalItems'),
      ('عدد الفئات', '${categories.length}'),
    ];

    for (final (arLabel, value) in gtInfo) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue('$arLabel : $value');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString(grandTotalFg),
        backgroundColorHex: ExcelColor.fromHexString(grandTotalBg),
        horizontalAlign: HorizontalAlign.Center,
      );
      r++;
    }

    r++; // blank

    // Per-currency grand totals
    for (final curr in sortedGrand) {
      final gVal = currencyTotals[curr] ?? 0;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue('اجمالي $curr');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 12,
        fontColorHex: ExcelColor.fromHexString(grandTotalFg),
        backgroundColorHex: ExcelColor.fromHexString(grandTotalBg),
        horizontalAlign: HorizontalAlign.Center,
      );
      r++;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value = TextCellValue(_formatNumber(gVal));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.fromHexString(grandTotalFg),
        backgroundColorHex: ExcelColor.fromHexString(grandTotalBg),
        horizontalAlign: HorizontalAlign.Center,
      );
      r++;

      r++; // blank
    }

    // --- Auto Width ---
    for (var c = 0; c < headers.length; c++) {
      double maxLen = headers[c].length.toDouble();
      for (var row = 0; row <= r; row++) {
        final val = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value;
        if (val != null) {
          final len = val.toString().length;
          if (len > maxLen) maxLen = len.toDouble();
        }
      }
      sheet.setColumnWidth(c, maxLen + 6);
    }
  }

  static void _buildSummarySheet(
    Sheet sheet,
    String title,
    DateTime now,
    List<Map<String, dynamic>> items,
    Set<String> categories,
    Map<String, List<Map<String, dynamic>>> categoryGroups,
    Map<String, double> currencyTotals,
  ) {
    const headerBg = '#FF1A237E';
    const headerFg = '#FFFFFFFF';
    const borderColor = '#FFB0BEC5';

    final border = ExcelColor.fromHexString(borderColor);
    int r = 0;

    // Title
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue('Summary');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: ExcelColor.fromHexString(headerBg),
      horizontalAlign: HorizontalAlign.Center,
    );
    r++;

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r),
    );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue('$title - Raw Materials Summary');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString('#FF546E7A'),
      horizontalAlign: HorizontalAlign.Center,
    );
    r += 2;

    // Report info
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr = _formatTime(now);

    _addSummaryRow(sheet, r, 'تاريخ التقرير', dateStr, headerBg, headerFg);
    r++;
    _addSummaryRow(sheet, r, 'وقت التقرير', timeStr, headerBg, headerFg);
    r++;
    r++;

    // Counts
    _addSummaryRow(
        sheet, r, 'عدد الأصناف', '${items.length}', headerBg, headerFg);
    r++;
    _addSummaryRow(
        sheet, r, 'عدد الفئات', '${categories.length}', headerBg, headerFg);
    r++;
    r++;

    // Currency totals
    _addSectionHeader(sheet, r, 'اجمالي العملات', headerBg, headerFg);
    r++;
    final sortedCurr = currencyTotals.keys.toList()..sort();
    for (final curr in sortedCurr) {
      final val = currencyTotals[curr] ?? 0;
      _addSummaryRow(sheet, r, curr, _formatNumber(val), headerBg, headerFg);
      r++;
    }
    r++;

    // Category breakdown
    _addSectionHeader(sheet, r, 'اجمالي الفئات', headerBg, headerFg);
    r++;

    final catHeaders = ['الفئة', 'الصنف', 'العملة', 'الاجمالي'];
    for (var c = 0; c < catHeaders.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value = TextCellValue(catHeaders[c]);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .cellStyle = CellStyle(
        bold: true,
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#FF37474F'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
        topBorder: _thinBorder(border),
        bottomBorder: _thinBorder(border),
        leftBorder: _thinBorder(border),
        rightBorder: _thinBorder(border),
      );
    }
    r++;

    final sortedCats = categoryGroups.keys.toList()..sort();
    for (final catName in sortedCats) {
      final catItems = categoryGroups[catName]!;
      final catCurrMap = <String, double>{};

      for (final item in catItems) {
        final currency = (item['currency']?.toString() ?? 'EGP').toUpperCase();
        final value = (item['totalValue'] as num?)?.toDouble() ?? 0.0;
        catCurrMap[currency] = (catCurrMap[currency] ?? 0) + value;
      }

      final sortedCCurr = catCurrMap.keys.toList()..sort();
      bool first = true;
      for (final curr in sortedCCurr) {
        final val = catCurrMap[curr] ?? 0;
        if (first) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
              .value = TextCellValue(catName);
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
              .value = TextCellValue('${catItems.length} صنف');
          first = false;
        } else {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
              .value = TextCellValue('');
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
              .value = TextCellValue('');
        }
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
            .value = TextCellValue(curr);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
            .value = TextCellValue(_formatNumber(val));

        for (var c = 0; c < 4; c++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .cellStyle = CellStyle(
            fontSize: 10,
            topBorder: _thinBorder(border),
            bottomBorder: _thinBorder(border),
            leftBorder: _thinBorder(border),
            rightBorder: _thinBorder(border),
          );
        }
        r++;
      }
    }

    // Auto width
    for (var c = 0; c < 7; c++) {
      sheet.setColumnWidth(c, 18);
    }
  }

  static void _addSummaryRow(Sheet sheet, int row, String label, String value,
      String bgColor, String fgColor) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
    );
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(label);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString(fgColor),
      backgroundColorHex: ExcelColor.fromHexString(bgColor),
    );

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
        .value = TextCellValue(value);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString(fgColor),
      backgroundColorHex: ExcelColor.fromHexString(bgColor),
    );
  }

  static void _addSectionHeader(
      Sheet sheet, int row, String text, String bgColor, String fgColor) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(text);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString(fgColor),
      backgroundColorHex: ExcelColor.fromHexString(bgColor),
      horizontalAlign: HorizontalAlign.Center,
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  static String _formatNumber(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    final buffer = StringBuffer();
    int count = 0;
    for (var i = intPart.length - 1; i >= 0; i--) {
      buffer.write(intPart[i]);
      count++;
      if (count % 3 == 0 && i > 0) buffer.write(',');
    }

    return '${buffer.toString().split('').reversed.join()}.$decPart';
  }
}
