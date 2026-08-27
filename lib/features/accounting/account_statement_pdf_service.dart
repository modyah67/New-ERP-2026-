// lib/features/accounting/account_statement_pdf_service.dart
// ────────────────────────────────────────────────────────
// Professional PDF generation service for Account Statement
// ────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../core/ui_utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class AccountStatementPdfService {
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

  static const _dark     = PdfColor.fromInt(0xFF1565C0); // Premium blue
  static const _gray     = PdfColor.fromInt(0xFF757575);
  static const _lightBg  = PdfColor.fromInt(0xFFF8F9FA);
  static const _border   = PdfColor.fromInt(0xFFE0E0E0);
  static const _white    = PdfColors.white;

  static Future<void> generateAndPrint({
    required AccountModel account,
    required List<Map<String, dynamic>> rows,
    required double totalDebit,
    required double totalCredit,
    required double openingBalance,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      account:        account,
      rows:           rows,
      totalDebit:     totalDebit,
      totalCredit:    totalCredit,
      openingBalance: openingBalance,
      finalBalance:   finalBalance,
      fromDate:       fromDate,
      toDate:         toDate,
      settings:       settings,
    );
    final docTitle = _formattedFileName('كشف حساب مالي');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:     docTitle,
    );
  }

  static Future<File> saveToFile(
    BuildContext context, {
    required AccountModel account,
    required List<Map<String, dynamic>> rows,
    required double totalDebit,
    required double totalCredit,
    required double openingBalance,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _build(
      account:        account,
      rows:           rows,
      totalDebit:     totalDebit,
      totalCredit:    totalCredit,
      openingBalance: openingBalance,
      finalBalance:   finalBalance,
      fromDate:       fromDate,
      toDate:         toDate,
      settings:       settings,
    );
    final dir  = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('كشف حساب مالي');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    return file;
  }

  static Future<Uint8List> _build({
    required AccountModel account,
    required List<Map<String, dynamic>> rows,
    required double totalDebit,
    required double totalCredit,
    required double openingBalance,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    required Map<String, String> settings,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme:         theme,
          pageFormat:    PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          _buildCompanyHeader(settings),
          pw.SizedBox(height: 12),
          _buildAccountHeader(account, fromDate, toDate),
          pw.SizedBox(height: 12),
          _buildTable(rows, openingBalance),
          pw.SizedBox(height: 10),
          _buildSummary(openingBalance, totalDebit, totalCredit, finalBalance),
        ],
        footer: (ctx) => _buildFooter(ctx, settings),
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildCompanyHeader(Map<String, String> settings) {
    return pw.SizedBox(); // We don't need company name or address here because logo handles it
  }

  static pw.Widget _buildAccountHeader(AccountModel account, DateTime? fromDate, DateTime? toDate) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('كشف حساب', style: pw.TextStyle(font: _boldFont, fontSize: 16, color: _dark)),
            pw.Text('الحساب: ${account.name}', style: pw.TextStyle(font: _boldFont, fontSize: 14, color: _dark)),
            pw.Text('رقم الحساب: ${account.code}', style: pw.TextStyle(font: _font, fontSize: 12, color: _gray)),
            if (fromDate != null && toDate != null)
              pw.Text('الفترة: ${AppUtils.formatDate(fromDate)} - ${AppUtils.formatDate(toDate)}',
                  style: pw.TextStyle(font: _font, fontSize: 12, color: _gray)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('تاريخ الطباعة: ${AppUtils.formatDate(DateTime.now())}', style: pw.TextStyle(font: _font, fontSize: 9, color: _gray)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTable(List<Map<String, dynamic>> rows, double openingBalance) {
    const headers = ['رقم القيد', 'التاريخ', 'النوع', 'المبلغ', 'رصيد قبل', 'رصيد بعد', 'البيان'];

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(0.08), // رقم القيد
        1: const pw.FlexColumnWidth(0.12), // التاريخ
        2: const pw.FlexColumnWidth(0.10), // النوع
        3: const pw.FlexColumnWidth(0.12), // المبلغ
        4: const pw.FlexColumnWidth(0.12), // رصيد قبل
        5: const pw.FlexColumnWidth(0.12), // رصيد بعد
        6: const pw.FlexColumnWidth(0.34), // البيان
      },
      border: pw.TableBorder.all(color: _border, width: 0.5),
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _dark),
          children: headers.map((h) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(h, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: _boldFont, fontSize: 9, color: _white)),
          )).toList(),
        ),
        // Opening Balance Row if it is non-zero or filtering applied
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _cell('—'),
            _cell('—'),
            _cell('رصيد افتتاحي'),
            _cell('—'),
            _cell('—'),
            _cell(AppUtils.formatCurrency(openingBalance), isBold: true),
            _cell('الرصيد السابق للفترة المحددة', align: pw.TextAlign.right),
          ],
        ),
        // Data Rows
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          final isEven = i % 2 == 0;
          final tx = row['tx'] as TransactionModel;
          final isDebit = row['isDebit'] as bool;
          final balBefore = row['balanceBefore'] as double;
          final balAfter = row['balanceAfter'] as double;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? _white : _lightBg),
            children: [
              _cell(tx.entryNumber?.toString() ?? '—'),
              _cell(AppUtils.formatDate(DateTime.tryParse(tx.transactionDate) ?? DateTime.now())),
              _cell(isDebit ? 'مدين' : 'دائن'),
              _cell(AppUtils.formatCurrency(tx.amount)),
              _cell(AppUtils.formatCurrency(balBefore)),
              _cell(AppUtils.formatCurrency(balAfter), isBold: true),
              _cell(tx.description, align: pw.TextAlign.right),
            ],
          );
        }).toList(),
      ],
    );
  }

  static pw.Widget _cell(String text, {pw.TextAlign align = pw.TextAlign.center, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? _boldFont : _font,
          fontSize: 8,
          color: _dark,
        ),
      ),
    );
  }

  static pw.Widget _buildSummary(double opening, double debit, double credit, double finalBalance) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
        color: _lightBg,
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _summaryText('الرصيد السابق: ${AppUtils.formatCurrency(opening)}'),
          _summaryText('إجمالي مدين (سحب): ${AppUtils.formatCurrency(debit)}'),
          _summaryText('إجمالي دائن (إيداع): ${AppUtils.formatCurrency(credit)}'),
          _summaryText('الرصيد النهائي: ${AppUtils.formatCurrency(finalBalance)}', isBold: true),
        ],
      ),
    );
  }

  static pw.Widget _summaryText(String text, {bool isBold = false}) {
    return pw.Text(
      text,
      textDirection: pw.TextDirection.rtl,
      style: pw.TextStyle(
        font: isBold ? _boldFont : _font,
        fontSize: 10,
        color: _dark,
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx, Map<String, String> settings) {
    final pageNum = ctx.pageNumber;
    final pagesCount = ctx.pagesCount;
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('صفحة $pageNum من $pagesCount', style: pw.TextStyle(font: _font, fontSize: 8, color: _gray)),
          pw.Text(settings['companyFooter'] ?? 'نظام المحاسبة الذهبي - نظام القيود المتكامل', style: pw.TextStyle(font: _font, fontSize: 8, color: _gray)),
        ],
      ),
    );
  }
}
