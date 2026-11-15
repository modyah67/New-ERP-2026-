// lib/core/cost_settlement_pdf_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Fruity Farms ERP — Professional Landscape A4 Supplier Cost Settlement PDF Service
// تسوية التكاليف الفعلية والتقديرية لموردي المحطات والتخصيمات
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/dao/settings_dao.dart';
import 'widgets/order_range_filter_field.dart';
import '../data/models/supplier_expected_cost_item_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

/// Professional PDF service for generating and printing Supplier Cost Settlement reports
/// in Landscape A4 orientation.
class CostSettlementPdfService {
  CostSettlementPdfService._();

  // ── Brand & Color Palette ─────────────────────────────────────────────────
  static const PdfColor _navyPrimary  = PdfColor.fromInt(0xFF1A365D); // #1A365D Deep Navy
  static const PdfColor _navyLight    = PdfColor.fromInt(0xFF2B4C7E);
  static const PdfColor _cyanAccent   = PdfColor.fromInt(0xFF0284C7); // #0284C7 Sky/Cyan
  static const PdfColor _greenAccent  = PdfColor.fromInt(0xFF059669); // #059669 Emerald
  static const PdfColor _greenBg      = PdfColor.fromInt(0xFFECFDF5);
  static const PdfColor _amberAccent  = PdfColor.fromInt(0xFFD97706); // #D97706 Amber
  static const PdfColor _amberBg      = PdfColor.fromInt(0xFFFFFBEB);
  static const PdfColor _dangerAccent = PdfColor.fromInt(0xFFDC2626); // #DC2626 Red
  static const PdfColor _dangerBg     = PdfColor.fromInt(0xFFFEF2F2);
  static const PdfColor _textDark     = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const PdfColor _textMuted    = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const PdfColor _lightBg      = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const PdfColor _zebraBg      = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const PdfColor _border       = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const PdfColor _white        = PdfColors.white;

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

  static Future<String> _resolveCompanyName() async {
    try {
      final settings = await SettingsDao().getAllSettings();
      final name = settings['company_name'] ?? settings['companyName'];
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    } catch (_) {}
    return 'مزارع فروتي فارمز لتصدير الحاصلات الزراعية';
  }

