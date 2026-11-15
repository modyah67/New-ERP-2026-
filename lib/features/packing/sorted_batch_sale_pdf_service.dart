// lib/features/packing/sorted_batch_sale_pdf_service.dart
// Professional Landscape A4 PDF Service for Produce Sorting & Grade Sales (إذن بيع الفرزة / المحصول المفرز)
// Fruity Farms ERP System

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
import '../../data/models/packing_order_sorting_model.dart';

/// Data class holding sorting sale receipt parameters
class SortedBatchSaleDetails {
  final PackingOrderSortingModel sorting;
  final String? customerName;
  final String? journalEntryNumber;
  final String? journalEntryId;
  final String? treasuryName;
  final double? customSoldQty;
  final double? customUnitPrice;
  final double? customTotalAmount;
  final DateTime? saleDate;
  final String? notes;
  final String currency;
  final String? unit; // e.g. 'كجم' or 'كرتونة'

  const SortedBatchSaleDetails({
    required this.sorting,
    this.customerName,
    this.journalEntryNumber,
    this.journalEntryId,
    this.treasuryName,
    this.customSoldQty,
    this.customUnitPrice,
    this.customTotalAmount,
    this.saleDate,
    this.notes,
    this.currency = 'EGP',
    this.unit,
  });

  String get effectiveUnit =>
      unit ?? SortedBatchSalePdfService.resolveUnit(sorting);

  bool get isCarton => SortedBatchSalePdfService.isCartonUnit(effectiveUnit);

  double get soldWeightKg =>
      customSoldQty ?? (sorting.weightKg - sorting.remainingWeightKg);

  double get totalSaleValue =>
      customTotalAmount ?? sorting.totalSaleAmount;

  double get unitSalePrice {
    if (customUnitPrice != null && customUnitPrice! > 0) {
      return customUnitPrice!;
    }
    final qty = soldWeightKg;
    if (qty > 0 && totalSaleValue > 0) {
      return totalSaleValue / qty;
    }
    return sorting.costPerKg;
  }
}

/// Data class holding segregated aggregation metrics for sorted produce sales.
class SortedBatchSaleSummary {
  final int totalCount;
  final int soldCount;

  // Weight segregation (كجم / طن)
  final double totalOriginalWeight;
  final double totalSoldWeight;
  final double totalRemainingWeight;

  // Carton / Packaging count segregation (كرتونة / صندوق)
  final double totalOriginalCartons;
  final double totalSoldCartons;
  final double totalRemainingCartons;

  // Financial metrics
  final double totalSalesRevenue;
  final Map<String, double> revenueByCurrency;

  const SortedBatchSaleSummary({
    required this.totalCount,
    required this.soldCount,
    required this.totalOriginalWeight,
    required this.totalSoldWeight,
    required this.totalRemainingWeight,
    required this.totalOriginalCartons,
    required this.totalSoldCartons,
    required this.totalRemainingCartons,
    required this.totalSalesRevenue,
    required this.revenueByCurrency,
  });

  bool get hasCartons => totalOriginalCartons > 0 || totalSoldCartons > 0;
  bool get hasWeights => totalOriginalWeight > 0 || totalSoldWeight > 0;
}

class SortedBatchSalePdfService {
  SortedBatchSalePdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Corporate Fruity Farms Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static const PdfColor _navyPrimary  = PdfColor.fromInt(0xFF1A365D); // #1A365D Deep Navy
  static const PdfColor _cyanAccent   = PdfColor.fromInt(0xFF0284C7); // #0284C7 Cyan
  static const PdfColor _cardBg       = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const PdfColor _lightBg      = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const PdfColor _zebraBg      = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _borderColor  = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const PdfColor _darkText     = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const PdfColor _mutedText    = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const PdfColor _white        = PdfColors.white;

  static const PdfColor _successGreen = PdfColor.fromInt(0xFF059669); // Emerald 600
  static const PdfColor _successBg    = PdfColor.fromInt(0xFFECFDF5); // Emerald 50
  static const PdfColor _warningAmber = PdfColor.fromInt(0xFFD97706); // Amber 600

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');
  static final intl.NumberFormat _qtyFmt  = intl.NumberFormat('#,##0.0#', 'en_US');

