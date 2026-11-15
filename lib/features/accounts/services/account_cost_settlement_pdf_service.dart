// lib/features/accounts/services/account_cost_settlement_pdf_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Fruity Farms ERP — Professional Landscape A4 Cost Settlement PDF Service
// تسوية التكاليف التقديرية والفعلية لأوامر التعبئة والحسابات المالية
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext, TextEditingController;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/ui_utils.dart';
import '../../../core/utils/file_helper.dart';
import '../../../data/dao/settings_dao.dart';
import '../../../data/models/account_model.dart';

/// Data model representing a single cost settlement item for the PDF export
class CostSettlementPdfRow {
  final int index;
  final dynamic id;
  final String orderNumber;
  final String productName;
  final String itemName;
  final String category;
  final double estimatedCost;
  final double actualQuantity;
  final double actualUnitPrice;
  final double actualAmount;
  final double varianceAmount;
  final double variancePct;
  final DateTime? invoiceDateTime;
  final String notes;
  final bool isLocked;
  final String statusText;

  const CostSettlementPdfRow({
    required this.index,
    this.id,
    required this.orderNumber,
    required this.productName,
    required this.itemName,
    required this.category,
    required this.estimatedCost,
    required this.actualQuantity,
    required this.actualUnitPrice,
    required this.actualAmount,
    required this.varianceAmount,
    required this.variancePct,
    this.invoiceDateTime,
    required this.notes,
    required this.isLocked,
    required this.statusText,
  });
}

/// Professional PDF service for generating and printing Cost Settlement reports
/// in Landscape A4 orientation.
class AccountCostSettlementPdfService {
  AccountCostSettlementPdfService._();

  // ── Brand & Color Palette ─────────────────────────────────────────────────
  static const PdfColor _navyPrimary = PdfColor.fromInt(0xFF1A365D); // #1A365D Deep Navy
  static const PdfColor _navyLight   = PdfColor.fromInt(0xFF2B4C7E);
  static const PdfColor _cyanAccent  = PdfColor.fromInt(0xFF0284C7); // #0284C7 Sky/Cyan
  static const PdfColor _greenAccent = PdfColor.fromInt(0xFF059669); // #059669 Emerald
  static const PdfColor _greenBg     = PdfColor.fromInt(0xFFECFDF5);
  static const PdfColor _amberAccent = PdfColor.fromInt(0xFFD97706); // #D97706 Amber
  static const PdfColor _amberBg     = PdfColor.fromInt(0xFFFFFBEB);
  static const PdfColor _dangerAccent = PdfColor.fromInt(0xFFDC2626); // #DC2626 Red
  static const PdfColor _dangerBg    = PdfColor.fromInt(0xFFFEF2F2);
  static const PdfColor _textDark    = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const PdfColor _textMuted   = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const PdfColor _lightBg     = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const PdfColor _zebraBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const PdfColor _border      = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const PdfColor _white       = PdfColors.white;

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');
  static final intl.NumberFormat _qtyFmt  = intl.NumberFormat('#,##0.##', 'en_US');

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
  // RESOLVE ROW DATA FROM UI CONTROLLERS & MAPS
  // ──────────────────────────────────────────────────────────────────────────

