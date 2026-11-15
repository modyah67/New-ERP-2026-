// lib/features/lots/crop_return_pdf_service.dart
// Professional Landscape A4 PDF Service for Crop Purchase Returns (إذن مرتجع شراء محاصيل)
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

/// Alias for naming compatibility across modules
typedef LotReturnPdfService = CropReturnPdfService;

/// Data model holding segregated aggregation metrics for crop returns.
class CropReturnUnitSummary {
  final int totalCount;
  final double totalWeightQty;
  final double totalCartonQty;
  final Map<String, double> quantityByUnit;
  final Map<String, double> valueByCurrency;
  final int linkedJeCount;

  const CropReturnUnitSummary({
    required this.totalCount,
    required this.totalWeightQty,
    required this.totalCartonQty,
    required this.quantityByUnit,
    required this.valueByCurrency,
    required this.linkedJeCount,
  });
}

class CropReturnPdfService {
  CropReturnPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Corporate Fruity Farms Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static const PdfColor _navyPrimary = PdfColor.fromInt(0xFF1A365D); // #1A365D
  static const PdfColor _cyanAccent  = PdfColor.fromInt(0xFF0284C7); // #0284C7
  static const PdfColor _cardBg      = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const PdfColor _lightBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const PdfColor _zebraBg     = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _borderColor = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const PdfColor _darkText    = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const PdfColor _mutedText   = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const PdfColor _white       = PdfColors.white;

  static const PdfColor _dangerRed   = PdfColor.fromInt(0xFFDC2626); // Red 600
  static const PdfColor _dangerBg    = PdfColor.fromInt(0xFFFEF2F2); // Red 50
  static const PdfColor _dangerBorder = PdfColor.fromInt(0xFFFECACA); // Red 200
  static const PdfColor _successGreen = PdfColor.fromInt(0xFF059669); // Emerald 600
  static const PdfColor _warningAmber = PdfColor.fromInt(0xFFD97706); // Amber 600

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');
  static final intl.NumberFormat _qtyFmt = intl.NumberFormat('#,##0.0#', 'en_US');

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

