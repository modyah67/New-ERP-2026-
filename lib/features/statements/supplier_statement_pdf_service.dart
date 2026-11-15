// lib/features/statements/supplier_statement_pdf_service.dart
// Landscape A4 Executive Statement PDF Export for Individual Suppliers (كشف حساب المورد)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/supplier_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../core/ui_utils.dart';
import '../../data/models/statement_row_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class SupplierStatementPdfService {
  // ── Colors: Executive Landscape Palette ──────────────────────────────────
  static const _navyPrimary = PdfColor.fromInt(0xFF0F2942);
  static const _navyLight   = PdfColor.fromInt(0xFF1E3A5F);
  static const _darkText    = PdfColor.fromInt(0xFF1E293B);
  static const _mutedText   = PdfColor.fromInt(0xFF64748B);
  static const _lightBg     = PdfColor.fromInt(0xFFF8FAFC);
  static const _cardBg      = PdfColor.fromInt(0xFFF1F5F9);
  static const _borderColor = PdfColor.fromInt(0xFFCBD5E1);
  static const _white       = PdfColors.white;
  static const _greenText   = PdfColor.fromInt(0xFF15803D);
  static const _greenBg     = PdfColor.fromInt(0xFFDCFCE7);
  static const _redText     = PdfColor.fromInt(0xFFB91C1C);
  static const _redBg       = PdfColor.fromInt(0xFFFEE2E2);

  // ── Fonts ─────────────────────────────────────────────────────────────────
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

  // ── Filename formatting helper ────────────────────────────────────────────
  static String _formattedFileName(String title) {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '$title $minute-$hour-$day-$month-$year';
  }

  // ── Public APIs ───────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes in landscape format.
  static Future<Uint8List> generatePdfBytes({
    required SupplierModel supplier,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
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
      supplier: supplier,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      settings: resolvedSettings,
    );
  }

  /// Opens the system print preview explicitly configured for Landscape orientation.
  static Future<void> generateAndPrint({
    required SupplierModel supplier,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    final bytes = await generatePdfBytes(
      supplier: supplier,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
    );
    final docTitle = _formattedFileName('كشف_حساب_مورد_${supplier.name}');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the landscape PDF directly to user storage.
  static Future<File> saveToFile(
    BuildContext context, {
    required SupplierModel supplier,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    final bytes = await generatePdfBytes(
      supplier: supplier,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('كشف_حساب_مورد_${supplier.name}');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ الملف بنجاح في:\n$path');
    }
    return file;
  }

  // ── Document Builder ──────────────────────────────────────────────────────

  static Future<Uint8List> _build({
    required SupplierModel supplier,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
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
              supplier: supplier,
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
            statementNumber: statementNumber,
            printDate: printDate,
          ),
          pw.SizedBox(height: 10),
          _buildSupplierInfo(
            supplier: supplier,
            fromDate: fromDate,
            toDate: toDate,
            rowCount: rows.length,
          ),
          pw.SizedBox(height: 12),
          _buildTable(
            rows: rows,
            supplier: supplier,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
          ),
          pw.SizedBox(height: 14),
          _buildSummary(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            currency: supplier.currency,
            supplier: supplier,
          ),
          pw.SizedBox(height: 14),
          _buildSignatureSection(),
        ],
        footer: (ctx) => _buildFooter(ctx, supplier, companyName, printDate),
      ),
    );

    return doc.save();
  }

  // ── Header Components ─────────────────────────────────────────────────────

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
                'نظام الفروتي فارمز لإدارة العمليات والحسابات | Fruity Farms ERP',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: const PdfColor(0.85, 0.90, 0.95),
                ),
              ),
            ],
          ),

          // Center (Title Badge)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _navyLight,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
              border: pw.Border.all(color: const PdfColor(0.4, 0.6, 0.8), width: 0.8),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'كشف حساب مورد تفصيلي',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 13,
                    color: _white,
                  ),
                ),
                pw.Text(
                  'SUPPLIER ACCOUNT STATEMENT (DETAILED)',
                  style: pw.TextStyle(
                    font: _font,
                    fontSize: 6.5,
                    color: const PdfColor(0.8, 0.85, 0.95),
                  ),
                ),
              ],
            ),
          ),

          // Left side (Meta info)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (statementNumber > 0)
                pw.Text(
                  'رقم الكشف: #$statementNumber',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 9,
                    color: _white,
                  ),
                ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ الطباعة: $printDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: const PdfColor(0.85, 0.90, 0.95),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSubsequentHeader({
    required SupplierModel supplier,
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
            'كشف حساب المورد: ${supplier.name} (${supplier.supplierCode.isNotEmpty ? supplier.supplierCode : "-"}) | $companyName',
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

  // ── Vendor Meta Information Card (Landscape Grid) ─────────────────────────

  static pw.Widget _buildSupplierInfo({
    required SupplierModel supplier,
    required DateTime? fromDate,
    required DateTime? toDate,
    required int rowCount,
  }) {
    final periodText = (fromDate != null && toDate != null)
        ? 'من ${AppUtils.formatDate(fromDate)} إلى ${AppUtils.formatDate(toDate)}'
        : (fromDate != null)
            ? 'من ${AppUtils.formatDate(fromDate)} وحتى تاريخه'
            : (toDate != null)
                ? 'حتى تاريخ ${AppUtils.formatDate(toDate)}'
                : 'كافة المعاملات المسجلة';

    final phoneClean = (supplier.phone.trim().isNotEmpty && supplier.phone.trim() != '-')
        ? supplier.phone.trim()
        : '—';

    final codeClean = supplier.supplierCode.trim().isNotEmpty
        ? supplier.supplierCode.trim()
        : '—';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _lightBg,
        border: pw.Border.all(color: _borderColor, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: pw.Column(
        children: [
          // Row 1: Primary Vendor Meta
          pw.Row(
            children: [
              _infoTile('اسم المورد', supplier.name, flex: 3, isBold: true),
              _vDiv(),
              _infoTile('كود المورد', codeClean, flex: 2),
              _vDiv(),
              _infoTile('رقم الهاتف', phoneClean, flex: 2),
              _vDiv(),
              _infoTile(
                'عملة الحساب',
                supplier.supportsMultiCurrency && supplier.hasMultiCurrencyInitialBalance
                    ? 'متعدد (${supplier.supportedCurrencies.join(", ")})'
                    : '${supplier.currency} (${supplier.currencySymbol})',
                flex: 2,
                isBold: true,
              ),
              _vDiv(),
              _infoTile('تصنيف المورد', supplier.supplierTypeLabel, flex: 2),
            ],
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Divider(color: _borderColor, thickness: 0.5, height: 0),
          ),
          // Row 2: Statement Parameters
          pw.Row(
            children: [
              _infoTile('فترة كشف الحساب', periodText, flex: 4, isBold: true),
              _vDiv(),
              _infoTile('إجمالي الحركات', '$rowCount حركة مسجلة', flex: 2),
              _vDiv(),
              _infoTile(
                'الرصيد الافتتاحي',
                supplier.hasMultiCurrencyInitialBalance
                    ? '${supplier.formattedInitialBalance}\n(معادل ${AppUtils.formatNumber(supplier.totalInitialBalanceInEgp)} ج.م)'
                    : '${AppUtils.formatNumber(supplier.initialBalance)} ${supplier.currencySymbol} (${supplier.initialBalanceDirection == "CREDIT" ? "له" : "عليه"})',
                flex: 3,
              ),
              _vDiv(),
              _infoTile(
                'الرصيد المالي الحالي',
                supplier.hasMultiCurrencyInitialBalance
                    ? '${supplier.formattedCurrentBalance}\n(معادل ${AppUtils.formatNumber(supplier.outstandingBalance.abs())} ج.م)'
                    : '${AppUtils.formatNumber(supplier.outstandingBalance.abs())} ${supplier.currencySymbol} (${supplier.outstandingBalance > 0 ? "له" : supplier.outstandingBalance < 0 ? "عليه" : "متزن"})',
                flex: 3,
                isBold: true,
                valueColor: supplier.outstandingBalance > 0
                    ? _greenText
                    : supplier.outstandingBalance < 0
                        ? _redText
                        : _darkText,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoTile(
    String label,
    String value, {
    int flex = 1,
    bool isBold = false,
    PdfColor? valueColor,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font: _font,
              fontSize: 7.5,
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
              fontSize: 9,
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
      margin: const pw.EdgeInsets.symmetric(horizontal: 6),
    );
  }

  // ── 9-Column Landscape Data Table ─────────────────────────────────────────

  static pw.Widget _buildTable({
    required List<StatementRow> rows,
    required SupplierModel supplier,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
  }) {
    if (rows.isEmpty) {
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(24),
        decoration: pw.BoxDecoration(
          color: _lightBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _borderColor, width: 0.6),
        ),
        child: pw.Text(
          'لا توجد حركات مسجلة لهذا المورد في الفترة المحددة',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 11, color: _mutedText),
        ),
      );
    }

    // Column widths in Landscape (794pt total width)
    // 0: Ref, 1: Date, 2: Type, 3: Description, 4: Foreign Cur., 5: Debit, 6: Credit, 7: Balance, 8: Note
    const columnWidths = {
      0: pw.FlexColumnWidth(0.10), // Ref / رقم المعاملة
      1: pw.FlexColumnWidth(0.09), // Date / التاريخ
      2: pw.FlexColumnWidth(0.10), // Type / نوع الحركة
      3: pw.FlexColumnWidth(0.23), // Description / البيان (wide breathing room)
      4: pw.FlexColumnWidth(0.13), // Foreign Cur. / المبلغ بالعملة الأجنبية
      5: pw.FlexColumnWidth(0.10), // Debit / مدين (منه) ج.م
      6: pw.FlexColumnWidth(0.10), // Credit / دائن (له) ج.م
      7: pw.FlexColumnWidth(0.10), // Balance / الرصيد ج.م
      8: pw.FlexColumnWidth(0.07), // Note / ملاحظات
    };

    const headers = [
      'رقم المعاملة\nRef No',
      'التاريخ\nDate',
      'نوع الحركة\nType',
      'البيان والشرح\nDescription',
      'العملة الأجنبية\nForeign Cur.',
      'مدين (منه) ج.م\nDebit (EGP)',
      'دائن (له) ج.م\nCredit (EGP)',
      'الرصيد ج.م\nBalance (EGP)',
      'ملاحظات\nNote',
    ];

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      children: [
        // Header Row (Deep Navy)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          repeat: true,
          children: headers.map((h) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              alignment: pw.Alignment.center,
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
          final row = entry.value;
          final isEven = (i % 2 == 0);

          // 1. Ref cleaning
          String refClean = row.transactionNumber.replaceAll(RegExp(r'[\u202A-\u202C\u200E\u200F]'), '').trim();
          if (refClean.isEmpty || refClean == '-' || refClean == '—') {
            refClean = (row.referenceId != null && row.referenceId!.trim().isNotEmpty && row.referenceId != '-')
                ? row.referenceId!.trim()
                : '-';
          }

          // 2. Date cleaning
          final dateClean = _formatDate(row.date);

          // 3. Type mapping
          final typeClean = _formatType(row.type, row.accountName);

          // 4. Description cleaning
          final descClean = row.description.trim().isNotEmpty && row.description.trim() != 'null'
              ? row.description.trim()
              : '-';

          // 5. Foreign Currency cleaning
          final foreignClean = row.isForeignCurrency ? row.foreignDisplayCompact : '-';

          // 6. Debit cleaning
          final isObRow = row.type == 'opening' || row.type == 'initial';
          final isMultiOb = isObRow && supplier.hasMultiCurrencyInitialBalance;

          final debitClean = isMultiOb && row.debit > 0
              ? '${supplier.formattedInitialBalance}\n(≈ ${AppUtils.formatNumber(row.debit)} ج.م)'
              : (row.debit > 0
                  ? '${AppUtils.formatNumber(row.debit)} ج.م'
                  : '-');

          // 7. Credit cleaning
          final creditClean = isMultiOb && row.credit > 0
              ? '${supplier.formattedInitialBalance}\n(≈ ${AppUtils.formatNumber(row.credit)} ج.م)'
              : (row.credit > 0
                  ? '${AppUtils.formatNumber(row.credit)} ج.م'
                  : '-');

          // 8. Balance formatting
          final balSign = row.balance > 0 ? ' (له)' : row.balance < 0 ? ' (عليه)' : '';
          final balanceClean = isMultiOb
              ? '${supplier.formattedInitialBalance}\n(≈ ${AppUtils.formatNumber(row.balance.abs())} ج.م)$balSign'
              : (row.balance != 0
                  ? '${AppUtils.formatNumber(row.balance.abs())} ج.م$balSign'
                  : '0.00 (متزن)');

          // 9. Note cleaning
          String noteClean = row.accountName.trim();
          if (noteClean.isEmpty || noteClean == '-' || noteClean == '—' || noteClean == 'null') {
            noteClean = (row.referenceType != null && row.referenceType!.trim().isNotEmpty && row.referenceType != '-')
                ? row.referenceType!.trim()
                : '-';
          }

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? _white : _lightBg,
            ),
            children: [
              _cell(refClean, isBold: true),
              _cell(dateClean),
              _cell(typeClean),
              _cell(descClean, align: pw.TextAlign.right),
              _cell(
                foreignClean,
                color: row.isForeignCurrency ? _navyLight : _mutedText,
                isBold: row.isForeignCurrency,
              ),
              _cell(
                debitClean,
                color: row.debit > 0 ? _redText : _mutedText,
                isBold: row.debit > 0,
              ),
              _cell(
                creditClean,
                color: row.credit > 0 ? _greenText : _mutedText,
                isBold: row.credit > 0,
              ),
              _cell(
                balanceClean,
                isBold: true,
                color: row.balance > 0 ? _greenText : row.balance < 0 ? _redText : _darkText,
              ),
              _cell(noteClean, align: pw.TextAlign.right),
            ],
          );
        }),

        // Embedded Table Totals Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cardBg),
          children: [
            _cell('المجموع', isBold: true, color: _navyPrimary),
            _cell('-', isBold: true),
            _cell('-', isBold: true),
            _cell('إجمالي حركات الفترة (${rows.length})', isBold: true, align: pw.TextAlign.right, color: _navyPrimary),
            _cell('-', isBold: true),
            _cell(
              totalDebit > 0 ? '${AppUtils.formatNumber(totalDebit)} ج.م' : '0.00 ج.م',
              isBold: true,
              color: _redText,
            ),
            _cell(
              totalCredit > 0 ? '${AppUtils.formatNumber(totalCredit)} ج.م' : '0.00 ج.م',
              isBold: true,
              color: _greenText,
            ),
            _cell(
              '${AppUtils.formatNumber(finalBalance.abs())} ج.م ${finalBalance > 0 ? "(له)" : finalBalance < 0 ? "(عليه)" : ""}',
              isBold: true,
              color: finalBalance > 0 ? _greenText : finalBalance < 0 ? _redText : _navyPrimary,
            ),
            _cell('-', isBold: true),
          ],
        ),
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

  // ── Executive KPI Summary Footer (Landscape 3-Card Strip) ─────────────────

  static pw.Widget _buildSummary({
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required String currency,
    SupplierModel? supplier,
  }) {
    final safeCur = currency == 'MULTI' ? 'ج.م' : SupplierModel.getCurrencySymbol(currency);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Card 1: Total Debit (منه)
        _buildSummaryCard(
          title: 'إجمالي مدين (منه)',
          englishTitle: 'Total Debit',
          value: '${AppUtils.formatNumber(totalDebit)} $safeCur',
          subText: 'سندات صرف ومسحوبات',
          accentColor: _redText,
          bgColor: _redBg,
        ),
        pw.SizedBox(width: 8),

        // Card 2: Total Credit (له)
        _buildSummaryCard(
          title: 'إجمالي دائن (له)',
          englishTitle: 'Total Credit',
          value: '${AppUtils.formatNumber(totalCredit)} $safeCur',
          subText: 'فواتير وتوريدات محصول ومواد',
          accentColor: _greenText,
          bgColor: _greenBg,
        ),
        pw.SizedBox(width: 8),

        // Card 3: Final Balance
        _buildSummaryCard(
          title: 'صافي الرصيد الختامي',
          englishTitle: 'Final Balance',
          value: '${AppUtils.formatNumber(finalBalance.abs())} $safeCur',
          subText: supplier?.hasMultiCurrencyInitialBalance == true
              ? 'الرصيد بالعملات: ${supplier!.formattedCurrentBalance}'
              : (finalBalance > 0
                  ? 'مستحق للمورد (دائن / له)'
                  : finalBalance < 0
                      ? 'مستحق على المورد (مدين / عليه)'
                      : 'الحساب متزن تماماً (خالص)'),
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
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
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
                  style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
                ),
                pw.Text(
                  englishTitle,
                  style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
                ),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: _boldFont,
                fontSize: isHero ? 11.5 : 10,
                color: accentColor,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  fontSize: 6.5,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Signature Section ─────────────────────────────────────────────────────

  static pw.Widget _buildSignatureSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _signatureBox('إعداد / المحاسب المسؤول', 'Accountant'),
          _signatureBox('مراجعة / الإدارة المالية', 'Financial Auditor'),
          _signatureBox('توقيع واعتماد المورد', 'Supplier Acknowledged'),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(String titleAr, String titleEn) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          titleAr,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _darkText),
        ),
        pw.Text(
          titleEn,
          style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
        ),
        pw.SizedBox(height: 18),
        pw.Container(width: 140, height: 0.6, color: _borderColor),
        pw.SizedBox(height: 2),
        pw.Text(
          'التوقيع / الختم الرسمي',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
        ),
      ],
    );
  }

  // ── Page Footer ───────────────────────────────────────────────────────────

  static pw.Widget _buildFooter(
    pw.Context ctx,
    SupplierModel supplier,
    String companyName,
    String printDate,
  ) {
    return pw.Column(
      children: [
        pw.Divider(color: _borderColor, thickness: 0.5),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
            ),
            pw.Text(
              'كشف حساب تفصيلي - $companyName | تاريخ الطباعة: $printDate',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
            ),
            pw.Text(
              'المورد: ${supplier.name}',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helper Formatter Functions ────────────────────────────────────────────

  static String _formatDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty || trimmed == '-' || trimmed == '—' || trimmed == 'null') {
      return '-';
    }
    try {
      if (trimmed.contains('T')) {
        final dt = DateTime.parse(trimmed);
        return AppUtils.formatDate(dt);
      }
      if (trimmed.contains('-')) {
        final parts = trimmed.split('-');
        if (parts.length >= 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2].split(' ')[0]);
          return AppUtils.formatDate(DateTime(year, month, day));
        }
      }
      return trimmed;
    } catch (_) {
      return trimmed;
    }
  }

  static String _formatType(String type, String accountName) {
    final t = type.trim().toLowerCase();
    switch (t) {
      case 'purchase':
        return 'فاتورة شراء';
      case 'lot_receipt':
        return 'شراء محصول';
      case 'payment':
      case 'treasury_payment':
        return 'سند صرف';
      case 'treasury_receipt':
        return 'سند قبض';
      case 'opening_balance':
      case 'initial_balance':
        return 'رصيد افتتاحي';
      case 'lot_return':
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'debit_note':
        return 'إشعار خصم';
      case 'credit_note':
        return 'إشعار إضافة';
      case 'journal_entry':
        return 'قيد تسوية';
      default:
        if (type.trim().isNotEmpty && type.trim() != '-' && type.trim() != '—') {
          return type.trim();
        }
        if (accountName.trim().isNotEmpty && accountName.trim() != '-' && accountName.trim() != '—') {
          return accountName.trim();
        }
        return '-';
    }
  }
}
