// lib/features/invoices/pdf_service.dart
// ─────────────────────────────────────────────
// Generates a real A4 Arabic RTL invoice PDF.
// Sections:
//   1. Company header
//   2. Invoice info box
//   3. Items table
//   4. Totals box
//   5. Amount in Arabic words
//   6. Footer
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/invoice_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../core/ui_utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class PdfService {
  // ── Filename formatting helper ───────────
  static String _formattedFileName(InvoiceModel invoice) {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    final typeName = invoice.type == 'return' ? 'فاتورة مرتجع' : 'فاتورة مبيعات';
    return '$typeName $minute-$hour-$day-$month-$year';
  }
  // ── Arabic font (loaded once) ─────────────
  static pw.Font? _arabicFont;
  static pw.Font? _arabicBoldFont;

  static Future<void> _loadFonts() async {
    if (_arabicFont != null) return; // already loaded
    final regular = await rootBundle
        .load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle
        .load('assets/fonts/Cairo-Bold.ttf');
    _arabicFont     = pw.Font.ttf(regular);
    _arabicBoldFont = pw.Font.ttf(bold);
  }

  // ── Colors (Black & White for printing) ──
  static const _primaryColor  = PdfColor.fromInt(0xFF212121);
  static const _darkColor     = PdfColor.fromInt(0xFF212121);
  static const _grayColor     = PdfColor.fromInt(0xFF757575);
  static const _lightGray     = PdfColor.fromInt(0xFFF5F5F5);
  static const _borderColor   = PdfColor.fromInt(0xFFBDBDBD);
  static const _successColor  = PdfColor.fromInt(0xFF212121);
  static const _dangerColor   = PdfColor.fromInt(0xFF212121);
  static const _white         = PdfColors.white;

  // ── Main entry point ──────────────────────
  // Call this to generate + save + open PDF

  static Future<void> generateAndPrint(
      InvoiceModel invoice) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final pdf = await _buildPdf(invoice, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: _formattedFileName(invoice),
    );
  }

  static Future<Uint8List> generateBytes(
      InvoiceModel invoice) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    return await _buildPdf(invoice, settings);
  }

  static Future<File> saveToFile(BuildContext context, InvoiceModel invoice) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildPdf(invoice, settings);
    final dir   = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName(invoice);
    final path  = '${dir.path}/$fileName.pdf';
    final file  = File(path);
    await file.writeAsBytes(bytes);
    UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    return file;
  }

  // ── Build the PDF document ─────────────────
  static Future<Uint8List> _buildPdf(
      InvoiceModel invoice, Map<String, String> settings) async {
    final doc = pw.Document();

    // Fonts theme
    final theme = pw.ThemeData.withFont(
      base: _arabicFont!,
      bold: _arabicBoldFont!,
    );

    String customerCode = '—';
    if (invoice.customerId != null) {
      try {
        final customer = await CustomerDao().getById(invoice.customerId!);
        if (customer != null) {
          customerCode = customer.code.isNotEmpty ? customer.code : customer.id?.toString() ?? '—';
        }
      } catch (_) {}
    }

    final isReturn = invoice.type == 'return';
    final title = isReturn ? 'فاتورة مرتجع' : 'فاتورة مبيعات';

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme:       theme,
          pageFormat:  PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(
              horizontal: 32, vertical: 30),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context ctx) => [
          pw.Center(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: _arabicBoldFont,
                fontSize: 18,
                color: _primaryColor,
              ),
            ),
          ),
          pw.SizedBox(height: 15),
          _buildInvoiceInfoBox(invoice, customerCode),
          pw.SizedBox(height: 12),
          _buildItemsTable(invoice),
          pw.SizedBox(height: 10),
          _buildTotalsBox(invoice),
          pw.SizedBox(height: 10),
          _buildAmountInWords(invoice),
          if (invoice.notes != null &&
              invoice.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _buildNotesBox(invoice.notes!),
          ],
          pw.SizedBox(height: 15),
          _buildSignatureRow(),
        ],
        footer: (pw.Context ctx) =>
            _buildFooter(ctx, invoice, settings),
      ),
    );

    return doc.save();
  }

  // ── 2. Invoice info box ───────────────────
  static pw.Widget _buildInvoiceInfoBox(InvoiceModel invoice, String customerCode) {
    final isReturn = invoice.type == 'return';
    return pw.Container(
      decoration: pw.BoxDecoration(
        border:        pw.Border.all(color: _borderColor),
        borderRadius:  pw.BorderRadius.circular(6),
        color:         _lightGray,
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: pw.Row(
        children: [
          // Customer info
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _infoLabel('العميل'),
                pw.SizedBox(height: 2),
                _infoValue(invoice.customerName ?? '—', fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          // Customer code
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _infoLabel('كود العميل'),
                pw.SizedBox(height: 2),
                _infoValue(customerCode, fontSize: 11),
              ],
            ),
          ),
          _verticalDivider(),
          // Invoice date
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _infoLabel(isReturn ? 'تاريخ المرتجع' : 'تاريخ الفاتورة'),
                pw.SizedBox(height: 2),
                _infoValue(
                  AppUtils.formatDate(
                    AppUtils.parseDate(invoice.invoiceDate),
                  ),
                  fontSize: 11,
                ),
              ],
            ),
          ),
          _verticalDivider(),
          // Invoice number
          pw.Expanded(
            flex: 1,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoLabel(isReturn ? 'رقم المرتجع' : 'رقم الفاتورة'),
                pw.SizedBox(height: 2),
                _infoValue(
                  invoice.invoiceNumber
                      .toString()
                      .padLeft(6, '0'),
                  color: _primaryColor,
                  fontSize: 13,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Items table ────────────────────────
  static pw.Widget _buildItemsTable(InvoiceModel invoice) {
    return pw.Table(
      border: pw.TableBorder.all(
          color: _borderColor, width: 0.5),
      children: [
        // Header row
        _tableHeaderRow([
          'الإجمالي', 'السعر', 'العدد', 'الكمية', 'الكود', 'الصنف', '#'
        ]),
        // Data rows
        ...invoice.items.asMap().entries.map((entry) {
          final i    = entry.key;
          final item = entry.value;
          return _tableDataRow(
            [
              AppUtils.formatCurrency(item.totalPrice),
              AppUtils.formatCurrency(item.unitPrice),
              AppUtils.formatNumber(item.piecesCount),
              '${AppUtils.formatNumber(item.quantity)} ${item.unit}',
              item.itemCode ?? '—',
              item.itemName ?? '—',
              '${i + 1}',
            ],
            isEven: i % 2 == 0,
          );
        }),
      ],
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _primaryColor),
      children: cells.map((cell) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(
            horizontal: 8, vertical: 8),
        child: pw.Text(
          cell,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font:     _arabicBoldFont,
            fontSize: 11,
            color:    _white,
          ),
        ),
      )).toList(),
    );
  }

  static pw.TableRow _tableDataRow(
      List<String> cells, {required bool isEven}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: isEven ? _white : _lightGray,
      ),
      children: cells.asMap().entries.map((entry) {
        final idx  = entry.key;
        final cell = entry.value;
        // Right-align item name (idx == 4), center rest
        final align = idx == 4
            ? pw.TextAlign.right
            : pw.TextAlign.center;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 8, vertical: 7),
          child: pw.Text(
            cell,
            textDirection: pw.TextDirection.rtl,
            textAlign:     align,
            style: pw.TextStyle(
              font:     _arabicFont,
              fontSize: 10,
              color:    _darkColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 4. Totals box ─────────────────────────
  static pw.Widget _buildTotalsBox(InvoiceModel invoice) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260,
          decoration: pw.BoxDecoration(
            border:       pw.Border.all(color: _borderColor),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              // Subtotal
              _totalLine(
                'إجمالي الأصناف',
                AppUtils.formatCurrency(invoice.totalAmount),
              ),
              _totalDivider(),

              // Discount (if any)
              if (invoice.discountAmount > 0) ...[
                _totalLine(
                  'الخصم',
                  '- ${AppUtils.formatCurrency(invoice.discountAmount)}',
                  valueColor: _dangerColor,
                ),
                _totalDivider(),
              ],

              // Net total
              _totalLine(
                'الصافي',
                AppUtils.formatCurrency(invoice.netAmount),
                isBold:     true,
                bgColor:    _lightGray,
              ),
              _totalDivider(),

              // Paid
              _totalLine(
                'المدفوع',
                AppUtils.formatCurrency(invoice.paidAmount),
                valueColor: _successColor,
              ),
              _totalDivider(),

              // Remaining
              _totalLine(
                'المتبقي',
                AppUtils.formatCurrency(
                    invoice.remainingAmount.abs()),
                isBold: true,
                valueColor: _darkColor,
                bgColor:    _lightGray,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _totalLine(
    String label,
    String value, {
    bool isBold = false,
    PdfColor? valueColor,
    PdfColor? bgColor,
  }) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(
          horizontal: 12, vertical: 7),
      child: pw.Row(
        mainAxisAlignment:
            pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            value,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font:     isBold ? _arabicBoldFont : _arabicFont,
              fontSize: isBold ? 12 : 11,
              color:    valueColor ?? _darkColor,
            ),
          ),
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font:     isBold ? _arabicBoldFont : _arabicFont,
              fontSize: 11,
              color:    _grayColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalDivider() {
    return pw.Divider(
        height: 0.5, color: _borderColor, thickness: 0.5);
  }

  // ── 5. Amount in Arabic words ─────────────
  static pw.Widget _buildAmountInWords(InvoiceModel invoice) {
    final words =
        AppUtils.numberToArabicWords(invoice.netAmount);
    return pw.Container(
      width:       double.infinity,
      decoration: pw.BoxDecoration(
        color:        _lightGray,
        border:       pw.Border.all(
            color: _borderColor,
            width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      padding: const pw.EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              words,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font:     _arabicFont,
                fontSize: 11,
                color:    _darkColor,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            'فقط لا غير:',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font:     _arabicBoldFont,
              fontSize: 11,
              color:    _darkColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Notes box ──────────────────────────
  static pw.Widget _buildNotesBox(String notes) {
    return pw.Container(
      width:       double.infinity,
      decoration:  pw.BoxDecoration(
        color:        _lightGray,
        border:       pw.Border.all(color: _borderColor, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'ملاحظات:',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font:     _arabicBoldFont,
              fontSize: 10,
              color:    _grayColor,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            notes,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font:     _arabicFont,
              fontSize: 10,
              color:    _darkColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── 7. Signature row ──────────────────────
  static pw.Widget _buildSignatureRow() {
    return pw.Row(
      mainAxisAlignment:
          pw.MainAxisAlignment.spaceBetween,
      children: [
        _signatureBox('توقيع العميل'),
        _signatureBox('توقيع المسؤول'),
        _signatureBox('الختم'),
      ],
    );
  }

  static pw.Widget _signatureBox(String label) {
    return pw.Column(
      children: [
        pw.Container(
          width:  140,
          height: 50,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                  color: _borderColor, width: 0.5),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            font:     _arabicFont,
            fontSize: 10,
            color:    _grayColor,
          ),
        ),
      ],
    );
  }

  // ── Page footer ───────────────────────────
  static pw.Widget _buildFooter(
      pw.Context ctx, InvoiceModel invoice, Map<String, String> settings) {
    return pw.Column(
      children: [
        pw.Divider(color: _borderColor, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment:
              pw.MainAxisAlignment.spaceBetween,
          children: [
            // Page number (left in RTL)
            pw.Text(
              'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font:     _arabicFont,
                fontSize: 9,
                color:    _grayColor,
              ),
            ),
            // Company name (center)
            pw.Text(
              settings['company_name'] ?? AppConstants.companyName,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font:     _arabicFont,
                fontSize: 9,
                color:    _grayColor,
              ),
            ),
            // Invoice number (right in RTL)
            pw.Text(
              '${invoice.type == 'return' ? 'مرتجع' : 'فاتورة'} رقم: ${invoice.invoiceNumber.toString().padLeft(6, '0')}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font:     _arabicFont,
                fontSize: 9,
                color:    _grayColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Small helpers ─────────────────────────

  static pw.Widget _infoLabel(String text) {
    return pw.Text(
      text,
      textDirection: pw.TextDirection.rtl,
      style: pw.TextStyle(
        font:     _arabicFont,
        fontSize: 9,
        color:    _grayColor,
      ),
    );
  }

  static pw.Widget _infoValue(
    String text, {
    PdfColor? color,
    double fontSize = 12,
  }) {
    return pw.Text(
      text,
      textDirection: pw.TextDirection.rtl,
      style: pw.TextStyle(
        font:     _arabicBoldFont,
        fontSize: fontSize,
        color:    color ?? _darkColor,
      ),
    );
  }

  static pw.Widget _verticalDivider() {
    return pw.Container(
      width:  0.5,
      height: 40,
      color:  _borderColor,
      margin: const pw.EdgeInsets.symmetric(horizontal: 10),
    );
  }
}
