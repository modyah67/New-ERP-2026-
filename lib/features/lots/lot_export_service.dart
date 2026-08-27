import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/lot_model.dart';
import '../../data/dao/station_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class LotExportService {
  static pw.Font? _font;
  static pw.Font? _boldFont;
  static Map<String, String>? _stationCache;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<void> _ensureStationCache() async {
    if (_stationCache != null) return;
    final stations = await StationDao().getAll(limit: 10000);
    _stationCache = {for (final s in stations) (s.id ?? ''): s.name};
  }

  static String _stationName(String? stationId) {
    if (stationId == null || stationId.isEmpty) return '—';
    return _stationCache?[stationId] ?? '—';
  }

  // ═══════════════════════════════════════════════════
  // Single Lot - PDF
  // ═══════════════════════════════════════════════════

  static Future<Uint8List> generatePdfBytes(LotReceiptModel lot) async {
    await _loadFonts();
    await _ensureStationCache();
    return _buildSinglePdf(lot);
  }

  static Future<void> exportSinglePdf(LotReceiptModel lot) async {
    final bytes = await generatePdfBytes(lot);
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'lot_${lot.lotNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static Future<Uint8List> _buildSinglePdf(LotReceiptModel lot) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(font: _boldFont, fontSize: 18, color: PdfColors.blueGrey)),
          pw.Text('شراء محصول #${lot.lotNumber}',
              style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
          pw.SizedBox(height: 12),
          _infoRow('المنتج', lot.productName ?? '—'),
          _infoRow('المورد', lot.supplierName ?? '—'),
          _infoRow('المحطة', _stationName(lot.stationId)),
          _infoRow('تاريخ الشراء', DateFormat('yyyy-MM-dd').format(lot.receiptDate)),
          _infoRow('الوزن الإجمالي', '${lot.grossWeightKg.toStringAsFixed(1)} كجم'),
          _infoRow('الوزن الصافي', '${lot.netWeightKg.toStringAsFixed(1)} كجم'),
          _infoRow('تكلفة الوحدة', lot.purchaseMode == 'carton'
              ? '${(lot.pricePerCarton ?? 0).toStringAsFixed(2)} ${lot.currency}'
              : '${lot.grossWeightKg > 0 ? (lot.totalProductCost / lot.grossWeightKg).toStringAsFixed(2) : '0.00'} ${lot.currency}'),
          _infoRow('التكلفة الإجمالية', '${lot.totalProductCost.toStringAsFixed(2)} ${lot.currency}'),
          if (lot.purchaseMode == 'carton') ...[
            _infoRow('طريقة الشراء', 'بالكرتون'),
            _infoRow('عدد الكراتين الكلي', '${lot.cartonCount ?? 0} كرتونة'),
            _infoRow('الكراتين الصافي', '${lot.netCartonCount} كرتونة'),
            _infoRow('سعر الكرتونة', '${lot.pricePerCarton?.toStringAsFixed(2) ?? '0.00'} ${lot.currency}'),
            _infoRow('تكلفة الكرتونة', '${lot.costPerCarton.toStringAsFixed(2)} ${lot.currency}'),
            _infoRow('وزن الكرتونة الصافي', '${lot.weightPerCartonKg?.toStringAsFixed(2) ?? '0.00'} كجم'),
            _infoRow('وزن الكرتونة الإجمالي', '${lot.grossWeightPerCartonKg?.toStringAsFixed(2) ?? '0.00'} كجم'),
          ] else ...[
            _infoRow('طريقة الشراء', 'بالوزن'),
          ],
          if (lot.notes != null && lot.notes!.isNotEmpty)
            _infoRow('ملاحظات', lot.notes!),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 8),
          if (lot.gradingResults.isNotEmpty) ...[
            pw.Text('نتائج الفرز',
                style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.blue800)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerAlignment: pw.Alignment.center,
              cellAlignment: pw.Alignment.centerRight,
              headerStyle: pw.TextStyle(font: _boldFont, fontSize: 9, color: PdfColors.white),
              cellStyle: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.black),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
              cellHeight: 24,
              headers: ['#', 'الدرجة', 'الوزن (كجم)', 'النسبة %'],
              data: [
                for (int i = 0; i < lot.gradingResults.length; i++)
                  _gradingRow(i + 1, lot.gradingResults[i], lot.grossWeightKg),
              ],
            ),
          ] else
            pw.Text('لا توجد نتائج فرز',
                style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey500)),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: _boldFont!, fontSize: 11, color: PdfColors.grey700)),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(font: _font!, fontSize: 11, color: PdfColors.black))),
        ],
      ),
    );
  }

  static List<String> _gradingRow(int index, LotGradingResult r, double totalKg) {
    final pct = totalKg > 0 ? (r.weightKg / totalKg * 100).toStringAsFixed(1) : '0.0';
    return [
      index.toString(),
      r.grade,
      r.weightKg.toStringAsFixed(1),
      '$pct%',
    ];
  }



  // ═══════════════════════════════════════════════════
  // Single Lot - Excel
  // ═══════════════════════════════════════════════════

  static Future<List<int>?> generateExcelBytes(LotReceiptModel lot) async {
    await _ensureStationCache();
    return _buildSingleExcel(lot);
  }

  static Future<void> exportSingleExcel(LotReceiptModel lot) async {
    final fileBytes = await generateExcelBytes(lot);
    if (fileBytes == null) return;

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = 'lot_${lot.lotNumber}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }

  static List<int>? _buildSingleExcel(LotReceiptModel lot) {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['شراء #${lot.lotNumber}'];
    final originalUnitCost = lot.purchaseMode == 'carton'
        ? (lot.pricePerCarton ?? 0.0)
        : (lot.grossWeightKg > 0 ? lot.totalProductCost / lot.grossWeightKg : 0.0);
    final headers = [
      'المنتج', 'المورد', 'المحطة', 'التاريخ', 'الوزن الإجمالي', 'الوزن الصافي', 
      'تكلفة الوحدة', 'التكلفة الإجمالية', 'العملة',
      'طريقة الشراء', 'عدد الكراتين', 'الكراتين الصافي', 'سعر الكرتونة', 'تكلفة الكرتونة', 'وزن الكرتونة (صافي)', 'وزن الكرتونة (إجمالي)'
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
    }

    final vals = [
      lot.productName ?? '—',
      lot.supplierName ?? '—',
      _stationName(lot.stationId),
      DateFormat('yyyy-MM-dd').format(lot.receiptDate),
      lot.grossWeightKg,
      lot.netWeightKg,
      originalUnitCost,
      lot.totalProductCost,
      lot.currency,
      lot.purchaseMode == 'carton' ? 'بالكرتون' : 'بالوزن',
      lot.purchaseMode == 'carton' ? (lot.cartonCount ?? 0) : '—',
      lot.purchaseMode == 'carton' ? lot.netCartonCount : '—',
      lot.purchaseMode == 'carton' ? (lot.pricePerCarton ?? 0.0) : '—',
      lot.purchaseMode == 'carton' ? lot.costPerCarton : '—',
      lot.purchaseMode == 'carton' ? (lot.weightPerCartonKg ?? 0.0) : '—',
      lot.purchaseMode == 'carton' ? (lot.grossWeightPerCartonKg ?? 0.0) : '—',
    ];
    for (var c = 0; c < vals.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
      cell.value = vals[c] is double ? DoubleCellValue(vals[c] as double) : TextCellValue('${vals[c]}');
    }

    if (lot.gradingResults.isNotEmpty) {
      final gHeaders = ['#', 'الدرجة', 'الوزن (كجم)', 'النسبة %'];
      for (var c = 0; c < gHeaders.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 3));
        cell.value = TextCellValue(gHeaders[c]);
        cell.cellStyle = CellStyle(bold: true);
      }
      for (var i = 0; i < lot.gradingResults.length; i++) {
        final r = lot.gradingResults[i];
        final pct = lot.grossWeightKg > 0 ? (r.weightKg / lot.grossWeightKg * 100) : 0.0;
        final row = i + 4;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue('${i + 1}');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(r.grade);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = DoubleCellValue(r.weightKg);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = DoubleCellValue(pct);
      }
    }

    return excel.save();
  }

  // ═══════════════════════════════════════════════════
  // Bulk Lots - Batch Loading (handles 100K+)
  // ═══════════════════════════════════════════════════

  static const int _batchSize = 2000;
  static const int _maxRows = 80000;

  static Future<List<LotReceiptModel>> _loadAllLots() async {
    final client = Supabase.instance.client;
    final allLots = <LotReceiptModel>[];
    int offset = 0;
    bool hasMore = true;

    while (hasMore && allLots.length < _maxRows) {
      final data = await client
          .from('lot_receipts')
          .select('*, suppliers(name, code)')
          .order('receipt_date', ascending: false)
          .range(offset, offset + _batchSize - 1);

      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) break;

      for (final e in rows) {
        final row = Map<String, dynamic>.from(e);
        final supplier = AppUtils.asMap(row.remove('suppliers'));
        allLots.add(LotReceiptModel.fromMap({
          ...row,
          'supplier_name': supplier?['name'],
        }));
      }

      offset += _batchSize;
      hasMore = rows.length >= _batchSize;
    }

    return allLots;
  }

  // ═══════════════════════════════════════════════════
  // Bulk Lots - PDF
  // ═══════════════════════════════════════════════════

  static Future<void> exportAllPdf({
    Function(String)? onProgress,
  }) async {
    await _loadFonts();
    await _ensureStationCache();
    onProgress?.call('جاري تحميل البيانات...');
    final lots = await _loadAllLots();
    onProgress?.call('جاري إنشاء PDF...');

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    final totalPages = (lots.length / 50).ceil();
    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final start = pageIdx * 50;
      final end = (start + 50).clamp(0, lots.length);
      final pageLots = lots.sublist(start, end);

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            theme: theme,
            pageFormat: PdfPageFormat.a4.landscape,
            textDirection: pw.TextDirection.rtl,
            margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),
          ),
          build: (ctx) => [
            if (pageIdx == 0) ...[
              pw.Text(AppConstants.companyName,
                  style: pw.TextStyle(font: _boldFont, fontSize: 16, color: PdfColors.blueGrey)),
              pw.Text('شراء المحاصيل',
                  style: pw.TextStyle(font: _boldFont, fontSize: 13, color: PdfColors.black)),
              pw.Text('إجمالي الأوردرات: ${lots.length} | تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 8),
            ],
            pw.TableHelper.fromTextArray(
              headerAlignment: pw.Alignment.center,
              cellAlignment: pw.Alignment.centerRight,
              headerStyle: pw.TextStyle(font: _boldFont, fontSize: 8, color: PdfColors.white),
              cellStyle: pw.TextStyle(font: _font!, fontSize: 7, color: PdfColors.black),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
              cellHeight: 18,
              headerAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
                9: pw.Alignment.center,
              },
              headers: ['#', 'رقم اللوت', 'المنتج', 'المورد', 'المحطة', 'التاريخ', 'العملة', 'الوزن الإجمالي', 'صافي', 'تفاصيل'],
              data: [
                for (int i = 0; i < pageLots.length; i++)
                  _bulkLotRow(start + i + 1, pageLots[i]),
              ],
            ),
          ],
        ),
      );
    }

    onProgress?.call('جاري الحفظ...');
    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'all_lots_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static List<String> _bulkLotRow(int index, LotReceiptModel lot) {
    final date = DateFormat('yyyy-MM-dd').format(lot.receiptDate);
    
    String details = '${lot.totalProductCost.toStringAsFixed(0)} إجمالي';
    if (lot.purchaseMode == 'carton') {
      details += '\n(${lot.cartonCount ?? 0} كرتونة | ${(lot.pricePerCarton ?? 0).toStringAsFixed(2)} للكرتونة)';
      details += '\n(وزن الكرتونة: ${(lot.weightPerCartonKg ?? 0).toStringAsFixed(1)} كجم)';
    } else {
      details += '\n(بالوزن | ${(lot.grossWeightKg > 0 ? lot.totalProductCost / lot.grossWeightKg : 0).toStringAsFixed(2)} للوحدة)';
    }

    return [
      index.toString(),
      lot.lotNumber,
      lot.productName ?? '—',
      lot.supplierName ?? '—',
      _stationName(lot.stationId),
      date,
      lot.currency,
      '${lot.grossWeightKg.toStringAsFixed(0)} كجم',
      '${lot.netWeightKg.toStringAsFixed(0)} كجم',
      details,
    ];
  }

  // ═══════════════════════════════════════════════════
  // Bulk Lots - Excel
  // ═══════════════════════════════════════════════════

  static Future<List<int>?> generateAllExcelBytes({
    Function(String)? onProgress,
    List<LotReceiptModel>? lots,
  }) async {
    await _ensureStationCache();
    lots ??= await _loadAllLots();

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['المحاصيل'];
    final headers = [
      '#', 'رقم اللوت', 'المنتج', 'المورد', 'المحطة', 'التاريخ', 'العملة',
      'وزن إجمالي', 'وزن صافي', 'تكلفة الوحدة', 'التكلفة الإجمالية',
      'طريقة الشراء', 'عدد الكراتين', 'الكراتين الصافي', 'سعر الكرتونة', 'تكلفة الكرتونة', 'وزن الكرتونة (صافي)', 'وزن الكرتونة (إجمالي)'
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
    }

    final maxRows = lots.length.clamp(0, _maxRows);
    for (var i = 0; i < maxRows; i++) {
      final lot = lots[i];
      final r = i + 1;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue('${i + 1}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(lot.lotNumber);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(lot.productName ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(lot.supplierName ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(_stationName(lot.stationId));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = TextCellValue(DateFormat('yyyy-MM-dd').format(lot.receiptDate));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(lot.currency);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = DoubleCellValue(lot.grossWeightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = DoubleCellValue(lot.netWeightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r)).value = DoubleCellValue(lot.purchaseMode == 'carton' ? (lot.pricePerCarton ?? 0.0) : (lot.grossWeightKg > 0 ? lot.totalProductCost / lot.grossWeightKg : 0.0));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r)).value = DoubleCellValue(lot.totalProductCost);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r)).value = TextCellValue(lot.purchaseMode == 'carton' ? 'بالكرتون' : 'بالوزن');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: r)).value = lot.purchaseMode == 'carton' ? IntCellValue(lot.cartonCount ?? 0) : TextCellValue('—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r)).value = lot.purchaseMode == 'carton' ? IntCellValue(lot.netCartonCount) : TextCellValue('—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r)).value = lot.purchaseMode == 'carton' ? DoubleCellValue(lot.pricePerCarton ?? 0.0) : TextCellValue('—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: r)).value = lot.purchaseMode == 'carton' ? DoubleCellValue(lot.costPerCarton) : TextCellValue('—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: r)).value = lot.purchaseMode == 'carton' ? DoubleCellValue(lot.weightPerCartonKg ?? 0.0) : TextCellValue('—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: r)).value = lot.purchaseMode == 'carton' ? DoubleCellValue(lot.grossWeightPerCartonKg ?? 0.0) : TextCellValue('—');
    }

    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length.toDouble();
      for (var row = 0; row < maxRows + 1 && row < 200; row++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value;
        if (val != null && val.toString().length > maxLen) {
          maxLen = val.toString().length.toDouble();
        }
      }
      sheet.setColumnWidth(c, maxLen + 4);
    }

    return excel.save();
  }

  static Future<void> exportAllExcel({
    Function(String)? onProgress,
  }) async {
    onProgress?.call('جاري تحميل البيانات...');
    final lots = await _loadAllLots();
    onProgress?.call('جاري إنشاء Excel...');

    final fileBytes = await generateAllExcelBytes(onProgress: onProgress, lots: lots);
    if (fileBytes == null) return;

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = 'all_lots_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }
}
