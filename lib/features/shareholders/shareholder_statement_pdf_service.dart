// lib/features/shareholders/shareholder_statement_pdf_service.dart
// Professional Landscape A4 Statement PDF Service for Shareholders

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/ui_utils.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../data/dao/settings_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShareholderStatementPdfService {
  ShareholderStatementPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Executive Navy & Emerald Equity Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static const _navyPrimary = PdfColor.fromInt(0xFF1A365D); // Deep Navy (#1A365D)
  static const _accentBlue  = PdfColor.fromInt(0xFF2980B9); // Corporate Blue (#2980B9)
  static const _cardBg      = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const _lightBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const _borderColor = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const _darkText    = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const _mutedText   = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const _white       = PdfColors.white;

  static const _greenText   = PdfColor.fromInt(0xFF15803D); // Green 700
  static const _greenBg     = PdfColor.fromInt(0xFFDCFCE7); // Green 100
  static const _redText     = PdfColor.fromInt(0xFFB91C1C); // Red 700
  static const _redBg       = PdfColor.fromInt(0xFFFEE2E2); // Red 100
  static const _blueText    = PdfColor.fromInt(0xFF0284C7); // Sky 600
  static const _blueBg      = PdfColor.fromInt(0xFFE0F2FE); // Sky 100

  // ──────────────────────────────────────────────────────────────────────────
  // FONT LOADER WITH CAIRO & NOTOSANS FALLBACK SUPPORT
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Font? _font;
  static pw.Font? _boldFont;
  static pw.Font? _fallbackFont;

  static Future<void> _loadFonts() async {
    if (_font != null && _boldFont != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _font = pw.Font.ttf(r);
      _boldFont = pw.Font.ttf(b);
    } catch (_) {
      try {
        final regularFile = File('assets/fonts/Cairo-Regular.ttf');
        final boldFile = File('assets/fonts/Cairo-Bold.ttf');
        if (regularFile.existsSync() && boldFile.existsSync()) {
          _font = pw.Font.ttf(regularFile.readAsBytesSync().buffer.asByteData());
          _boldFont = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } else {
          _font = await PdfGoogleFonts.cairoRegular();
          _boldFont = await PdfGoogleFonts.cairoBold();
        }
      } catch (_) {
        _font = await PdfGoogleFonts.cairoRegular();
        _boldFont = await PdfGoogleFonts.cairoBold();
      }
    }

    try {
      _fallbackFont = await PdfGoogleFonts.notoSansRegular();
    } catch (_) {
      _fallbackFont = pw.Font.courier();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILENAME FORMATTING HELPER
  // ──────────────────────────────────────────────────────────────────────────
  static String _formattedFileName(String title) {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '$title $minute-$hour-$day-$month-$year';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC ENTRY POINTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes in landscape format.
  static Future<Uint8List> generatePdfBytes({
    required ShareholderModel shareholder,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    double totalProfitShare = 0.0,
    double openingBalance = 0.0,
    required String currency,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    Map<String, String>? notes,
    Map<String, String>? settings,
  }) async {
    await _loadFonts();
    final resolvedSettings = settings ?? await () async {
      try {
        return await SettingsDao().getAllSettings();
      } catch (_) {
        return <String, String>{};
      }
    }();

    return _build(
      shareholder: shareholder,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      totalProfitShare: totalProfitShare,
      openingBalance: openingBalance,
      currency: currency,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      notes: notes,
      settings: resolvedSettings,
    );
  }

  /// Generates and opens the standard system print / export dialog in Landscape mode.
  static Future<void> generateAndPrint({
    required ShareholderModel shareholder,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    double totalProfitShare = 0.0,
    double openingBalance = 0.0,
    required String currency,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    Map<String, String>? notes,
  }) async {
    final bytes = await generatePdfBytes(
      shareholder: shareholder,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      totalProfitShare: totalProfitShare,
      openingBalance: openingBalance,
      currency: currency,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      notes: notes,
    );
    final docTitle = _formattedFileName('كشف_حساب_مساهم_${shareholder.name}');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the landscape PDF directly to the user's export storage.
  static Future<File> saveToFile(
    BuildContext context, {
    required ShareholderModel shareholder,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    double totalProfitShare = 0.0,
    double openingBalance = 0.0,
    required String currency,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    Map<String, String>? notes,
  }) async {
    final bytes = await generatePdfBytes(
      shareholder: shareholder,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      totalProfitShare: totalProfitShare,
      openingBalance: openingBalance,
      currency: currency,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      notes: notes,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('كشف_حساب_مساهم_${shareholder.name}');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف الحساب بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDER
  // ──────────────────────────────────────────────────────────────────────────

  static Future<Uint8List> _build({
    required ShareholderModel shareholder,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalProfitShare,
    required double openingBalance,
    required String currency,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    Map<String, String>? notes,
    required Map<String, String> settings,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final companyName = settings['company_name'] ?? AppConstants.companyName;
    final printDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final resolvedStatementNumber = statementNumber > 0
        ? statementNumber
        : (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000;

    pw.MemoryImage? bgImage;
    try {
      final bgData = await rootBundle.load('assets/images/statment.png');
      bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    } catch (_) {
      try {
        final f = File('assets/images/statment.png');
        if (f.existsSync()) {
          bgImage = pw.MemoryImage(f.readAsBytesSync());
        }
      } catch (_) {}
    }

    final pageTheme = pw.PageTheme(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      orientation: pw.PageOrientation.landscape,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      buildBackground: bgImage != null
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(bgImage!, fit: pw.BoxFit.cover),
              )
          : null,
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) {
          if (context.pageNumber > 1) {
            return _buildSubsequentHeader(
              shareholder: shareholder,
              companyName: companyName,
              printDate: printDate,
              pageNumber: context.pageNumber,
            );
          }
          return pw.SizedBox.shrink();
        },
        build: (ctx) => [
          _buildTopBanner(
            companyName: companyName,
            statementNumber: resolvedStatementNumber,
            printDate: printDate,
          ),
          pw.SizedBox(height: 10),
          _buildShareholderInfo(
            shareholder: shareholder,
            fromDate: fromDate,
            toDate: toDate,
            currency: currency,
            rowCount: rows.length,
          ),
          pw.SizedBox(height: 10),
          if (fromDate != null && openingBalance != 0.0) ...[
            _buildOpeningBalanceAlert(openingBalance, currency),
            pw.SizedBox(height: 10),
          ],
          _buildTable(
            rows: rows,
            notes: notes,
            currency: currency,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
          ),
          pw.SizedBox(height: 14),
          _buildSummary(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            totalProfitShare: totalProfitShare,
            currency: currency,
          ),
          pw.SizedBox(height: 14),
          _buildSignatureSection(),
        ],
        footer: (ctx) => _buildFooter(ctx, shareholder, companyName, printDate),
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER COMPONENTS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildTopBanner({
    required String companyName,
    required int statementNumber,
    required String printDate,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const pw.BoxDecoration(
        color: _navyPrimary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right side (Company branding)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 14,
                  color: _white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'نظام إدارة العمليات وحقوق المساهمين | Fruity Farms ERP',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: PdfColors.blueGrey100,
                ),
              ),
            ],
          ),

          // Center (Title Badge)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: _accentBlue,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'كشف حساب المساهم',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 12,
                    color: _white,
                  ),
                ),
                pw.Text(
                  'SHAREHOLDER ACCOUNT STATEMENT',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 6,
                    color: _white,
                  ),
                ),
              ],
            ),
          ),

          // Left side (Meta statement info)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    '#$statementNumber',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: _white),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    'رقم الكشف:',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.blueGrey100),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    printDate,
                    style: pw.TextStyle(font: _font, fontSize: 7.5, color: _white),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    'تاريخ الطباعة:',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 7.5, color: PdfColors.blueGrey100),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSubsequentHeader({
    required ShareholderModel shareholder,
    required String companyName,
    required String printDate,
    required int pageNumber,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.7)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'كشف حساب المساهم: ${shareholder.name} (${shareholder.code.isNotEmpty ? shareholder.code : "-"}) | $companyName',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _navyPrimary),
          ),
          pw.Text(
            'صفحة $pageNumber | تاريخ الطباعة: $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SHAREHOLDER META INFORMATION CARD (Landscape Grid)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildShareholderInfo({
    required ShareholderModel shareholder,
    required DateTime? fromDate,
    required DateTime? toDate,
    required String currency,
    required int rowCount,
  }) {
    final periodText = (fromDate != null && toDate != null)
        ? 'من ${AppUtils.formatDate(fromDate)} إلى ${AppUtils.formatDate(toDate)}'
        : (fromDate != null)
            ? 'من ${AppUtils.formatDate(fromDate)} وحتى تاريخه'
            : (toDate != null)
                ? 'حتى تاريخ ${AppUtils.formatDate(toDate)}'
                : 'كافة المعاملات المسجلة';

    final codeClean = shareholder.code.trim().isNotEmpty
        ? shareholder.code.trim()
        : '—';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _lightBg,
        border: pw.Border.all(color: _borderColor, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // 1. Shareholder Name
          _metaCell(
            label: 'اسم المساهم',
            englishLabel: 'Shareholder Name',
            value: shareholder.name,
            isBold: true,
          ),
          _vDiv(),

          // 2. Shareholder Code
          _metaCell(
            label: 'كود المساهم',
            englishLabel: 'Code',
            value: codeClean,
          ),
          _vDiv(),

          // 3. Currency
          _metaCell(
            label: 'عملة الحساب',
            englishLabel: 'Currency',
            value: currency,
            isBold: true,
            valueColor: _navyPrimary,
          ),
          _vDiv(),

          // 4. Accounting Period
          _metaCell(
            label: 'الفترة المحاسبية',
            englishLabel: 'Period',
            value: periodText,
          ),
          _vDiv(),

          // 5. Total Transactions
          _metaCell(
            label: 'إجمالي الحركات',
            englishLabel: 'Transactions Count',
            value: '$rowCount حركة مسجلة',
            valueColor: _accentBlue,
            isBold: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildOpeningBalanceAlert(double openingBalance, String currency) {
    final isNeg = openingBalance < 0;
    final absVal = AppUtils.formatNumber(openingBalance.abs());
    final bgColor = isNeg ? _redBg : _blueBg;
    final textColor = isNeg ? _redText : _navyPrimary;
    final borderColor = isNeg ? _redText : _accentBlue;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'ملحوظة هامة: ',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: textColor),
          ),
          pw.Text(
            'الرصيد السابق قبل بداية الفترة = $absVal $currency ${openingBalance > 0 ? "(دائن / له)" : "(مدين / عليه)"}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: textColor),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaCell({
    required String label,
    required String englishLabel,
    required String value,
    bool isBold = false,
    PdfColor? valueColor,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: _font,
              fontSize: 6.5,
              color: _mutedText,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: isBold ? _boldFont : _font,
              fontSize: 8.5,
              color: valueColor ?? _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _vDiv() {
    return pw.Container(
      width: 0.6,
      height: 24,
      color: _borderColor,
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 7-COLUMN LANDSCAPE DATA TABLE
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildTable({
    required List<StatementRow> rows,
    Map<String, String>? notes,
    required String currency,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
  }) {
    // Landscape A4 Printable width (~794pt)
    // 0: Date (0.11), 1: Type (0.12), 2: Description (0.28), 3: Debit (0.12),
    // 4: Credit (0.12), 5: Balance (0.13), 6: Notes (0.12)
    const columnWidths = {
      0: pw.FlexColumnWidth(0.11), // Date / التاريخ
      1: pw.FlexColumnWidth(0.12), // Type / النوع
      2: pw.FlexColumnWidth(0.28), // Description / الوصف
      3: pw.FlexColumnWidth(0.12), // Debit / مدين (سحوبات)
      4: pw.FlexColumnWidth(0.12), // Credit / دائن (إيداعات)
      5: pw.FlexColumnWidth(0.13), // Balance / الرصيد
      6: pw.FlexColumnWidth(0.12), // Notes / ملاحظات
    };

    const headers = [
      'التاريخ\nDate',
      'نوع الحركة\nType',
      'الوصف والبيان\nDescription',
      'مدين (سحوبات)\nDebit',
      'دائن (إيداعات/أرباح)\nCredit',
      'الرصيد\nBalance',
      'ملاحظات\nNotes',
    ];

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      children: [
        // Table Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: pw.Text(
                h,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 7.5,
                  color: _white,
                ),
              ),
            );
          }).toList(),
        ),

        // Data Rows
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final isEven = i % 2 == 0;

          final dateClean = r.date.trim().isNotEmpty ? r.date.trim() : '—';
          final typeClean = _formatTypeLabel(r.type, r.accountName);
          final descClean = r.description.trim().isNotEmpty ? r.description.trim() : '—';

          final rawNote = (notes != null && notes.containsKey(r.transactionNumber))
              ? notes[r.transactionNumber]!
              : '';
          final noteClean = rawNote.trim().isNotEmpty ? rawNote.trim() : '—';

          final debitClean = r.debit > 0 ? AppUtils.formatNumber(r.debit) : '—';
          final creditClean = r.credit > 0 ? AppUtils.formatNumber(r.credit) : '—';

          final balSign = r.balance > 0
              ? ' (له)'
              : r.balance < 0
                  ? ' (عليه)'
                  : '';
          final balanceClean = '${AppUtils.formatNumber(r.balance.abs())}$balSign';

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? _white : _cardBg,
            ),
            children: [
              _cell(dateClean),
              _cell(
                typeClean,
                isBold: true,
                color: r.type == 'profit'
                    ? _greenText
                    : r.type == 'treasury'
                        ? _navyPrimary
                        : _accentBlue,
              ),
              _cell(descClean, align: pw.TextAlign.right),
              _cell(
                debitClean,
                color: r.debit > 0 ? _redText : _mutedText,
                isBold: r.debit > 0,
              ),
              _cell(
                creditClean,
                color: r.credit > 0 ? _greenText : _mutedText,
                isBold: r.credit > 0,
              ),
              _cell(
                balanceClean,
                isBold: true,
                color: r.balance > 0
                    ? _greenText
                    : r.balance < 0
                        ? _redText
                        : _darkText,
              ),
              _cell(noteClean, align: pw.TextAlign.right),
            ],
          );
        }),

        // Embedded Table Totals Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _cell('المجموع', isBold: true, color: _navyPrimary),
            _cell('—', isBold: true),
            _cell(
              'إجمالي حركات الفترة (${rows.length} حركة)',
              isBold: true,
              align: pw.TextAlign.right,
              color: _navyPrimary,
            ),
            _cell(
              totalDebit > 0 ? AppUtils.formatNumber(totalDebit) : '0.00',
              isBold: true,
              color: _redText,
            ),
            _cell(
              totalCredit > 0 ? AppUtils.formatNumber(totalCredit) : '0.00',
              isBold: true,
              color: _greenText,
            ),
            _cell(
              '${AppUtils.formatNumber(finalBalance.abs())} ${finalBalance > 0 ? "(له)" : finalBalance < 0 ? "(عليه)" : ""}',
              isBold: true,
              color: finalBalance > 0 ? _greenText : finalBalance < 0 ? _redText : _navyPrimary,
            ),
            _cell('—', isBold: true),
          ],
        ),
      ],
    );
  }

  static String _formatTypeLabel(String type, String accountName) {
    switch (type.trim().toLowerCase()) {
      case 'treasury':
        return 'سند صرف / قبض';
      case 'bank':
        return 'تحويل بنكي';
      case 'cheque':
        return 'حركة شيك';
      case 'profit':
        return 'توزيع أرباح';
      case 'ledger':
        return 'قيد تسوية';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      default:
        if (accountName.trim().isNotEmpty && accountName.trim() != '-' && accountName.trim() != '—') {
          return accountName.trim();
        }
        if (type.trim().isNotEmpty && type.trim() != '-' && type.trim() != '—') {
          return type.trim();
        }
        return '—';
    }
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    PdfColor? color,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? _boldFont : _font,
          fontSize: 7.5,
          color: color ?? _darkText,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EXECUTIVE KPI SUMMARY FOOTER (Landscape 3 or 4-Card Strip)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSummary({
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalProfitShare,
    required String currency,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Card 1: Total Withdrawals / Debit (مسدد - مدين)
        _buildSummaryCard(
          title: 'إجمالي السحوبات (مدين)',
          englishTitle: 'Total Withdrawals (Debit)',
          value: '${AppUtils.formatNumber(totalDebit)} $currency',
          subText: 'سندات صرف ومسحوبات نقدية وبنكية',
          accentColor: _redText,
          bgColor: _redBg,
        ),
        pw.SizedBox(width: 8),

        // Card 2: Total Additions / Credit (إيداعات - دائن)
        _buildSummaryCard(
          title: 'إجمالي الإيداعات (دائن)',
          englishTitle: 'Total Additions (Credit)',
          value: '${AppUtils.formatNumber(totalCredit)} $currency',
          subText: 'إيداعات رأس المال والمبالغ الموردة',
          accentColor: _greenText,
          bgColor: _greenBg,
        ),
        pw.SizedBox(width: 8),

        // Card 3 (Optional Profit Share if > 0)
        if (totalProfitShare > 0) ...[
          _buildSummaryCard(
            title: 'حصة الأرباح الموزعة',
            englishTitle: 'Profit Share',
            value: '${AppUtils.formatNumber(totalProfitShare)} $currency',
            subText: 'أرباح مستحقة ومضافة للمساهم',
            accentColor: _blueText,
            bgColor: _blueBg,
          ),
          pw.SizedBox(width: 8),
        ],

        // Card 4: Final Net Balance (صافي الرصيد الختامي)
        _buildSummaryCard(
          title: 'الصافي النهائي المستحق',
          englishTitle: 'Final Net Balance',
          value: '${AppUtils.formatNumber(finalBalance.abs())} $currency',
          subText: finalBalance > 0
              ? 'مستحق للمساهم (دائن / له)'
              : finalBalance < 0
                  ? 'مستحق على المساهم (مدين / عليه)'
                  : 'الحساب متزن تماماً (خالص)',
          accentColor: finalBalance > 0
              ? _greenText
              : finalBalance < 0
                  ? _redText
                  : _navyPrimary,
          bgColor: finalBalance > 0
              ? _greenBg
              : finalBalance < 0
                  ? _redBg
                  : _cardBg,
          isHero: true,
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryCard({
    required String title,
    required String englishTitle,
    required String value,
    required String subText,
    required PdfColor accentColor,
    required PdfColor bgColor,
    bool isHero = false,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _borderColor, width: 0.65),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  title,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                ),
                pw.Text(
                  englishTitle,
                  style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: _boldFont,
                fontSize: isHero ? 12 : 10.5,
                color: accentColor,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: pw.BoxDecoration(
                color: bgColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Text(
                subText,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SIGNATURES SECTION
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSignatureSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _signatureColumn('إعداد الإدارة المالية', 'Financial Management'),
          _signatureColumn('المراجعة والتدقيق المالي', 'Financial Auditor'),
          _signatureColumn('اعتماد وتوقيع المساهم', 'Shareholder Signature'),
        ],
      ),
    );
  }

  static pw.Widget _signatureColumn(String arTitle, String enTitle) {
    return pw.Column(
      children: [
        pw.Text(
          arTitle,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.Text(
          enTitle,
          style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 1, style: pw.BorderStyle.dashed)),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER COMPONENT
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildFooter(
    pw.Context ctx,
    ShareholderModel shareholder,
    String companyName,
    String printDate,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم استخراج هذا التقرير آلياً من نظام إدارة العمليات والحسابات (Fruity Farms ERP) | $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 7, color: _mutedText),
          ),
          pw.Text(
            'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
          ),
        ],
      ),
    );
  }
}
