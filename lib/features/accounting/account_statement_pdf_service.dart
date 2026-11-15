// lib/features/accounting/account_statement_pdf_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Fruity Farms ERP — Professional Landscape A4 Account Statement PDF Service
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../core/utils/file_helper.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/models/account_ledger_result.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';

/// Professional PDF service for generating and printing Account Statements /
/// General Ledger vouchers in Landscape A4 orientation.
class AccountStatementPdfService {
  AccountStatementPdfService._();

  // ── Brand & Color Palette ─────────────────────────────────────────────────
  static const PdfColor _navyPrimary = PdfColor.fromInt(0xFF1A365D); // #1A365D Deep Navy
  static const PdfColor _navyLight   = PdfColor.fromInt(0xFF2B4C7E);
  static const PdfColor _cyanAccent  = PdfColor.fromInt(0xFF0284C7); // #0284C7 Sky/Cyan
  static const PdfColor _greenAccent = PdfColor.fromInt(0xFF059669); // #059669 Emerald
  static const PdfColor _greenBg     = PdfColor.fromInt(0xFFECFDF5);
  static const PdfColor _amberAccent = PdfColor.fromInt(0xFFD97706); // #D97706 Amber
  static const PdfColor _amberBg     = PdfColor.fromInt(0xFFFFFBEB);
  static const PdfColor _textDark    = PdfColor.fromInt(0xFF0F172A); // #0F172A Slate 900
  static const PdfColor _textMuted   = PdfColor.fromInt(0xFF64748B); // #64748B Slate 500
  static const PdfColor _lightBg     = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const PdfColor _zebraBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const PdfColor _border      = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const PdfColor _white       = PdfColors.white;

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');

  // ── Font & Asset Loading ──────────────────────────────────────────────────
  static pw.Font? _font;
  static pw.Font? _boldFont;
  static pw.Font? _fallbackFont;

