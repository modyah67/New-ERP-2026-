// lib/features/statements/brief_statement_pdf_service.dart
// ─────────────────────────────────────────────────────────────
// Landscape A4, Black & White, 7-column summarized statement PDF
// Tailored to handle both Customers and Suppliers with dynamic labels.
// ─────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../core/ui_utils.dart';
import '../../data/models/statement_row_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class BriefStatementPdfService {
  // ── Filename formatting helper ───────────
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

  // ── Colors: Black & White only ────────────
  static const _dark     = PdfColor.fromInt(0xFF212121);
  static const _gray     = PdfColor.fromInt(0xFF757575);
  static const _lightBg  = PdfColor.fromInt(0xFFF5F5F5);
  static const _border   = PdfColor.fromInt(0xFFBDBDBD);
  static const _white    = PdfColors.white;

  // ── Public API ───────────────────────────

  static Future<void> generateAndPrint({
    CustomerModel? customer,
    SupplierModel? supplier,
    required bool isCustomerMode,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalMeters,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      customer:        customer,
      supplier:        supplier,
      isCustomerMode:  isCustomerMode,
      rows:            rows,
      totalDebit:      totalDebit,
      totalCredit:     totalCredit,
      finalBalance:    finalBalance,
      totalMeters:     totalMeters,
      fromDate:        fromDate,
      toDate:          toDate,
      statementNumber: statementNumber,
      settings:        settings,
    );
    final title = isCustomerMode ? 'كشف عميل مختصر' : 'كشف مورد مختصر';
    final docTitle = _formattedFileName(title);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:     docTitle,
    );
  }

  static Future<File> saveToFile(
    BuildContext context, {
    CustomerModel? customer,
    SupplierModel? supplier,
    required bool isCustomerMode,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalMeters,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      customer:        customer,
      supplier:        supplier,
      isCustomerMode:  isCustomerMode,
      rows:            rows,
      totalDebit:      totalDebit,
      totalCredit:     totalCredit,
      finalBalance:    finalBalance,
      totalMeters:     totalMeters,
      fromDate:        fromDate,
      toDate:          toDate,
      statementNumber: statementNumber,
      settings:        settings,
    );
    final dir  = await FileHelper.getExportDirectory();
    final title = isCustomerMode ? 'كشف عميل مختصر' : 'كشف مورد مختصر';
    final fileName = _formattedFileName(title);
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    return file;
  }

  // ── Build PDF ─────────────────────────────

  static Future<Uint8List> _build({
    CustomerModel? customer,
    SupplierModel? supplier,
    required bool isCustomerMode,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalMeters,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    required Map<String, String> settings,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);
    final entityCurrency = isCustomerMode ? (customer?.currency ?? 'EGP') : (supplier?.currency ?? 'EGP');

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme:         theme,
          pageFormat:    PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(
              horizontal: 28, vertical: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          _buildTitle(isCustomerMode),
          pw.SizedBox(height: 10),
          _buildInfoBox(customer, supplier, isCustomerMode),
          pw.SizedBox(height: 12),
          _buildTable(rows, isCustomerMode, entityCurrency),
          pw.SizedBox(height: 10),
          _buildSummary(totalDebit, totalCredit, finalBalance, totalMeters, isCustomerMode, entityCurrency),
        ],
        footer: (ctx) => _buildFooter(ctx, customer, supplier, isCustomerMode, settings),
      ),
    );

    return doc.save();
  }

  // ── Header Title ──────────────────────────

  static pw.Widget _buildTitle(bool isCustomerMode) {
    final titleText = isCustomerMode
        ? 'كشف حساب مختصر للعميل (إجمالي الحركات)'
        : 'كشف حساب مختصر للمورد (إجمالي الحركات)';
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text(
        titleText,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(font: _boldFont, fontSize: 14, color: _dark),
      ),
    );
  }

  // ── Info Box ──────────────────────────────

  static pw.Widget _buildInfoBox(
    CustomerModel? c,
    SupplierModel? s,
    bool isCustomerMode,
  ) {
    final name  = isCustomerMode ? (c?.name ?? '—') : (s?.name ?? '—');
    final phone = isCustomerMode ? (c?.phone ?? '—') : (s?.phone ?? '—');
    final code  = isCustomerMode ? (c?.id?.toString() ?? '—') : (s?.supplierCode ?? '—');

    return pw.Container(
      decoration: pw.BoxDecoration(
        color:        _lightBg,
        border:       pw.Border.all(color: _border, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        children: [
          _infoCell(isCustomerMode ? 'اسم العميل' : 'اسم المورد', name),
          _vDiv(),
          _infoCell('التليفون', phone),
          _vDiv(),
          _infoCell(isCustomerMode ? 'كود العميل' : 'كود المورد', code),
          if (!isCustomerMode) ...[
            _vDiv(),
            _infoCell('العنوان', s != null && s.address.isNotEmpty ? s.address : '—'),
          ],
        ],
      ),
    );
  }

  static pw.Widget _infoCell(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: _font, fontSize: 8, color: _gray)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 10, color: _dark)),
        ],
      ),
    );
  }

  static pw.Widget _vDiv() {
    return pw.Container(
        width: 0.5, height: 28, color: _border,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6));
  }

  // ── 7-column summarized table ─────────────

  static pw.Widget _buildTable(List<StatementRow> rows, bool isCustomerMode, String currency) {
    if (rows.isEmpty) {
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'لا توجد حركات في هذه الفترة',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _font, fontSize: 11, color: _gray),
        ),
      );
    }

    const headers = [
      'الرصيد', 'له', 'منه', 'البيان', 'اسم الحساب', 'التاريخ', 'رقم الفاتورة أو المعاملة'
    ];

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(0.13),  // الرصيد
        1: const pw.FlexColumnWidth(0.11),  // له
        2: const pw.FlexColumnWidth(0.11),  // منه
        3: const pw.FlexColumnWidth(0.28),  // البيان
        4: const pw.FlexColumnWidth(0.16),  // اسم الحساب
        5: const pw.FlexColumnWidth(0.10),  // التاريخ
        6: const pw.FlexColumnWidth(0.11),  // رقم الفاتورة أو المعاملة
      },
      border: pw.TableBorder.all(color: _border, width: 0.5),
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _dark),
          children: headers.map((h) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 4, vertical: 6),
            child: pw.Text(h,
                textDirection: pw.TextDirection.rtl,
                textAlign:     pw.TextAlign.center,
                style: pw.TextStyle(
                    font:     _boldFont,
                    fontSize: 8,
                    color:    _white)),
          )).toList(),
        ),
        // Data rows
        ...rows.asMap().entries.map((entry) {
          final i   = entry.key;
          final row = entry.value;
          final isEven = i % 2 == 0;

          // Format running balance text
          String balanceText = AppUtils.formatCurrency(row.balance.abs(), currency);
          if (row.type != 'opening') {
            if (isCustomerMode) {
              balanceText += row.balance > 0 ? ' (عليه)' : row.balance < 0 ? ' (له)' : '';
            } else {
              balanceText += row.balance > 0 ? ' (له)' : row.balance < 0 ? ' (عليه)' : '';
            }
          }

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? _white : _lightBg,
            ),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                child: pw.Text(
                  balanceText,
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _dark),
                ),
              ),
              _cell(row.credit > 0 ? AppUtils.formatCurrency(row.credit, currency) : '—'),
              _cell(row.debit > 0 ? AppUtils.formatCurrency(row.debit, currency) : '—'),
              _cell(row.description, align: pw.TextAlign.right),
              _cell(row.accountName),
              _cell(AppUtils.formatDate(AppUtils.parseDate(row.date))),
              _cell(row.transactionNumber.replaceAll(RegExp(r'[\u202A-\u202C\u200E\u200F]'), '')),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    PdfColor? color,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
          horizontal: 4, vertical: 6),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign:     align,
        style: pw.TextStyle(
          font:     isBold ? _boldFont : _font,
          fontSize: 8,
          color:    color ?? _dark,
        ),
      ),
    );
  }

  // ── Summary box ───────────────────────────

  static pw.Widget _buildSummary(
    double totalDebit,
    double totalCredit,
    double finalBalance,
    double totalMeters,
    bool isCustomerMode,
    String currency,
  ) {
    String balLabel = 'متوازن';
    if (finalBalance != 0) {
      if (isCustomerMode) {
        balLabel = finalBalance > 0 ? 'عليه' : 'له';
      } else {
        balLabel = finalBalance > 0 ? 'له' : 'عليه';
      }
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 300,
          decoration: pw.BoxDecoration(
            border:       pw.Border.all(color: _border, width: 0.5),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              _summaryRow('إجمالي الأمتار',
                  '${AppUtils.formatNumber(totalMeters)} م'),
              pw.Divider(color: _border, thickness: 0.5, height: 0),
              _summaryRow('إجمالي منه (مدين)', AppUtils.formatCurrency(totalDebit, currency)),
              pw.Divider(color: _border, thickness: 0.5, height: 0),
              _summaryRow('إجمالي له (دائن)', AppUtils.formatCurrency(totalCredit, currency)),
              pw.Divider(color: _border, thickness: 0.5, height: 0),
              _summaryRow(
                'الرصيد النهائي ($balLabel)',
                AppUtils.formatCurrency(finalBalance.abs(), currency),
                isBold:  true,
                bgColor: _lightBg,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    bool isBold  = false,
    PdfColor? bgColor,
  }) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(
          horizontal: 10, vertical: 7),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(value,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font:     isBold ? _boldFont : _font,
                  fontSize: isBold ? 11 : 9,
                  color:    _dark)),
          pw.Text(label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font:     _font,
                  fontSize: 9,
                  color:    _gray)),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────

  static pw.Widget _buildFooter(
    pw.Context ctx,
    CustomerModel? customer,
    SupplierModel? supplier,
    bool isCustomerMode,
    Map<String, String> settings,
  ) {
    final name = isCustomerMode ? (customer?.name ?? '') : (supplier?.name ?? '');
    final typeLabel = isCustomerMode ? 'كشف حساب عميل مختصر' : 'كشف حساب مورد مختصر';

    return pw.Column(
      children: [
        pw.Divider(color: _border, thickness: 0.5),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: _font, fontSize: 8, color: _gray),
            ),
            pw.Text(
              settings['company_name'] ?? AppConstants.companyName,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: _font, fontSize: 8, color: _gray),
            ),
            pw.Text(
              '$typeLabel: $name',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  font: _font, fontSize: 8, color: _gray),
            ),
          ],
        ),
      ],
    );
  }
}
