import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../data/models/shipping_company_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShippingCompanyPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<Uint8List> _build(
      List<ShippingCompanyModel> companies) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    // Per-currency totals
    final Map<String, double> totalsByCurrency = {};
    for (final c in companies) {
      final curr = c.currency;
      totalsByCurrency[curr] = (totalsByCurrency[curr] ?? 0) + c.balance;
    }
    final sortedCurrencies = totalsByCurrency.keys.toList()..sort();

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.only(
            top: 70,
            bottom: 70,
            left: 28,
            right: 28,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 18, color: PdfColors.blueGrey)),
          pw.Text('كشف مجمع - شركات الشحن',
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 14, color: PdfColors.black)),
          pw.SizedBox(height: 4),
          pw.Text('تاريخ التقرير: ${DateTime.now().toString().substring(0, 16)}',
              style: pw.TextStyle(
                  font: _font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),

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
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: _boldFont, fontSize: 10, color: PdfColors.white),
            cellStyle: pw.TextStyle(
                font: _font, fontSize: 9, color: PdfColors.black),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300))),
            headers: ['#', 'الكود', 'اسم الشركة', 'الهاتف', 'البريد الإلكتروني', 'العملة', 'الرصيد الافتتاحي', 'الرصيد المالي الحالي'],
            data: List.generate(companies.length, (i) {
              final c = companies[i];
              return [
                '${i + 1}',
                c.code,
                c.name,
                c.phone,
                c.email,
                c.currency,
                c.initialBalance.toStringAsFixed(2),
                c.currentBalance.toStringAsFixed(2),
              ];
            }),
          ),
          pw.SizedBox(height: 12),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> printSummary(
      List<ShippingCompanyModel> companies) async {
    final bytes = await _build(companies);
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'shipping_companies_summary',
    );
  }

  static Future<String> saveToFile(
      List<ShippingCompanyModel> companies) async {
    final bytes = await _build(companies);
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'shipping_companies_summary_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