  static Future<({pw.Font regular, pw.Font bold, pw.Font fallback})> _loadFonts() async {
    if (_font != null && _boldFont != null && _fallbackFont != null) {
      return (regular: _font!, bold: _boldFont!, fallback: _fallbackFont!);
    }
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final fallback = await PdfGoogleFonts.notoSansRegular();
      _font = pw.Font.ttf(regData);
      _boldFont = pw.Font.ttf(boldData);
      _fallbackFont = fallback;
      return (regular: _font!, bold: _boldFont!, fallback: _fallbackFont!);
    } catch (_) {
      try {
        final reg = await PdfGoogleFonts.cairoRegular();
        final bold = await PdfGoogleFonts.cairoBold();
        final fallback = await PdfGoogleFonts.notoSansRegular();
        _font = reg;
        _boldFont = bold;
        _fallbackFont = fallback;
        return (regular: _font!, bold: _boldFont!, fallback: _fallbackFont!);
      } catch (_) {
        _font = pw.Font.helvetica();
        _boldFont = pw.Font.helveticaBold();
        _fallbackFont = pw.Font.helvetica();
        return (regular: _font!, bold: _boldFont!, fallback: _fallbackFont!);
      }
    }
  }

  static Future<pw.MemoryImage?> _loadLogoImage() async {
    return null;
  }

  static Future<String> _resolveCompanyName(String? companyName) async {
    if (companyName != null && companyName.trim().isNotEmpty) {
      return companyName.trim();
    }
    try {
      final settings = await SettingsDao().getAllSettings();
      final name = settings['company_name'] ?? settings['companyName'];
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    } catch (_) {}
    return 'مزارع فروتي فارمز لتصدير الحاصلات الزراعية';
  }

  static String _formattedFileName(String title, String accountCode) {
    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return '${title}_${accountCode}_${d}_$t';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIMARY PUBLIC API: PRINT & EXPORT FOR CHART OF ACCOUNTS & LEDGER
  // ──────────────────────────────────────────────────────────────────────────

  /// Generate, layout, and print an account statement PDF in Landscape A4.
  static Future<void> printLedgerStatement({
    required AccountModel account,
    required List<AccountLedgerEntry> entries,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String currency = 'EGP',
    bool isBranch = false,
    String? companyName,
  }) async {
    final bytes = await generateLedgerPdf(
      account: account,
      entries: entries,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: closingBalance,
      fromDate: fromDate,
      toDate: toDate,
      currency: currency,
      isBranch: isBranch,
      companyName: companyName,
    );

    final fileName = _formattedFileName('كشف_حساب', account.code);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Save the account statement PDF directly to file in export directory.
  static Future<File> saveLedgerStatementToFile(
    BuildContext context, {
    required AccountModel account,
    required List<AccountLedgerEntry> entries,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String currency = 'EGP',
    bool isBranch = false,
    String? companyName,
  }) async {
    final bytes = await generateLedgerPdf(
      account: account,
      entries: entries,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: closingBalance,
      fromDate: fromDate,
      toDate: toDate,
      currency: currency,
      isBranch: isBranch,
      companyName: companyName,
    );

    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('كشف_حساب', account.code)}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف الحساب بنجاح في:\n$path');
    }
    return file;
  }

  /// Compile and generate PDF document bytes formatted in Landscape A4.
  static Future<Uint8List> generateLedgerPdf({
    required AccountModel account,
    required List<AccountLedgerEntry> entries,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    DateTime? fromDate,
    DateTime? toDate,
    String currency = 'EGP',
    bool isBranch = false,
    String? companyName,
  }) async {
    final fonts = await _loadFonts();
    final logoImage = await _loadLogoImage();
    final effectiveCompanyName = await _resolveCompanyName(companyName);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(
            base: fonts.regular,
            bold: fonts.bold,
            fontFallback: [fonts.fallback],
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        header: (context) => _buildCorporateHeader(
          companyName: effectiveCompanyName,
          logoImage: logoImage,
          account: account,
          isBranch: isBranch,
          fromDate: fromDate,
          toDate: toDate,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          fontBold: fonts.bold,
          fontRegular: fonts.regular,
        ),
        footer: (context) => _buildCorporateFooter(
          companyName: effectiveCompanyName,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          fontRegular: fonts.regular,
        ),
        build: (context) => [
          // 1. Account Metadata Banner
          _buildAccountMetaCard(
            account: account,
            isBranch: isBranch,
            currency: currency,
            entriesCount: entries.length,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 8),

          // 2. 4-Pillar Financial KPI Summary Cards
          _buildKpiSummaryCards(
            openingBalance: openingBalance,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            closingBalance: closingBalance,
            currency: currency,
            isCreditNormal: account.isCreditNormal,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 3. Itemized Ledger Table
          _buildItemizedLedgerTable(
            entries: entries,
            openingBalance: openingBalance,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            closingBalance: closingBalance,
            currency: currency,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 12),

          // 4. Financial Audit & Control Triple Signature Block
          _buildAuditSignaturesBlock(
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER & BANNER WIDGETS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCorporateHeader({
    required String companyName,
    required pw.MemoryImage? logoImage,
    required AccountModel account,
    required bool isBranch,
    required DateTime? fromDate,
    required DateTime? toDate,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final now = DateTime.now();
    final printDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final periodLabel = (fromDate != null && toDate != null)
        ? '${AppUtils.formatDate(fromDate)} — ${AppUtils.formatDate(toDate)}'
        : (fromDate != null)
            ? 'من ${AppUtils.formatDate(fromDate)} وحتى تاريخه'
            : (toDate != null)
                ? 'حتى ${AppUtils.formatDate(toDate)}'
                : 'كافة الحركات التاريخية المسجلة';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navyPrimary, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right: Corporate Company Identity
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: _navyPrimary),
                  ),
                  pw.Text(
                    'FRUITY FARMS FOR AGRICULTURAL CROPS EXPORT',
                    style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _cyanAccent),
                  ),
                  pw.Text(
                    'الإدارة المالية والحسابات العامة — دليل الحسابات',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _textMuted),
                  ),
                ],
              ),
            ],
          ),

          // Center: Document Title & Scope Badge
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'كشف حساب تفصيلي / دفتر الأستاذ للحساب',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: _white),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                isBranch
                    ? 'شجرة الحسابات — كشف حساب رئيسي وتجميعي للفروع (${account.entityHeaderTitle})'
                    : 'شجرة الحسابات — كشف تحليلي وتفصيلي (${account.entityHeaderTitle})',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 7, color: _cyanAccent),
              ),
            ],
          ),

          // Left: Metadata & Page Counts
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: const pw.BoxDecoration(
                  color: _lightBg,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'الفترة: $periodLabel',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ الطباعة: $printDateStr',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _textMuted),
              ),
              pw.Text(
                'صفحة $pageNumber من $totalPages',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAccountMetaCard({
    required AccountModel account,
    required bool isBranch,
    required String currency,
    required int entriesCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final typeLabelAr = _getAccountTypeArabic(account.type);
    final natureLabel = account.isCreditNormal ? 'دائن بطبيعته (Credit)' : 'مدين بطبيعته (Debit)';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Account identity
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  account.code,
                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: _white),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '${account.entityLabel}: ${account.name}',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: _navyPrimary),
              ),
              if (account.accountName != null && account.accountName!.isNotEmpty && account.accountName != account.name) ...[
                pw.SizedBox(width: 6),
                pw.Text(
                  '(${account.accountName})',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
                ),
              ],
            ],
          ),

          // Badges: Level, Account Type, Nature, Currency, Entries
          pw.Row(
            children: [
              _badgeItem('المستوى:', account.levelLabel, _navyPrimary, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('النوع:', typeLabelAr, _navyLight, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('الطبيعة:', natureLabel, _cyanAccent, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('العملة:', currency, _greenAccent, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('عدد القيود:', '$entriesCount حركة', _textDark, fontBold, fontRegular),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _badgeItem(
    String label,
    String val,
    PdfColor color,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: _border, width: 0.5),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _textMuted),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            val,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontBold, fontSize: 7, color: color),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // KPI SUMMARY CARDS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildKpiSummaryCards({
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    required String currency,
    required bool isCreditNormal,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final openingNature = openingBalance > 0
        ? (isCreditNormal ? '(دائن)' : '(مدين)')
        : (openingBalance < 0 ? (isCreditNormal ? '(مدين)' : '(دائن)') : '(متزن)');

    final closingNature = closingBalance > 0
        ? (isCreditNormal ? '(دائن)' : '(مدين)')
        : (closingBalance < 0 ? (isCreditNormal ? '(مدين)' : '(دائن)') : '(متزن)');

    return pw.Row(
      children: [
        // 1. Opening Balance
        pw.Expanded(
          child: _kpiCard(
            title: 'الرصيد الافتتاحي (السابق)',
            amountStr: '${_currFmt.format(openingBalance.abs())} $currency',
            subtitle: 'طبيعة الرصيد: $openingNature',
            accentColor: _cyanAccent,
            bgColor: _lightBg,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 2. Total Debit
        pw.Expanded(
          child: _kpiCard(
            title: 'إجمالي حركات المدين (+)',
            amountStr: '${_currFmt.format(totalDebit)} $currency',
            subtitle: 'إجمالي المبالغ المدينة للفترة',
            accentColor: _greenAccent,
            bgColor: _greenBg,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 3. Total Credit
        pw.Expanded(
          child: _kpiCard(
            title: 'إجمالي حركات الدائن (-)',
            amountStr: '${_currFmt.format(totalCredit)} $currency',
            subtitle: 'إجمالي المبالغ الدائنة للفترة',
            accentColor: _amberAccent,
            bgColor: _amberBg,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 4. Closing Balance
        pw.Expanded(
          child: _kpiCard(
            title: 'الرصيد الختامي الحالي',
            amountStr: '${_currFmt.format(closingBalance.abs())} $currency',
            subtitle: 'الرصيد النهائي: $closingNature',
            accentColor: _navyPrimary,
            bgColor: _lightBg,
            isProminent: true,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
      ],
    );
  }

  static pw.Widget _kpiCard({
    required String title,
    required String amountStr,
    required String subtitle,
    required PdfColor accentColor,
    required PdfColor bgColor,
    bool isProminent = false,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(
          color: isProminent ? _navyPrimary : _border,
          width: isProminent ? 1.2 : 0.6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 7, color: accentColor),
              ),
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: accentColor,
                  shape: pw.BoxShape.circle,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            amountStr,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: isProminent ? 11 : 9.5,
              color: isProminent ? _navyPrimary : _textDark,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            subtitle,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ITEMIZED LEDGER TABLE
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildItemizedLedgerTable({
    required List<AccountLedgerEntry> entries,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    required String currency,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final headers = [
      'الرصيد بعد الحركة',
      'دائن',
      'مدين',
      'مركز التكلفة',
      'البيان / الشرح التفصيلي',
      'نوع العملية',
      'رقم القيد',
      'التاريخ',
      'م',
    ];

    final tableData = <List<dynamic>>[];

    // Opening Balance Row if non-zero
    if (openingBalance.abs() > 0.001) {
      tableData.add([
        '${_currFmt.format(openingBalance)} $currency',
        '—',
        '—',
        '—',
        'الرصيد الافتتاحي السابق لبداية الفترة المحددة',
        'رصيد افتتاحي',
        '—',
        '—',
        '•',
      ]);
    }

    // Itemized entries rows
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final dateStr = AppUtils.formatDate(e.date);
      final entryNum = (e.entryNumber != null && e.entryNumber!.isNotEmpty) ? e.entryNumber! : '—';
      final debitStr = e.debit > 0 ? _currFmt.format(e.debit) : '—';
      final creditStr = e.credit > 0 ? _currFmt.format(e.credit) : '—';
      final balanceStr = _currFmt.format(e.runningBalance);

      // Compose clean description
      String fullDesc = e.description.isNotEmpty ? e.description : 'حركة دفتر أستاذ';
      if (e.accountName.isNotEmpty) {
        // In branch views, append account name
        fullDesc = '${e.accountName} | $fullDesc';
      }

      tableData.add([
        balanceStr,
        creditStr,
        debitStr,
        (e.costCenterName != null && e.costCenterName!.isNotEmpty) ? e.costCenterName! : '—',
        fullDesc,
        e.referenceTypeLabel,
        entryNum,
        dateStr,
        '${i + 1}',
      ]);
    }

    return pw.Column(
      children: [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: tableData,
          border: pw.TableBorder.all(color: _border, width: 0.5),
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 7.8, color: _white),
          headerDecoration: const pw.BoxDecoration(color: _navyPrimary),
          headerHeight: 22,
          rowDecoration: const pw.BoxDecoration(color: _white),
          oddRowDecoration: const pw.BoxDecoration(color: _zebraBg),
          cellHeight: 18,
          cellStyle: pw.TextStyle(font: fontRegular, fontSize: 7.2, color: _textDark),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {
            0: pw.Alignment.centerLeft,  // الرصيد بعد الحركة
            1: pw.Alignment.centerLeft,  // دائن
            2: pw.Alignment.centerLeft,  // مدين
            3: pw.Alignment.center,      // مركز التكلفة
            4: pw.Alignment.centerRight, // البيان / الشرح
            5: pw.Alignment.center,      // نوع العملية
            6: pw.Alignment.center,      // رقم القيد
            7: pw.Alignment.center,      // التاريخ
            8: pw.Alignment.center,      // م
          },
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3), // الرصيد بعد الحركة
            1: pw.FlexColumnWidth(1.0), // دائن
            2: pw.FlexColumnWidth(1.0), // مدين
            3: pw.FlexColumnWidth(1.4), // مركز التكلفة
            4: pw.FlexColumnWidth(3.0), // البيان والشرح
            5: pw.FlexColumnWidth(1.0), // نوع العملية
            6: pw.FlexColumnWidth(0.8), // رقم القيد
            7: pw.FlexColumnWidth(0.9), // التاريخ
            8: pw.FlexColumnWidth(0.35), // م
          },
        ),

        // Total Summary Row at bottom of table
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _lightBg,
            border: pw.Border.all(color: _border, width: 0.7),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Row(
            children: [
              // Closing Balance
              pw.Expanded(
                flex: 12,
                child: pw.Text(
                  '${_currFmt.format(closingBalance)} $currency',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.8, color: _navyPrimary),
                ),
              ),
              // Total Credit
              pw.Expanded(
                flex: 10,
                child: pw.Text(
                  '${_currFmt.format(totalCredit)} $currency',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.8, color: _amberAccent),
                ),
              ),
              // Total Debit
              pw.Expanded(
                flex: 10,
                child: pw.Text(
                  '${_currFmt.format(totalDebit)} $currency',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.8, color: _greenAccent),
                ),
              ),
              // Label
              pw.Expanded(
                flex: 70,
                child: pw.Text(
                  'إجمالي حركات الفترة والرصيد النهائي للحساب:',
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: _navyPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FINANCIAL AUDIT & CONTROL TRIPLE SIGNATURE BLOCK
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildAuditSignaturesBlock({
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSignatureSlot(
            'رئيس قسم الحسابات العامة',
            'Head of General Accounts',
            fontBold,
            fontRegular,
          ),
          _buildSignatureSlot(
            'مدير الرقابة والمراجعة المالية',
            'Financial Audit & Control Manager',
            fontBold,
            fontRegular,
          ),
          _buildSignatureSlot(
            'المدير العام والاعتماد',
            'General Manager & Authorization',
            fontBold,
            fontRegular,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureSlot(
    String titleAr,
    String titleEn,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          titleAr,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fontBold, fontSize: 8, color: _navyPrimary),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          titleEn,
          style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _textMuted),
        ),
        pw.SizedBox(height: 18), // Space for manual stamp / signature
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.8)),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'التوقيع والاعتماد الرسمي',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _textMuted),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER WIDGET
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCorporateFooter({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة $pageNumber من $totalPages',
            style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _textMuted),
          ),
          pw.Text(
            'كشف حساب تفصيلي معتمد | $companyName | الحسابات العامة',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _navyPrimary),
          ),
          pw.Text(
            'نظام Fruity Farms ERP المالي والمحاسبي المتكامل',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BACKWARDS COMPATIBILITY FOR EXISTING CALLERS (accounts_page.dart)
  // ──────────────────────────────────────────────────────────────────────────

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
    // Adapt legacy rows to AccountLedgerEntry
    final entries = _convertLegacyRows(rows);
    await printLedgerStatement(
      account: account,
      entries: entries,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      currency: account.currency,
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
    final entries = _convertLegacyRows(rows);
    return saveLedgerStatementToFile(
      context,
      account: account,
      entries: entries,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      currency: account.currency,
    );
  }

  static List<AccountLedgerEntry> _convertLegacyRows(List<Map<String, dynamic>> rows) {
    return rows.map((r) {
      final tx = r['tx'] as TransactionModel?;
      final isDebit = r['isDebit'] as bool? ?? true;
      final balAfter = (r['balanceAfter'] as num?)?.toDouble() ?? 0.0;
      final amount = tx?.amount ?? 0.0;

      return AccountLedgerEntry(
        id: tx?.id ?? '',
        date: DateTime.tryParse(tx?.transactionDate ?? '') ?? DateTime.now(),
        entryNumber: tx?.entryNumber?.toString(),
        referenceType: tx?.description,
        description: tx?.description ?? '',
        debit: isDebit ? amount : 0.0,
        credit: !isDebit ? amount : 0.0,
        runningBalance: balAfter,
        currency: 'EGP',
        accountCode: '',
        accountName: '',
        createdAt: '',
      );
    }).toList();
  }

  static String _getAccountTypeArabic(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return 'أصول (Assets)';
      case 'liability':
        return 'التزامات / خصوم (Liabilities)';
      case 'equity':
        return 'حقوق ملكية (Equity)';
      case 'revenue':
        return 'إيرادات ومبيعات (Revenues)';
      case 'expense':
        return 'مصروفات وتكاليف (Expenses)';
      case 'system':
        return 'حساب نظامي (System)';
      default:
        return type;
    }
  }
}
