import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ConsolidatedStatementPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<Uint8List> build({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final hasExtra = extraColumnHeader != null && extraColumnKey != null;

    // Build per-currency totals
    final Map<String, double> totalsByCurrency = {};
    for (final r in rows) {
      final curr = r['currency'] ?? 'EGP';
      final bal = double.tryParse(r['balance'] ?? '0') ?? 0;
      totalsByCurrency[curr] = (totalsByCurrency[curr] ?? 0) + bal;
    }
    final sortedCurrencies = totalsByCurrency.keys.toList()..sort();

    final headers = ['#', 'الكود', 'الاسم', 'العملة', 'الرصيد'];
    if (hasExtra) headers.insert(3, extraColumnHeader);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.portrait,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.only(
            top: 70,
            bottom: 70,
            left: 20,
            right: 20,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(AppConstants.companyName,
                style: pw.TextStyle(
                    font: _boldFont, fontSize: 16, color: PdfColors.blueGrey)),
          ),
          pw.SizedBox(height: 4),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(title,
                style: pw.TextStyle(
                    font: _boldFont, fontSize: 13, color: PdfColors.black)),
          ),
          pw.SizedBox(height: 4),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text('تاريخ التقرير: ${DateTime.now().toString().substring(0, 16)}',
                style: pw.TextStyle(
                    font: _font, fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 10),

          // Per-currency summary
          if (sortedCurrencies.length > 1) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('الاجمالي لكل عملة',
                      style: pw.TextStyle(font: _boldFont, fontSize: 11, color: PdfColors.blue900)),
                  pw.SizedBox(height: 4),
                  ...sortedCurrencies.map((curr) {
                    final val = totalsByCurrency[curr] ?? 0;
                    return pw.Text(
                      '$curr: ${val.toStringAsFixed(2)}',
                      style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.black),
                    );
                  }),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
          ],

          pw.Divider(),
          pw.SizedBox(height: 10),
          _buildTable(headers, rows, hasExtra, extraColumnKey),
          pw.SizedBox(height: 12),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildTable(
    List<String> headers,
    List<Map<String, String>> rows,
    bool hasExtra,
    String? extraColumnKey,
  ) {
    final colCount = headers.length;

    final List<double> colWidths;
    if (hasExtra) {
      colWidths = [30, 60, 140, 60, 60, 125];
    } else {
      colWidths = [30, 70, 180, 60, 135];
    }

    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle: pw.TextStyle(
          font: _boldFont, fontSize: 9, color: PdfColors.white),
      cellStyle: pw.TextStyle(
          font: _font, fontSize: 8, color: PdfColors.black),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellDecoration: (row, col, isHeader) => pw.BoxDecoration(
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300))),
      columnWidths: {
        for (int i = 0; i < colCount; i++) i: pw.FlexColumnWidth(colWidths[i.clamp(0, colWidths.length - 1)]),
      },
      headers: headers,
      data: List.generate(rows.length, (i) {
        final r = rows[i];
        final cells = [
          '${i + 1}',
          r['code'] ?? '',
          r['name'] ?? '',
          r['currency'] ?? 'EGP',
          r['balance'] ?? '',
        ];
        if (hasExtra) {
          cells.insert(4, r[extraColumnKey] ?? '');
        }
        return cells;
      }),
    );
  }

  static Future<void> print({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    final bytes = await build(
      title: title,
      rows: rows,
      totalBalance: totalBalance,
      extraColumnHeader: extraColumnHeader,
      extraColumnKey: extraColumnKey,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: title,
    );
  }

  static Future<String> saveToFile({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    final bytes = await build(
      title: title,
      rows: rows,
      totalBalance: totalBalance,
      extraColumnHeader: extraColumnHeader,
      extraColumnKey: extraColumnKey,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
