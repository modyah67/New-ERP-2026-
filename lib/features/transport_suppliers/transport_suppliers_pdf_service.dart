// lib/features/transport_suppliers/transport_suppliers_pdf_service.dart
// Professional Landscape A4 Consolidated Statement for Transport Suppliers

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
import '../../data/models/transport_supplier_model.dart';
import '../../data/dao/settings_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class TransportSuppliersPdfService {
  TransportSuppliersPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Deep Navy Professional Transport Logistics Theme)
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
  static final _blueText     = PdfColor.fromHex('#0369A1'); // Sky 700
  static final _blueBg       = PdfColor.fromHex('#E0F2FE'); // Sky 100
  static final _blueBorder   = PdfColor.fromHex('#7DD3FC'); // Sky 300

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
    required List<TransportSupplierModel> suppliers,
    String? companyName,
  }) async {
    final fonts = await _loadFonts();
    Map<String, String> settings = const {};
    try {
      settings = await SettingsDao().getAllSettings();
    } catch (_) {}
    final resolvedCompanyName = companyName ?? settings['company_name'] ?? AppConstants.companyName;

    // Derived Transport Metrics
    final totalCount = suppliers.length;
    double totalBalance = 0.0;
    double totalCreditDues = 0.0;
    double totalDebitAdvances = 0.0;
    double totalInitialBalance = 0.0;
    double totalTruckStock = 0.0;
    double totalInitialTrucks = 0.0;
    int creditorsCount = 0;
    int debtorsCount = 0;

    for (final s in suppliers) {
      totalBalance += s.balance;
      totalInitialBalance += s.initialBalance;
      totalTruckStock += s.truckBalance;
      totalInitialTrucks += s.initialTruckBalance;

      if (s.balance > 0) {
        totalCreditDues += s.balance;
        creditorsCount++;
      } else if (s.balance < 0) {
        totalDebitAdvances += s.balance.abs();
        debtorsCount++;
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
            totalSuppliers: totalCount,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 2. Transport Logistics KPI Summary Cards
          _buildKpiSummaryHeader(
            totalCount: totalCount,
            totalBalance: totalBalance,
            totalCreditDues: totalCreditDues,
            totalDebitAdvances: totalDebitAdvances,
            totalInitialBalance: totalInitialBalance,
            totalTruckStock: totalTruckStock,
            totalInitialTrucks: totalInitialTrucks,
            creditorsCount: creditorsCount,
            debtorsCount: debtorsCount,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 12),

          // 3. Transport Suppliers Table
          _buildTransportTable(
            suppliers: suppliers,
            totalBalance: totalBalance,
            totalInitialBalance: totalInitialBalance,
            totalTruckStock: totalTruckStock,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
            fontFallback: fonts.fallback,
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Direct print method using Printing package in Landscape.
  static Future<void> generateAndPrint({
    required List<TransportSupplierModel> suppliers,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      suppliers: suppliers,
      companyName: companyName,
    );
    final docTitle = _formattedFileName('كشف حساب مجمع - موردو النقل');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the PDF to export directory and shows snackbar.
  static Future<File> saveToFile(
    BuildContext context, {
    required List<TransportSupplierModel> suppliers,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      suppliers: suppliers,
      companyName: companyName,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('كشف_حساب_مجمع_موردو_النقل')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف حساب موردي النقل بنجاح في:\n$path');
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
                  'قطاع النقل واللوجستيات والشحن الزراعي (Fruity Farms ERP)',
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
                    'كشف حساب مجمع - موردو النقل والشحن',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 11.5,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Transport Suppliers Consolidated Statement',
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
              'إجمالي مقاولي وسيارات النقل: $totalSuppliers مقاول',
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
            'كشف حساب مجمع - موردو النقل والشحن | $companyName',
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
  // KPI SUMMARY CARDS (4 Side-by-Side Cards)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildKpiSummaryHeader({
    required int totalCount,
    required double totalBalance,
    required double totalCreditDues,
    required double totalDebitAdvances,
    required double totalInitialBalance,
    required double totalTruckStock,
    required double totalInitialTrucks,
    required int creditorsCount,
    required int debtorsCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Card 1: Total Transport Suppliers
        pw.Expanded(
          child: _buildKpiCard(
            title: 'إجمالي مقاولي النقل',
            englishTitle: 'Transport Contractors',
            heroValue: '$totalCount مقاول',
            heroColor: _navyPrimary,
            subText: 'مسجلون في قطاع النقل',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildStatPill('مستحق لهم: ', '$creditorsCount', _greenBg, _greenText, _greenBorder, fontBold, fontRegular),
                _buildStatPill('سلف عليهم: ', '$debtorsCount', _redBg, _redText, _redBg, fontBold, fontRegular),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),

        // Card 2: Current Net Balances
        pw.Expanded(
          child: _buildKpiCard(
            title: 'صافي الأرصدة القائمة',
            englishTitle: 'Current Net Balances',
            heroValue: '${AppUtils.formatNumber(totalBalance.abs())} ج.م',
            heroColor: totalBalance >= 0 ? _greenText : _redText,
            subText: totalBalance >= 0 ? 'صافي مستحق للموردين (دائن)' : 'صافي سلف ومقدمات (مدين)',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('مستحقات (له):', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: _greenText)),
                    pw.Text('${AppUtils.formatNumber(totalCreditDues)} ج.م', style: pw.TextStyle(font: fontBold, fontSize: 7.0, color: _greenText)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('سلف مقدمة (عليه):', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: _redText)),
                    pw.Text('${AppUtils.formatNumber(totalDebitAdvances)} ج.م', style: pw.TextStyle(font: fontBold, fontSize: 7.0, color: _redText)),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),

        // Card 3: Total Trips / Truck Stock Balance
        pw.Expanded(
          child: _buildKpiCard(
            title: 'مخزون ورصيد النقلات',
            englishTitle: 'Operational Truck Balance',
            heroValue: '${totalTruckStock % 1 == 0 ? totalTruckStock.toInt() : totalTruckStock.toStringAsFixed(1)} نقلة / سيارة',
            heroColor: _blueText,
            subText: 'إجمالي رصيد النقلات المعلقة',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildStatPill('افتتاحي: ', '${totalInitialTrucks % 1 == 0 ? totalInitialTrucks.toInt() : totalInitialTrucks.toStringAsFixed(1)}', _cardBg, _navyPrimary, _borderColor, fontBold, fontRegular),
                _buildStatPill('رصيد حالي: ', '${totalTruckStock % 1 == 0 ? totalTruckStock.toInt() : totalTruckStock.toStringAsFixed(1)}', _blueBg, _blueText, _blueBorder, fontBold, fontRegular),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),

        // Card 4: Total Opening Balances
        pw.Expanded(
          child: _buildKpiCard(
            title: 'إجمالي الأرصدة الافتتاحية',
            englishTitle: 'Opening Balances',
            heroValue: '${AppUtils.formatNumber(totalInitialBalance.abs())} ج.م',
            heroColor: _amberText,
            subText: 'رصيد مالي عند بدء التعامل',
            fontBold: fontBold,
            fontRegular: fontRegular,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildStatPill('افتتاحي: ', '${AppUtils.formatNumber(totalInitialBalance)} ج.م', _amberBg, _amberText, _amberBorder, fontBold, fontRegular),
              ],
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.65),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                title,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _navyPrimary),
              ),
              pw.Text(
                englishTitle,
                style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _textMuted),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                heroValue,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: heroColor),
              ),
              pw.Text(
                subText,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _textMuted),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  static pw.Widget _buildStatPill(
    String label,
    String count,
    PdfColor bgColor,
    PdfColor textColor,
    PdfColor borderColor,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: borderColor, width: 0.4),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: textColor),
          ),
          pw.Text(
            count,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontBold, fontSize: 7.0, color: textColor),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAIN DATA TABLE (Deep Navy Headers, Alternating Rows, RTL)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildTransportTable({
    required List<TransportSupplierModel> suppliers,
    required double totalBalance,
    required double totalInitialBalance,
    required double totalTruckStock,
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
          _buildHeaderCell('كود المورد\nCode', fontBold, width: 75),
          _buildHeaderCell('اسم مقاول / مورد النقل\nSupplier Name', fontBold, align: pw.TextAlign.right),
          _buildHeaderCell('الهاتف\nPhone', fontBold, width: 85),
          _buildHeaderCell('رصيد النقلات\nTrips / Trucks', fontBold, width: 85),
          _buildHeaderCell('الرصيد الافتتاحي\nOpening Balance', fontBold, align: pw.TextAlign.right, width: 100),
          _buildHeaderCell('الرصيد الحالي\nCurrent Balance', fontBold, align: pw.TextAlign.right, width: 110),
          _buildHeaderCell('طبيعة الرصيد\nStatus', fontBold, width: 75),
        ],
      ),
    ];

    // Data Rows
    for (int i = 0; i < suppliers.length; i++) {
      final s = suppliers[i];
      final isEven = (i % 2 == 0);
      final rowBg = isEven ? PdfColors.white : _zebraBg;
      final curBal = s.balance;
      final isCurrentNeg = curBal < 0;

      // Status text
      String statusText;
      PdfColor statusColor;
      if (curBal > 0) {
        statusText = 'مستحق له (دائن)';
        statusColor = _greenText;
      } else if (curBal < 0) {
        statusText = 'سلفة عليه (مدين)';
        statusColor = _redText;
      } else {
        statusText = 'متزن (خالص)';
        statusColor = _textMuted;
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
            _buildDataCell(s.code.isNotEmpty ? s.code : '—', font: fontBold, fontSize: 7.5, textColor: _navyPrimary, align: pw.TextAlign.center),

            // 2: Supplier Name
            _buildDataCell(s.name, font: fontBold, fontSize: 8.0, textColor: _textDark, align: pw.TextAlign.right),

            // 3: Phone
            _buildDataCell(s.phone.isNotEmpty ? s.phone : '—', font: fontRegular, fontSize: 7.0, textColor: _textMuted, align: pw.TextAlign.center),

            // 4: Total Trips Count (مخزون النقل / عدد النقلات)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
              alignment: pw.Alignment.center,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: pw.BoxDecoration(
                  color: s.truckBalance != 0 ? _blueBg : _cardBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  border: pw.Border.all(color: s.truckBalance != 0 ? _blueBorder : _borderColor, width: 0.4),
                ),
                child: pw.Text(
                  '${s.truckBalance % 1 == 0 ? s.truckBalance.toInt() : s.truckBalance.toStringAsFixed(1)} نقلة',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 7.0,
                    color: s.truckBalance != 0 ? _blueText : _textMuted,
                  ),
                ),
              ),
            ),

            // 5: Opening Balance
            _buildDataCell(
              '${AppUtils.formatNumber(s.initialBalance.abs())} ج.م',
              font: fontRegular,
              fontSize: 7.5,
              textColor: _textDark,
              align: pw.TextAlign.right,
            ),

            // 6: Current Balance
            _buildDataCell(
              '${isCurrentNeg ? '-' : ''}${AppUtils.formatNumber(curBal.abs())} ج.م',
              font: fontBold,
              fontSize: 8.0,
              textColor: isCurrentNeg ? _redText : _greenText,
              align: pw.TextAlign.right,
            ),

            // 7: Status
            _buildDataCell(statusText, font: fontBold, fontSize: 7.0, textColor: statusColor, align: pw.TextAlign.center),
          ],
        ),
      );
    }

    // Grand Total Row
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
              'إجمالي قطاع النقل والشحن (${suppliers.length} مقاول)',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _navyPrimary),
            ),
          ),
          pw.Container(padding: const pw.EdgeInsets.all(5)), // phone
          // Total Truck Trips Count
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '$totalTruckStock نقلة',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _blueText),
            ),
          ),
          // Total Opening Balance
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${AppUtils.formatNumber(totalInitialBalance.abs())} ج.م',
              style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: _amberText),
            ),
          ),
          // Total Current Balance
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${AppUtils.formatNumber(totalBalance.abs())} ج.م',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 8.5,
                color: totalBalance >= 0 ? _greenText : _redText,
              ),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            alignment: pw.Alignment.center,
            child: pw.Text(
              totalBalance >= 0 ? 'صافي دائن' : 'صافي مدين',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: fontBold, fontSize: 7.0, color: totalBalance >= 0 ? _greenText : _redText),
            ),
          ),
        ],
      ),
    );

    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(28),  // #
        1: const pw.FixedColumnWidth(75),  // Code
        2: const pw.FlexColumnWidth(3.0),  // Name
        3: const pw.FixedColumnWidth(85),  // Phone
        4: const pw.FixedColumnWidth(85),  // Trips Count
        5: const pw.FixedColumnWidth(100), // Initial Balance
        6: const pw.FixedColumnWidth(110), // Current Balance
        7: const pw.FixedColumnWidth(75),  // Status
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
              'كشف حساب مجمع - موردو النقل والشحن | $companyName',
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
}