  // ──────────────────────────────────────────────────────────────────────────
  // UNIT DETECTION & SEGREGATION HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Determines whether a given unit string represents packaging/count units.
  static bool isCartonUnit(String? unit) {
    if (unit == null) return false;
    final u = unit.toLowerCase().trim();
    return u.contains('كرتون') ||
        u.contains('كراتين') ||
        u.contains('صندوق') ||
        u.contains('صناديق') ||
        u.contains('طرد') ||
        u.contains('طرود') ||
        u.contains('علب') ||
        u.contains('علبة') ||
        u.contains('box') ||
        u.contains('carton') ||
        u.contains('وحدة') ||
        u.contains('وحدات') ||
        u.contains('crt') ||
        u.contains('pkg');
  }

  /// Resolves the canonical unit label for a sorting item.
  static String resolveUnit(PackingOrderSortingModel sorting, [String? explicitUnit]) {
    if (explicitUnit != null && explicitUnit.trim().isNotEmpty) {
      return explicitUnit.trim();
    }
    final name = sorting.productName.toLowerCase();
    final lot = (sorting.lotNumber ?? '').toLowerCase();
    if (isCartonUnit(name) || isCartonUnit(lot)) {
      return 'كرتونة';
    }
    return 'كجم';
  }

  /// Computes segregated aggregation metrics separating weight from packaging count units.
  static SortedBatchSaleSummary computeSummary(
    List<PackingOrderSortingModel> items, {
    String defaultCurrency = 'EGP',
    Map<int, String>? unitOverrides,
  }) {
    final totalCount = items.length;
    int soldCount = 0;

    double totalOriginalWeight = 0.0;
    double totalSoldWeight = 0.0;
    double totalRemainingWeight = 0.0;

    double totalOriginalCartons = 0.0;
    double totalSoldCartons = 0.0;
    double totalRemainingCartons = 0.0;

    double totalSalesRevenue = 0.0;
    final Map<String, double> revenueByCurrency = {};

    for (final item in items) {
      final origQty = item.weightKg;
      final remQty = item.remainingWeightKg;
      final soldQty = (origQty - remQty > 0) ? (origQty - remQty) : 0.0;
      final saleAmount = item.totalSaleAmount;

      if (saleAmount > 0 || item.isSoldOut) {
        soldCount++;
      }

      totalSalesRevenue += saleAmount;
      revenueByCurrency[defaultCurrency] =
          (revenueByCurrency[defaultCurrency] ?? 0.0) + saleAmount;

      final unitStr = (unitOverrides != null && item.id != null && unitOverrides.containsKey(item.id))
          ? unitOverrides[item.id]!
          : resolveUnit(item);

      final isCarton = isCartonUnit(unitStr);

      if (isCarton) {
        totalOriginalCartons += origQty;
        totalSoldCartons += soldQty;
        totalRemainingCartons += remQty;
      } else {
        totalOriginalWeight += origQty;
        totalSoldWeight += soldQty;
        totalRemainingWeight += remQty;
      }
    }

    return SortedBatchSaleSummary(
      totalCount: totalCount,
      soldCount: soldCount,
      totalOriginalWeight: totalOriginalWeight,
      totalSoldWeight: totalSoldWeight,
      totalRemainingWeight: totalRemainingWeight,
      totalOriginalCartons: totalOriginalCartons,
      totalSoldCartons: totalSoldCartons,
      totalRemainingCartons: totalRemainingCartons,
      totalSalesRevenue: totalSalesRevenue,
      revenueByCurrency: revenueByCurrency,
    );
  }

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
  // LOGO & ASSET HELPERS
  // ──────────────────────────────────────────────────────────────────────────
  static Future<pw.MemoryImage?> _loadLogoImage() async {
    return null;
  }

  static Future<String> _resolveCompanyName(String? companyName) async {
    if (companyName != null && companyName.trim().isNotEmpty) {
      return companyName.trim();
    }
    try {
      final settings = await SettingsDao().getAllSettings();
      final name = settings['company_name'];
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    } catch (_) {}
    return 'شركة مزارع فروتي فارمز لتصدير الحاصلات الزراعية';
  }