  /// Helper to convert UI settlement items and their active controllers into
  /// strongly typed [CostSettlementPdfRow] items.
  static List<CostSettlementPdfRow> resolveRowsFromUi({
    required List<Map<String, dynamic>> items,
    required Map<dynamic, TextEditingController> actualControllers,
    required Map<dynamic, TextEditingController> qtyControllers,
    required Map<dynamic, TextEditingController> unitPriceControllers,
    required Map<dynamic, TextEditingController> notesControllers,
    required Map<dynamic, DateTime> itemDateTimes,
    Map<dynamic, List<double>>? unitPriceBreakdowns,
    required bool Function(Map<String, dynamic> item) isItemLockedFn,
    required double Function(Map<String, dynamic> item) getEstimatedCostFn,
  }) {
    final resolved = <CostSettlementPdfRow>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final key = item['id'];
      final poNum = item['order_number']?.toString() ?? '-';
      final poProd = item['product_name']?.toString() ?? '';
      final itemName = (item['name'] ?? item['item_name'] ?? 'بند تكلفة').toString();
      final category = (item['category'] ?? '').toString();

      final est = getEstimatedCostFn(item);

      final actCtrl = actualControllers[key] ??
          actualControllers[key?.toString()] ??
          actualControllers[int.tryParse(key?.toString() ?? '')];
      final qtyCtrl = qtyControllers[key] ??
          qtyControllers[key?.toString()] ??
          qtyControllers[int.tryParse(key?.toString() ?? '')];
      final upCtrl = unitPriceControllers[key] ??
          unitPriceControllers[key?.toString()] ??
          unitPriceControllers[int.tryParse(key?.toString() ?? '')];
      final notesCtrl = notesControllers[key] ??
          notesControllers[key?.toString()] ??
          notesControllers[int.tryParse(key?.toString() ?? '')];

      final rawAct = actCtrl?.text.replaceAll(',', '').trim() ?? '';
      final parsedAct = double.tryParse(rawAct);
      final dbAct = (item['actual_amount'] as num?)?.toDouble();
      final actVal = parsedAct ?? dbAct ?? 0.0;
      final hasActual = parsedAct != null || (dbAct != null && dbAct > 0) || rawAct.isNotEmpty;

      final rawQty = qtyCtrl?.text.replaceAll(',', '').trim() ?? '';
      final parsedQty = double.tryParse(rawQty);
      final dbQty = (item['actual_quantity'] as num?)?.toDouble();
      final qtyVal = parsedQty ?? dbQty ?? 1.0;

      final rawUp = upCtrl?.text.replaceAll(',', '').trim() ?? '';
      final parsedUp = double.tryParse(rawUp);
      final dbUp = (item['actual_unit_price'] as num?)?.toDouble() ?? (item['unit_price'] as num?)?.toDouble();
      final unitPriceVal = parsedUp ?? dbUp ?? (qtyVal > 0 && actVal > 0 ? actVal / qtyVal : 0.0);

      String notesVal = notesCtrl?.text.trim() ?? '';
      if (notesVal.isEmpty) {
        notesVal = (item['detailed_notes'] ?? item['settlement_notes'] ?? item['notes'] ?? '').toString();
      }
      if (notesVal == 'null') notesVal = '';

      final breakdown = unitPriceBreakdowns?[key] ?? unitPriceBreakdowns?[key?.toString()];
      if (breakdown != null && breakdown.length > 1 && breakdown.any((p) => p > 0)) {
        final bdStr = breakdown.map((p) => p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(2)).join(' + ');
        if (notesVal.isEmpty) {
          notesVal = 'تفاصيل الأسعار: $bdStr';
        } else if (!notesVal.contains(bdStr)) {
          notesVal = '$notesVal ($bdStr)';
        }
      }

      final dt = itemDateTimes[key] ??
          itemDateTimes[key?.toString()] ??
          (item['actual_date_time'] != null ? DateTime.tryParse(item['actual_date_time'].toString()) : null);

      final isLocked = isItemLockedFn(item);
      final varianceAmt = hasActual ? (actVal - est) : 0.0;
      final variancePct = (hasActual && est > 0) ? (varianceAmt / est) * 100 : 0.0;

      String statusText;
      if (isLocked) {
        statusText = 'معتمد ومقفل';
      } else if (hasActual && actVal > 0) {
        statusText = 'بانتظار الاعتماد';
      } else {
        statusText = 'بانتظار التسوية';
      }

      resolved.add(
        CostSettlementPdfRow(
          index: i + 1,
          id: key,
          orderNumber: poNum,
          productName: poProd,
          itemName: itemName,
          category: category,
          estimatedCost: est,
          actualQuantity: qtyVal,
          actualUnitPrice: unitPriceVal,
          actualAmount: actVal,
          varianceAmount: varianceAmt,
          variancePct: variancePct,
          invoiceDateTime: dt,
          notes: notesVal,
          isLocked: isLocked,
          statusText: statusText,
        ),
      );
    }