  static String _formattedFileName(String title, String supplierKey) {
    final now = DateTime.now();
    final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return '${title}_${supplierKey}_${d}_$t';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIMARY PUBLIC API: PRINT & EXPORT
  // ──────────────────────────────────────────────────────────────────────────

  /// Print the supplier cost settlement report directly via layout dialog.
  static Future<void> printPdf({
    required List<SupplierExpectedCostItemModel> items,
    required String supplierType,
    String? supplierName,
    String? supplierCode,
    DateTime? fromDate,
    DateTime? toDate,
    int? fromOrderId,
    int? toOrderId,
    Map<dynamic, double>? actualAmounts,
    Map<dynamic, double>? quantities,
    Map<dynamic, double>? unitPrices,
    Map<dynamic, String>? notes,
    Map<dynamic, DateTime>? dateTimes,
    Map<dynamic, List<double>>? unitPriceBreakdowns,
    Map<dynamic, bool>? lockedMap,
    String locale = 'ar',
  }) async {
    final bytes = await build(
      items: items,
      supplierType: supplierType,
      supplierName: supplierName,
      supplierCode: supplierCode,
      fromDate: fromDate,
      toDate: toDate,
      fromOrderId: fromOrderId,
      toOrderId: toOrderId,
      actualAmounts: actualAmounts,
      quantities: quantities,
      unitPrices: unitPrices,
      notes: notes,
      dateTimes: dateTimes,
      unitPriceBreakdowns: unitPriceBreakdowns,
      lockedMap: lockedMap,
      locale: locale,
    );

    final cleanKey = supplierCode?.isNotEmpty == true
        ? supplierCode!
        : (supplierName?.isNotEmpty == true ? supplierName! : 'all');
    final fileName = _formattedFileName('تسوية_تكاليف_المحطات', cleanKey);

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Save the PDF document to disk in export directory.
  static Future<File> saveToFile({
    required List<SupplierExpectedCostItemModel> items,
    required String supplierType,
    String? supplierName,
    String? supplierCode,
    DateTime? fromDate,
    DateTime? toDate,
    int? fromOrderId,
    int? toOrderId,
    Map<dynamic, double>? actualAmounts,
    Map<dynamic, double>? quantities,
    Map<dynamic, double>? unitPrices,
    Map<dynamic, String>? notes,
    Map<dynamic, DateTime>? dateTimes,
    Map<dynamic, List<double>>? unitPriceBreakdowns,
    Map<dynamic, bool>? lockedMap,
    String locale = 'ar',
  }) async {
    final bytes = await build(
      items: items,
      supplierType: supplierType,
      supplierName: supplierName,
      supplierCode: supplierCode,
      fromDate: fromDate,
      toDate: toDate,
      fromOrderId: fromOrderId,
      toOrderId: toOrderId,
      actualAmounts: actualAmounts,
      quantities: quantities,
      unitPrices: unitPrices,
      notes: notes,
      dateTimes: dateTimes,
      unitPriceBreakdowns: unitPriceBreakdowns,
      lockedMap: lockedMap,
      locale: locale,
    );

    final dir = await FileHelper.getExportDirectory();
    final cleanKey = supplierCode?.isNotEmpty == true
        ? supplierCode!
        : (supplierName?.isNotEmpty == true ? supplierName! : 'all');
    final fileName = '${_formattedFileName('تسوية_تكاليف_المحطات', cleanKey)}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Build the PDF bytes for the Actual vs Expected cost variance report in Landscape A4.
  static Future<Uint8List> build({
    required List<SupplierExpectedCostItemModel> items,
    required String supplierType,
    String? supplierName,
    String? supplierCode,
    DateTime? fromDate,
    DateTime? toDate,
    int? fromOrderId,
    int? toOrderId,
    Map<dynamic, double>? actualAmounts,
    Map<dynamic, double>? quantities,
    Map<dynamic, double>? unitPrices,
    Map<dynamic, String>? notes,
    Map<dynamic, DateTime>? dateTimes,
    Map<dynamic, List<double>>? unitPriceBreakdowns,
    Map<dynamic, bool>? lockedMap,
    String locale = 'ar',
  }) async {
    final fonts = await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName();

    // ── Filter by date range and order range if provided ──
    final filtered = items.where((item) {
      if (fromDate != null && item.orderDate != null) {
        if (item.orderDate!.isBefore(fromDate)) return false;
      }
      if (toDate != null && item.orderDate != null) {
        final endOfDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
        if (item.orderDate!.isAfter(endOfDay)) return false;
      }
      if (!OrderRangeFilterHelper.matchesOrderRange(
        orderNumber: item.orderNumber,
        packingOrderId: item.packingOrderId,
        fromOrderId: fromOrderId,
        toOrderId: toOrderId,
      )) {
        return false;
      }
      return true;
    }).toList();

    // ── Compute KPIs ──
    double totalExpected = 0.0;
    double totalActual = 0.0;
    int pendingCount = 0;
    int settledCount = 0;
    final distinctOrders = <String>{};

    for (final item in filtered) {
      final key = item.costItemId;
      totalExpected += item.expectedAmount;
      if (item.orderNumber.isNotEmpty) distinctOrders.add(item.orderNumber);

      final actVal = actualAmounts?[key] ?? (item.isActual ? item.actualAmount : null);
      final isLocked = lockedMap?[key] ?? (item.isActual && item.actualAmount != null && item.actualAmount! > 0);

      if (actVal != null && actVal > 0) {
        totalActual += actVal;
      }

      if (isLocked) {
        settledCount++;
      } else {
        pendingCount++;
      }
    }

    final netVariance = totalActual - totalExpected;
    final netVariancePct = totalExpected > 0 ? (netVariance / totalExpected) * 100 : 0.0;

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
          supplierType: supplierType,
          supplierName: supplierName,
          supplierCode: supplierCode,
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
          // 1. Entity Metadata Banner
          _buildEntityMetaCard(
            supplierType: supplierType,
            supplierName: supplierName,
            supplierCode: supplierCode,
            fromDate: fromDate,
            toDate: toDate,
            fromOrderId: fromOrderId,
            toOrderId: toOrderId,
            ordersCount: distinctOrders.length,
            itemsCount: filtered.length,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 8),

          // 2. 4-Pillar Financial KPI Summary Cards
          _buildKpiSummaryCards(
            totalEstimated: totalExpected,
            totalActual: totalActual,
            netVariance: netVariance,
            netVariancePct: netVariancePct,
            lockedCount: settledCount,
            pendingCount: pendingCount,
            distinctOrdersCount: distinctOrders.length,
            currency: 'EGP',
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 10),

          // 3. Itemized Settlement Table
          _buildItemizedSettlementTable(
            items: filtered,
            totalEstimated: totalExpected,
            totalActual: totalActual,
            netVariance: netVariance,
            netVariancePct: netVariancePct,
            actualAmounts: actualAmounts,
            quantities: quantities,
            unitPrices: unitPrices,
            notes: notes,
            dateTimes: dateTimes,
            unitPriceBreakdowns: unitPriceBreakdowns,
            lockedMap: lockedMap,
            currency: 'EGP',
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
          ),
          pw.SizedBox(height: 12),

          // 4. Financial Audit & Control Triple Signatures Block
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
    required String supplierType,
    required String? supplierName,
    required String? supplierCode,
    required int pageNumber,
    required int totalPages,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final now = DateTime.now();
    final printDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final typeLabel = supplierType == 'station' ? 'موردي المحطات (Station Suppliers)' : 'موردي التخصيمات';
    final targetLabel = supplierName != null && supplierName.isNotEmpty
        ? 'المورد: $supplierName${supplierCode != null && supplierCode.isNotEmpty ? " ($supplierCode)" : ""}'
        : 'كافة $typeLabel';

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
                'الإدارة المالية — إدارة التكاليف ومراقبة حسابات الموردين',
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
                  'تقرير تسوية التكاليف الفعلية والتقديرية - $typeLabel',
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
                  targetLabel,
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

  static pw.Widget _buildEntityMetaCard({
    required String supplierType,
    required String? supplierName,
    required String? supplierCode,
    required DateTime? fromDate,
    required DateTime? toDate,
    int? fromOrderId,
    int? toOrderId,
    required int ordersCount,
    required int itemsCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final orderRangeStr = OrderRangeFilterHelper.formatRangeLabel(
      fromOrderId: fromOrderId,
      toOrderId: toOrderId,
    );
    final typeLabel = supplierType == 'station' ? 'مورد محطة' : 'مورد تخصيمات';
    final hasSupplier = supplierName != null && supplierName.isNotEmpty;
    final periodStr = (fromDate != null && toDate != null)
        ? '${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')} — ${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}'
        : (fromDate != null
            ? 'من ${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}'
            : (toDate != null ? 'حتى ${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}' : 'كافة الفترات'));

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
          // Supplier identity
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  hasSupplier ? (supplierCode ?? '—') : 'ALL',
                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: _white),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                hasSupplier ? '$typeLabel: $supplierName' : 'كافة موردي المحطات والتشغيل',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: _navyPrimary),
              ),
            ],
          ),

          // Badges: Period, Currency, Orders Count, Items Count
          pw.Row(
            children: [
              _badgeItem('الفترة:', periodStr, _cyanAccent, fontBold, fontRegular),
              if (orderRangeStr != null) ...[
                pw.SizedBox(width: 6),
                _badgeItem('نطاق الأوامر:', orderRangeStr, _navyPrimary, fontBold, fontRegular),
              ],
              pw.SizedBox(width: 6),
              _badgeItem('العملة:', 'EGP', _greenAccent, fontBold, fontRegular),
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
  // 4-PILLAR FINANCIAL KPI SUMMARY CARDS
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
  // ITEMIZED SETTLEMENT TABLE (11 COLUMNS IN RTL)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildItemizedSettlementTable({
    required List<SupplierExpectedCostItemModel> items,
    required double totalEstimated,
    required double totalActual,
    required double netVariance,
    required double netVariancePct,
    Map<dynamic, double>? actualAmounts,
    Map<dynamic, double>? quantities,
    Map<dynamic, double>? unitPrices,
    Map<dynamic, String>? notes,
    Map<dynamic, DateTime>? dateTimes,
    Map<dynamic, List<double>>? unitPriceBreakdowns,
    Map<dynamic, bool>? lockedMap,
    required String currency,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    final headers = [
      'مؤشر الحالة',
      'البيان والملاحظات التفصيلية',
      'تاريخ ووقت الفاتورة',
      'الفارق الحسابي (%)',
      'التكلفة الفعلية',
      'سعر الوحدة',
      'الكمية',
      'التكلفة التقديرية',
      'المورد / بند التكلفة والتصنيف',
      'أمر التعبئة / الشحنة',
      'م',
    ];

    final tableData = <List<dynamic>>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final key = item.costItemId;

      final double est = item.expectedAmount;
      final double actVal = actualAmounts?[key] ?? (item.isActual ? (item.actualAmount ?? 0.0) : 0.0);
      final bool hasActual = actVal > 0 || (actualAmounts != null && actualAmounts.containsKey(key));
      final double varianceAmt = hasActual ? (actVal - est) : 0.0;
      final double variancePct = (hasActual && est > 0) ? (varianceAmt / est) * 100 : 0.0;
      final varianceSign = varianceAmt > 0 ? '+' : '';

      final varianceDisplay = hasActual && actVal > 0
          ? '$varianceSign${_currFmt.format(varianceAmt)} ($varianceSign${variancePct.toStringAsFixed(1)}%)'
          : 'بانتظار الفاتورة';

      final dt = dateTimes?[key] ?? item.reconciledAt ?? item.orderDate;
      final dtStr = dt != null
          ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '—';

      // Order display
      String orderDisplay = 'أمر #${item.orderNumber}';
      if (item.linkedShipments.isNotEmpty) {
        final shipNo = item.linkedShipments.first['shipment_no'] ?? item.linkedShipments.first['shipment_id'];
        if (shipNo != null) orderDisplay += '\n(شحنة #$shipNo)';
      }

      // Supplier and item display
      String itemDisplay = item.itemName;
      if (item.supplierName != null && item.supplierName!.isNotEmpty) {
        itemDisplay += '\n[${item.supplierName}${item.supplierCode != null ? " (${item.supplierCode})" : ""}]';
      } else if (item.category.isNotEmpty) {
        itemDisplay += '\n[${item.category}]';
      }

      final double qVal = quantities?[key] ?? item.displayQuantity;
      final double uPrice = unitPrices?[key] ?? item.displayUnitPrice;

      final estStr = _currFmt.format(est);
      final qtyStr = qVal > 0 ? _qtyFmt.format(qVal) : '—';
      final unitPriceStr = uPrice > 0 ? _currFmt.format(uPrice) : '—';
      final actStr = actVal > 0 ? _currFmt.format(actVal) : '—';

      final controllerNote = notes?[key]?.trim();
      String notesDisplay = (controllerNote != null && controllerNote.isNotEmpty)
          ? controllerNote
          : (item.detailedNotes?.trim().isNotEmpty == true
              ? item.detailedNotes!.trim()
              : (item.settlementNotes?.trim().isNotEmpty == true
                  ? item.settlementNotes!.trim()
                  : (item.invoiceRef?.trim() ?? '')));
      final breakdown = unitPriceBreakdowns?[key];
      if (breakdown != null && breakdown.length > 1 && breakdown.any((p) => p > 0)) {
        final bdStr = breakdown.map((p) => p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(2)).join(' + ');
        if (notesDisplay.isEmpty) {
          notesDisplay = 'الأسعار: $bdStr';
        } else if (!notesDisplay.contains(bdStr)) {
          notesDisplay = '$notesDisplay ($bdStr)';
        }
      }
      if (notesDisplay.isEmpty) notesDisplay = '—';

      final isLocked = lockedMap?[key] ?? (item.isActual && item.actualAmount != null && item.actualAmount! > 0);
      final statusBadgeText = isLocked
          ? 'معتمد ومقفل'
          : (actVal > 0 ? 'بانتظار الاعتماد' : 'بانتظار التسوية');

      tableData.add([
        statusBadgeText,                                  // Col 0: مؤشر الحالة (Leftmost)
        notesDisplay,                                     // Col 1: البيان والملاحظات
        dtStr,                                            // Col 2: تاريخ ووقت الفاتورة
        varianceDisplay,                                  // Col 3: الفارق الحسابي (%)
        actStr,                                           // Col 4: التكلفة الفعلية
        unitPriceStr,                                     // Col 5: سعر الوحدة
        qtyStr,                                           // Col 6: الكمية
        estStr,                                           // Col 7: التكلفة التقديرية
        itemDisplay,                                      // Col 8: المورد / بند التكلفة
        orderDisplay,                                     // Col 9: أمر التعبئة / الشحنة
        '${i + 1}',                                       // Col 10: م (Rightmost)
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
            8: pw.Alignment.centerRight, // المورد / بند التكلفة
            9: pw.Alignment.centerRight, // أمر التعبئة / الشحنة
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
            8: pw.FlexColumnWidth(1.4),  // المورد / بند التكلفة
            9: pw.FlexColumnWidth(1.6),  // أمر التعبئة / الشحنة
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
                    'إجمالي البنود: ${items.length} بند',
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
