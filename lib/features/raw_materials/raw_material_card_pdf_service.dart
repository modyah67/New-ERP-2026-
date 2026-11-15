// lib/features/raw_materials/raw_material_card_pdf_service.dart
// Professional Landscape A4 Ledger & Item Card PDF Service for Packaging Materials

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
import '../../data/dao/settings_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class RawMaterialCardPdfService {
  RawMaterialCardPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Deep Navy & Cyan Packaging Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static const _navyPrimary = PdfColor.fromInt(0xFF1A365D); // Deep Navy (#1A365D)
  static const _cyanAccent  = PdfColor.fromInt(0xFF00B4D8); // Cyan Accent (#00B4D8)
  static const _cardBg      = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const _lightBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const _borderColor = PdfColor.fromInt(0xFFCBD5E1); // Slate 300
  static const _darkText    = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const _mutedText   = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const _white       = PdfColors.white;

  static const _greenText   = PdfColor.fromInt(0xFF15803D); // Green 700
  static const _greenBg     = PdfColor.fromInt(0xFFDCFCE7); // Green 100
  static const _greenBorder = PdfColor.fromInt(0xFF86EFAC); // Green 300
  static const _redText     = PdfColor.fromInt(0xFFB91C1C); // Red 700
  static const _redBg       = PdfColor.fromInt(0xFFFEE2E2); // Red 100
  static const _redBorder   = PdfColor.fromInt(0xFFFCA5A5); // Red 300
  static const _amberText   = PdfColor.fromInt(0xFFB45309); // Amber 700
  static const _amberBg     = PdfColor.fromInt(0xFFFEF3C7); // Amber 100
  static const _amberBorder = PdfColor.fromInt(0xFFFDE68A); // Amber 300

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
    required String itemName,
    required String itemCode,
    required String categoryName,
    required String unit,
    required String currency,
    required double initialQuantity,
    required double initialAvgPrice,
    required double currentQuantity,
    required double minimumStock,
    required double estimatedValue,
    required double avgCost,
    required String statusLabel,
    required List<Map<String, dynamic>> batches,
    Map<String, String>? settings,
    String? cardSerial,
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
      itemName: itemName,
      itemCode: itemCode,
      categoryName: categoryName,
      unit: unit,
      currency: currency,
      initialQuantity: initialQuantity,
      initialAvgPrice: initialAvgPrice,
      currentQuantity: currentQuantity,
      minimumStock: minimumStock,
      estimatedValue: estimatedValue,
      avgCost: avgCost,
      statusLabel: statusLabel,
      batches: batches,
      settings: resolvedSettings,
      cardSerial: cardSerial,
    );
  }

  /// Generates and opens the standard system print / export dialog in Landscape mode.
  static Future<void> generateAndPrint({
    required String itemName,
    required String itemCode,
    required String categoryName,
    required String unit,
    required String currency,
    required double initialQuantity,
    required double initialAvgPrice,
    required double currentQuantity,
    required double minimumStock,
    required double estimatedValue,
    required double avgCost,
    required String statusLabel,
    required List<Map<String, dynamic>> batches,
    Map<String, String>? settings,
    String? cardSerial,
  }) async {
    final bytes = await generatePdfBytes(
      itemName: itemName,
      itemCode: itemCode,
      categoryName: categoryName,
      unit: unit,
      currency: currency,
      initialQuantity: initialQuantity,
      initialAvgPrice: initialAvgPrice,
      currentQuantity: currentQuantity,
      minimumStock: minimumStock,
      estimatedValue: estimatedValue,
      avgCost: avgCost,
      statusLabel: statusLabel,
      batches: batches,
      settings: settings,
      cardSerial: cardSerial,
    );

    final cleanName = itemName.isNotEmpty ? itemName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') : 'صنف';
    final docTitle = _formattedFileName('كارت_صنف_$cleanName');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the landscape PDF directly to the user's export storage.
  static Future<File> saveToFile(
    BuildContext context, {
    required String itemName,
    required String itemCode,
    required String categoryName,
    required String unit,
    required String currency,
    required double initialQuantity,
    required double initialAvgPrice,
    required double currentQuantity,
    required double minimumStock,
    required double estimatedValue,
    required double avgCost,
    required String statusLabel,
    required List<Map<String, dynamic>> batches,
    Map<String, String>? settings,
    String? cardSerial,
  }) async {
    final bytes = await generatePdfBytes(
      itemName: itemName,
      itemCode: itemCode,
      categoryName: categoryName,
      unit: unit,
      currency: currency,
      initialQuantity: initialQuantity,
      initialAvgPrice: initialAvgPrice,
      currentQuantity: currentQuantity,
      minimumStock: minimumStock,
      estimatedValue: estimatedValue,
      avgCost: avgCost,
      statusLabel: statusLabel,
      batches: batches,
      settings: settings,
      cardSerial: cardSerial,
    );

    final dir = await FileHelper.getExportDirectory();
    final cleanName = itemName.isNotEmpty ? itemName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') : 'صنف';
    final fileName = _formattedFileName('كارت_صنف_$cleanName');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كارت الصنف بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDER
  // ──────────────────────────────────────────────────────────────────────────

  static Future<Uint8List> _build({
    required String itemName,
    required String itemCode,
    required String categoryName,
    required String unit,
    required String currency,
    required double initialQuantity,
    required double initialAvgPrice,
    required double currentQuantity,
    required double minimumStock,
    required double estimatedValue,
    required double avgCost,
    required String statusLabel,
    required List<Map<String, dynamic>> batches,
    required Map<String, String> settings,
    String? cardSerial,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final companyName = settings['company_name'] ?? AppConstants.companyName;
    final printDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final resolvedSerial = cardSerial ??
        '#${(DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000}';

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
                child: pw.Opacity(
                  opacity: 0.04,
                  child: pw.Image(bgImage!, fit: pw.BoxFit.cover),
                ),
              )
          : null,
    );

    // Calculate Grand Totals for FIFO batches
    final totalRemainingQty = batches.fold<double>(
      0.0,
      (sum, b) => sum + ((b['remaining_quantity'] as num?)?.toDouble() ?? 0.0),
    );
    final totalRemainingValue = batches.fold<double>(
      0.0,
      (sum, b) {
        final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        final cost = (b['purchase_cost'] as num?)?.toDouble() ?? (b['unit_cost'] as num?)?.toDouble() ?? 0.0;
        return sum + (rem * cost);
      },
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) => _buildHeader(
          companyName: companyName,
          itemName: itemName,
          itemCode: itemCode,
          serial: resolvedSerial,
          printDate: printDate,
        ),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.SizedBox(height: 10),
          // 1. Item Metadata & Inventory Overview Cards
          _buildItemOverviewCard(
            itemName: itemName,
            itemCode: itemCode,
            categoryName: categoryName,
            unit: unit,
            currency: currency,
            initialQuantity: initialQuantity,
            initialAvgPrice: initialAvgPrice,
            currentQuantity: currentQuantity,
            minimumStock: minimumStock,
            estimatedValue: estimatedValue,
            avgCost: avgCost,
            statusLabel: statusLabel,
          ),
          pw.SizedBox(height: 14),

          // 2. FIFO Movement Table Section Title
          _buildSectionHeader('حركات ودفعات الوارد المتاحة بالمخزن (FIFO)', batches.length),
          pw.SizedBox(height: 6),

          // 3. FIFO Batches Table
          _buildBatchesTable(
            batches: batches,
            currency: currency,
            unit: unit,
            totalRemainingQty: totalRemainingQty,
            totalRemainingValue: totalRemainingValue,
          ),
          pw.SizedBox(height: 16),

          // 4. Signatures / Authorization Block
          _buildSignaturesBlock(),
        ],
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER COMPONENT
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader({
    required String companyName,
    required String itemName,
    required String itemCode,
    required String serial,
    required String printDate,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _cyanAccent, width: 1.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left: Serial & Date
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _cardBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: _borderColor, width: 0.5),
                ),
                child: pw.Text(
                  'رقم التقرير: $serial',
                  style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _navyPrimary),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ الطباعة: $printDate',
                style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
              ),
            ],
          ),

          // Center: Title Badge
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: const pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Text(
                  'كارت صنف ومستلزمات تعبئة (Ledger Card)',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 12.5,
                    color: _white,
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'نظام إدارة ومتابعة المخازن والتعبئة والتغليف (FIFO)',
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: _mutedText,
                ),
              ),
            ],
          ),

          // Right: Company Name & Brand
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 12.0,
                  color: _navyPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'إدارة المخازن والمهمات',
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 8.0,
                  color: _cyanAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ITEM METADATA & INVENTORY OVERVIEW CARD
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildItemOverviewCard({
    required String itemName,
    required String itemCode,
    required String categoryName,
    required String unit,
    required String currency,
    required double initialQuantity,
    required double initialAvgPrice,
    required double currentQuantity,
    required double minimumStock,
    required double estimatedValue,
    required double avgCost,
    required String statusLabel,
  }) {
    final isOut = currentQuantity <= 0;
    final isLow = currentQuantity < minimumStock && currentQuantity > 0;
    final badgeBg = isOut ? _redBg : (isLow ? _amberBg : _greenBg);
    final badgeText = isOut ? _redText : (isLow ? _amberText : _greenText);
    final badgeBorder = isOut ? _redBorder : (isLow ? _amberBorder : _greenBorder);

    final cleanCategory = categoryName.isNotEmpty ? categoryName : '—';
    final cleanCode = itemCode.isNotEmpty ? itemCode : '—';
    final cleanUnit = unit.isNotEmpty ? unit : 'قطعة';

    final initialVal = initialQuantity * initialAvgPrice;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _borderColor, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Top Row: Item Identity & Status Badge
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Item Name and Code
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const pw.BoxDecoration(
                      color: _navyPrimary,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Text(
                      'كود: $cleanCode',
                      style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _white),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    itemName.isNotEmpty ? itemName : '—',
                    style: pw.TextStyle(font: _boldFont, fontSize: 12.0, color: _navyPrimary),
                  ),
                  if (cleanCategory != '—') ...[
                    pw.SizedBox(width: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: _lightBg,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                        border: pw.Border.all(color: _borderColor, width: 0.5),
                      ),
                      child: pw.Text(
                        'التصنيف: $cleanCategory',
                        style: pw.TextStyle(font: _font, fontSize: 8.0, color: _mutedText),
                      ),
                    ),
                  ],
                ],
              ),

              // Status Badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: badgeBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: badgeBorder, width: 0.8),
                ),
                child: pw.Text(
                  'الحالة: $statusLabel',
                  style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: badgeText),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: _borderColor, thickness: 0.5),
          pw.SizedBox(height: 6),

          // Bottom Row: 4 Metric Overview Boxes
          pw.Row(
            children: [
              // 1. Initial Stock
              pw.Expanded(
                child: _buildMetricTile(
                  label: 'الرصيد المبدأي',
                  primaryValue: initialQuantity > 0 ? '${AppUtils.formatNumber(initialQuantity)} $cleanUnit' : '—',
                  secondaryValue: initialQuantity > 0
                      ? 'سعر: ${AppUtils.formatNumber(initialAvgPrice)} | قيمة: ${AppUtils.formatNumber(initialVal)} $currency'
                      : 'لا يوجد رصيد افتتاحي',
                  accentColor: _cyanAccent,
                ),
              ),
              pw.SizedBox(width: 8),

              // 2. Current Stock Balance
              pw.Expanded(
                child: _buildMetricTile(
                  label: 'الرصيد الحالي المتاح',
                  primaryValue: '${AppUtils.formatNumber(currentQuantity)} $cleanUnit',
                  secondaryValue: 'حد الأمان: ${minimumStock > 0 ? AppUtils.formatNumber(minimumStock) : '—'} $cleanUnit',
                  accentColor: badgeText,
                ),
              ),
              pw.SizedBox(width: 8),

              // 3. Average Unit Cost
              pw.Expanded(
                child: _buildMetricTile(
                  label: 'متوسط التكلفة',
                  primaryValue: avgCost > 0 ? '${AppUtils.formatNumber(avgCost)} $currency' : '—',
                  secondaryValue: 'لكل $cleanUnit واحدة',
                  accentColor: _navyPrimary,
                ),
              ),
              pw.SizedBox(width: 8),

              // 4. Estimated Total Value
              pw.Expanded(
                child: _buildMetricTile(
                  label: 'القيمة التقديرية للمخزون',
                  primaryValue: estimatedValue > 0 ? '${AppUtils.formatNumber(estimatedValue)} $currency' : '0.00 $currency',
                  secondaryValue: 'إجمالي تقييم الرصيد الحالي',
                  accentColor: _greenText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMetricTile({
    required String label,
    required String primaryValue,
    required String secondaryValue,
    required PdfColor accentColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
        border: pw.Border.all(color: _borderColor, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            primaryValue,
            style: pw.TextStyle(font: _boldFont, fontSize: 10.5, color: accentColor),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            secondaryValue,
            style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SECTION HEADER
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildSectionHeader(String title, int count) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 3.5,
              height: 12,
              decoration: const pw.BoxDecoration(
                color: _cyanAccent,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              title,
              style: pw.TextStyle(font: _boldFont, fontSize: 9.5, color: _navyPrimary),
            ),
          ],
        ),
        pw.Text(
          'عدد الدفعات: $count',
          style: pw.TextStyle(font: _font, fontSize: 8.0, color: _mutedText),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FIFO BATCHES MOVEMENT TABLE
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildBatchesTable({
    required List<Map<String, dynamic>> batches,
    required String currency,
    required String unit,
    required double totalRemainingQty,
    required double totalRemainingValue,
  }) {
    if (batches.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 24),
        decoration: pw.BoxDecoration(
          color: _cardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: _borderColor, width: 0.6),
        ),
        child: pw.Center(
          child: pw.Text(
            'لا توجد دفعات مخزنية متاحة لهذا الصنف حالياً',
            style: pw.TextStyle(font: _font, fontSize: 10.0, color: _mutedText),
          ),
        ),
      );
    }

    const colWidths = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(28),  // #
      1: pw.FixedColumnWidth(65),  // التاريخ
      2: pw.FixedColumnWidth(95),  // المخزن
      3: pw.FlexColumnWidth(2.2),  // المورد / الفاتورة
      4: pw.FixedColumnWidth(75),  // الكمية المتاحة
      5: pw.FixedColumnWidth(70),  // سعر الوحدة
      6: pw.FixedColumnWidth(60),  // سعر الصرف
      7: pw.FixedColumnWidth(90),  // القيمة الإجمالية
    };

    final rows = <pw.TableRow>[
      // Table Header Row
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _navyPrimary,
        ),
        children: [
          _buildTh('#', align: pw.TextAlign.center),
          _buildTh('التاريخ', align: pw.TextAlign.center),
          _buildTh('المخزن', align: pw.TextAlign.right),
          _buildTh('المورد / الفاتورة', align: pw.TextAlign.right),
          _buildTh('الكمية المتاحة', align: pw.TextAlign.center),
          _buildTh('سعر الوحدة', align: pw.TextAlign.center),
          _buildTh('سعر الصرف', align: pw.TextAlign.center),
          _buildTh('القيمة الإجمالية', align: pw.TextAlign.center),
        ],
      ),
    ];

    for (int i = 0; i < batches.length; i++) {
      final b = batches[i];
      final isEven = i % 2 == 0;
      final rowBg = isEven ? _white : _cardBg;

      final dateStr = _formatDate(b['created_at']);
      final station = b['station_name']?.toString().trim() ?? '';
      final cleanStation = station.isNotEmpty ? station : 'المخزن الرئيسي';

      final supplierName = b['supplier_name']?.toString().trim() ?? '';
      final invoiceNumber = b['invoice_number']?.toString().trim() ?? '';
      String sourceDesc = supplierName.isNotEmpty
          ? supplierName
          : (b['source_type'] == 'opening' ? 'رصيد افتتاحي' : (b['source_type']?.toString().isNotEmpty == true ? b['source_type'].toString() : '—'));
      if (invoiceNumber.isNotEmpty) {
        sourceDesc += ' | $invoiceNumber';
      }

      final remQty = (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (b['purchase_cost'] as num?)?.toDouble() ?? (b['unit_cost'] as num?)?.toDouble() ?? 0.0;
      final exRate = (b['exchange_rate'] as num?)?.toDouble();
      final totalVal = remQty * unitCost;

      // Clean dash placeholder for neutral exchange rates (1.0 or null or <= 0)
      final exRateClean = (exRate != null && exRate > 0 && exRate != 1.0)
          ? exRate.toStringAsFixed(4)
          : '—';

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: rowBg,
            border: const pw.Border(
              bottom: pw.BorderSide(color: _borderColor, width: 0.4),
            ),
          ),
          children: [
            _buildTd('${i + 1}', align: pw.TextAlign.center, isMuted: true),
            _buildTd(dateStr, align: pw.TextAlign.center),
            _buildTd(cleanStation, align: pw.TextAlign.right, color: _navyPrimary),
            _buildTd(sourceDesc, align: pw.TextAlign.right),
            _buildTd(
              AppUtils.formatNumber(remQty),
              align: pw.TextAlign.center,
              isBold: true,
              color: remQty > 0 ? _greenText : _mutedText,
            ),
            _buildTd(
              unitCost > 0 ? '${AppUtils.formatNumber(unitCost)} $currency' : '—',
              align: pw.TextAlign.center,
            ),
            _buildTd(exRateClean, align: pw.TextAlign.center, isMuted: exRateClean == '—'),
            _buildTd(
              totalVal > 0 ? '${AppUtils.formatNumber(totalVal)} $currency' : '0.00 $currency',
              align: pw.TextAlign.center,
              isBold: true,
              color: _navyPrimary,
            ),
          ],
        ),
      );
    }

    // Totals Footer Row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _lightBg,
          border: pw.Border(
            top: pw.BorderSide(color: _navyPrimary, width: 1.2),
            bottom: pw.BorderSide(color: _navyPrimary, width: 1.2),
          ),
        ),
        children: [
          _buildTd('', align: pw.TextAlign.center),
          _buildTd('الإجمالي الكلي', align: pw.TextAlign.center, isBold: true, color: _navyPrimary),
          _buildTd('', align: pw.TextAlign.right),
          _buildTd('', align: pw.TextAlign.right),
          _buildTd(
            AppUtils.formatNumber(totalRemainingQty),
            align: pw.TextAlign.center,
            isBold: true,
            color: _greenText,
          ),
          _buildTd('—', align: pw.TextAlign.center, isMuted: true),
          _buildTd('—', align: pw.TextAlign.center, isMuted: true),
          _buildTd(
            '${AppUtils.formatNumber(totalRemainingValue)} $currency',
            align: pw.TextAlign.center,
            isBold: true,
            color: _navyPrimary,
          ),
        ],
      ),
    );

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.6),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 6,
        verticalRadius: 6,
        child: pw.Table(
          columnWidths: colWidths,
          children: rows,
        ),
      ),
    );
  }

  static pw.Widget _buildTh(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: _boldFont,
          fontSize: 7.8,
          color: _white,
        ),
      ),
    );
  }

  static pw.Widget _buildTd(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    bool isBold = false,
    bool isMuted = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
      child: pw.Text(
        text.isNotEmpty ? text : '—',
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? _boldFont : _font,
          fontSize: 7.5,
          color: color ?? (isMuted ? _mutedText : _darkText),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SIGNATURES BLOCK
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildSignaturesBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _borderColor, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSignatureBox('أمين المخزن المختص'),
          _buildSignatureBox('محاسب التكاليف والمخازن'),
          _buildSignatureBox('المدير المالي والاعتماد'),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureBox(String role) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          role,
          style: pw.TextStyle(font: _boldFont, fontSize: 8.0, color: _navyPrimary),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          width: 120,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _borderColor, width: 0.8, style: pw.BorderStyle.dashed),
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'التوقيع: ...........................',
          style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER COMPONENT
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderColor, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Fruity Farms ERP — نظام إدارة الموارد المتكامل',
            style: pw.TextStyle(font: _font, fontSize: 7.0, color: _mutedText),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: _font, fontSize: 7.0, color: _mutedText),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DATE HELPER
  // ──────────────────────────────────────────────────────────────────────────
  static String _formatDate(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      final s = raw.toString().trim();
      return s.length >= 10 ? s.substring(0, 10) : (s.isNotEmpty ? s : '—');
    }
  }
}

/// Convenience alias to match alternative nomenclature
typedef PackagingItemCardPdfService = RawMaterialCardPdfService;