  static String _formattedFileName(String title) {
    final now = DateTime.now();
    final minute = now.minute.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    return '${title}_$year$month$day-$hour$minute';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. SINGLE SORTED BATCH SALE VOUCHER (إذن بيع الفرزة / المحصول المفرز)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes for an individual Sorted Produce Sale Voucher (Landscape A4).
  static Future<Uint8List> generateSaleVoucherPdf(
    SortedBatchSaleDetails details, {
    String? companyName,
  }) async {
    await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName(companyName);
    final logoImage = await _loadLogoImage();

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final sorting = details.sorting;
    final voucherId = sorting.id?.toString() ?? '—';
    final lotNumber = sorting.lotNumber ?? '—';
    final productName = sorting.productName.isNotEmpty ? sorting.productName : 'محصول مفرز';
    final customerName = details.customerName?.isNotEmpty == true
        ? details.customerName!
        : 'عميل نقدي / مبيعات سوق محلي';
    final treasury = details.treasuryName ?? sorting.treasuryNames ?? 'الخزينة العامة';

    final unitLabel = details.effectiveUnit;
    final soldQty = details.soldWeightKg;
    final unitPrice = details.unitSalePrice;
    final totalAmount = details.totalSaleValue;
    final currency = details.currency;

    final saleDateStr = details.saleDate != null
        ? intl.DateFormat('yyyy-MM-dd').format(details.saleDate!)
        : (sorting.soldAt != null
            ? intl.DateFormat('yyyy-MM-dd').format(sorting.soldAt!)
            : intl.DateFormat('yyyy-MM-dd').format(DateTime.now()));

    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
    final jeEntryNumber = details.journalEntryNumber;
    final notes = (details.notes ?? '').trim();

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textDirection: pw.TextDirection.rtl,
          theme: theme,
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _white),
          ),
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Corporate Header & Document Title
              _buildCorporateVoucherHeader(
                companyName: effectiveCompanyName,
                voucherId: voucherId,
                saleDate: saleDateStr,
                printDate: printDate,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 8),

              // 2. Metadata Grid (Landscape 8-Cell Grid with Unit Segregation)
              _buildVoucherMetadataGrid(
                customerName: customerName,
                lotNumber: lotNumber,
                productName: productName,
                treasuryName: treasury,
                currency: currency,
                saleDate: saleDateStr,
                unitLabel: unitLabel,
                jeEntryNumber: jeEntryNumber,
                isSoldOut: sorting.isSoldOut,
              ),
              pw.SizedBox(height: 10),

              // 3. Itemized Sale Details Table (with specific unit label)
              _buildSingleSaleTable(
                sorting: sorting,
                soldQty: soldQty,
                unitPrice: unitPrice,
                totalAmount: totalAmount,
                currency: currency,
                unitLabel: unitLabel,
              ),
              pw.SizedBox(height: 8),

              // 4. Reason, Notes & Financial Impact Summary Row
              _buildFinancialImpactAndNotesRow(
                notes: notes.isNotEmpty
                    ? notes
                    : 'تم استخراج هذا الإذن لإثبات بيع وتوريد محصول الفرزة من المحطة واستلام الحصيلة النقدية بالخزينة.',
                totalAmount: totalAmount,
                soldQty: soldQty,
                unitLabel: unitLabel,
                currency: currency,
                jeEntryNumber: jeEntryNumber,
                treasuryName: treasury,
              ),
              pw.Spacer(),

              // 5. Formal 3-Pillar Financial Signatures Block
              _buildAuditSignaturesBlock(),
              pw.SizedBox(height: 5),

              // 6. System Audit Footer
              _buildSystemFooter(effectiveCompanyName, printDate),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Opens the print / preview dialog directly for an individual sorted produce sale voucher.
  static Future<void> printSaleVoucher(
    BuildContext context,
    SortedBatchSaleDetails details, {
    String? companyName,
  }) async {
    final bytes = await generateSaleVoucherPdf(details, companyName: companyName);
    final sortingId = details.sorting.id?.toString() ?? 'voucher';
    final docTitle = _formattedFileName('إذن_بيع_فرزة_رقم_$sortingId');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the single voucher PDF directly to the system export directory.
  static Future<File> saveSaleVoucherToFile(
    BuildContext context,
    SortedBatchSaleDetails details, {
    String? companyName,
  }) async {
    final bytes = await generateSaleVoucherPdf(details, companyName: companyName);
    final sortingId = details.sorting.id?.toString() ?? 'voucher';
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('إذن_بيع_فرزة_رقم_$sortingId')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ إذن بيع الفرزة بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. CONSOLIDATED SALES REPORT / REGISTER (سجل وتقارير مبيعات الفرزة)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates raw PDF bytes for a full tabular Statement / Register of produce sorting sales (Landscape A4).
  static Future<Uint8List> generateSalesRegisterPdf(
    List<PackingOrderSortingModel> items, {
    String? companyName,
    String? filterQuery,
    String? dateLabel,
    String currency = 'EGP',
    Map<int, String>? unitOverrides,
  }) async {
    await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName(companyName);
    final logoImage = await _loadLogoImage();

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    // Compute strictly segregated summary metrics
    final summary = computeSummary(
      items,
      defaultCurrency: currency,
      unitOverrides: unitOverrides,
    );

    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
    const int rowsPerPage = 11;
    final totalPages = (items.length / rowsPerPage).ceil().clamp(1, 9999);

    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final startIndex = pageIndex * rowsPerPage;
      final pageItems = items.skip(startIndex).take(rowsPerPage).toList();
      final isLastPage = pageIndex == totalPages - 1;

      doc.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4.landscape,
            orientation: pw.PageOrientation.landscape,
            margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            textDirection: pw.TextDirection.rtl,
            theme: theme,
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: _white),
            ),
          ),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Top Corporate Report Header
                _buildReportHeader(
                  companyName: effectiveCompanyName,
                  pageNumber: pageIndex + 1,
                  totalPages: totalPages,
                  printDate: printDate,
                  logoImage: logoImage,
                  filterQuery: filterQuery,
                  dateLabel: dateLabel,
                ),
                pw.SizedBox(height: 6),

