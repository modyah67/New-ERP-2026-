import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/ui_utils.dart';
import '../../core/utils/file_helper.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/models/clearing_agent_model.dart';
import 'clearing_agent_state.dart';

/// Alias for naming compatibility
typedef ClearingAgentsPdfService = ClearanceAgentsPdfService;

/// Landscape PDF service for generating and printing Consolidated Statements for Custom Clearance Agents.
class ClearanceAgentsPdfService {
  // Brand & Visual Palette (Matching the General & Transport Suppliers Multi-Currency Theme)
  static const PdfColor _navy = PdfColor.fromInt(0xFF1A365D);
  static const PdfColor _primaryBlue = PdfColor.fromInt(0xFF0284C7);
  static const PdfColor _textDark = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _textMuted = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _lightBg = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor _zebraBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor _green = PdfColor.fromInt(0xFF059669);
  static const PdfColor _red = PdfColor.fromInt(0xFFDC2626);
  static const PdfColor _amber = PdfColor.fromInt(0xFFD97706);
  static const PdfColor _cyan = PdfColor.fromInt(0xFF0891B2);
  static const PdfColor _indigo = PdfColor.fromInt(0xFF4F46E5);

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');
  static final intl.NumberFormat _intFmt = intl.NumberFormat('#,##0', 'en_US');