  /// Computes segregated aggregation metrics grouping weight and packaging units distinctly.
  static CropReturnUnitSummary computeSummary(List<Map<String, dynamic>> returns) {
    final totalCount = returns.length;
    double totalWeightQty = 0.0;
    double totalCartonQty = 0.0;
    final Map<String, double> quantityByUnit = {};
    final Map<String, double> valueByCurrency = {};
    int linkedJeCount = 0;

    for (final ret in returns) {
      final qty = (ret['returned_quantity'] as num?)?.toDouble() ?? 0.0;
      final val = (ret['return_value'] as num?)?.toDouble() ?? 0.0;
      final lotInfo = ret['lot_receipts'] as Map<String, dynamic>? ?? {};
      final curr = (lotInfo['currency'] ?? ret['currency'] ?? 'EGP').toString().toUpperCase();

      final mode = (lotInfo['purchase_mode'] ?? ret['purchase_mode'] ?? 'weight').toString().toLowerCase();
      final unit = (lotInfo['unit'] ?? ret['unit'] ?? (mode == 'carton' ? 'كرتونة' : 'كجم')).toString().toLowerCase();

      final isCarton = mode == 'carton' ||
          unit.contains('كرتون') ||
          unit.contains('صندوق') ||
          unit.contains('طرد') ||
          unit.contains('box');

      if (isCarton) {
        totalCartonQty += qty;
        final key = unit.isNotEmpty ? unit : 'كرتونة';
        quantityByUnit[key] = (quantityByUnit[key] ?? 0.0) + qty;
      } else {
        totalWeightQty += qty;
        final key = unit.isNotEmpty ? unit : 'كجم';
        quantityByUnit[key] = (quantityByUnit[key] ?? 0.0) + qty;
      }

      valueByCurrency[curr] = (valueByCurrency[curr] ?? 0.0) + val;
      if (ret['journal_entry_id'] != null) {
        linkedJeCount++;
      }
    }

    return CropReturnUnitSummary(
      totalCount: totalCount,
      totalWeightQty: totalWeightQty,
      totalCartonQty: totalCartonQty,
      quantityByUnit: quantityByUnit,
      valueByCurrency: valueByCurrency,
      linkedJeCount: linkedJeCount,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. SINGLE RETURN VOUCHER (إذن مرتجع شراء محاصيل)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes for an individual Crop Return Voucher (Landscape A4).
  static Future<Uint8List> generateSingleReturnReceiptPdf(
    Map<String, dynamic> returnData, {
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

    final lotInfo = returnData['lot_receipts'] as Map<String, dynamic>? ?? {};
    final supplierInfo = returnData['suppliers'] as Map<String, dynamic>? ?? {};
    final stationInfo = returnData['stations'] as Map<String, dynamic>? ?? {};
    final jeInfo = returnData['journal_entries'] as Map<String, dynamic>?;

    final retId = returnData['id']?.toString() ?? '—';
    final lotNumber = lotInfo['lot_number']?.toString() ?? returnData['lot_number']?.toString() ?? '—';
    final productName = lotInfo['product_name']?.toString() ?? returnData['product_name']?.toString() ?? 'محصول زراعي';
    final supplierName = supplierInfo['name']?.toString() ?? returnData['supplier_name']?.toString() ?? '—';
    final supplierCode = supplierInfo['code']?.toString() ?? '';
    final stationName = stationInfo['name']?.toString() ?? returnData['station_name']?.toString() ?? '—';

    final returnedQty = (returnData['returned_quantity'] as num?)?.toDouble() ?? 0.0;
    final returnValue = (returnData['return_value'] as num?)?.toDouble() ?? 0.0;
    final purchaseMode = lotInfo['purchase_mode']?.toString() ?? 'weight';
    final isCarton = purchaseMode == 'carton';
    final unitLabel = isCarton ? 'كرتونة' : 'كجم';
    final currency = lotInfo['currency']?.toString() ?? returnData['currency']?.toString() ?? 'EGP';

    final unitCost = returnedQty > 0 ? (returnValue / returnedQty) : 0.0;
    final dateStr = returnData['created_at'] != null
        ? returnData['created_at'].toString().split('T').first
        : intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    final rawJeId = returnData['journal_entry_id'];
    final jeEntryNumber = jeInfo?['entry_number']?.toString() ?? (rawJeId != null ? '#$rawJeId' : null);
    final notes = (returnData['notes'] ?? '').toString().trim();

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                voucherId: retId,
                returnDate: dateStr,
                printDate: printDate,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 10),

              // 2. Return & Entity Metadata Card (Landscape 6-Cell Grid)
              _buildVoucherMetadataGrid(
                supplierName: supplierName,
                supplierCode: supplierCode,
                stationName: stationName,
                lotNumber: lotNumber,
                purchaseModeLabel: isCarton ? 'شراء بالكرتونة' : 'شراء بالوزن (كجم)',
                currency: currency,
                jeEntryNumber: jeEntryNumber,
                statusLabel: rawJeId != null ? 'مرحل ومقيد دفترياً' : 'معتمد ومحفوظ',
              ),
              pw.SizedBox(height: 12),

              // 3. Return Line Items Table
              _buildSingleReturnItemTable(
                productName: productName,
                lotNumber: lotNumber,
                stationName: stationName,
                returnedQty: returnedQty,
                unitLabel: unitLabel,
                unitCost: unitCost,
                returnValue: returnValue,
                currency: currency,
              ),
              pw.SizedBox(height: 10),

              // 4. Reason, Notes & Financial Impact Summary Row
              _buildReasonAndImpactRow(
                notes: notes.isNotEmpty ? notes : 'مرتجع شراء حاصلات زراعية إلى المورد المعتمد.',
                returnValue: returnValue,
                returnedQty: returnedQty,
                unitLabel: unitLabel,
                currency: currency,
                jeEntryNumber: jeEntryNumber,
              ),
              pw.Spacer(),

              // 5. Formal 3-Pillar Financial Signatures Block
              _buildAuditSignaturesBlock(),
              pw.SizedBox(height: 6),

              // 6. System Audit Footer
              _buildSystemFooter(effectiveCompanyName, printDate),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Opens the print / preview dialog directly for an individual return voucher.
  static Future<void> printSingleReturn(
    BuildContext context,
    Map<String, dynamic> returnData, {
    String? companyName,
  }) async {
    final bytes = await generateSingleReturnReceiptPdf(returnData, companyName: companyName);
    final retId = returnData['id']?.toString() ?? 'voucher';
    final docTitle = _formattedFileName('إذن_مرتجع_محاصيل_رقم_$retId');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the single return voucher PDF directly to the system export directory.
  static Future<File> saveSingleReturnToFile(
    BuildContext context,
    Map<String, dynamic> returnData, {
    String? companyName,
  }) async {
    final bytes = await generateSingleReturnReceiptPdf(returnData, companyName: companyName);
    final retId = returnData['id']?.toString() ?? 'voucher';
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('إذن_مرتجع_محاصيل_رقم_$retId')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ إذن المرتجع بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. CONSOLIDATED RETURNS REPORT (تقرير مرتجعات شراء المحاصيل)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates raw PDF bytes for a full tabular Statement / Register of crop returns (Landscape A4).
  static Future<Uint8List> generateReturnsReportPdf(
    List<Map<String, dynamic>> returns, {
    String? companyName,
    String? filterQuery,
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

    // Compute Segregated Metrics & Aggregations
    final summary = computeSummary(returns);
    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
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
        header: (context) => _buildReportHeader(
          companyName: effectiveCompanyName,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          printDate: printDate,
          logoImage: logoImage,
          filterQuery: filterQuery,
        ),
        footer: (context) => _buildReportMultiPageFooter(
          companyName: effectiveCompanyName,
          pageNumber: context.pageNumber,
          totalPages: context.pagesCount,
          printDate: printDate,
        ),
        build: (context) => [
          // 1. Segregated KPI Summary Dashboard Cards
          _buildReportKpiCards(summary: summary),
          pw.SizedBox(height: 10),

          // 2. Tabular Listing of Returns with Segregated Totals
          _buildReturnsDataTable(returns, summary: summary),
          pw.SizedBox(height: 12),

          // 3. Formal 3-Pillar Financial Signatures Block
          _buildAuditSignaturesBlock(),
        ],
      ),
    );

    return doc.save();
  }

  /// Opens the print / preview dialog directly for the consolidated returns report.
  static Future<void> printReturnsReport(
    BuildContext context,
    List<Map<String, dynamic>> returns, {
    String? companyName,
    String? filterQuery,
  }) async {
    final bytes = await generateReturnsReportPdf(
      returns,
      companyName: companyName,
      filterQuery: filterQuery,
    );
    final docTitle = _formattedFileName('تقرير_مرتجعات_شراء_المحاصيل');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the consolidated returns report PDF directly to storage.
  static Future<File> saveReturnsReportToFile(
    BuildContext context,
    List<Map<String, dynamic>> returns, {
    String? companyName,
    String? filterQuery,
  }) async {
    final bytes = await generateReturnsReportPdf(
      returns,
      companyName: companyName,
      filterQuery: filterQuery,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${_formattedFileName('تقرير_مرتجعات_شراء_المحاصيل')}.pdf';
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ تقرير المرتجعات بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VOUCHER WIDGET BUILDERS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCorporateVoucherHeader({
    required String companyName,
    required String voucherId,
    required String returnDate,
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
          // Right: Company Brand
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: _boldFont,
                      fontSize: 12.5,
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
                  'إذن مرتجع شراء محاصيل',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 13,
                    color: _white,
                  ),
                ),
                pw.Text(
                  'CROP PURCHASE RETURN VOUCHER',
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
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: _dangerRed,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'إذن مرتجع #$voucherId',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 10, color: _white),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'تاريخ المرتجع: $returnDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 8, color: _white),
              ),
              pw.Text(
                'تاريخ الطباعة: $printDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 7, color: PdfColors.blueGrey200),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildVoucherMetadataGrid({
    required String supplierName,
    required String supplierCode,
    required String stationName,
    required String lotNumber,
    required String purchaseModeLabel,
    required String currency,
    required String? jeEntryNumber,
    required String statusLabel,
  }) {
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
          // 1. Supplier
          _metaGridCell(
            label: 'اسم المورد المعتمد',
            englishLabel: 'Crop Supplier',
            value: supplierName,
            subValue: supplierCode.isNotEmpty ? 'كود: $supplierCode' : null,
            isBold: true,
          ),
          _vSeparator(),

          // 2. Station / Warehouse
          _metaGridCell(
            label: 'المحطة / المخزن المستلم',
            englishLabel: 'Station / Warehouse',
            value: stationName,
            isBold: true,
          ),
          _vSeparator(),

          // 3. Lot Reference
          _metaGridCell(
            label: 'رقم شراء المحصول (اللوط)',
            englishLabel: 'Crop Purchase Ref',
            value: 'لوط #$lotNumber',
            valueColor: _cyanAccent,
            isBold: true,
          ),
          _vSeparator(),

          // 4. Mode & Currency
          _metaGridCell(
            label: 'نظام الشراء والعملة',
            englishLabel: 'Mode & Currency',
            value: '$purchaseModeLabel ($currency)',
          ),
          _vSeparator(),

          // 5. Linked Journal Entry
          _metaGridCell(
            label: 'القيد المحاسبي المرتبط',
            englishLabel: 'Journal Entry Ref',
            value: jeEntryNumber != null ? 'قيد $jeEntryNumber' : 'معلق للترحيل',
            valueColor: jeEntryNumber != null ? _successGreen : _warningAmber,
            isBold: true,
          ),
          _vSeparator(),

          // 6. Status
          _metaGridCell(
            label: 'حالة المعاملة',
            englishLabel: 'Status',
            value: statusLabel,
            valueColor: _navyPrimary,
            isBold: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaGridCell({
    required String label,
    required String englishLabel,
    required String value,
    String? subValue,
    PdfColor? valueColor,
    bool isBold = false,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
          ),
          pw.Text(
            englishLabel,
            style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
          ),
          pw.SizedBox(height: 3),
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
          if (subValue != null) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              subValue,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _vSeparator() {
    return pw.Container(width: 1, height: 32, color: _borderColor);
  }

  static pw.Widget _buildSingleReturnItemTable({
    required String productName,
    required String lotNumber,
    required String stationName,
    required double returnedQty,
    required String unitLabel,
    required double unitCost,
    required double returnValue,
    required String currency,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.6),  // م
        1: pw.FlexColumnWidth(3.0),  // البيان / المحصول
        2: pw.FlexColumnWidth(1.4),  // رقم الشراء
        3: pw.FlexColumnWidth(1.6),  // المحطة
        4: pw.FlexColumnWidth(1.6),  // الكمية المرتجعة
        5: pw.FlexColumnWidth(1.5),  // سعر الوحدة
        6: pw.FlexColumnWidth(2.0),  // إجمالي قيمة المرتجع
        7: pw.FlexColumnWidth(1.0),  // العملة
      },
      children: [
        // Header Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: [
            _tableHeaderCell('م'),
            _tableHeaderCell('بيان الصنف والمحصول المرتجع'),
            _tableHeaderCell('رقم الشراء (اللوط)'),
            _tableHeaderCell('المحطة المستلمة'),
            _tableHeaderCell('الكمية المرتجعة'),
            _tableHeaderCell('سعر الوحدة'),
            _tableHeaderCell('إجمالي قيمة المرتجع'),
            _tableHeaderCell('العملة'),
          ],
        ),
        // Item Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _white),
          children: [
            _tableDataCell('1', align: pw.TextAlign.center),
            _tableDataCell(productName, isBold: true, color: _navyPrimary),
            _tableDataCell('لوط #$lotNumber', align: pw.TextAlign.center),
            _tableDataCell(stationName, align: pw.TextAlign.center),
            _tableDataCell(
              '${_qtyFmt.format(returnedQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
              color: _warningAmber,
            ),
            _tableDataCell(
              _currFmt.format(unitCost),
              align: pw.TextAlign.center,
            ),
            _tableDataCell(
              _currFmt.format(returnValue),
              align: pw.TextAlign.center,
              isBold: true,
              color: _dangerRed,
            ),
            _tableDataCell(currency, align: pw.TextAlign.center, isBold: true),
          ],
        ),
        // Total Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _tableDataCell('', align: pw.TextAlign.center),
            _tableDataCell('الإجمالي الكلي لمردودات الشراء', isBold: true, color: _navyPrimary),
            _tableDataCell(''),
            _tableDataCell(''),
            _tableDataCell(
              '${_qtyFmt.format(returnedQty)} $unitLabel',
              align: pw.TextAlign.center,
              isBold: true,
              color: _navyPrimary,
            ),
            _tableDataCell(''),
            _tableDataCell(
              _currFmt.format(returnValue),
              align: pw.TextAlign.center,
              isBold: true,
              color: _dangerRed,
            ),
            _tableDataCell(currency, align: pw.TextAlign.center, isBold: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableHeaderCell(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _white),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
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
          fontSize: 8.5,
          color: color ?? _darkText,
        ),
      ),
    );
  }

  static pw.Widget _buildReasonAndImpactRow({
    required String notes,
    required double returnValue,
    required double returnedQty,
    required String unitLabel,
    required String currency,
    required String? jeEntryNumber,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Notes & Reason Box
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
                  'سبب الإرجاع وملاحظات الفحص:',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  notes,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 8, color: _darkText),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'ملاحظة: تم تخفيض رصيد المحاصيل الزراعية بالمخزن المختص طبقاً لهذا الإذن، ويعد هذا المستند إقراراً رسمياً بالمرتجع.',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),

        // Right: Accounting & GL Impact Box
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _dangerBg,
              border: pw.Border.all(color: _dangerBorder, width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الأثر المالي والقيد المحاسبي',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _dangerRed),
                    ),
                    if (jeEntryNumber != null)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: _white,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'قيد $jeEntryNumber',
                          style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _successGreen),
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '• مدين (Dr): حساب الموردين (تخفيض التزام المستحقات)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
                ),
                pw.Text(
                  '• دائن (Cr): حساب مخزون المحاصيل (تخفيض تكلفة المخزون)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'صافي قيمة الخصم الدفتري:',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                    ),
                    pw.Text(
                      '${_currFmt.format(returnValue)} $currency',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 9.5, color: _dangerRed),
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
  // REPORT WIDGET BUILDERS (Multi-record statement)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildReportHeader({
    required String companyName,
    required int pageNumber,
    required int totalPages,
    required String printDate,
    pw.MemoryImage? logoImage,
    String? filterQuery,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
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
                    style: pw.TextStyle(font: _boldFont, fontSize: 11, color: _navyPrimary),
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
                'سجل وتقارير مرتجعات شراء المحاصيل الزراعية',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _boldFont, fontSize: 13, color: _navyPrimary),
              ),
              if (filterQuery != null && filterQuery.trim().isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  'تصفية بحث: $filterQuery',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7, color: _cyanAccent),
                ),
              ],
            ],
          ),

          // Left: Meta Information
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'تاريخ التصدير: $printDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
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

  static pw.Widget _buildReportKpiCards({
    required CropReturnUnitSummary summary,
  }) {
    final currencySummary = summary.valueByCurrency.entries
        .map((e) => '${_currFmt.format(e.value)} ${e.key}')
        .join(' | ');

    return pw.Row(
      children: [
        _kpiCard(
          title: 'إجمالي أذونات المرتجع',
          value: '${summary.totalCount} إذن',
          subText: 'عمليات معتمدة بالسجل',
          accentColor: _navyPrimary,
        ),
        pw.SizedBox(width: 6),
        _kpiCard(
          title: 'إجمالي الوزن المرتجع',
          value: '${_qtyFmt.format(summary.totalWeightQty)} كجم',
          subText: 'صافي وزن المحاصيل (كجم)',
          accentColor: _warningAmber,
        ),
        pw.SizedBox(width: 6),
        _kpiCard(
          title: 'إجمالي الكراتين المرتجعة',
          value: '${_qtyFmt.format(summary.totalCartonQty)} كرتونة',
          subText: 'عدد الطرود والكراتين',
          accentColor: _cyanAccent,
        ),
        pw.SizedBox(width: 6),
        _kpiCard(
          title: 'إجمالي قيمة المرتجعات',
          value: currencySummary.isNotEmpty ? currencySummary : '0.00 EGP',
          subText: 'قيمة المردودات الدفترية',
          accentColor: _dangerRed,
        ),
        pw.SizedBox(width: 6),
        _kpiCard(
          title: 'القيود الدفترية المرحلة',
          value: '${summary.linkedJeCount} من ${summary.totalCount}',
          subText: 'قيود مرتبطة بالحسابات',
          accentColor: _successGreen,
        ),
      ],
    );
  }

  static pw.Widget _kpiCard({
    required String title,
    required String value,
    required String subText,
    required PdfColor accentColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _lightBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _borderColor, width: 0.6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 7, color: _mutedText),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _boldFont, fontSize: 9.5, color: accentColor),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              subText,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildReturnsDataTable(
    List<Map<String, dynamic>> returns, {
    CropReturnUnitSummary? summary,
  }) {
    if (returns.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(20),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'لا توجد بيانات مرتجعات مسجلة مطابقة لخيارات العرض',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _font, fontSize: 9, color: _mutedText),
        ),
      );
    }

    final computed = summary ?? computeSummary(returns);
    final currencySummary = computed.valueByCurrency.entries
        .map((e) => '${_currFmt.format(e.value)} ${e.key}')
        .join(' | ');

    final qtySummaryParts = <String>[];
    if (computed.totalWeightQty > 0) {
      qtySummaryParts.add('${_qtyFmt.format(computed.totalWeightQty)} كجم');
    }
    if (computed.totalCartonQty > 0) {
      qtySummaryParts.add('${_qtyFmt.format(computed.totalCartonQty)} كرتونة');
    }
    if (qtySummaryParts.isEmpty) {
      qtySummaryParts.add('0.0');
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.6),  // م
        1: pw.FlexColumnWidth(1.1),  // رقم الإذن
        2: pw.FlexColumnWidth(1.4),  // التاريخ
        3: pw.FlexColumnWidth(2.4),  // المورد
        4: pw.FlexColumnWidth(2.4),  // المحصول
        5: pw.FlexColumnWidth(1.3),  // رقم اللوط
        6: pw.FlexColumnWidth(1.6),  // المحطة
        7: pw.FlexColumnWidth(1.8),  // الكمية
        8: pw.FlexColumnWidth(1.6),  // القيمة
        9: pw.FlexColumnWidth(1.3),  // القيد
        10: pw.FlexColumnWidth(2.2), // الملاحظات
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: [
            _tableHeaderCell('م'),
            _tableHeaderCell('رقم الإذن'),
            _tableHeaderCell('تاريخ المرتجع'),
            _tableHeaderCell('المورد'),
            _tableHeaderCell('المحصول / الصنف'),
            _tableHeaderCell('رقم اللوط'),
            _tableHeaderCell('المحطة'),
            _tableHeaderCell('الكمية'),
            _tableHeaderCell('قيمة المرتجع'),
            _tableHeaderCell('رقم القيد'),
            _tableHeaderCell('الملاحظات'),
          ],
        ),
        // Rows
        for (int i = 0; i < returns.length; i++) ...[
          _buildReportDataRow(returns[i], i + 1, isEven: i % 2 == 0),
        ],
        // Segregated Totals Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _tableDataCell('', align: pw.TextAlign.center),
            _tableDataCell('الإجمالي (${computed.totalCount} إذن)', isBold: true, color: _navyPrimary),
            _tableDataCell(''),
            _tableDataCell(''),
            _tableDataCell(''),
            _tableDataCell(''),
            _tableDataCell(''),
            _tableDataCell(
              qtySummaryParts.join('\n'),
              align: pw.TextAlign.center,
              isBold: true,
              color: _navyPrimary,
            ),
            _tableDataCell(
              currencySummary.isNotEmpty ? currencySummary : '0.00',
              align: pw.TextAlign.center,
              isBold: true,
              color: _dangerRed,
            ),
            _tableDataCell('${computed.linkedJeCount} مرحل', align: pw.TextAlign.center, color: _successGreen, isBold: true),
            _tableDataCell(''),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _buildReportDataRow(
    Map<String, dynamic> item,
    int index, {
    required bool isEven,
  }) {
    final lotInfo = item['lot_receipts'] as Map<String, dynamic>? ?? {};
    final supplierInfo = item['suppliers'] as Map<String, dynamic>? ?? {};
    final stationInfo = item['stations'] as Map<String, dynamic>? ?? {};
    final jeInfo = item['journal_entries'] as Map<String, dynamic>?;

    final retId = item['id']?.toString() ?? '—';
    final lotNumber = lotInfo['lot_number']?.toString() ?? item['lot_number']?.toString() ?? '—';
    final productName = lotInfo['product_name']?.toString() ?? item['product_name']?.toString() ?? 'محصول';
    final supplierName = supplierInfo['name']?.toString() ?? item['supplier_name']?.toString() ?? '—';
    final stationName = stationInfo['name']?.toString() ?? item['station_name']?.toString() ?? '—';

    final returnedQty = (item['returned_quantity'] as num?)?.toDouble() ?? 0.0;
    final returnValue = (item['return_value'] as num?)?.toDouble() ?? 0.0;
    final unitLabel = lotInfo['purchase_mode'] == 'carton' ? 'كرتونة' : 'كجم';
    final currency = lotInfo['currency']?.toString() ?? item['currency']?.toString() ?? 'EGP';

    final dateStr = item['created_at'] != null
        ? item['created_at'].toString().split('T').first
        : '—';
    final rawJeId = item['journal_entry_id'];
    final jeNumber = jeInfo?['entry_number']?.toString() ?? (rawJeId != null ? '#$rawJeId' : '—');
    final notes = (item['notes'] ?? '').toString().trim();

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
      children: [
        _tableDataCell('$index', align: pw.TextAlign.center),
        _tableDataCell('#$retId', align: pw.TextAlign.center, isBold: true, color: _dangerRed),
        _tableDataCell(dateStr, align: pw.TextAlign.center),
        _tableDataCell(supplierName, isBold: true),
        _tableDataCell(productName),
        _tableDataCell('لوط $lotNumber', align: pw.TextAlign.center),
        _tableDataCell(stationName, align: pw.TextAlign.center),
        _tableDataCell('${_qtyFmt.format(returnedQty)} $unitLabel', align: pw.TextAlign.center),
        _tableDataCell('${_currFmt.format(returnValue)} $currency', align: pw.TextAlign.center, isBold: true),
        _tableDataCell(jeNumber, align: pw.TextAlign.center, color: rawJeId != null ? _successGreen : _mutedText),
        _tableDataCell(notes.isNotEmpty ? notes : '—', color: _mutedText),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUDIT & FINANCIAL SIGNATURES BLOCK (STANDARD 3 PILLARS)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildAuditSignaturesBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        pw.SizedBox(height: 14),
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
      padding: const pw.EdgeInsets.only(top: 4),
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
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Fruity Farms ERP • تقرير مرتجعات شراء المحاصيل • تاريخ الطباعة: $printDate',
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