                // Segregated KPI Metrics Bar (Independent indicator cards for weights & count units)
                if (pageIndex == 0) ...[
                  _buildRegisterKpisRow(
                    summary: summary,
                    currency: currency,
                  ),
                  pw.SizedBox(height: 8),
                ],

                // Tabular Items Listing with Explicit Unit Column & Segregated Totals
                _buildRegisterTable(
                  items: pageItems,
                  startIndex: startIndex,
                  currency: currency,
                  isLastPage: isLastPage,
                  summary: summary,
                  unitOverrides: unitOverrides,
                ),

                pw.Spacer(),

                // Signatures block on the last page
                if (isLastPage) ...[
                  _buildAuditSignaturesBlock(),
                  pw.SizedBox(height: 5),
                ],

                // Report Multi-page Footer
                _buildReportMultiPageFooter(
                  companyName: effectiveCompanyName,
                  pageNumber: pageIndex + 1,
                  totalPages: totalPages,
                  printDate: printDate,
                ),
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }

  /// Opens the print / preview dialog directly for the consolidated sales register.
  static Future<void> printSalesRegister(
    BuildContext context,
    List<PackingOrderSortingModel> items, {
    String? companyName,
    String? filterQuery,
    String? dateLabel,
    String currency = 'EGP',
    Map<int, String>? unitOverrides,
  }) async {
    final bytes = await generateSalesRegisterPdf(
      items,
      companyName: companyName,
      filterQuery: filterQuery,
      dateLabel: dateLabel,
      currency: currency,
      unitOverrides: unitOverrides,
    );
    final docTitle = _formattedFileName('تقرير_سجل_مبيعات_الفرزة');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VOUCHER WIDGET BUILDERS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCorporateVoucherHeader({
    required String companyName,
    required String voucherId,
    required String saleDate,
    required String printDate,
    pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const pw.BoxDecoration(
        color: _navyPrimary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right: Brand & Identity
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: _boldFont,
                      fontSize: 12,
                      color: _white,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'FRUITY FARMS FOR AGRICULTURAL CROPS EXPORT',
                    style: pw.TextStyle(
                      font: _font,
                      fontSize: 6.5,
                      color: PdfColors.blueGrey100,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center: Document Title Badge
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: _cyanAccent,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'إذن بيع الفرزة / المحصول المفرز',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 13,
                    color: _white,
                  ),
                ),
                pw.Text(
                  'SORTED PRODUCE SALE VOUCHER / CASH RECEIPT',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 6.5,
                    color: _navyPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Left: Voucher Number & Meta
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: const pw.BoxDecoration(
                  color: _white,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  'إذن بيع فرزة #$voucherId',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 9,
                    color: _navyPrimary,
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'تاريخ العملية: $saleDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: PdfColors.blueGrey100,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildVoucherMetadataGrid({
    required String customerName,
    required String lotNumber,
    required String productName,
    required String treasuryName,
    required String currency,
    required String saleDate,
    required String unitLabel,
    required String? jeEntryNumber,
    required bool isSoldOut,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        border: pw.Border.all(color: _borderColor, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              _buildMetaCell('العميل / المشتري:', customerName, isHighlight: true),
              pw.SizedBox(width: 8),
              _buildMetaCell('رقم اللوط / الشراء:', lotNumber),
              pw.SizedBox(width: 8),
              _buildMetaCell('الصنف / المحصول:', productName),
              pw.SizedBox(width: 8),
              _buildMetaCell('الوحدة القياسية:', unitLabel, isBold: true, customColor: _cyanAccent),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              _buildMetaCell('الخزينة المستهدفة:', treasuryName),
              pw.SizedBox(width: 8),
              _buildMetaCell('تاريخ البيع والاعتماد:', saleDate),
              pw.SizedBox(width: 8),
              _buildMetaCell(
                'القيد المحاسبي المرتبط:',
                jeEntryNumber != null ? 'قيد $jeEntryNumber' : 'معتمد ومرحل آلياً',
                customColor: jeEntryNumber != null ? _successGreen : _navyPrimary,
                isBold: true,
              ),
              pw.SizedBox(width: 8),
              _buildMetaCell(
                'حالة الدفعة:',
                isSoldOut ? 'تم البيع بالكامل' : 'مباع جزئياً (يوجد متبقي)',
                customColor: isSoldOut ? _successGreen : _warningAmber,
                isBold: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMetaCell(
    String label,
    String value, {
    bool isHighlight = false,
    bool isBold = false,
    PdfColor? customColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
          color: isHighlight ? _lightBg : _white,
          border: pw.Border.all(color: _borderColor, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: _font,
                fontSize: 6.5,
                color: _mutedText,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                font: (isBold || isHighlight) ? _boldFont : _font,
                fontSize: 8,
                color: customColor ?? (isHighlight ? _navyPrimary : _darkText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildSingleSaleTable({
    required PackingOrderSortingModel sorting,
    required double soldQty,
    required double unitPrice,
    required double totalAmount,
    required String currency,
    required String unitLabel,
  }) {
    final origQty = sorting.weightKg;
    final remQty = sorting.remainingWeightKg;

    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.6),  // م
        1: pw.FlexColumnWidth(2.6),  // بيان الصنف
        2: pw.FlexColumnWidth(1.4),  // رقم اللوط
        3: pw.FlexColumnWidth(1.5),  // الكمية الأصلية
        4: pw.FlexColumnWidth(1.6),  // الكمية المباعة
        5: pw.FlexColumnWidth(1.5),  // الكمية المتبقية
        6: pw.FlexColumnWidth(1.5),  // سعر البيع/الوحدة
        7: pw.FlexColumnWidth(2.0),  // إجمالي المبيعات
        8: pw.FlexColumnWidth(1.0),  // العملة
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: [
            _tableHeaderCell('م'),
            _tableHeaderCell('بيان الصنف والمحصول المفرز'),
            _tableHeaderCell('رقم اللوط'),
            _tableHeaderCell('الكمية الأصلية ($unitLabel)'),
            _tableHeaderCell('الكمية المباعة ($unitLabel)'),
            _tableHeaderCell('الكمية المتبقية ($unitLabel)'),
            _tableHeaderCell('سعر البيع / $unitLabel'),
            _tableHeaderCell('إجمالي قيمة البيع'),
            _tableHeaderCell('العملة'),
          ],
        ),
        // Item Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _white),
          children: [
            _tableDataCell('1', align: pw.TextAlign.center),
            _tableDataCell(sorting.productName, isBold: true, color: _navyPrimary),
            _tableDataCell(sorting.lotNumber ?? '—', align: pw.TextAlign.center),
            _tableDataCell(
              '${_qtyFmt.format(origQty)} $unitLabel',
              align: pw.TextAlign.center,
            ),
            _tableDataCell(
              '${_qtyFmt.format(soldQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
              color: _successGreen,
            ),
            _tableDataCell(
              '${_qtyFmt.format(remQty)} $unitLabel',
              align: pw.TextAlign.center,
              color: remQty > 0 ? _warningAmber : _mutedText,
            ),
            _tableDataCell(
              _currFmt.format(unitPrice),
              align: pw.TextAlign.center,
            ),
            _tableDataCell(
              _currFmt.format(totalAmount),
              align: pw.TextAlign.center,
              isBold: true,
              color: _navyPrimary,
            ),
            _tableDataCell(currency, align: pw.TextAlign.center, isBold: true),
          ],
        ),
        // Totals Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _tableDataCell('', align: pw.TextAlign.center),
            _tableDataCell('الإجمالي الكلي لمبيعات الفرزة ($unitLabel)', isBold: true, color: _navyPrimary),
            _tableDataCell(''),
            _tableDataCell(
              '${_qtyFmt.format(origQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
            ),
            _tableDataCell(
              '${_qtyFmt.format(soldQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
              color: _successGreen,
            ),
            _tableDataCell(
              '${_qtyFmt.format(remQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
            ),
            _tableDataCell(''),
            _tableDataCell(
              _currFmt.format(totalAmount),
              align: pw.TextAlign.center,
              isBold: true,
              color: _navyPrimary,
            ),
            _tableDataCell(currency, align: pw.TextAlign.center, isBold: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableHeaderCell(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _white),
      ),
    );
  }

  static pw.Widget _tableDataCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.start,
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      alignment: align == pw.TextAlign.center
          ? pw.Alignment.center
          : align == pw.TextAlign.right
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? _boldFont : _font,
          fontSize: 8,
          color: color ?? _darkText,
        ),
      ),
    );
  }

  static pw.Widget _buildFinancialImpactAndNotesRow({
    required String notes,
    required double totalAmount,
    required double soldQty,
    required String unitLabel,
    required String currency,
    required String? jeEntryNumber,
    required String treasuryName,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Notes & Declaration Box
        pw.Expanded(
          flex: 6,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _cardBg,
              border: pw.Border.all(color: _borderColor, width: 0.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'بيان العملية وملاحظات الاعتماد:',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  notes,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7.5, color: _darkText),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'إقرار: تم تسليم كمية ${_qtyFmt.format(soldQty)} $unitLabel للعميل وفقاً للأوزان والعبوات المعتمدة وتوريد القيمة إلى $treasuryName.',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),

        // Right: Accounting & GL Impact Box (Direct 2-legged entry)
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _successBg,
              border: pw.Border.all(color: _successGreen, width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'التوجيه المالي والقيد المحاسبي',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _successGreen),
                    ),
                    if (jeEntryNumber != null)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: _white,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'قيد $jeEntryNumber',
                          style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _navyPrimary),
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '• مدين (Dr): حساب الخزينة / النقدية (إيداع حصيلة البيع)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
                ),
                pw.Text(
                  '• دائن (Cr): حساب مخزون الفرز 1032 (تخفيض المخزون بنفس القيمة)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'إجمالي حصيلة البيع المودعة:',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                    ),
                    pw.Text(
                      '${_currFmt.format(totalAmount)} $currency',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 9.5, color: _successGreen),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REGISTER WIDGET BUILDERS (Multi-batch consolidated report)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildReportHeader({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required String printDate,
    pw.MemoryImage? logoImage,
    String? filterQuery,
    String? dateLabel,
  }) {
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
          // Right: Company Brand
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _boldFont, fontSize: 10.5, color: _navyPrimary),
                  ),
                  pw.Text(
                    'نظام إدارة الحسابات والمخازن • Fruity Farms ERP',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
                  ),
                ],
              ),
            ],
          ),

          // Center: Document Title
          pw.Column(
            children: [
              pw.Text(
                'سجل وتقارير مبيعات الفرزة والمحصول المفرز',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _boldFont, fontSize: 12.5, color: _navyPrimary),
              ),
              if (dateLabel != null && dateLabel.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  'الفترة: $dateLabel',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _mutedText),
                ),
              ],
              if (filterQuery != null && filterQuery.trim().isNotEmpty) ...[
                pw.Text(
                  'تصفية بحث: $filterQuery',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.5, color: _cyanAccent),
                ),
              ],
            ],
          ),

          // Left: Document Meta
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'تاريخ التقرير: $printDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
              ),
              pw.Text(
                'صفحة $pageNumber من $totalPages',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Refined independent KPI cards row strictly isolating weight quantities from carton/packaging quantities.
  static pw.Widget _buildRegisterKpisRow({
    required SortedBatchSaleSummary summary,
    required String currency,
  }) {
    String remainingSubtext;
    String remainingDisplay;

    if (summary.hasCartons && summary.hasWeights) {
      remainingDisplay = '${_qtyFmt.format(summary.totalRemainingWeight)} كجم | ${_qtyFmt.format(summary.totalRemainingCartons)} طرد';
      remainingSubtext = 'رصيد متبقي (وزن + عبوات)';
    } else if (summary.hasCartons) {
      remainingDisplay = '${_qtyFmt.format(summary.totalRemainingCartons)} كرتونة';
      remainingSubtext = 'رصيد كراتين متاح';
    } else {
      remainingDisplay = '${_qtyFmt.format(summary.totalRemainingWeight)} كجم';
      remainingSubtext = 'رصيد وزن متاح';
    }

    return pw.Row(
      children: [
        _buildKpiCard(
          'عدد الدفعات',
          '${summary.totalCount} دفعة',
          'تم بيع ${summary.soldCount} دفعة',
          _navyPrimary,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'إجمالي الوزن الأصلي',
          '${_qtyFmt.format(summary.totalOriginalWeight)} كجم',
          'وارد بالوزن الصافي',
          _darkText,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'إجمالي الكراتين الأصلية',
          '${_qtyFmt.format(summary.totalOriginalCartons)} كرتونة',
          'وارد بالعبوة والكرتونة',
          _cyanAccent,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'إجمالي الوزن المباع',
          '${_qtyFmt.format(summary.totalSoldWeight)} كجم',
          'مبيعات كجم محققة',
          _successGreen,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'إجمالي الكراتين المباعة',
          '${_qtyFmt.format(summary.totalSoldCartons)} كرتونة',
          'مبيعات كراتين محققة',
          _cyanAccent,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'المتبقي بالمستودع',
          remainingDisplay,
          remainingSubtext,
          _warningAmber,
        ),
        pw.SizedBox(width: 5),
        _buildKpiCard(
          'إجمالي المبيعات',
          '${_currFmt.format(summary.totalSalesRevenue)} $currency',
          'الحصيلة النقدية الإجمالية',
          _navyPrimary,
          isBold: true,
        ),
      ],
    );
  }

  static pw.Widget _buildKpiCard(
    String label,
    String value,
    String subText,
    PdfColor valueColor, {
    bool isBold = false,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: pw.BoxDecoration(
          color: _cardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          border: pw.Border.all(color: _borderColor, width: 0.6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              label,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 6.2, color: _mutedText),
            ),
            pw.SizedBox(height: 1.5),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(
                font: isBold ? _boldFont : _boldFont,
                fontSize: 8.2,
                color: valueColor,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              subText,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 5.2, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildRegisterTable({
    required List<PackingOrderSortingModel> items,
    required int startIndex,
    required String currency,
    required bool isLastPage,
    required SortedBatchSaleSummary summary,
    Map<int, String>? unitOverrides,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.5), // م
        1: pw.FlexColumnWidth(1.2), // التاريخ
        2: pw.FlexColumnWidth(2.2), // الصنف
        3: pw.FlexColumnWidth(1.2), // اللوط
        4: pw.FlexColumnWidth(0.9), // الوحدة
        5: pw.FlexColumnWidth(1.3), // الكمية الأصلية
        6: pw.FlexColumnWidth(1.3), // الكمية المباعة
        7: pw.FlexColumnWidth(1.3), // الكمية المتبقية
        8: pw.FlexColumnWidth(1.7), // قيمة المبيعات
        9: pw.FlexColumnWidth(1.5), // الخزينة
        10: pw.FlexColumnWidth(1.2), // الحالة
      },
      children: [
        // Header Row (unambiguous, unit-neutral quantity columns with explicit 'الوحدة' column)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: [
            _tableHeaderCell('م'),
            _tableHeaderCell('التاريخ'),
            _tableHeaderCell('الصنف / المحصول'),
            _tableHeaderCell('رقم اللوط'),
            _tableHeaderCell('الوحدة'),
            _tableHeaderCell('الكمية الأصلية'),
            _tableHeaderCell('الكمية المباعة'),
            _tableHeaderCell('الكمية المتبقية'),
            _tableHeaderCell('قيمة المبيعات ($currency)'),
            _tableHeaderCell('الخزينة'),
            _tableHeaderCell('الحالة'),
          ],
        ),
        // Item Rows
        ...items.asMap().entries.map((entry) {
          final index = startIndex + entry.key + 1;
          final s = entry.value;
          final sold = s.weightKg - s.remainingWeightKg;
          final isEven = entry.key % 2 == 0;
          final dateStr = s.createdAt != null
              ? intl.DateFormat('yyyy-MM-dd').format(s.createdAt!)
              : '—';

          final unitLabel = (unitOverrides != null && s.id != null && unitOverrides.containsKey(s.id))
              ? unitOverrides[s.id]!
              : resolveUnit(s);
          final isCarton = isCartonUnit(unitLabel);

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
            children: [
              _tableDataCell('$index', align: pw.TextAlign.center),
              _tableDataCell(dateStr, align: pw.TextAlign.center),
              _tableDataCell(s.productName, isBold: true, color: _navyPrimary),
              _tableDataCell(s.lotNumber ?? '—', align: pw.TextAlign.center),
              _tableDataCell(
                unitLabel,
                align: pw.TextAlign.center,
                isBold: true,
                color: isCarton ? _cyanAccent : _navyPrimary,
              ),
              _tableDataCell(
                '${_qtyFmt.format(s.weightKg)} $unitLabel',
                align: pw.TextAlign.center,
              ),
              _tableDataCell(
                sold > 0 ? '${_qtyFmt.format(sold)} $unitLabel' : '—',
                align: pw.TextAlign.center,
                isBold: sold > 0,
                color: sold > 0 ? _successGreen : _mutedText,
              ),
              _tableDataCell(
                s.remainingWeightKg > 0
                    ? '${_qtyFmt.format(s.remainingWeightKg)} $unitLabel'
                    : '0.0 $unitLabel',
                align: pw.TextAlign.center,
                color: s.remainingWeightKg > 0 ? _warningAmber : _mutedText,
              ),
              _tableDataCell(
                s.totalSaleAmount > 0 ? _currFmt.format(s.totalSaleAmount) : '—',
                align: pw.TextAlign.center,
                isBold: s.totalSaleAmount > 0,
                color: s.totalSaleAmount > 0 ? _navyPrimary : _mutedText,
              ),
              _tableDataCell(s.treasuryNames ?? '—', align: pw.TextAlign.center),
              _tableDataCell(
                s.isSoldOut ? 'مباع بالكامل' : (sold > 0 ? 'مباع جزئياً' : 'متاح'),
                align: pw.TextAlign.center,
                isBold: true,
                color: s.isSoldOut
                    ? _successGreen
                    : (sold > 0 ? _warningAmber : _mutedText),
              ),
            ],
          );
        }),
        // Totals Row on Last Page (Segregated by unit: weights & packaging are never combined)
        if (isLastPage) ...[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _lightBg),
            children: [
              _tableDataCell('', align: pw.TextAlign.center),
              _tableDataCell(''),
              _tableDataCell('الإجمالي الكلي المُصنف', isBold: true, color: _navyPrimary),
              _tableDataCell(''),
              _tableDataCell(''),
              // Segregated Original Total
              _buildSegregatedQtyCell(
                weightQty: summary.totalOriginalWeight,
                cartonQty: summary.totalOriginalCartons,
              ),
              // Segregated Sold Total
              _buildSegregatedQtyCell(
                weightQty: summary.totalSoldWeight,
                cartonQty: summary.totalSoldCartons,
                isSold: true,
              ),
              // Segregated Remaining Total
              _buildSegregatedQtyCell(
                weightQty: summary.totalRemainingWeight,
                cartonQty: summary.totalRemainingCartons,
              ),
              // Sales Total
              _tableDataCell(
                _currFmt.format(summary.totalSalesRevenue),
                align: pw.TextAlign.center,
                isBold: true,
                color: _navyPrimary,
              ),
              _tableDataCell(''),
              _tableDataCell(''),
            ],
          ),
        ],
      ],
    );
  }

  /// Builds a stacked cell in the totals row showing independent totals for weights and cartons.
  static pw.Widget _buildSegregatedQtyCell({
    required double weightQty,
    required double cartonQty,
    bool isSold = false,
  }) {
    final children = <pw.Widget>[];

    if (weightQty > 0 || cartonQty == 0) {
      children.add(
        pw.Text(
          '${_qtyFmt.format(weightQty)} كجم',
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: _boldFont,
            fontSize: 7.2,
            color: isSold ? _successGreen : _navyPrimary,
          ),
        ),
      );
    }

    if (cartonQty > 0) {
      children.add(
        pw.Text(
          '${_qtyFmt.format(cartonQty)} كرتونة',
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: _boldFont,
            fontSize: 7.2,
            color: isSold ? _cyanAccent : _warningAmber,
          ),
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUDIT & FINANCIAL SIGNATURES BLOCK (STANDARD 3 PILLARS)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildAuditSignaturesBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSignatureSlot('رئيس قسم الحسابات العامة', 'Head of General Accounts'),
          _buildSignatureSlot('مدير الرقابة والمراجعة المالية', 'Financial Audit & Control Manager'),
          _buildSignatureSlot('المدير العام والاعتماد', 'General Manager & Authorization'),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureSlot(String arTitle, String enTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          arTitle,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.Text(
          enTitle,
          style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _borderColor, width: 0.8, style: pw.BorderStyle.dashed),
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'التوقيع: .......................................',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER BUILDERS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSystemFooter(String companyName, String printDate) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم استخراج هذا الإذن آلياً عبر نظام إدارة العمليات والحسابات (Fruity Farms ERP) • $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
          ),
          pw.Text(
            companyName,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _navyPrimary),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildReportMultiPageFooter({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required String printDate,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Fruity Farms ERP • تقرير وسجل مبيعات الفرزة • تاريخ الطباعة: $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
          ),
          pw.Text(
            'صفحة $pageNumber من $totalPages',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _navyPrimary),
          ),
        ],
      ),
    );
  }
}