    return resolved;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIMARY PUBLIC API: PRINT & EXPORT
  // ──────────────────────────────────────────────────────────────────────────

  /// Generate, layout, and print the cost settlement report PDF in Landscape A4.
  static Future<void> printCostSettlementReport({
    required AccountModel account,
    required List<CostSettlementPdfRow> rows,
    String currency = 'EGP',
    String? companyName,
    String? orderRangeLabel,
  }) async {
    final bytes = await generateCostSettlementPdf(
      account: account,
      rows: rows,
      currency: currency,
      companyName: companyName,
      orderRangeLabel: orderRangeLabel,
    );

    final fileName = _formattedFileName('تسوية_تكاليف', account.code);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Save the cost settlement PDF directly to file in export directory.
  static Future<File> saveCostSettlementToFile(
    BuildContext context, {
    required AccountModel account,
    required List<CostSettlementPdfRow> rows,
    String currency = 'EGP',
    String? companyName,
    String? orderRangeLabel,
  }) async {
    final bytes = await generateCostSettlementPdf(
      account: account,
      rows: rows,
      currency: currency,
      companyName: companyName,
      orderRangeLabel: orderRangeLabel,
    );

    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('تسوية_تكاليف', account.code)}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ تقرير تسوية التكاليف بنجاح في:\n$path');
    }
    return file;
  }

  /// Compile and generate PDF document bytes formatted in Landscape A4.
  static Future<Uint8List> generateCostSettlementPdf({
    required AccountModel account,
    required List<CostSettlementPdfRow> rows,
    String currency = 'EGP',
    String? companyName,
    String? orderRangeLabel,
  }) async {
    final fonts = await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName(companyName);

    // Compute Overall Totals
    double totalEst = 0.0;
    double totalAct = 0.0;
    int lockedCount = 0;
    int pendingCount = 0;
    final distinctOrders = <String>{};

    for (final r in rows) {
      totalEst += r.estimatedCost;
      totalAct += r.actualAmount;
      if (r.isLocked) {
        lockedCount++;
      } else {
        pendingCount++;
      }
      if (r.orderNumber.isNotEmpty && r.orderNumber != '-') {
        distinctOrders.add(r.orderNumber);
      }
    }

    final netVariance = totalAct - totalEst;
    final netVariancePct = totalEst > 0 ? (netVariance / totalEst) * 100 : 0.0;

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
          account: account,
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
            currency: currency,
            ordersCount: distinctOrders.length,
            itemsCount: rows.length,
            orderRangeLabel: orderRangeLabel,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 8),

          // 2. 4-Pillar Financial KPI Summary Cards
          _buildKpiSummaryCards(
            totalEstimated: totalEst,
            totalActual: totalAct,
            netVariance: netVariance,
            netVariancePct: netVariancePct,
            lockedCount: lockedCount,
            pendingCount: pendingCount,
            distinctOrdersCount: distinctOrders.length,
            currency: currency,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 3. Itemized Settlement Table
          _buildItemizedSettlementTable(
            rows: rows,
            totalEstimated: totalEst,
            totalActual: totalAct,
            netVariance: netVariance,
            netVariancePct: netVariancePct,
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
    required AccountModel account,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final now = DateTime.now();
    final printDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

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
                'الإدارة المالية — إدارة التكاليف والمحاسبة الإدارية',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontRegular, fontSize: 7, color: _textMuted),
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
                  'تقرير تسوية التكاليف (التقديري / الفعلي)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: _white),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'مطابقة التكاليف التقديرية بأوامر التعبئة مع الفواتير الفعلية ومصادقة الفروق',
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
                  'الحساب: ${account.code} - ${account.name}',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ الاستخراج: $printDateStr',
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
    required String currency,
    required int ordersCount,
    required int itemsCount,
    String? orderRangeLabel,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
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

          // Badges: Nature, Currency, Orders Count, Items Count, Optional Order Range
          pw.Row(
            children: [
              if (orderRangeLabel != null && orderRangeLabel.isNotEmpty) ...[
                _badgeItem('نطاق الأوامر:', orderRangeLabel, _navyPrimary, fontBold, fontRegular),
                pw.SizedBox(width: 6),
              ],
              _badgeItem('طبيعة الحساب:', natureLabel, _cyanAccent, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('العملة:', currency, _greenAccent, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('أوامر التعبئة:', '$ordersCount أمر', _navyPrimary, fontBold, fontRegular),
              pw.SizedBox(width: 6),
              _badgeItem('إجمالي البنود:', '$itemsCount بند مسجل', _textDark, fontBold, fontRegular),
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
  // 4-PILLAR KPI SUMMARY CARDS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildKpiSummaryCards({
    required double totalEstimated,
    required double totalActual,
    required double netVariance,
    required double netVariancePct,
    required int lockedCount,
    required int pendingCount,
    required int distinctOrdersCount,
    required String currency,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final isSaving = netVariance < 0 && totalEstimated > 0;
    final isOverrun = netVariance > 0 && totalEstimated > 0;

    final varianceStatusLabel = isSaving
        ? 'وفر في التكاليف (-)'
        : (isOverrun ? 'تجاوز/عجز في التكاليف (+)' : 'تكاليف متطابقة تماماً');

    final varianceAccentColor = isSaving
        ? _greenAccent
        : (isOverrun ? _dangerAccent : _cyanAccent);

    final varianceBgColor = isSaving
        ? _greenBg
        : (isOverrun ? _dangerBg : _lightBg);

    final varianceSign = netVariance > 0 ? '+' : '';

    return pw.Row(
      children: [
        // 1. Total Estimated Cost
        pw.Expanded(
          child: _kpiCard(
            title: 'إجمالي التكلفة التقديرية (المقدر)',
            amountStr: '${_currFmt.format(totalEstimated)} $currency',
            subtitle: 'المسجل مبدئياً بأوامر التعبئة',
            accentColor: _navyLight,
            bgColor: _lightBg,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 2. Total Actual Cost
        pw.Expanded(
          child: _kpiCard(
            title: 'إجمالي التكلفة الفعلية (الفعلي)',
            amountStr: '${_currFmt.format(totalActual)} $currency',
            subtitle: 'المعتمد بالفواتير الفعلية للمصروفات',
            accentColor: _cyanAccent,
            bgColor: _lightBg,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 3. Net Variance & Deviation %
        pw.Expanded(
          child: _kpiCard(
            title: 'صافي الانحراف والفروق الحسابية',
            amountStr: '$varianceSign${_currFmt.format(netVariance)} $currency ($varianceSign${netVariancePct.toStringAsFixed(1)}%)',
            subtitle: varianceStatusLabel,
            accentColor: varianceAccentColor,
            bgColor: varianceBgColor,
            fontBold: fontBold,
            fontRegular: fontRegular,
          ),
        ),
        pw.SizedBox(width: 6),

        // 4. Approval & Audit Status
        pw.Expanded(
          child: _kpiCard(
            title: 'حالة التسوية والاعتماد المالي',
            amountStr: '$lockedCount معتمد ومقفل',
            subtitle: '$pendingCount بانتظار التسوية | $distinctOrdersCount أمر تعبئة',
            accentColor: pendingCount == 0 ? _greenAccent : _amberAccent,
            bgColor: pendingCount == 0 ? _greenBg : _amberBg,
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
              fontSize: isProminent ? 10.5 : 9.5,
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
  // ITEMIZED SETTLEMENT TABLE
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildItemizedSettlementTable({
    required List<CostSettlementPdfRow> rows,
    required double totalEstimated,
    required double totalActual,
    required double netVariance,
    required double netVariancePct,
    required String currency,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    // In PDF RTL Landscape layout, column indices are physically placed from Left (0) to Right (10).
    // For an Arabic reader reading from Right to Left:
    // Rightmost is Index 10: 'م' (Serial #)
    // Leftmost is Index 0: 'مؤشر الحالة' (Status)
    final headers = [
      'مؤشر الحالة',
      'البيان والملاحظات التفصيلية',
      'تاريخ ووقت الفاتورة',
      'الفارق الحسابي (%)',
      'التكلفة الفعلية',
      'سعر الوحدة',
      'الكمية',
      'التكلفة التقديرية',
      'بند التكلفة والتصنيف',
      'أمر التعبئة / المحصول',
      'م',
    ];

    final tableData = <List<dynamic>>[];

    for (final r in rows) {
      final varianceSign = r.varianceAmount > 0 ? '+' : '';

      final varianceDisplay = r.actualAmount > 0
          ? '$varianceSign${_currFmt.format(r.varianceAmount)} ($varianceSign${r.variancePct.toStringAsFixed(1)}%)'
          : 'بانتظار الفاتورة';

      final dtStr = r.invoiceDateTime != null
          ? '${r.invoiceDateTime!.year}-${r.invoiceDateTime!.month.toString().padLeft(2, '0')}-${r.invoiceDateTime!.day.toString().padLeft(2, '0')} '
              '${r.invoiceDateTime!.hour.toString().padLeft(2, '0')}:${r.invoiceDateTime!.minute.toString().padLeft(2, '0')}'
          : '—';

      final orderDisplay = r.productName.isNotEmpty
          ? 'أمر #${r.orderNumber}\n(${r.productName})'
          : 'أمر #${r.orderNumber}';

      final itemDisplay = r.category.isNotEmpty
          ? '${r.itemName}\n[${r.category}]'
          : r.itemName;

      final estStr = _currFmt.format(r.estimatedCost);
      final qtyStr = r.actualQuantity > 0 ? _qtyFmt.format(r.actualQuantity) : '—';
      final unitPriceStr = r.actualUnitPrice > 0 ? _currFmt.format(r.actualUnitPrice) : '—';
      final actStr = r.actualAmount > 0 ? _currFmt.format(r.actualAmount) : '—';
      final notesDisplay = r.notes.isNotEmpty ? r.notes : '—';

      final statusBadgeText = r.isLocked
          ? 'معتمد ومقفل'
          : (r.actualAmount > 0 ? 'بانتظار الاعتماد' : 'بانتظار التسوية');

      // Map cells to match the header columns 0..10
      tableData.add([
        statusBadgeText,                                  // Col 0: مؤشر الحالة (Leftmost)
        notesDisplay,                                     // Col 1: البيان والملاحظات
        dtStr,                                            // Col 2: تاريخ ووقت الفاتورة
        varianceDisplay,                                  // Col 3: الفارق الحسابي (%)
        actStr,                                           // Col 4: التكلفة الفعلية
        unitPriceStr,                                     // Col 5: سعر الوحدة
        qtyStr,                                           // Col 6: الكمية
        estStr,                                           // Col 7: التكلفة التقديرية
        itemDisplay,                                      // Col 8: بند التكلفة والتصنيف
        orderDisplay,                                     // Col 9: أمر التعبئة / المحصول
        '${r.index}',                                     // Col 10: م (Rightmost)
      ]);
    }

    final isSavingTotal = netVariance < 0 && totalEstimated > 0;
    final isOverrunTotal = netVariance > 0 && totalEstimated > 0;
    final varianceSignTotal = netVariance > 0 ? '+' : '';

    return pw.Column(
      children: [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: tableData,
          border: pw.TableBorder.all(color: _border, width: 0.5),
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 7.2, color: _white),
          headerDecoration: const pw.BoxDecoration(color: _navyPrimary),
          headerHeight: 22,
          rowDecoration: const pw.BoxDecoration(color: _white),
          oddRowDecoration: const pw.BoxDecoration(color: _zebraBg),
          cellHeight: 20,
          cellStyle: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _textDark),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {
            0: pw.Alignment.center,      // مؤشر الحالة
            1: pw.Alignment.centerRight, // البيان والملاحظات التفصيلية
            2: pw.Alignment.center,      // تاريخ ووقت الفاتورة
            3: pw.Alignment.center,      // الفارق الحسابي (%)
            4: pw.Alignment.centerLeft,  // التكلفة الفعلية
            5: pw.Alignment.centerLeft,  // سعر الوحدة
            6: pw.Alignment.center,      // الكمية
            7: pw.Alignment.centerLeft,  // التكلفة التقديرية
            8: pw.Alignment.centerRight, // بند التكلفة والتصنيف
            9: pw.Alignment.centerRight, // أمر التعبئة / المحصول
            10: pw.Alignment.center,     // م
          },
          columnWidths: const {
            0: pw.FlexColumnWidth(0.9),  // مؤشر الحالة
            1: pw.FlexColumnWidth(2.0),  // البيان والملاحظات التفصيلية
            2: pw.FlexColumnWidth(1.15), // تاريخ ووقت الفاتورة
            3: pw.FlexColumnWidth(1.3),  // الفارق الحسابي (%)
            4: pw.FlexColumnWidth(1.1),  // التكلفة الفعلية
            5: pw.FlexColumnWidth(0.85), // سعر الوحدة
            6: pw.FlexColumnWidth(0.65), // الكمية
            7: pw.FlexColumnWidth(1.1),  // التكلفة التقديرية
            8: pw.FlexColumnWidth(1.4),  // بند التكلفة والتصنيف
            9: pw.FlexColumnWidth(1.6),  // أمر التعبئة / المحصول
            10: pw.FlexColumnWidth(0.35),// م
          },
        ),

        // Total Summary Row at bottom of table
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _lightBg,
            border: pw.Border.all(color: _border, width: 0.7),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Left: Total Status summary
              pw.Row(
                children: [
                  pw.Text(
                    'إجمالي البنود: ${rows.length} بند',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    'صافي الفروق: $varianceSignTotal${_currFmt.format(netVariance)} $currency ($varianceSignTotal${netVariancePct.toStringAsFixed(1)}%)',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 8,
                      color: isSavingTotal ? _greenAccent : (isOverrunTotal ? _dangerAccent : _navyPrimary),
                    ),
                  ),
                ],
              ),

              // Right: Total Estimated vs Actual
              pw.Row(
                children: [
                  pw.Text(
                    'إجمالي التقديري: ${_currFmt.format(totalEstimated)} $currency',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: _navyPrimary),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Text(
                    'إجمالي الفعلي: ${_currFmt.format(totalActual)} $currency',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: _cyanAccent),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Text(
                    'الإجمالي العام المعتمد:',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: _textDark),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FINANCIAL AUDIT & CONTROL SIGNATURES
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildAuditSignaturesBlock({
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _signatureColumn('اعتماد المدير المالي والإداري', 'CFO / Financial Approval', fontBold, fontRegular),
          pw.Container(width: 0.8, height: 42, color: _border),
          _signatureColumn('المراجعة والتدقيق المالي الداخلي', 'Internal Financial Audit', fontBold, fontRegular),
          pw.Container(width: 0.8, height: 42, color: _border),
          _signatureColumn('إعداد المحاسب المسؤول', 'Prepared by Accountant', fontBold, fontRegular),
        ],
      ),
    );
  }

  static pw.Widget _signatureColumn(
    String arTitle,
    String enTitle,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            arTitle,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
          ),
          pw.Text(
            enTitle,
            style: pw.TextStyle(font: fontRegular, fontSize: 5.5, color: _textMuted),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            width: 130,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.8)),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'التوقيع والتاريخ: .......................................',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 5.8, color: _textMuted),
          ),
        ],
      ),
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
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'صفحة $pageNumber من $totalPages',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _textMuted),
          ),
          pw.Text(
            'نظام Fruity Farms ERP لإدارة الحسابات والتكاليف — تقرير معتمد للاستخدام الداخلي والمحاسبي',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _textMuted),
          ),
          pw.Text(
            companyName,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: _navyPrimary),
          ),
        ],
      ),
    );
  }
}
