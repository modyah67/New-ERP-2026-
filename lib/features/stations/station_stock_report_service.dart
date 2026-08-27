import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/constants.dart';
import '../../data/dao/station_product_batch_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/models/station_product_batch.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/models/raw_material_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class StationStockReportService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<List<_ProductWithBatches>> _loadData(int stationId, [Map<String, String>? productDisplayCurrency]) async {
    final productDao = StationProductDao();
    final batchDao = StationProductBatchDao();
    final fruitTypeDao = FruitTypeDao();
    final rawMaterialDao = RawMaterialDao();

    final results = await Future.wait([
      productDao.getByStation(stationId),
      fruitTypeDao.getAllWithPrices(),
      rawMaterialDao.getAll(),
    ]);
    final products = results[0] as List;
    final fruitTypes = results[1] as List;
    final rawMaterials = results[2] as List;
    final fruitTypeMap = {for (final ft in fruitTypes) ft.name: ft};
    final rawMaterialMap = {for (final rm in rawMaterials) rm.name: rm};

    final result = <_ProductWithBatches>[];
    for (final prod in products) {
      final batches = await batchDao.getBatches(
        stationId: stationId,
        productName: prod.productName,
      );
      final isFruit = fruitTypeMap.containsKey(prod.productName);
      final ft = fruitTypeMap[prod.productName];
      final rm = rawMaterialMap[prod.productName];
      
      String? batchCurr;
      for (final b in batches) {
        if (b.quantity > 0 && b.currency.isNotEmpty) {
          batchCurr = b.currency;
          break;
        }
      }
      
      final fallbackCurr = isFruit ? ft?.currency ?? 'EGP' : rm?.currency ?? 'EGP';
      final currency = productDisplayCurrency?[prod.productName] ?? batchCurr ?? fallbackCurr;
      result.add(_ProductWithBatches(
        product: prod,
        batches: batches,
        isFruitType: isFruit,
        fruitType: ft,
        currency: currency,
      ));
    }

    return result;
  }

  static double _itemValue(_ProductWithBatches d) {
    final batchValue = d.batches.fold<double>(0, (bs, b) => bs + b.remainingQuantity * b.unitCost);
    if (batchValue > 0) return batchValue;
    final price = d.fruitType?.latestPurchasePrice ?? d.fruitType?.averagePurchasePrice ?? 0;
    return d.product.quantity * price;
  }

  // ═══════════════════════════════════════════════════
  // PDF Export
  // ═══════════════════════════════════════════════════

  static Future<void> exportPdf({
    required int stationId,
    required String stationName,
    required String stationCode,
    Map<String, String>? productDisplayCurrency,
  }) async {
    await _loadFonts();
    final data = await _loadData(stationId, productDisplayCurrency);
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final fruitItems = data.where((d) => d.isFruitType).toList();
    final otherItems = data.where((d) => !d.isFruitType).toList();

    // Compute per-currency totals
    final fruitValueByCurrency = <String, double>{};
    final otherValueByCurrency = <String, double>{};
    for (final d in fruitItems) {
      final curr = d.currency;
      fruitValueByCurrency[curr] = (fruitValueByCurrency[curr] ?? 0) + _itemValue(d);
    }
    for (final d in otherItems) {
      final curr = d.currency;
      otherValueByCurrency[curr] = (otherValueByCurrency[curr] ?? 0) + _itemValue(d);
    }

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          // Header
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(font: _boldFont, fontSize: 18, color: PdfColors.blueGrey)),
          pw.Text('ملخص المخزون - $stationName ($stationCode)',
              style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
          pw.Text('تاريخ التقرير: ${DateTime.now().toString().substring(0, 10)}',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          ..._buildCurrencySummaryLines(fruitValueByCurrency, otherValueByCurrency, fruitItems.length, otherItems.length),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 12),

          // ── محاصيل ──
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.green50,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.Text('الفئة: محاصيل',
                    style: pw.TextStyle(font: _boldFont, fontSize: 13, color: PdfColors.green800)),
                pw.SizedBox(width: 10),
                pw.Text('(${fruitItems.length} صنف)',
                    style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          for (final item in fruitItems) ...[
            _buildProductHeader(item),
            pw.SizedBox(height: 6),
            if (item.batches.isEmpty)
              pw.Text('لا توجد دفعات',
                  style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey500))
            else
              pw.TableHelper.fromTextArray(
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.centerRight,
                headerStyle: pw.TextStyle(font: _boldFont, fontSize: 9, color: PdfColors.white),
                cellStyle: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.black),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
                cellHeight: 24,
                headerAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: ['#', 'التاريخ', 'المصدر', 'العملة', 'الكمية الأصلية', 'المتبقي', 'سعر الوحدة', 'الإجمالي'],
                data: [
                  for (int i = 0; i < item.batches.length; i++)
                    _batchRow(i + 1, item.batches[i], item: item),
                ],
              ),
            pw.SizedBox(height: 16),
          ],
          _buildCategoryTotal('محاصيل', fruitItems.length,
              fruitItems.fold<double>(0, (s, d) => s + d.product.quantity),
              fruitValueByCurrency, PdfColors.green50, PdfColors.green200, PdfColors.green900, PdfColors.green800),

          // ── مواد خام ──
          if (otherItems.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColors.orange50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                children: [
                  pw.Text('الفئة: مواد خام',
                      style: pw.TextStyle(font: _boldFont, fontSize: 13, color: PdfColors.orange800)),
                  pw.SizedBox(width: 10),
                  pw.Text('(${otherItems.length} صنف)',
                      style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            for (final item in otherItems) ...[
              _buildProductHeader(item),
              pw.SizedBox(height: 6),
              if (item.batches.isEmpty)
                pw.Text('لا توجد دفعات',
                    style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey500))
              else
                pw.TableHelper.fromTextArray(
                  headerAlignment: pw.Alignment.center,
                  cellAlignment: pw.Alignment.centerRight,
                  headerStyle: pw.TextStyle(font: _boldFont, fontSize: 9, color: PdfColors.white),
                  cellStyle: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.black),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
                  cellHeight: 24,
                  headerAlignments: {
                    0: pw.Alignment.center,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerRight,
                    6: pw.Alignment.centerRight,
                    7: pw.Alignment.centerRight,
                  },
                  headers: ['#', 'التاريخ', 'المصدر', 'العملة', 'الكمية الأصلية', 'المتبقي', 'سعر الوحدة', 'الإجمالي'],
                  data: [
                    for (int i = 0; i < item.batches.length; i++)
                      _batchRow(i + 1, item.batches[i], item: item),
                  ],
                ),
              pw.SizedBox(height: 16),
            ],
            _buildCategoryTotal('مواد خام', otherItems.length,
                otherItems.fold<double>(0, (s, d) => s + d.product.quantity),
                otherValueByCurrency, PdfColors.orange50, PdfColors.orange200, PdfColors.orange900, PdfColors.orange800),
          ],

          // Grand totals
          pw.SizedBox(height: 16),
          _buildGrandTotal(
              data.length,
              data.fold<double>(0, (s, d) => s + d.product.quantity),
              {...fruitValueByCurrency, ...otherValueByCurrency}),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'stock_${stationName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static pw.Widget _buildProductHeader(_ProductWithBatches item) {
    final unit = _displayUnit(item);
    final dispQty = _displayQty(item);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          pw.Text(item.product.productCode,
              style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.blue800)),
          pw.SizedBox(width: 10),
          pw.Text(item.product.productName,
              style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.black)),
          pw.SizedBox(width: 10),
          pw.Text('الكمية: ${dispQty.toStringAsFixed(0)} $unit',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(width: 10),
          pw.Text('العملة: ${item.currency}',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey700)),
          if (_isCartonMode(item) && _weightPerCarton(item) > 0) ...[
            pw.SizedBox(width: 10),
            pw.Text('وزن/كرتونة: ${_weightPerCarton(item).toStringAsFixed(1)} كجم',
                style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey600)),
          ],
        ],
      ),
    );
  }

  static List<pw.Widget> _buildCurrencySummaryLines(
      Map<String, double> fruitByCurrency, Map<String, double> otherByCurrency,
      int fruitCount, int otherCount) {
    final allCurrencies = <String>{...fruitByCurrency.keys, ...otherByCurrency.keys}.toList()..sort();
    if (allCurrencies.isEmpty) {
      return [pw.Text('إجمالي الأصناف: ${fruitCount + otherCount}',
          style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey600))];
    }
    final lines = <pw.Widget>[];
    for (final curr in allCurrencies) {
      final fv = fruitByCurrency[curr] ?? 0;
      final ov = otherByCurrency[curr] ?? 0;
      final total = fv + ov;
      lines.add(pw.Text(
        '$curr: ${total.toStringAsFixed(2)}  |  محاصيل: ${fv.toStringAsFixed(2)}  |  مواد خام: ${ov.toStringAsFixed(2)}',
        style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey600),
      ));
    }
    lines.insert(0, pw.Text('إجمالي الأصناف: ${fruitCount + otherCount}',
        style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.grey800)));
    return lines;
  }

  static pw.Widget _buildCategoryTotal(String catName, int count, double qty,
      Map<String, double> valueByCurrency,
      PdfColor bgColor, PdfColor borderColor, PdfColor textColor, PdfColor valColor) {
    final sorted = valueByCurrency.entries.where((e) => e.value > 0).toList()..sort((a, b) => a.key.compareTo(b.key));
    final valueStr = sorted.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join('  |  ');
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: borderColor),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('إجمالي فئة $catName ($count صنف)',
              style: pw.TextStyle(font: _boldFont, fontSize: 11, color: textColor)),
          pw.Text(
            'الكمية: ${qty.toStringAsFixed(0)} | $valueStr',
            style: pw.TextStyle(font: _boldFont, fontSize: 10, color: valColor),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildGrandTotal(int totalCount, double totalQty, Map<String, double> allValueByCurrency) {
    final sorted = allValueByCurrency.entries.where((e) => e.value > 0).toList()..sort((a, b) => a.key.compareTo(b.key));
    final valueStr = sorted.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join('  |  ');
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('الاجمالي الكلي ($totalCount صنف)',
              style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.white)),
          pw.Text(
            'الكمية: ${totalQty.toStringAsFixed(0)} | $valueStr',
            style: pw.TextStyle(font: _boldFont, fontSize: 11, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  static List<String> _batchRow(int index, StationProductBatch batch, {_ProductWithBatches? item}) {
    final source = batch.sourceType == 'transfer'
        ? 'نقل من ${batch.sourceStationName}'
        : batch.supplierName.isNotEmpty
            ? batch.supplierName
            : 'مشتريات';
    final dateOnly = batch.sourceDate.length >= 10 ? batch.sourceDate.substring(0, 10) : batch.sourceDate;
    final isCarton = item != null && _isCartonMode(item);
    final origQty = item != null ? _displayBatchOriginalQty(item, batch) : batch.quantity;
    final remainQty = item != null ? _displayBatchQty(item, batch) : batch.remainingQuantity;
    final costPer = item != null ? _costPerUnit(item, batch) : batch.unitCost;
    final unit = item != null ? _displayUnit(item) : (batch.quantity > 0 ? 'كجم' : '');
    return [
      index.toString(),
      dateOnly,
      source,
      batch.currency,
      '${origQty.toStringAsFixed(0)} $unit',
      '${remainQty.toStringAsFixed(0)} $unit',
      '${costPer.toStringAsFixed(2)}',
      '${batch.batchTotalCost.toStringAsFixed(2)}',
    ];
  }

  // ═══════════════════════════════════════════════════
  // Excel Export
  // ═══════════════════════════════════════════════════

  static String _displayUnit(_ProductWithBatches item) {
    final mode = item.fruitType?.latestPurchaseMode;
    if (mode == 'carton') return 'كرتونة';
    if (item.fruitType != null) return 'كجم';
    return item.product.unit == 'carton' ? 'كرتونة' : 'قطعة';
  }

  static bool _isCartonMode(_ProductWithBatches item) => item.fruitType?.latestPurchaseMode == 'carton';

  static double _weightPerCarton(_ProductWithBatches item) => item.fruitType?.latestWeightPerCartonKg ?? 0;

  static double _displayQty(_ProductWithBatches item) {
    if (_isCartonMode(item)) {
      final wpc = _weightPerCarton(item);
      if (wpc > 0) return item.product.quantity / wpc;
      return item.product.quantity;
    }
    return item.product.quantity;
  }

  static double _displayBatchQty(_ProductWithBatches item, StationProductBatch batch) {
    if (_isCartonMode(item)) {
      final wpc = _weightPerCarton(item);
      if (wpc > 0) return batch.remainingQuantity / wpc;
      return batch.remainingQuantity;
    }
    return batch.remainingQuantity;
  }

  static double _displayBatchOriginalQty(_ProductWithBatches item, StationProductBatch batch) {
    if (_isCartonMode(item)) {
      final wpc = _weightPerCarton(item);
      if (wpc > 0) return batch.quantity / wpc;
      return batch.quantity;
    }
    return batch.quantity;
  }

  static double _costPerUnit(_ProductWithBatches item, StationProductBatch batch) {
    if (_isCartonMode(item)) {
      final wpc = _weightPerCarton(item);
      return batch.unitCost * wpc;
    }
    return batch.unitCost;
  }

  static Future<List<int>?> buildExcelBytes({
    required int stationId,
    required String stationName,
    required String stationCode,
    Map<String, String>? productDisplayCurrency,
  }) async {
    final data = await _loadData(stationId, productDisplayCurrency);
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['المخزون'];
    final headers = ['الفئة', 'المنتج', 'الكود', 'الوحدة', 'العملة', 'الكمية الإجمالية', 'التاريخ', 'المصدر', 'الكمية الأصلية', 'المتبقي', 'سعر الوحدة', 'الإجمالي'];

    const headerBg = '#FF1A237E';
    const headerFg = '#FFFFFFFF';
    const categoryBg = '#FF0D47A1';
    const categoryFg = '#FFFFFFFF';
    const subtotalBg = '#FF1B5E20';
    const subtotalFg = '#FFFFFFFF';
    const grandTotalBg = '#FF263238';
    const grandTotalFg = '#FFFFFFFF';

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString(headerBg),
        fontColorHex: ExcelColor.fromHexString(headerFg),
        fontSize: 12,
      );
    }

    final fruitItems = data.where((d) => d.isFruitType).toList();
    final otherItems = data.where((d) => !d.isFruitType).toList();

    var r = 1;

    final grandQty = <String, double>{};
    final grandValue = <String, double>{};

    for (final section in [
      ('محاصيل', fruitItems),
      if (otherItems.isNotEmpty) ('مواد خام', otherItems),
    ]) {
      final (catName, items) = section;

      for (var c = 0; c < headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString(categoryBg),
          fontColorHex: ExcelColor.fromHexString(categoryFg),
          fontSize: 11,
        );
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
          TextCellValue('--- $catName (${items.length} صنف) ---');
      r++;

      final catQty = <String, double>{};
      final catValue = <String, double>{};

      for (final item in items) {
        final currency = item.currency;
        final unit = _displayUnit(item);
        final dispQty = _displayQty(item);

        if (item.batches.isEmpty) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(catName);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(item.product.productName);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(item.product.productCode);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(unit);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(currency);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(dispQty);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue('—');
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = TextCellValue('لا توجد دفعات');
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = DoubleCellValue(0);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r)).value = DoubleCellValue(0);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r)).value = DoubleCellValue(0);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r)).value = DoubleCellValue(0);

          final itemVal = _itemValue(item);
          catQty[currency] = (catQty[currency] ?? 0) + dispQty;
          catValue[currency] = (catValue[currency] ?? 0) + itemVal;
          grandQty[currency] = (grandQty[currency] ?? 0) + dispQty;
          grandValue[currency] = (grandValue[currency] ?? 0) + itemVal;
          r++;
        } else {
          for (int i = 0; i < item.batches.length; i++) {
            final batch = item.batches[i];
            final source = batch.sourceType == 'transfer'
                ? 'نقل من ${batch.sourceStationName}'
                : batch.supplierName.isNotEmpty
                    ? batch.supplierName
                    : 'مشتريات';

            final batchDispQty = _displayBatchQty(item, batch);
            final batchOrigQty = _displayBatchOriginalQty(item, batch);
            final costPer = _costPerUnit(item, batch);

            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(catName);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(item.product.productName);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(item.product.productCode);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(unit);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(currency);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(dispQty);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(batch.sourceDate.length >= 10 ? batch.sourceDate.substring(0, 10) : batch.sourceDate);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = TextCellValue(source);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = DoubleCellValue(batchOrigQty);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r)).value = DoubleCellValue(batchDispQty);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r)).value = DoubleCellValue(costPer);
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r)).value = DoubleCellValue(batch.batchTotalCost);
            r++;
          }

          final itemQty = item.batches.fold<double>(0, (s, b) => s + _displayBatchQty(item, b));
          final itemVal = _itemValue(item);
          catQty[currency] = (catQty[currency] ?? 0) + itemQty;
          catValue[currency] = (catValue[currency] ?? 0) + itemVal;
          grandQty[currency] = (grandQty[currency] ?? 0) + itemQty;
          grandValue[currency] = (grandValue[currency] ?? 0) + itemVal;
        }
      }

      final sortedCurrencies = catValue.keys.toList()..sort();
      for (final curr in sortedCurrencies) {
        final cQty = catQty[curr] ?? 0;
        final cVal = catValue[curr] ?? 0;

        for (var c = 0; c < headers.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString(subtotalBg),
            fontColorHex: ExcelColor.fromHexString(subtotalFg),
            fontSize: 10,
          );
        }
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
            TextCellValue('اجمالي فئة $catName');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(curr);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(cQty);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r)).value = DoubleCellValue(cVal);
        r++;
      }
      r++;
    }

    final sortedGrand = grandValue.keys.toList()..sort();
    for (final curr in sortedGrand) {
      final gQty = grandQty[curr] ?? 0;
      final gVal = grandValue[curr] ?? 0;

      for (var c = 0; c < headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString(grandTotalBg),
          fontColorHex: ExcelColor.fromHexString(grandTotalFg),
          fontSize: 11,
        );
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
          TextCellValue('اجمالي الكلي ($curr)');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(curr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(gQty);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r)).value = DoubleCellValue(gVal);
      r++;
    }

    r++;
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString(headerBg),
        fontColorHex: ExcelColor.fromHexString(headerFg),
        fontSize: 12,
      );
    }
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
        TextCellValue('اجمالي الاصناف: ${data.length}');

    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length.toDouble();
      for (var row = 0; row < r && row < 500; row++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value;
        if (val != null && val.toString().length > maxLen) {
          maxLen = val.toString().length.toDouble();
        }
      }
      sheet.setColumnWidth(c, maxLen + 4);
    }

    return excel.save();
  }

  static Future<void> exportExcel({
    required int stationId,
    required String stationName,
    required String stationCode,
    Map<String, String>? productDisplayCurrency,
  }) async {
    final fileBytes = await buildExcelBytes(
      stationId: stationId,
      stationName: stationName,
      stationCode: stationCode,
      productDisplayCurrency: productDisplayCurrency,
    );
    if (fileBytes == null) return;

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = 'stock_${stationName}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }
}

class _ProductWithBatches {
  final dynamic product;
  final List<StationProductBatch> batches;
  final bool isFruitType;
  final FruitTypeModel? fruitType;
  final String currency;
  const _ProductWithBatches({
    required this.product,
    required this.batches,
    this.isFruitType = false,
    this.fruitType,
    this.currency = 'EGP',
  });
}