  /// Main method to generate Landscape PDF document bytes.
  static Future<Uint8List> generatePdf({
    required List<ClearingAgentModel> agents,
    Map<String, ClearingCurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? seaCount,
    int? airCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final fonts = await _loadFonts();
    String effectiveCompanyName = companyName ?? 'مزارع فروتي فارمز لتصدير الحاصلات الزراعية';

    try {
      final settings = await SettingsDao().getAllSettings();
      if (companyName == null && settings['company_name'] != null && settings['company_name']!.isNotEmpty) {
        effectiveCompanyName = settings['company_name']!;
      }
    } catch (_) {}

    // Calculation / fallback of metrics
    final totalAgents = agents.length;
    final rates = exchangeRates ?? const {'EGP': 1.0, 'USD': 50.0, 'EUR': 55.0, 'GBP': 65.0};

    int effectiveSea = seaCount ?? 0;
    int effectiveAir = airCount ?? 0;
    Map<String, ClearingCurrencyBalance> effectiveByC = balanceByCurrency ?? {};
    double effectiveTotalCurrentEgp = totalCurrentBalanceEgp ?? 0.0;
    double effectiveTotalInitialEgp = totalInitialBalanceEgp ?? 0.0;

    int creditorsCount = 0;
    int debtorsCount = 0;
    double totalCreditBalanceEgp = 0.0;
    double totalDebitBalanceEgp = 0.0;

    if (balanceByCurrency == null || totalCurrentBalanceEgp == null) {
      final loaded = ClearingAgentLoaded.fromList(agents: agents, rates: rates);
      effectiveSea = loaded.seaCount;
      effectiveAir = loaded.airCount;
      effectiveByC = loaded.balanceByCurrency;
      effectiveTotalCurrentEgp = loaded.totalCurrentBalanceEgp;
      effectiveTotalInitialEgp = loaded.totalInitialBalanceEgp;
    }

    for (final a in agents) {
      final rate = a.currency == 'EGP' ? 1.0 : (rates[a.currency.toUpperCase()] ?? 1.0);
      final egpBal = a.balance * rate;
      if (a.balance > 0.0001) {
        creditorsCount++;
        totalCreditBalanceEgp += egpBal;
      } else if (a.balance < -0.0001) {
        debtorsCount++;
        totalDebitBalanceEgp += egpBal.abs();
      }
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
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
        header: (context) => _buildReportHeader(
          companyName: effectiveCompanyName,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          fontBold: fonts.bold,
          fontRegular: fonts.regular,
        ),
        footer: (context) => _buildReportFooter(
          companyName: effectiveCompanyName,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          fontRegular: fonts.regular,
        ),
        build: (context) => [
          // 1. Report Title & Meta Badge
          _buildReportTitleBadge(
            totalCount: totalAgents,
            seaCount: effectiveSea,
            airCount: effectiveAir,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 2. Multi-Metric KPI Summary Header Block
          _buildKpiSummaryHeader(
            totalAgents: totalAgents,
            seaCount: effectiveSea,
            airCount: effectiveAir,
            balanceByCurrency: effectiveByC,
            totalCurrentBalanceEgp: effectiveTotalCurrentEgp,
            totalInitialBalanceEgp: effectiveTotalInitialEgp,
            totalCreditBalanceEgp: totalCreditBalanceEgp,
            totalDebitBalanceEgp: totalDebitBalanceEgp,
            creditorsCount: creditorsCount,
            debtorsCount: debtorsCount,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 12),

          // 3. Main Clearance Agents Table
          _buildAgentsTable(
            agents: agents,
            totalCurrentBalanceEgp: effectiveTotalCurrentEgp,
            totalInitialBalanceEgp: effectiveTotalInitialEgp,
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
    required List<ClearingAgentModel> agents,
    Map<String, ClearingCurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? seaCount,
    int? airCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      agents: agents,
      balanceByCurrency: balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp,
      seaCount: seaCount,
      airCount: airCount,
      exchangeRates: exchangeRates,
      companyName: companyName,
    );
    final docTitle = _formattedFileName('كشف حساب مجمع - مخلصو الجمارك');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the PDF to export directory and shows snackbar.
  static Future<File> saveToFile(
    BuildContext context, {
    required List<ClearingAgentModel> agents,
    Map<String, ClearingCurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? seaCount,
    int? airCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) async {
    final bytes = await generatePdf(
      agents: agents,
      balanceByCurrency: balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp,
      seaCount: seaCount,
      airCount: airCount,
      exchangeRates: exchangeRates,
      companyName: companyName,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('كشف_حساب_مجمع_مخلصو_الجمارك')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف حساب مخلصي الجمارك بنجاح في:\n$path');
    }
    return file;
  }

  // ── Header & Branding ──

  static pw.Widget _buildReportHeader({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final nowFormatted = intl.DateFormat('yyyy/MM/dd - HH:mm', 'en_US').format(DateTime.now());

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left meta: Print Date & System
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('تاريخ التصدير: $nowFormatted',
                  style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _textMuted)),
              pw.SizedBox(height: 2),
              pw.Text('نظام الفروتي فارمز ERP • الإدارة المالية',
                  style: pw.TextStyle(font: fontRegular, fontSize: 8, color: _textMuted)),
            ],
          ),

          // Center: Document Title
          pw.Column(
            children: [
              pw.Text(
                'كشف حساب مجمع - مخلصو الجمارك والشحن',
                style: pw.TextStyle(font: fontBold, fontSize: 15, color: _navy),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تقرير الأرصدة المالية والعملات وحركات التخليص الجمركي',
                style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _textMuted),
              ),
            ],
          ),

          // Right: Company Brand
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(font: fontBold, fontSize: 13, color: _navy),
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE0F2FE),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'قطاع التصدير والتخليص الجمركي',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navy),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildReportTitleBadge({
    required int totalCount,
    required int seaCount,
    required int airCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: const pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'كشف حساب مجمع - مخلصو الجمارك',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  '${_intFmt.format(totalCount)} مخلص',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _navy),
                ),
              ),
            ],
          ),
        ),
        pw.Row(
          children: [
            _buildTypePill('بحري (موانئ)', seaCount, _cyan, fontBold, fontRegular),
            pw.SizedBox(width: 6),
            _buildTypePill('جوي (مطارات)', airCount, _indigo, fontBold, fontRegular),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTypePill(String label, int count, PdfColor color, pw.Font bold, pw.Font reg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 7, height: 7,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 5),
          pw.Text(
            '$label: ${_intFmt.format(count)}',
            style: pw.TextStyle(font: bold, fontSize: 8.5, color: _textDark),
          ),
        ],
      ),
    );
  }

  // ── Multi-Metric KPI Summary Header Block ──

  static pw.Widget _buildKpiSummaryHeader({
    required int totalAgents,
    required int seaCount,
    required int airCount,
    required Map<String, ClearingCurrencyBalance> balanceByCurrency,
    required double totalCurrentBalanceEgp,
    required double totalInitialBalanceEgp,
    required double totalCreditBalanceEgp,
    required double totalDebitBalanceEgp,
    required int creditorsCount,
    required int debtorsCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    const order = ['EGP', 'USD', 'EUR', 'GBP'];
    final currencyBalances = <ClearingCurrencyBalance>[];
    for (final c in order) {
      if (balanceByCurrency.containsKey(c)) currencyBalances.add(balanceByCurrency[c]!);
    }
    for (final entry in balanceByCurrency.entries) {
      if (!order.contains(entry.key)) currencyBalances.add(entry.value);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Card 1: Total Agents & Clearance Types
          pw.Expanded(
            flex: 2,
            child: _buildSummaryCard(
              title: 'إجمالي مخلصي الجمارك',
              value: '${_intFmt.format(totalAgents)} مخلص',
              subtitle: 'بحري $seaCount • جوي $airCount',
              badgeText: 'توزيع التخليص',
              badgeColor: _navy,
              chips: [
                _buildSummaryMiniChip('بحري', '$seaCount مخلص', _cyan, fontBold, fontRegular),
                _buildSummaryMiniChip('جوي', '$airCount مخلص', _indigo, fontBold, fontRegular),
              ],
              fontBold: fontBold,
              fontRegular: fontRegular,
            ),
          ),
          pw.SizedBox(width: 8),

          // Card 2: Current Balances (Multi-Currency)
          pw.Expanded(
            flex: 3,
            child: _buildSummaryCard(
              title: 'صافي الأرصدة الحالية (مكافئ ج.م)',
              value: '${_currFmt.format(totalCurrentBalanceEgp.abs())} ج.م',
              subtitle: totalCurrentBalanceEgp >= 0 ? 'مستحق للمخلصين (دائن)' : 'دفعات مقدمة / عليهم (مدين)',
              badgeText: totalCurrentBalanceEgp >= 0 ? 'رصيد دائن' : 'رصيد مدين',
              badgeColor: totalCurrentBalanceEgp >= 0 ? _green : _red,
              chips: currencyBalances.isEmpty
                  ? null
                  : currencyBalances
                      .map((c) => _buildSummaryMiniChip(
                            c.currency,
                            '${c.symbol} ${_currFmt.format(c.nativeCurrentBalance.abs())}',
                            c.nativeCurrentBalance >= 0 ? _green : _red,
                            fontBold,
                            fontRegular,
                          ))
                      .toList(),
              fontBold: fontBold,
              fontRegular: fontRegular,
            ),
          ),
          pw.SizedBox(width: 8),

          // Card 3: Initial Balances (Multi-Currency)
          pw.Expanded(
            flex: 3,
            child: _buildSummaryCard(
              title: 'إجمالي الأرصدة الافتتاحية (ج.م)',
              value: '${_currFmt.format(totalInitialBalanceEgp.abs())} ج.م',
              subtitle: 'إجمالي الرصيد البدئي المعتمد بالدفاتر',
              badgeText: 'افتتاحي معادل',
              badgeColor: _amber,
              chips: currencyBalances.isEmpty
                  ? null
                  : currencyBalances
                      .map((c) => _buildSummaryMiniChip(
                            c.currency,
                            '${c.symbol} ${_currFmt.format(c.nativeInitialBalance.abs())}',
                            _amber,
                            fontBold,
                            fontRegular,
                          ))
                      .toList(),
              fontBold: fontBold,
              fontRegular: fontRegular,
            ),
          ),
          pw.SizedBox(width: 8),

          // Card 4: Dues & Advances (Creditors vs Debtors)
          pw.Expanded(
            flex: 2,
            child: _buildSummaryCard(
              title: 'حالة الحسابات والالتزامات',
              value: '${_intFmt.format(creditorsCount)} دائن / ${_intFmt.format(debtorsCount)} مدين',
              subtitle: 'دائن: ${_currFmt.format(totalCreditBalanceEgp)} ج.م',
              badgeText: 'التزامات ومستحقات',
              badgeColor: _primaryBlue,
              chips: [
                _buildSummaryMiniChip('مستحق لهم', '${_currFmt.format(totalCreditBalanceEgp)} ج.م', _green, fontBold, fontRegular),
                _buildSummaryMiniChip('مقدمات/عليهم', '${_currFmt.format(totalDebitBalanceEgp)} ج.م', _red, fontBold, fontRegular),
              ],
              fontBold: fontBold,
              fontRegular: fontRegular,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required String badgeText,
    required PdfColor badgeColor,
    List<pw.Widget>? chips,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  maxLines: 1,
                  style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: _textMuted),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: pw.BoxDecoration(
                  color: badgeColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  badgeText,
                  style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: PdfColors.white),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: _navy),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            subtitle,
            maxLines: 1,
            style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _textMuted),
          ),
          if (chips != null && chips.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Wrap(
              spacing: 3,
              runSpacing: 2,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryMiniChip(
    String label,
    String value,
    PdfColor color,
    pw.Font bold,
    pw.Font reg,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        border: pw.Border.all(color: color, width: 0.5),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: reg, fontSize: 6.5, color: _textMuted)),
          pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 6.5, color: color)),
        ],
      ),
    );
  }

  // ── Main Data Table ──

  static pw.Widget _buildAgentsTable({
    required List<ClearingAgentModel> agents,
    required double totalCurrentBalanceEgp,
    required double totalInitialBalanceEgp,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required pw.Font fontFallback,
  }) {
    final headers = [
      'طبيعة الرصيد',
      'الرصيد الحالي',
      'الرصيد الافتتاحي',
      'العملة',
      'رقم الهاتف',
      'نوع التخليص',
      'اسم مخلص الجمارك',
      'كود المخلص',
      'م',
    ];

    final tableData = <List<dynamic>>[];

    for (int i = 0; i < agents.length; i++) {
      final a = agents[i];
      final isCredit = a.balance > 0.0001;
      final isDebit = a.balance < -0.0001;
      final statusLabel = isCredit
          ? 'مستحق له'
          : (isDebit ? 'مدين / عليه' : 'متزن');

      final currSymbol = _getCurrencySymbol(a.currency);

      tableData.add([
        statusLabel,
        '${_currFmt.format(a.balance.abs())} $currSymbol',
        '${_currFmt.format(a.initialBalance.abs())} $currSymbol',
        a.currency.toUpperCase(),
        a.phone.isNotEmpty ? a.phone : '—',
        a.brokerType.isNotEmpty ? a.brokerType : 'بحري',
        a.name,
        a.code.isNotEmpty ? a.code : '—',
        '${i + 1}',
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: tableData,
      border: pw.TableBorder.all(color: _border, width: 0.5),
      headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _navy),
      headerHeight: 24,
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      oddRowDecoration: const pw.BoxDecoration(color: _zebraBg),
      cellHeight: 20,
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 8, color: _textDark),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.center,
        8: pw.Alignment.center,
      },
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2), // طبيعة الرصيد
        1: pw.FlexColumnWidth(1.5), // الرصيد الحالي
        2: pw.FlexColumnWidth(1.4), // الافتتاحي
        3: pw.FlexColumnWidth(0.8), // العملة
        4: pw.FlexColumnWidth(1.2), // الهاتف
        5: pw.FlexColumnWidth(1.1), // نوع التخليص
        6: pw.FlexColumnWidth(2.6), // الاسم
        7: pw.FlexColumnWidth(1.0), // الكود
        8: pw.FlexColumnWidth(0.5), // م
      },
    );
  }

  // ── Footer ──

  static pw.Widget _buildReportFooter({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة $pageNumber من $totalPages',
            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _textMuted),
          ),
          pw.Text(
            'كشف حساب مجمع - مخلصو الجمارك | $companyName',
            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: _navy),
          ),
          pw.Text(
            'نظام Fruity Farms ERP المالي والمحاسبي',
            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: _textMuted),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  static String _getCurrencySymbol(String curr) {
    switch (curr.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'EGP':
      default:
        return 'ج.م';
    }
  }

  static String _formattedFileName(String base) {
    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return '${base}_${d}_$t';
  }

  static Future<({pw.Font regular, pw.Font bold, pw.Font fallback})> _loadFonts() async {
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final fallbackFont = await PdfGoogleFonts.notoSansRegular();

      return (
        regular: pw.Font.ttf(regData),
        bold: pw.Font.ttf(boldData),
        fallback: fallbackFont,
      );
    } catch (_) {
      final reg = await PdfGoogleFonts.cairoRegular();
      final bold = await PdfGoogleFonts.cairoBold();
      final fallback = await PdfGoogleFonts.notoSansRegular();
      return (regular: reg, bold: bold, fallback: fallback);
    }
  }
}
