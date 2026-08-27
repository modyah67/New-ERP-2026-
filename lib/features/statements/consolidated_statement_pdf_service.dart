import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/customer_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../core/ui_utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ConsolidatedStatementPdfService {
  static String _formattedFileName(String title) {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '$title $minute-$hour-$day-$month-$year';
  }

  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font     = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static const _dark    = PdfColor.fromInt(0xFF212121);
  static const _gray    = PdfColor.fromInt(0xFF757575);
  static const _lightBg = PdfColor.fromInt(0xFFF5F5F5);
  static const _border  = PdfColor.fromInt(0xFFBDBDBD);
  static const _red     = PdfColor.fromInt(0xFFD32F2F);
  static const _green   = PdfColor.fromInt(0xFF2E7D32);
  static const _white   = PdfColors.white;

  static Future<void> generateAndPrint({
    required List<CustomerModel> customers,
    required DateTime printDate,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      customers: customers,
      printDate: printDate,
      settings:  settings,
    );
    final docTitle = _formattedFileName('كشف حساب مجمع');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:     docTitle,
    );
  }

  static Future<File> saveToFile(
    BuildContext context, {
    required List<CustomerModel> customers,
    required DateTime printDate,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      customers: customers,
      printDate: printDate,
      settings:  settings,
    );
    final dir  = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('كشف حساب مجمع');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    return file;
  }

  static Future<Uint8List> _build({
    required List<CustomerModel> customers,
    required DateTime printDate,
    required Map<String, String> settings,
  }) async {
    final font     = _font!;
    final boldFont = _boldFont!;

    pw.TextStyle txt(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(font: bold ? boldFont : font, fontSize: size,
            color: color ?? _dark);

    final companyName = settings['company_name'] ?? 'نظام المحاسبة';
    final companyPhone = settings['company_phone'] ?? '';

    final grandTotal = customers.fold(0.0, (s, c) => s + c.balance);

    const rowsPerPage = 20;
    final pages = <List<CustomerModel>>[];
    for (var i = 0; i < customers.length; i += rowsPerPage) {
      pages.add(customers.sublist(
          i, (i + rowsPerPage).clamp(0, customers.length)));
    }
    final totalPages = pages.isEmpty ? 1 : pages.length;

    final pdf = pw.Document();
    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final pageCustomers = pages.isEmpty ? <CustomerModel>[] : pages[pageIdx];
      final isLastPage = pageIdx == totalPages - 1;

      pdf.addPage(pw.Page(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.only(top: 70, bottom: 70, left: 24, right: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _lightBg,
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(companyName, style: txt(16, bold: true)),
                    if (companyPhone.isNotEmpty)
                      pw.Text(companyPhone, style: txt(10, color: _gray)),
                    pw.SizedBox(height: 6),
                    pw.Text('كشف حساب مجمع', style: txt(13, bold: true)),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي العملاء: ${customers.length}',
                        style: txt(10, bold: true)),
                    pw.Text('تاريخ الطباعة: ${AppUtils.formatDate(printDate)}',
                        style: txt(10, color: _gray)),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),
              _tableHeader(txt),
              ...pageCustomers.asMap().entries.map((e) => _tableRow(e.value, (pageIdx * rowsPerPage) + e.key, txt)),

              pw.Spacer(),

              if (isLastPage) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: pw.BoxDecoration(
                    color: _lightBg,
                    border: pw.Border.all(color: _border),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('إجمالي العملاء: ${customers.length}',
                          style: txt(10, bold: true)),
                      pw.Row(
                        children: [
                          pw.Text('إجمالي الأرصدة: ', style: txt(10, color: _gray)),
                          pw.Text(
                            grandTotal < 0
                                ? '-${AppUtils.formatCurrency(grandTotal.abs())}'
                                : '${AppUtils.formatCurrency(grandTotal)}',
                            style: txt(13, bold: true,
                                color: grandTotal < 0 ? _green : _red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
              ],

              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'صفحة ${pageIdx + 1} من $totalPages',
                  style: txt(9, color: _gray),
                ),
              ),
            ],
          );
        },
      ));
    }

    return pdf.save();
  }

  static pw.Widget _tableHeader(pw.TextStyle Function(double, {bool bold, PdfColor? color}) txt) {
    return pw.Container(
      color: _lightBg,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 30, child: pw.Text('#', style: txt(10, bold: true))),
          pw.SizedBox(width: 80, child: pw.Text('الكود', style: txt(10, bold: true))),
          pw.Expanded(child: pw.Text('اسم العميل', style: txt(10, bold: true))),
          pw.SizedBox(width: 100, child: pw.Text('الرصيد', style: txt(10, bold: true), textAlign: pw.TextAlign.center)),
          pw.SizedBox(width: 50,  child: pw.Text('البيان', style: txt(10, bold: true), textAlign: pw.TextAlign.center)),
        ],
      ),
    );
  }

  static pw.Widget _tableRow(
      CustomerModel c, int globalIdx,
      pw.TextStyle Function(double, {bool bold, PdfColor? color}) txt) {
    final balance  = c.balance;
    final isEven   = globalIdx % 2 == 0;
    final isDebt   = balance > 0;
    final isCredit = balance < 0;

    final balanceColor = isDebt ? _red : isCredit ? _green : _gray;
    final displayBalance = isCredit
        ? '-${AppUtils.formatCurrency(balance.abs())}'
        : AppUtils.formatCurrency(balance.abs());
    final label = isDebt ? 'عليه' : isCredit ? 'له' : 'متوازن';

    return pw.Container(
      color: isEven ? _white : _lightBg,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 30,
              child: pw.Text('${globalIdx + 1}', style: txt(9, color: _gray))),
          pw.SizedBox(width: 80,
              child: pw.Text(c.id.toString(), style: txt(9, bold: true))),
          pw.Expanded(
              child: pw.Text(c.name, style: txt(10))),
          pw.SizedBox(width: 100,
              child: pw.Text(displayBalance,
                  textAlign: pw.TextAlign.center,
                  style: txt(10, bold: true, color: balanceColor))),
          pw.SizedBox(width: 50,
              child: pw.Text(label,
                  textAlign: pw.TextAlign.center,
                  style: txt(9, color: balanceColor))),
        ],
      ),
    );
  }
}
