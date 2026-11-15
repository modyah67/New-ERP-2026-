// lib/features/statements/supplier_consolidated_statement_pdf_service.dart
// Professional Landscape A4 Multi-Currency Consolidated Statement for Suppliers

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
import '../../data/models/supplier_model.dart';
import '../../data/dao/settings_dao.dart';
import '../suppliers/supplier_state.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class SupplierConsolidatedStatementPdfService {
  SupplierConsolidatedStatementPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Deep Navy Professional Accounting Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static final _navyPrimary  = PdfColor.fromHex('#1A365D'); // Deep Navy
  static final _accentTeal   = PdfColor.fromHex('#0D9488'); // Teal 600
  static final _cardBg       = PdfColor.fromHex('#F8FAFC'); // Slate 50
  static final _zebraBg      = PdfColor.fromHex('#F1F5F9'); // Slate 100
  static final _totalRowBg   = PdfColor.fromHex('#E2E8F0'); // Slate 200
  static final _textDark     = PdfColor.fromHex('#0F172A'); // Slate 900
  static final _textMuted    = PdfColor.fromHex('#64748B'); // Slate 500
  static final _borderColor  = PdfColor.fromHex('#CBD5E1'); // Slate 300
  static final _borderLight  = PdfColor.fromHex('#E2E8F0'); // Slate 200
  static final _greenText    = PdfColor.fromHex('#15803D'); // Green 700
  static final _greenBg      = PdfColor.fromHex('#DCFCE7'); // Green 100
  static final _greenBorder  = PdfColor.fromHex('#86EFAC'); // Green 300
  static final _redText      = PdfColor.fromHex('#B91C1C'); // Red 700
  static final _redBg        = PdfColor.fromHex('#FEE2E2'); // Red 100
  static final _amberText    = PdfColor.fromHex('#B45309'); // Amber 700
  static final _amberBg      = PdfColor.fromHex('#FEF3C7'); // Amber 100
  static final _amberBorder  = PdfColor.fromHex('#FDE68A'); // Amber 300
  static final _purpleText   = PdfColor.fromHex('#7E22CE'); // Purple 700
  static final _purpleBg     = PdfColor.fromHex('#F3E8FF'); // Purple 100
  static final _purpleBorder = PdfColor.fromHex('#D8B4FE'); // Purple 300

  // ──────────────────────────────────────────────────────────────────────────
  // FONT LOADER WITH CAIRO & FALLBACK SUPPORT
  // ──────────────────────────────────────────────────────────────────────────
  static Future<({pw.Font regular, pw.Font bold, pw.Font fallback})> _loadFonts() async {
    pw.Font regular;
    pw.Font bold;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      regular = pw.Font.ttf(r);
      bold = pw.Font.ttf(b);
    } catch (_) {
      try {
        final regularFile = File('assets/fonts/Cairo-Regular.ttf');
        final boldFile = File('assets/fonts/Cairo-Bold.ttf');
        if (regularFile.existsSync() && boldFile.existsSync()) {
          regular = pw.Font.ttf(regularFile.readAsBytesSync().buffer.asByteData());
          bold = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } else {
          regular = await PdfGoogleFonts.cairoRegular();
          bold = await PdfGoogleFonts.cairoBold();
        }
      } catch (_) {
        regular = await PdfGoogleFonts.cairoRegular();
        bold = await PdfGoogleFonts.cairoBold();
      }
    }

    pw.Font fallback;
    try {
      fallback = await PdfGoogleFonts.notoSansRegular();
    } catch (_) {
      fallback = pw.Font.courier();
    }

    return (regular: regular, bold: bold, fallback: fallback);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FILENAME HELPER
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

  /// Generates the PDF document as raw bytes in Landscape format.
  static Future<Uint8List> generatePdf({
    required List<SupplierModel> suppliers,
    Map<String, CurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? cropCount,
    int? packagingCount,
    int? sharedCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final fonts = await _loadFonts();
    Map<String, String> settings = const {};
    try {
      settings = await SettingsDao().getAllSettings();
    } catch (_) {}
    final resolvedCompanyName = companyName ?? settings['company_name'] ?? AppConstants.companyName;

    // Default rates
    final rates = exchangeRates ?? const {
      'EGP': 1.0,
      'USD': 50.0,
      'EUR': 55.0,
      'GBP': 65.0,
    };

    // Calculate/derive metrics if not supplied
    int crop = cropCount ?? 0;
    int pack = packagingCount ?? 0;
    int shared = sharedCount ?? 0;

    if (cropCount == null || packagingCount == null || sharedCount == null) {
      crop = 0; pack = 0; shared = 0;
      for (final s in suppliers) {
        if (s.supplierType == 'crop') {
          crop++;
        } else if (s.supplierType == 'packaging') {
          pack++;
        } else {
          shared++;
        }
      }
    }

    // Per-currency balances
    Map<String, CurrencyBalance> curBalances = balanceByCurrency ?? {};
    if (curBalances.isEmpty) {
      final Map<String, _CurrencyStats> stats = {};
      for (final s in suppliers) {
        final ccy = s.currency.isEmpty ? 'EGP' : s.currency;
        final entry = stats.putIfAbsent(ccy, () => _CurrencyStats(ccy));
        entry.count++;
        entry.current += s.outstandingBalance;
        entry.initial += s.initialBalance;
      }
      final Map<String, CurrencyBalance> computed = {};
      for (final kv in stats.entries) {
        final ccy = kv.key;
        final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);
        computed[ccy] = CurrencyBalance(
          currency: ccy,
          symbol: _getCurrencySymbol(ccy),
          nativeCurrentBalance: kv.value.current,
          nativeInitialBalance: kv.value.initial,
          egpCurrentBalance: kv.value.current * rate,
          egpInitialBalance: kv.value.initial * rate,
          supplierCount: kv.value.count,
        );
      }
      curBalances = computed;
    }

    // Calculate totals in EGP if not passed
    double totalCurrentEgp = totalCurrentBalanceEgp ?? 0.0;
    double totalInitialEgp = totalInitialBalanceEgp ?? 0.0;
    if (totalCurrentBalanceEgp == null || totalInitialBalanceEgp == null) {
      totalCurrentEgp = 0.0;
      totalInitialEgp = 0.0;
      for (final cb in curBalances.values) {
        totalCurrentEgp += cb.egpCurrentBalance;
        totalInitialEgp += cb.egpInitialBalance;
      }
    }

    final printDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final doc = pw.Document(
      pageMode: PdfPageMode.none,
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        fontFallback: [fonts.regular, fonts.bold, fonts.fallback],
      ),
    );

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4.landscape,
      orientation: pw.PageOrientation.landscape,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        fontFallback: [fonts.regular, fonts.bold, fonts.fallback],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) {
          if (context.pageNumber > 1) {
            return _buildSubsequentPageHeader(
              companyName: resolvedCompanyName,
              printDate: printDate,
              fontBold: fonts.bold,
              fontRegular: fonts.regular,
            );
          }
          return pw.SizedBox.shrink();
        },
        footer: (context) => _buildPageFooter(
          context: context,
          companyName: resolvedCompanyName,
          printDate: printDate,
          fontBold: fonts.bold,
          fontRegular: fonts.regular,
        ),
        build: (context) => [
          // 1. Formal Company Header & Title
          _buildFirstPageHeader(
            companyName: resolvedCompanyName,
            printDate: printDate,
            totalSuppliers: suppliers.length,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 2. Multi-Currency KPI Summary Cards (3 cards side-by-side)
          _buildKpiSummaryHeader(
            totalSuppliers: suppliers.length,
            cropCount: crop,
            packagingCount: pack,
            sharedCount: shared,
            totalCurrentBalanceEgp: totalCurrentEgp,
            totalInitialBalanceEgp: totalInitialEgp,
            curBalances: curBalances,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 12),

          // 3. Main Data Table
          _buildSuppliersTable(
            suppliers: suppliers,
            totalCurrentBalanceEgp: totalCurrentEgp,
            totalInitialBalanceEgp: totalInitialEgp,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
            fontFallback: fonts.fallback,
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Direct print method using Printing package.
  static Future<void> generateAndPrint({
    required List<SupplierModel> suppliers,
    Map<String, CurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? cropCount,
    int? packagingCount,
    int? sharedCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      suppliers: suppliers,
      balanceByCurrency: balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp,
      cropCount: cropCount,
      packagingCount: packagingCount,
      sharedCount: sharedCount,
      exchangeRates: exchangeRates,
      companyName: companyName,
    );
    final docTitle = _formattedFileName('كشف حساب مجمع - الموردون');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the PDF to export directory and shows user snackbar.
  static Future<File> saveToFile(
    BuildContext context, {
    required List<SupplierModel> suppliers,
    Map<String, CurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? cropCount,
    int? packagingCount,
    int? sharedCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      suppliers: suppliers,
      balanceByCurrency: balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp,
      cropCount: cropCount,
      packagingCount: packagingCount,
      sharedCount: sharedCount,
      exchangeRates: exchangeRates,
      companyName: companyName,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('كشف_حساب_مجمع_الموردون')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف الحساب المجمع بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER ON PAGE 1
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildFirstPageHeader({
    required String companyName,
    required String printDate,
    required int totalSuppliers,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Company Branding
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  companyName,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 15,
                    color: _navyPrimary,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'نظام إدارة الموارد والمحاسبة المالية (Fruity Farms ERP)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 8.5,
                    color: _textMuted,
                  ),
                ),
              ],
            ),

            // Report Title Badge
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: pw.BoxDecoration(
                color: _navyPrimary,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                boxShadow: [
                  pw.BoxShadow(
                    color: PdfColor.fromHex('#CBD5E1'),
                    blurRadius: 2,
                    offset: const PdfPoint(0, 1),
                  ),
                ],
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'كشف حساب مجمع - الموردون',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 11.5,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Suppliers Consolidated Statement (Multi-Currency)',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 6.5,
                      color: PdfColor.fromHex('#94A3B8'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Accent Separator Line
        pw.Container(
          height: 2.2,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [_navyPrimary, _accentTeal, _borderColor],
            ),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
        ),
        pw.SizedBox(height: 4),

        // Meta Info Bar
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'تاريخ استخراج التقرير: $printDate',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
            ),
            pw.Text(
              'إجمالي الموردين المدرجين: $totalSuppliers مورد',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
            ),
            pw.Text(
              'العملة الأساسية للنظام: الجنيه المصري (EGP)',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUBSEQUENT PAGE HEADER
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildSubsequentPageHeader({
    required String companyName,
    required String printDate,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.7)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'كشف حساب مجمع - الموردون | $companyName',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _navyPrimary),
          ),
          pw.Text(
            'تاريخ الطباعة: $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MULTI-CURRENCY KPI SUMMARY SECTION (3 Side-by-Side Cards)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildKpiSummaryHeader({
    required int totalSuppliers,
    required int cropCount,
    required int packagingCount,
    required int sharedCount,
    required double totalCurrentBalanceEgp,
    required double totalInitialBalanceEgp,
    required Map<String, CurrencyBalance> curBalances,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final sortedCurrencies = _sortCurrencies(curBalances.keys.toList());

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // CARD 1: Total Suppliers + Category Breakdown
        pw.Expanded(
          child: _buildKpiCard(
            title: 'إجمالي الموردين',
            englishTitle: 'Suppliers Categorization',
            heroValue: '$totalSuppliers مورد',
            heroColor: _navyPrimary,
            subText: 'موردون مسجلون في قاعدة البيانات',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildCategoryBadge('محاصيل', '$cropCount', _greenBg, _greenText, _greenBorder, fontBold, fontRegular),
                _buildCategoryBadge('تعبئة', '$packagingCount', _purpleBg, _purpleText, _purpleBorder, fontBold, fontRegular),
                _buildCategoryBadge('مشترك', '$sharedCount', _amberBg, _amberText, _amberBorder, fontBold, fontRegular),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),

        // CARD 2: Total Current Balances (Multi-Currency Breakdown)
        pw.Expanded(
          child: _buildKpiCard(
            title: 'إجمالي الأرصدة الحالية',
            englishTitle: 'Current Outstanding Balances',
            heroValue: '${AppUtils.formatNumber(totalCurrentBalanceEgp.abs())} ج.م',
            heroColor: totalCurrentBalanceEgp >= 0 ? _greenText : _redText,
            subText: 'إجمالي مكافئ بالجنيه المصري (Base Currency)',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Wrap(
              spacing: 5,
              runSpacing: 4,
              children: sortedCurrencies.map((ccy) {
                final cb = curBalances[ccy];
                final nativeBal = cb?.nativeCurrentBalance ?? 0.0;
                final sym = _getCurrencySymbol(ccy);
                final cnt = cb?.supplierCount ?? 0;
                final isNeg = nativeBal < 0;

                return _buildCurrencyPill(
                  symbol: sym,
                  currencyCode: ccy,
                  amountText: AppUtils.formatNumber(nativeBal.abs()),
                  countText: '$cnt مورد',
                  isNegative: isNeg,
                  fontBold: fontBold,
                  fontRegular: fontRegular,
                );
              }).toList(),
            ),
          ),
        ),
        pw.SizedBox(width: 10),

        // CARD 3: Total Opening Balances (Multi-Currency Breakdown)
        pw.Expanded(
          child: _buildKpiCard(
            title: 'إجمالي الأرصدة الافتتاحية',
            englishTitle: 'Opening Balances Breakdown',
            heroValue: '${AppUtils.formatNumber(totalInitialBalanceEgp.abs())} ج.م',
            heroColor: _amberText,
            subText: 'رصيد افتتاحي معادل بالجنيه المصري',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Wrap(
              spacing: 5,
              runSpacing: 4,
              children: sortedCurrencies.map((ccy) {
                final cb = curBalances[ccy];
                final initBal = cb?.nativeInitialBalance ?? 0.0;
                final sym = _getCurrencySymbol(ccy);
                final cnt = cb?.supplierCount ?? 0;

                return _buildCurrencyPill(
                  symbol: sym,
                  currencyCode: ccy,
                  amountText: AppUtils.formatNumber(initBal.abs()),
                  countText: '$cnt مورد',
                  isNegative: false,
                  fontBold: fontBold,
                  fontRegular: fontRegular,
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildKpiCard({
    required String title,
    required String englishTitle,
    required String heroValue,
    required PdfColor heroColor,
    required String subText,
    required pw.Widget child,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header row
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                title,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _navyPrimary),
              ),
              pw.Text(
                englishTitle,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.0, color: _textMuted),
              ),
            ],
          ),
          pw.SizedBox(height: 3),

          // Hero Value
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                heroValue,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 12.5, color: heroColor),
              ),
              pw.Text(
                subText,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontRegular, fontSize: 6.0, color: _textMuted),
              ),
            ],
          ),
          pw.SizedBox(height: 5),

          child,
        ],
      ),
    );
  }

  static pw.Widget _buildCategoryBadge(
    String label,
    String count,
    PdfColor bgColor,
    PdfColor textColor,
    PdfColor borderColor,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: borderColor, width: 0.5),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label: ',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 7.0, color: textColor),
          ),
          pw.Text(
            count,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: textColor),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCurrencyPill({
    required String symbol,
    required String currencyCode,
    required String amountText,
    required String countText,
    required bool isNegative,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final textColor = isNegative ? _redText : _navyPrimary;
    final pillBg = isNegative ? _redBg : PdfColors.white;
    final pillBorder = isNegative ? _borderColor : _borderLight;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: pw.BoxDecoration(
        color: pillBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: pillBorder, width: 0.5),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            symbol,
            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: textColor),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            amountText,
            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: textColor),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            '($countText)',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.0, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAIN DATA TABLE (Alternating Rows, Deep Navy Headers, RTL)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildSuppliersTable({
    required List<SupplierModel> suppliers,
    required double totalCurrentBalanceEgp,
    required double totalInitialBalanceEgp,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required pw.Font fontFallback,
  }) {
    if (suppliers.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(20),
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _cardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _borderColor, width: 0.5),
        ),
        child: pw.Text(
          'لا توجد بيانات موردين مسجلة للعرض',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fontBold, fontSize: 10, color: _textMuted),
        ),
      );
    }

    final rows = <pw.TableRow>[
      // Table Header Row (Deep Navy)
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: _navyPrimary,
          borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
        ),
        repeat: true,
        children: [
          _buildHeaderCell('#\nNo', fontBold, width: 28),
          _buildHeaderCell('كود المورد\nCode', fontBold, width: 68),
          _buildHeaderCell('اسم المورد\nSupplier Name', fontBold, align: pw.TextAlign.right),
          _buildHeaderCell('التصنيف\nCategory', fontBold, width: 70),
          _buildHeaderCell('الهاتف\nPhone', fontBold, width: 80),
          _buildHeaderCell('العملة\nCurrency', fontBold, width: 55),
          _buildHeaderCell('الرصيد الافتتاحي\nOpening Balance', fontBold, align: pw.TextAlign.right, width: 95),
          _buildHeaderCell('الرصيد الحالي\nCurrent Balance', fontBold, align: pw.TextAlign.right, width: 105),
          _buildHeaderCell('طبيعة الرصيد\nStatus', fontBold, width: 65),
        ],
      ),
    ];

    // Data Rows
    for (int i = 0; i < suppliers.length; i++) {
      final s = suppliers[i];
      final isEven = (i % 2 == 0);
      final rowBg = isEven ? PdfColors.white : _zebraBg;
      final curBal = s.outstandingBalance;
      final isCurrentNeg = curBal < 0;

      // Status text
      String statusText;
      PdfColor statusColor;
      if (curBal > 0) {
        statusText = 'له (دائن)';
        statusColor = _greenText;
      } else if (curBal < 0) {
        statusText = 'عليه (مدين)';
        statusColor = _redText;
      } else {
        statusText = 'متزن';
        statusColor = _textMuted;
      }

      // Category badge colors
      PdfColor catBg;
      PdfColor catText;
      PdfColor catBorder;
      if (s.supplierType == 'crop') {
        catBg = _greenBg; catText = _greenText; catBorder = _greenBorder;
      } else if (s.supplierType == 'packaging') {
        catBg = _purpleBg; catText = _purpleText; catBorder = _purpleBorder;
      } else {
        catBg = _amberBg; catText = _amberText; catBorder = _amberBorder;
      }

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: rowBg,
            border: pw.Border(bottom: pw.BorderSide(color: _borderLight, width: 0.45)),
          ),
          children: [
            // 0: Sequence #
            _buildDataCell('${i + 1}', font: fontRegular, fontSize: 7.5, align: pw.TextAlign.center),

            // 1: Supplier Code
            _buildDataCell(s.supplierCode, font: fontBold, fontSize: 7.5, textColor: _navyPrimary, align: pw.TextAlign.center),

            // 2: Supplier Name
            _buildDataCell(s.name, font: fontBold, fontSize: 8.0, textColor: _textDark, align: pw.TextAlign.right),

            // 3: Category Badge
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
              alignment: pw.Alignment.center,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: pw.BoxDecoration(
                  color: catBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  border: pw.Border.all(color: catBorder, width: 0.4),
                ),
                child: pw.Text(
                  s.supplierTypeLabel,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: catText),
                ),
              ),
            ),

            // 4: Phone
            _buildDataCell(s.phone.isNotEmpty ? s.phone : '—', font: fontRegular, fontSize: 7.0, textColor: _textMuted, align: pw.TextAlign.center),

            // 5: Currency
            _buildDataCell('${s.currency} (${s.currencySymbol})', font: fontBold, fontSize: 7.0, textColor: _navyPrimary, align: pw.TextAlign.center),

            // 6: Opening Balance
            _buildDataCell(
              '${AppUtils.formatNumber(s.initialBalance.abs())} ${s.currencySymbol}',
              font: fontRegular,
              fontSize: 7.5,
              textColor: _textDark,
              align: pw.TextAlign.right,
            ),

            // 7: Current Balance
            _buildDataCell(
              '${isCurrentNeg ? '-' : ''}${AppUtils.formatNumber(curBal.abs())} ${s.currencySymbol}',
              font: fontBold,
              fontSize: 8.0,
              textColor: isCurrentNeg ? _redText : _greenText,
              align: pw.TextAlign.right,
            ),

            // 8: Status
            _buildDataCell(statusText, font: fontBold, fontSize: 7.0, textColor: statusColor, align: pw.TextAlign.center),
          ],
        ),
      );
    }

    // Grand Total Row (Calculated in Base Currency EGP)
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: _totalRowBg,
          border: pw.Border(
            top: pw.BorderSide(color: _borderColor, width: 1.0),
            bottom: pw.BorderSide(color: _borderColor, width: 1.0),
          ),
        ),
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text('#', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _navyPrimary)),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text('الإجمالي', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _navyPrimary)),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'إجمالي معادل بالجنيه المصري لجميع الموردين (${suppliers.length} مورد)',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _navyPrimary),
            ),
          ),
          pw.Container(padding: const pw.EdgeInsets.all(5)), // category
          pw.Container(padding: const pw.EdgeInsets.all(5)), // phone
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text('EGP (ج.م)', style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary)),
          ),
          // Total Opening in EGP
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${AppUtils.formatNumber(totalInitialBalanceEgp.abs())} ج.م',
              style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _amberText),
            ),
          ),
          // Total Current in EGP
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${AppUtils.formatNumber(totalCurrentBalanceEgp.abs())} ج.م',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 8.5,
                color: totalCurrentBalanceEgp >= 0 ? _greenText : _redText,
              ),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text(
              totalCurrentBalanceEgp >= 0 ? 'صافي دائن' : 'صافي مدين',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 7.0, color: totalCurrentBalanceEgp >= 0 ? _greenText : _redText),
            ),
          ),
        ],
      ),
    );

    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(28),  // #
        1: const pw.FixedColumnWidth(68),  // Code
        2: const pw.FlexColumnWidth(3.0),  // Name
        3: const pw.FixedColumnWidth(70),  // Category
        4: const pw.FixedColumnWidth(80),  // Phone
        5: const pw.FixedColumnWidth(55),  // Currency
        6: const pw.FixedColumnWidth(95),  // Initial Balance
        7: const pw.FixedColumnWidth(105), // Current Balance
        8: const pw.FixedColumnWidth(65),  // Status
      },
      children: rows,
    );
  }

  static pw.Widget _buildHeaderCell(
    String text,
    pw.Font fontBold, {
    pw.TextAlign align = pw.TextAlign.center,
    double? width,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      alignment: align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : (align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: 7.5,
          color: PdfColors.white,
          lineSpacing: 1.1,
        ),
      ),
    );
  }

  static pw.Widget _buildDataCell(
    String text, {
    required pw.Font font,
    required double fontSize,
    PdfColor? textColor,
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      alignment: align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : (align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          color: textColor ?? _textDark,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER (Page numbering "صفحة X من Y", Company Name, Timestamp)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildPageFooter({
    required pw.Context context,
    required String companyName,
    required String printDate,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: _borderColor, thickness: 0.5),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Right: Document title & company
            pw.Text(
              'كشف حساب مجمع - الموردون | $companyName',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
            ),

            // Center: Page Numbering ("صفحة X من Y")
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: pw.BoxDecoration(
                color: _zebraBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: _borderColor, width: 0.5),
              ),
              child: pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
              ),
            ),

            // Left: Timestamp
            pw.Text(
              'طبع بتاريخ: $printDate',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPER FUNCTIONS
  // ──────────────────────────────────────────────────────────────────────────
  static String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD': return r'$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'EGP': return 'ج.م';
      default: return currency;
    }
  }

  static List<String> _sortCurrencies(List<String> currencies) {
    const priority = {'EGP': 0, 'USD': 1, 'EUR': 2, 'GBP': 3};
    final sorted = List<String>.from(currencies);
    sorted.sort((a, b) {
      final pA = priority[a.toUpperCase()] ?? 99;
      final pB = priority[b.toUpperCase()] ?? 99;
      if (pA != pB) return pA.compareTo(pB);
      return a.compareTo(b);
    });
    return sorted;
  }
}

class _CurrencyStats {
  final String currency;
  int count = 0;
  double current = 0.0;
  double initial = 0.0;
  _CurrencyStats(this.currency);
}
