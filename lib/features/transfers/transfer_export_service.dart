import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/stock_transfer_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class TransferExportService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<void> exportPdf({
    required List<StockTransferModel> transfers,
    required Map<int, String> stationNames,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final totalQty = transfers.fold<double>(0, (s, t) => s + t.quantity);

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
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(font: _boldFont, fontSize: 18, color: PdfColors.blueGrey)),
          pw.Text('تحويل بين المخازن',
              style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
          pw.Text('عدد التحويلات: ${transfers.length} | الكمية الإجمالية: ${totalQty.toStringAsFixed(0)} | تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(font: _boldFont, fontSize: 9, color: PdfColors.white),
            cellStyle: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellHeight: 22,
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
            },
            headers: ['#', 'من', 'إلى', 'المنتج', 'الكمية', 'التاريخ'],
            data: [
              for (int i = 0; i < transfers.length; i++)
                _txRow(i + 1, transfers[i], stationNames),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'transfers_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static List<String> _txRow(int index, StockTransferModel t, Map<int, String> names) {
    final from = names[t.fromStationId] ?? 'محطة #${t.fromStationId}';
    final to = names[t.toStationId] ?? 'محطة #${t.toStationId}';
    final date = _toLocalDate(t.createdAt);
    return [
      index.toString(),
      from,
      to,
      '${t.productName} (${t.productCode})',
      t.quantity.toStringAsFixed(0),
      date,
    ];
  }

  static Future<List<int>?> buildExcelBytes({
    required List<StockTransferModel> transfers,
    required Map<int, String> stationNames,
  }) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['التحويلات'];
    final headers = ['#', 'من', 'إلى', 'المنتج', 'الكود', 'الكمية', 'ملاحظات', 'التاريخ'];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
    }

    for (var i = 0; i < transfers.length; i++) {
      final t = transfers[i];
      final r = i + 1;
      final from = stationNames[t.fromStationId] ?? 'محطة #${t.fromStationId}';
      final to = stationNames[t.toStationId] ?? 'محطة #${t.toStationId}';
      final date = _toLocalDate(t.createdAt);

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue('${i + 1}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(from);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(to);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(t.productName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(t.productCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(t.quantity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(t.notes ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = TextCellValue(date);
    }

    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length.toDouble();
      for (var row = 0; row < transfers.length + 1 && row < 200; row++) {
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
    required List<StockTransferModel> transfers,
    required Map<int, String> stationNames,
  }) async {
    final fileBytes = await buildExcelBytes(transfers: transfers, stationNames: stationNames);
    if (fileBytes == null) return;

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = 'transfers_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }

  static String _toLocalDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }
}
