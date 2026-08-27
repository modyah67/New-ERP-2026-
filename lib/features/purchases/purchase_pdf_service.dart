// lib/features/purchases/purchase_pdf_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/purchase_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../core/ui_utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class PurchasePdfService {
  static pw.Font? _arabicFont;
  static pw.Font? _arabicBoldFont;

  static Future<void> _loadFonts() async {
    if (_arabicFont != null) return;
    final regular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _arabicFont = pw.Font.ttf(regular);
    _arabicBoldFont = pw.Font.ttf(bold);
  }

  static const _primaryColor = PdfColor.fromInt(0xFF212121);
  static const _white = PdfColors.white;
  static const _lightGray = PdfColor.fromInt(0xFFF5F5F5);
  static const _borderColor = PdfColor.fromInt(0xFF212121);
  static const _darkColor = PdfColor.fromInt(0xFF212121);
  static const _grayColor = PdfColor.fromInt(0xFF212121);

  static String _formattedFileName() {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return 'فاتورة مشتريات $minute-$hour-$day-$month-$year';
  }

  static Future<Uint8List> generatePdfBytes(PurchaseModel purchase) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    return _buildPdf(purchase, settings);
  }

  static Future<void> generateAndPrint(PurchaseModel purchase) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final pdf = await _buildPdf(purchase, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: _formattedFileName(),
    );
  }

  static Future<File> saveToFile(BuildContext context, PurchaseModel purchase) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildPdf(purchase, settings);
    final dir = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName();
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    return file;
  }

  static Future<Uint8List> _buildPdf(PurchaseModel purchase, Map<String, String> settings) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _arabicFont!, bold: _arabicBoldFont!);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 30),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        header: (pw.Context ctx) => pw.SizedBox(height: 60),
        build: (pw.Context ctx) => [
          pw.Center(
            child: pw.Text(
              'فاتورة مشتريات',
              style: pw.TextStyle(
                font: _arabicBoldFont,
                fontSize: 18,
                color: _primaryColor,
              ),
            ),
          ),
          pw.SizedBox(height: 15),
          _buildInfoBox(purchase),
          pw.SizedBox(height: 12),
          _buildItemsTable(purchase),
          pw.SizedBox(height: 10),
          _buildTotalsBox(purchase),
          if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _buildNotesBox(purchase.notes!),
          ],
          pw.SizedBox(height: 15),
          _buildSignatureRow(),
          pw.SizedBox(height: 80),
        ],
        footer: (pw.Context ctx) => pw.SizedBox(height: 60),
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildInfoBox(PurchaseModel purchase) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderColor),
        borderRadius: pw.BorderRadius.circular(6),
        color: _lightGray,
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _infoLabel('المورد'),
                pw.SizedBox(height: 2),
                _infoValue(purchase.supplierName ?? '—', fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _infoLabel('كود المورد'),
                pw.SizedBox(height: 2),
                _infoValue(purchase.supplierCode ?? '—', fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _infoLabel('سعر الصرف'),
                pw.SizedBox(height: 2),
                _infoValue(AppUtils.formatNumber(purchase.items.isNotEmpty ? purchase.items.first.exchangeRate : 1.0), fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _infoLabel('تاريخ المشتريات'),
                pw.SizedBox(height: 2),
                _infoValue(AppUtils.formatDate(AppUtils.parseDate(purchase.purchaseDate)), fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoLabel('رقم المشتريات'),
                pw.SizedBox(height: 2),
                _infoValue(purchase.purchaseNumber.toString().padLeft(6, '0'), color: _primaryColor, fontSize: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(PurchaseModel purchase) {
    final isForeign = purchase.currency.toUpperCase() != 'EGP';
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      children: [
        _tableHeaderRow([
          'الإجمالي',
          if (isForeign) 'بالجنيه المصري',
          'سعر الشراء',
          if (isForeign) 'سعر الصرف',
          'الكمية', 'الكود', 'الصنف', '#',
        ]),
        ...purchase.items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return _tableDataRow([
            '${AppUtils.formatNumber(item.totalPrice)} ${purchase.currency}',
            if (isForeign) '${AppUtils.formatNumber(item.totalPrice * item.exchangeRate)} ج.م',
            '${AppUtils.formatNumber(item.purchasePrice)} ${purchase.currency}',
            if (isForeign) '${AppUtils.formatNumber(item.exchangeRate)}',
            '${AppUtils.formatNumber(item.quantity)} ${item.unit}',
            item.itemCode,
            item.itemName,
            '${i + 1}',
          ], isEven: i % 2 == 0);
        }),
      ],
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _primaryColor),
      children: cells.map((cell) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: pw.Text(cell, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: _arabicBoldFont, fontSize: 11, color: _white)),
      )).toList(),
    );
  }

  static pw.TableRow _tableDataRow(List<String> cells, {required bool isEven}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: isEven ? _white : _lightGray),
      children: cells.map((cell) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(cell, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: _arabicFont, fontSize: 10, color: _darkColor)),
      )).toList(),
    );
  }

  static pw.Widget _buildTotalsBox(PurchaseModel purchase) {
    final isForeign = purchase.currency.toUpperCase() != 'EGP';
    final exchangeRate = purchase.items.isNotEmpty ? purchase.items.first.exchangeRate : 1.0;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _borderColor), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(children: [
            _totalLine('إجمالي المشتريات', '${AppUtils.formatNumber(purchase.totalAmount)} ${purchase.currency}'),
            if (isForeign) ...[
              pw.Divider(height: 0.5, color: _borderColor),
              _totalLine('إجمالي بالجنيه المصري', '${AppUtils.formatNumber(purchase.totalAmount * exchangeRate)} ج.م', isBold: true, bgColor: _lightGray),
            ],
          ]),
        ),
      ],
    );
  }

  static pw.Widget _totalLine(String label, String value, {bool isBold = false, PdfColor? bgColor}) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(value, style: pw.TextStyle(font: isBold ? _arabicBoldFont : _arabicFont, fontSize: 11)),
        pw.Text(label, style: pw.TextStyle(font: _arabicFont, fontSize: 11, color: _grayColor)),
      ]),
    );
  }

  static pw.Widget _buildNotesBox(String notes) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(color: _lightGray, border: pw.Border.all(color: _borderColor, width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('ملاحظات:', style: pw.TextStyle(font: _arabicBoldFont, fontSize: 10, color: _grayColor)),
        pw.SizedBox(height: 4),
        pw.Text(notes, style: pw.TextStyle(font: _arabicFont, fontSize: 10, color: _darkColor)),
      ]),
    );
  }

  static pw.Widget _buildSignatureRow() {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      _sig('توقيع المورد'), _sig('توقيع المستلم'), _sig('الختم'),
    ]);
  }

  static pw.Widget _sig(String label) => pw.Column(children: [
    pw.Container(width: 140, height: 40, decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.5)))),
    pw.SizedBox(height: 4),
    pw.Text(label, style: pw.TextStyle(font: _arabicFont, fontSize: 10, color: _grayColor)),
  ]);

  static pw.Widget _infoLabel(String text) => pw.Text(text, style: pw.TextStyle(font: _arabicFont, fontSize: 9, color: _grayColor));
  static pw.Widget _infoValue(String text, {PdfColor? color, double fontSize = 12}) =>
      pw.Text(text, style: pw.TextStyle(font: _arabicBoldFont, fontSize: fontSize, color: color ?? _darkColor));
  static pw.Widget _verticalDivider() => pw.Container(width: 0.5, height: 25, color: _borderColor, margin: const pw.EdgeInsets.symmetric(horizontal: 10));
}
