// lib/features/packing/packing_order_pdf_service.dart
// Professional Landscape A4 PDF Service for Packing Orders (إذن / أمر تعبئة وتغليف المحاصيل)
// Fruity Farms ERP System

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text, TextStyle;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme.dart';
import '../../core/utils/file_helper.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/services/packing_calculation_service.dart';
import 'utils/packing_excel_exporter.dart';

/// Aggregated metrics for packing orders, strictly segregating weights from packaging cartons.
class PackingOrderSummary {
  final int totalOrders;

  // Weight segregation (كجم)
  final double totalRawInputWeightKg;
  final double totalNetWeightKg;
  final double totalGrossWeightKg;
  final double totalWasteWeightKg;
  final double totalSortedWeightKg;

  // Packaging count segregation (كرتونة)
  final int totalCartonCount;
  final int totalSoldCartons;
  final int totalRemainingCartons;

  // Financial costs (EGP / display currency)
  final double totalFruitCost;
  final double totalMaterialCost;
  final double totalOperatingCost;
  final double totalPackingCost;
  final double totalAllCost;

  const PackingOrderSummary({
    required this.totalOrders,
    required this.totalRawInputWeightKg,
    required this.totalNetWeightKg,
    required this.totalGrossWeightKg,
    required this.totalWasteWeightKg,
    required this.totalSortedWeightKg,
    required this.totalCartonCount,
    required this.totalSoldCartons,
    required this.totalRemainingCartons,
    required this.totalFruitCost,
    required this.totalMaterialCost,
    required this.totalOperatingCost,
    required this.totalPackingCost,
    required this.totalAllCost,
  });

  double get averageCostPerCarton =>
      totalCartonCount > 0 ? (totalAllCost / totalCartonCount) : 0.0;

  double get averageCostPerKg =>
      totalNetWeightKg > 0 ? (totalAllCost / totalNetWeightKg) : 0.0;
}

class PackingOrderPdfService {
  PackingOrderPdfService._();

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
  static const PdfColor _warningBg   = PdfColor.fromInt(0xFFFFFBEB); // Amber 50
  static const PdfColor _dangerRed    = PdfColor.fromInt(0xFFDC2626); // Red 600

  static final intl.NumberFormat _currFmt = intl.NumberFormat('#,##0.00', 'en_US');
  static final intl.NumberFormat _qtyFmt  = intl.NumberFormat('#,##0.0#', 'en_US');

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
  // LOGO & SETTINGS HELPERS
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

  static String _statusLabel(String status) {
    switch (status) {
      case 'draft':
      case 'pending':
        return 'مسودة';
      case 'crops_confirmed':
        return 'مؤكد المحاصيل';
      case 'packaging_confirmed':
        return 'مؤكد مواد التعبئة';
      case 'costs_confirmed':
        return 'مؤكد التكاليف';
      case 'final_approved':
      case 'completed':
        return 'مؤكد ومعتمد';
      case 'in_progress':
        return 'قيد التشغيل';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SUMMARY COMPUTATION & SEGREGATION
  // ──────────────────────────────────────────────────────────────────────────

  /// Computes segregated aggregation metrics strictly separating weights (كجم)
  /// from finished packed units (كرتونة) across a list of packing orders.
  static PackingOrderSummary computeSummary(List<PackingOrderModel> orders) {
    int totalCartonCount = 0;
    int totalSoldCartons = 0;
    int totalRemainingCartons = 0;

    double totalRawInputWeightKg = 0.0;
    double totalNetWeightKg = 0.0;
    double totalGrossWeightKg = 0.0;
    double totalWasteWeightKg = 0.0;
    double totalSortedWeightKg = 0.0;

    double totalFruitCost = 0.0;
    double totalMaterialCost = 0.0;
    double totalOperatingCost = 0.0;
    double totalPackingCost = 0.0;
    double totalAllCost = 0.0;

    for (final o in orders) {
      totalCartonCount += o.cartonCount;
      totalSoldCartons += o.soldCartons;
      totalRemainingCartons += o.remainingCartons;

      totalNetWeightKg += o.totalNetWeight;
      totalGrossWeightKg += o.totalGrossWeight;

      // Extract raw weight and notes details
      double rawWeight = 0.0;
      double wasteWeight = 0.0;
      double sortedWeight = 0.0;

      if (o.notes != null && o.notes!.isNotEmpty) {
        try {
          final notes = jsonDecode(o.notes!) as Map<String, dynamic>;
          rawWeight = (notes['total_raw_weight_kg'] as num?)?.toDouble() ?? 0.0;
          wasteWeight = (notes['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
          final a = (notes['grade_a_kg'] as num?)?.toDouble() ?? 0.0;
          final b = (notes['grade_b_kg'] as num?)?.toDouble() ?? 0.0;
          final c = (notes['grade_c_kg'] as num?)?.toDouble() ?? 0.0;
          sortedWeight = a + b + c;
        } catch (_) {}
      }

      // Check lines if rawWeight wasn't in notes
      if (rawWeight == 0.0 && o.lines.isNotEmpty) {
        for (final l in o.lines) {
          rawWeight += (l.quantity > 0) ? l.quantity : (l.netWeightPerCarton * l.cartonCount);
          sortedWeight += l.sortedWeightKg;
        }
      }
      if (rawWeight == 0.0) {
        rawWeight = o.totalNetWeight;
      }

      totalRawInputWeightKg += rawWeight;
      totalWasteWeightKg += wasteWeight;
      totalSortedWeightKg += sortedWeight;

      // Financial allocation
      double opCost = o.totalPackingCost;
      if (opCost >= (o.fruitCostAllocated + o.actualMaterialCost) && opCost > 0) {
        opCost = opCost - o.fruitCostAllocated - o.actualMaterialCost;
      }

      totalFruitCost += o.fruitCostAllocated;
      totalMaterialCost += o.actualMaterialCost;
      totalOperatingCost += opCost;
      totalPackingCost += o.totalPackingCost;
      totalAllCost += (o.fruitCostAllocated + o.actualMaterialCost + opCost);
    }

    return PackingOrderSummary(
      totalOrders: orders.length,
      totalRawInputWeightKg: totalRawInputWeightKg,
      totalNetWeightKg: totalNetWeightKg,
      totalGrossWeightKg: totalGrossWeightKg,
      totalWasteWeightKg: totalWasteWeightKg,
      totalSortedWeightKg: totalSortedWeightKg,
      totalCartonCount: totalCartonCount,
      totalSoldCartons: totalSoldCartons,
      totalRemainingCartons: totalRemainingCartons,
      totalFruitCost: totalFruitCost,
      totalMaterialCost: totalMaterialCost,
      totalOperatingCost: totalOperatingCost,
      totalPackingCost: totalPackingCost,
      totalAllCost: totalAllCost,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. SINGLE PACKING ORDER VOUCHER (Landscape A4: إذن / أمر تعبئة وتغليف)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes for an individual Packing Order Voucher (Landscape A4).
  static Future<Uint8List> generateOrderVoucherPdf(
    PackingOrderModel order, {
    String? warehouseName,
    String? companyName,
  }) async {
    await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName(companyName);
    final logoImage = await _loadLogoImage();

    // Prepare calculations and breakdown data
    final preparedData = await PackingExcelExporter.prepareOrderData(order);
    final materials = preparedData?.materials ?? [];
    final costItems = preparedData?.costItems ?? [];
    final calcResult = preparedData?.calcResult;
    final summaries = preparedData?.productSummaries ?? [];

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final orderNumber = order.orderNumber.isNotEmpty ? order.orderNumber : 'PO-${order.id ?? "000"}';
    final lotNumber = order.lotNumber?.isNotEmpty == true ? order.lotNumber! : (order.lotId.isNotEmpty ? order.lotId : '—');
    final productName = order.productName?.isNotEmpty == true
        ? order.productName!
        : (order.lines.isNotEmpty ? order.lines.map((l) => l.productName).join(' ، ') : 'محصول زراعي');
    final supplierName = order.supplierName?.isNotEmpty == true ? order.supplierName! : 'المورد الرئيسي للتشغيلة';
    final effectiveStation = warehouseName?.isNotEmpty == true
        ? warehouseName!
        : (order.stationId != null ? 'محطة تعبئة وتغليف (${order.stationId})' : 'محطة التعبئة والتغليف المركزية');
    final recipeName = order.recipeName?.isNotEmpty == true ? order.recipeName! : 'المواصفة القياسية للتعبئة';
    final statusStr = _statusLabel(order.status);
    final currency = order.displayCurrency.isNotEmpty ? order.displayCurrency : 'EGP';

    final orderDateStr = order.packedAt != null
        ? intl.DateFormat('yyyy-MM-dd').format(order.packedAt!)
        : (order.createdAt != null
            ? intl.DateFormat('yyyy-MM-dd').format(order.createdAt!)
            : intl.DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    // Segregated metrics calculation
    final totalCartons = order.cartonCount;
    final netWeightPerCarton = order.netWeightPerCarton > 0
        ? order.netWeightPerCarton
        : (totalCartons > 0 ? order.totalNetWeight / totalCartons : 0.0);
    final totalNetWeight = order.totalNetWeight;
    final totalGrossWeight = order.totalGrossWeight;

    double totalRawWeight = preparedData?.totalRawWeightKg ?? 0.0;
    if (totalRawWeight == 0 && calcResult != null) {
      totalRawWeight = calcResult.weights.totalEffectiveWeight;
    }
    if (totalRawWeight == 0) {
      totalRawWeight = totalNetWeight;
    }

    double totalFruitCost = calcResult?.finalCost.fruitCost ?? order.fruitCostAllocated;
    double totalMatCost = calcResult?.finalCost.materialCost ?? order.actualMaterialCost;
    double totalOpCost = calcResult?.finalCost.costItemsTotal ??
        (order.totalPackingCost > (totalFruitCost + totalMatCost)
            ? (order.totalPackingCost - totalFruitCost - totalMatCost)
            : 0.0);
    double totalAllCost = calcResult?.finalCost.totalCost ??
        (totalFruitCost + totalMatCost + totalOpCost);
    if (totalAllCost == 0 && order.totalPackingCost > 0) {
      totalAllCost = order.totalPackingCost;
    }
    double unitCostPerCarton = totalCartons > 0 ? (totalAllCost / totalCartons) : 0.0;

    final jeNumber = order.journalEntryId != null && order.journalEntryId!.isNotEmpty
        ? 'JE-${order.journalEntryId}'
        : null;

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textDirection: pw.TextDirection.rtl,
          theme: theme,
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: _white),
          ),
        ),
        header: (context) => _buildCorporateVoucherHeader(
          companyName: effectiveCompanyName,
          orderNumber: orderNumber,
          statusStr: statusStr,
          orderDate: orderDateStr,
          printDate: printDate,
          logoImage: logoImage,
        ),
        footer: (context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _buildSystemFooter(effectiveCompanyName, printDate, context.pageNumber, context.pagesCount),
          ],
        ),
        build: (context) {
          return [
            // 1. Metadata Grid (Landscape 8-Cell Grid)
            _buildVoucherMetadataGrid(
              orderNumber: orderNumber,
              orderDate: orderDateStr,
              stationName: effectiveStation,
              productName: productName,
              lotNumber: lotNumber,
              supplierName: supplierName,
              recipeName: recipeName,
              jeNumber: jeNumber,
              currency: currency,
            ),
            pw.SizedBox(height: 2.5),

            // 2. Segregated Metric Cards (Strict separation of kg vs cartons)
            _buildVoucherKpiCards(
              totalRawInputWeightKg: totalRawWeight,
              totalPackedCartons: totalCartons,
              totalNetWeightKg: totalNetWeight,
              totalGrossWeightKg: totalGrossWeight,
              netWeightPerCarton: netWeightPerCarton,
              totalAllCost: totalAllCost,
              costPerCarton: unitCostPerCarton,
              currency: currency,
            ),
            pw.SizedBox(height: 2.5),

            // 3. Table 1: Raw Materials Input vs Output Packed Units
            _buildCropOperationTable(
              order: order,
              summaries: summaries,
              calcResult: calcResult,
              currency: currency,
            ),
            pw.SizedBox(height: 2.5),

            // 4. Table 2: Packaging Materials Used
            if (materials.isNotEmpty) ...[
              _buildMaterialsTable(materials, currency),
              pw.SizedBox(height: 2.5),
            ],

            // 5. Table 3: Operational & Direct Labor Costs
            if (costItems.isNotEmpty) ...[
              _buildCostItemsTable(costItems, currency),
              pw.SizedBox(height: 2.5),
            ],

            // 6. Accounting & GL Impact Box + Financial Summary
            _buildVoucherAccountingImpactBox(
              jeNumber: jeNumber,
              totalFruitCost: totalFruitCost,
              totalMaterialCost: totalMatCost,
              totalOperatingCost: totalOpCost,
              totalAllCost: totalAllCost,
              currency: currency,
              totalCartons: totalCartons,
              totalNetWeightKg: totalNetWeight,
            ),
            pw.SizedBox(height: 3),

            // 7. Formal Triple-Signature Block
            _buildAuditSignaturesBlock(),
          ];
        },
      ),
    );

    return doc.save();
  }

  /// Opens the print / preview dialog directly for an individual packing order voucher.
  static Future<void> printOrderVoucher(
    BuildContext context, {
    required PackingOrderModel order,
    String? warehouseName,
    String? companyName,
  }) async {
    try {
      final bytes = await generateOrderVoucherPdf(
        order,
        warehouseName: warehouseName,
        companyName: companyName,
      );
      final orderNo = order.orderNumber.isNotEmpty ? order.orderNumber : 'order';
      final docTitle = _formattedFileName('إذن_تعبئة_رقم_$orderNo');
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: docTitle,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تجهيز ملف الطباعة: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  /// Saves the individual packing order voucher to disk and returns its file path.
  static Future<String> saveOrderVoucherPdf(
    PackingOrderModel order, {
    String? warehouseName,
    String? companyName,
  }) async {
    final bytes = await generateOrderVoucherPdf(
      order,
      warehouseName: warehouseName,
      companyName: companyName,
    );
    final dir = await FileHelper.getExportDirectory();
    final orderNo = order.orderNumber.isNotEmpty ? order.orderNumber : 'order';
    final fileName = _formattedFileName('packing_order_$orderNo');
    final file = File('${dir.path}/$fileName.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. MULTI-ORDER CONSOLIDATED REGISTER (Landscape A4: سجل أوامر التعبئة)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes for a consolidated Packing Orders Register (Landscape A4).
  static Future<Uint8List> generateOrdersRegisterPdf({
    required List<PackingOrderModel> orders,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? filterQuery,
    String? companyName,
    String currency = 'EGP',
  }) async {
    await _loadFonts();
    final effectiveCompanyName = await _resolveCompanyName(companyName);
    final logoImage = await _loadLogoImage();
    final summary = computeSummary(orders);

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final printDate = intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
    String dateRangeLabel = 'كافة الفترات المسجلة';
    if (dateFrom != null && dateTo != null) {
      dateRangeLabel = 'من ${intl.DateFormat('yyyy-MM-dd').format(dateFrom)} إلى ${intl.DateFormat('yyyy-MM-dd').format(dateTo)}';
    } else if (dateFrom != null) {
      dateRangeLabel = 'من تاريخ ${intl.DateFormat('yyyy-MM-dd').format(dateFrom)}';
    } else if (dateTo != null) {
      dateRangeLabel = 'حتى تاريخ ${intl.DateFormat('yyyy-MM-dd').format(dateTo)}';
    }

    const int itemsPerPage = 12;
    final totalPages = orders.isEmpty ? 1 : (orders.length / itemsPerPage).ceil();

    for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final startIndex = pageIdx * itemsPerPage;
      final pageItems = orders.sublist(
        startIndex,
        (startIndex + itemsPerPage).clamp(0, orders.length),
      );
      final isLastPage = (pageIdx == totalPages - 1);

      doc.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4.landscape,
            orientation: pw.PageOrientation.landscape,
            margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                // Header on every page
                _buildRegisterReportHeader(
                  companyName: effectiveCompanyName,
                  dateRangeLabel: dateRangeLabel,
                  printDate: printDate,
                  pageNumber: pageIdx + 1,
                  totalPages: totalPages,
                  logoImage: logoImage,
                  filterQuery: filterQuery,
                ),
                pw.SizedBox(height: 6),

                // Top KPI Summary Cards (First page only)
                if (pageIdx == 0) ...[
                  _buildRegisterSummaryCards(summary, currency),
                  pw.SizedBox(height: 6),
                ],

                // Data Table with explicit segregated columns
                pw.Expanded(
                  child: _buildRegisterTable(
                    items: pageItems,
                    startIndex: startIndex,
                    currency: currency,
                    isLastPage: isLastPage,
                    summary: summary,
                  ),
                ),

                // Triple Signatures Block on the last page
                if (isLastPage) ...[
                  pw.SizedBox(height: 6),
                  _buildAuditSignaturesBlock(),
                  pw.SizedBox(height: 4),
                ],

                // Footer
                _buildSystemFooter(effectiveCompanyName, printDate, pageIdx + 1, totalPages),
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }

  /// Opens the print / preview dialog directly for the consolidated Packing Orders Register.
  static Future<void> printOrdersRegister(
    BuildContext context, {
    required List<PackingOrderModel> orders,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? filterQuery,
    String? companyName,
    String currency = 'EGP',
  }) async {
    try {
      final bytes = await generateOrdersRegisterPdf(
        orders: orders,
        dateFrom: dateFrom,
        dateTo: dateTo,
        filterQuery: filterQuery,
        companyName: companyName,
        currency: currency,
      );
      final docTitle = _formattedFileName('سجل_أوامر_التعبئة_والتغليف');
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: docTitle,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء طباعة السجل: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  /// Saves the consolidated Packing Orders Register to disk.
  static Future<String> saveOrdersRegisterPdf({
    required List<PackingOrderModel> orders,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? filterQuery,
    String? companyName,
    String currency = 'EGP',
  }) async {
    final bytes = await generateOrdersRegisterPdf(
      orders: orders,
      dateFrom: dateFrom,
      dateTo: dateTo,
      filterQuery: filterQuery,
      companyName: companyName,
      currency: currency,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('packing_orders_register');
    final file = File('${dir.path}/$fileName.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VOUCHER HEADER, METADATA & KPI BUILDERS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCorporateVoucherHeader({
    required String companyName,
    required String orderNumber,
    required String statusStr,
    required String orderDate,
    required String printDate,
    pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navyPrimary, width: 1.2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right: Corporate Identity
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
                      fontSize: 11,
                      color: _navyPrimary,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'FRUITY FARMS FOR AGRICULTURAL EXPORT - PACKING & PROCESSING DIVISION',
                    style: pw.TextStyle(
                      font: _font,
                      fontSize: 6,
                      color: _mutedText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center: Document Title Badge with Order Number
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: _navyPrimary,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'إذن / أمر تعبئة وتغليف المحاصيل',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 11, color: _white),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'CROP PACKING & PACKAGING WORK ORDER',
                  style: pw.TextStyle(font: _font, fontSize: 5.5, color: _cyanAccent),
                ),
              ],
            ),
          ),

          // Left: Order # & Status Badge
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: _statusStrColorBg(statusStr),
                      border: pw.Border.all(color: _statusStrColor(statusStr), width: 0.8),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      statusStr,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: _boldFont,
                        fontSize: 8,
                        color: _statusStrColor(statusStr),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    orderNumber,
                    style: pw.TextStyle(font: _boldFont, fontSize: 12, color: _navyPrimary),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'تاريخ التعبئة: $orderDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 7.5, color: _darkText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static PdfColor _statusStrColor(String status) {
    if (status.contains('مؤكد') || status.contains('معتمد')) return _successGreen;
    if (status.contains('تشغيل')) return _cyanAccent;
    if (status.contains('ملغي')) return _dangerRed;
    return _warningAmber;
  }

  static PdfColor _statusStrColorBg(String status) {
    if (status.contains('مؤكد') || status.contains('معتمد')) return _successBg;
    if (status.contains('تشغيل')) return _lightBg;
    if (status.contains('ملغي')) return const PdfColor.fromInt(0xFFFEF2F2);
    return _warningBg;
  }

  static pw.Widget _buildVoucherMetadataGrid({
    required String orderNumber,
    required String orderDate,
    required String stationName,
    required String productName,
    required String lotNumber,
    required String supplierName,
    required String recipeName,
    required String? jeNumber,
    required String currency,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _cardBg,
        border: pw.Border.all(color: _borderColor, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              _buildMetaCell('رقم أمر التعبئة', orderNumber, isBold: true, isHighlight: true),
              pw.SizedBox(width: 4),
              _buildMetaCell('تاريخ التشغيل والتعبئة', orderDate),
              pw.SizedBox(width: 4),
              _buildMetaCell('المحطة / خط الإنتاج', stationName, isBold: true),
              pw.SizedBox(width: 4),
              _buildMetaCell('المحصول / الصنف المعبأ', productName, isBold: true, customColor: _navyPrimary),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            children: [
              _buildMetaCell('رقم اللوط / التشغيلة', lotNumber),
              pw.SizedBox(width: 4),
              _buildMetaCell('المورد / المزرعة', supplierName),
              pw.SizedBox(width: 4),
              _buildMetaCell('مواصفة / تركيبة التعبئة', recipeName),
              pw.SizedBox(width: 4),
              _buildMetaCell(
                'القيد المحاسبي المرتبط',
                jeNumber ?? 'قيد تلقائي عند التأكيد',
                isBold: true,
                customColor: jeNumber != null ? _successGreen : _mutedText,
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
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.2),
        decoration: pw.BoxDecoration(
          color: isHighlight ? _lightBg : _white,
          border: pw.Border.all(color: _borderColor, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
            ),
            pw.SizedBox(height: 0.5),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                font: (isBold || isHighlight) ? _boldFont : _font,
                fontSize: 7.2,
                color: customColor ?? (isHighlight ? _navyPrimary : _darkText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildVoucherKpiCards({
    required double totalRawInputWeightKg,
    required int totalPackedCartons,
    required double totalNetWeightKg,
    required double totalGrossWeightKg,
    required double netWeightPerCarton,
    required double totalAllCost,
    required double costPerCarton,
    required String currency,
  }) {
    return pw.Row(
      children: [
        _buildKpiCard(
          title: 'وزن المواد الخام المدخلة',
          value: '${_qtyFmt.format(totalRawInputWeightKg)} كجم',
          subtext: 'إجمالي مدخلات الفرز والتشغيل',
          borderColor: _navyPrimary,
          valueColor: _navyPrimary,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'إنتاج الكراتين والعبوات',
          value: '$totalPackedCartons كرتونة',
          subtext: 'الإنتاج التام الجاهز للشحن',
          borderColor: _cyanAccent,
          valueColor: _cyanAccent,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'إجمالي الوزن الصافي المعبأ',
          value: '${_qtyFmt.format(totalNetWeightKg)} كجم',
          subtext: totalGrossWeightKg > 0 ? 'القائم: ${_qtyFmt.format(totalGrossWeightKg)} كجم' : 'صافي الفاكهة في العبوات',
          borderColor: _successGreen,
          valueColor: _successGreen,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'وزن الكرتونة الواحدة',
          value: '${_qtyFmt.format(netWeightPerCarton)} كجم / كرتونة',
          subtext: 'العيار القياسي للعبوة',
          borderColor: _borderColor,
          valueColor: _darkText,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'إجمالي تكلفة أمر التعبئة',
          value: '${_currFmt.format(totalAllCost)} $currency',
          subtext: 'خام + مواد تعبئة + تشغيل',
          borderColor: _navyPrimary,
          valueColor: _navyPrimary,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'تكلفة الكرتونة التامة',
          value: '${_currFmt.format(costPerCarton)} $currency',
          subtext: 'متوسط تكلفة إنتاج الكرتونة',
          borderColor: _warningAmber,
          valueColor: _warningAmber,
        ),
      ],
    );
  }

  static pw.Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtext,
    required PdfColor borderColor,
    required PdfColor valueColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        decoration: pw.BoxDecoration(
          color: _white,
          border: pw.Border.all(color: borderColor, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4.5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 6.2, color: _mutedText),
            ),
            pw.SizedBox(height: 1.5),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _boldFont, fontSize: 8, color: valueColor),
            ),
            pw.SizedBox(height: 0.5),
            pw.Text(
              subtext,
              textDirection: pw.TextDirection.rtl,
              maxLines: 1,
              style: pw.TextStyle(font: _font, fontSize: 5, color: _mutedText),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TABLES BUILDERS (CROP OPERATION, MATERIALS, OPERATIONAL COSTS)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCropOperationTable({
    required PackingOrderModel order,
    required List<Map<String, dynamic>> summaries,
    required PackingCalcResult? calcResult,
    required String currency,
  }) {
    final rows = <pw.TableRow>[];

    // Table Header
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _navyPrimary),
        children: [
          _tableHeaderCell('م'),
          _tableHeaderCell('بيان الصنف والمحصول'),
          _tableHeaderCell('رقم اللوط'),
          _tableHeaderCell('وزن الخام المدخل (كجم)'),
          _tableHeaderCell('كراتين الإنتاج (كرتونة)'),
          _tableHeaderCell('صافي الكرتونة (كجم)'),
          _tableHeaderCell('إجمالي الوزن الصافي (كجم)'),
          _tableHeaderCell('الهالك والفرز (كجم)'),
          _tableHeaderCell('تكلفة الخام ($currency)'),
        ],
      ),
    );

    if (summaries.isNotEmpty) {
      for (int i = 0; i < summaries.length; i++) {
        final s = summaries[i];
        final isEven = i % 2 == 0;
        final pName = s['productName']?.toString() ?? order.productName ?? 'محصول';
        final cartonCount = (s['cartonCount'] as num?)?.toInt() ?? 0;
        final totalNet = (s['totalNetWeight'] as num?)?.toDouble() ?? 0.0;
        final netPerCrt = cartonCount > 0 ? (totalNet / cartonCount) : 0.0;
        final rawCost = (s['originalCurrencyTotalCost'] as num?)?.toDouble() ?? 0.0;
        final wasteCost = (s['wasteCost'] as num?)?.toDouble() ?? 0.0;

        double lineRawWeight = totalNet;
        double lineWasteCost = wasteCost;
        if (calcResult != null && i < calcResult.productLines.length) {
          final pl = calcResult.productLines[i];
          lineRawWeight = pl.totalNetWeight;
          lineWasteCost = pl.wasteCost;
        }

        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
            children: [
              _tableDataCell('${i + 1}', align: pw.TextAlign.center),
              _tableDataCell(pName, isBold: true, color: _navyPrimary),
              _tableDataCell(order.lotNumber ?? '—', align: pw.TextAlign.center),
              _tableDataCell('${_qtyFmt.format(lineRawWeight)} كجم', align: pw.TextAlign.center, isBold: true),
              _tableDataCell('$cartonCount كرتونة', align: pw.TextAlign.center, isBold: true, color: _cyanAccent),
              _tableDataCell('${_qtyFmt.format(netPerCrt)} كجم', align: pw.TextAlign.center),
              _tableDataCell('${_qtyFmt.format(totalNet)} كجم', align: pw.TextAlign.center, color: _successGreen, isBold: true),
              _tableDataCell(
                lineWasteCost > 0 ? '${_currFmt.format(lineWasteCost)} ج.م' : '—',
                align: pw.TextAlign.center,
                color: _warningAmber,
              ),
              _tableDataCell(_currFmt.format(rawCost), align: pw.TextAlign.center, isBold: true),
            ],
          ),
        );
      }
    } else {
      // Single row fallback using order header
      final totalNet = order.totalNetWeight;
      final cartons = order.cartonCount;
      final netPerCrt = order.netWeightPerCarton > 0 ? order.netWeightPerCarton : (cartons > 0 ? totalNet / cartons : 0.0);

      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _white),
          children: [
            _tableDataCell('1', align: pw.TextAlign.center),
            _tableDataCell(order.productName ?? 'محصول زراعي', isBold: true, color: _navyPrimary),
            _tableDataCell(order.lotNumber ?? '—', align: pw.TextAlign.center),
            _tableDataCell('${_qtyFmt.format(totalNet)} كجم', align: pw.TextAlign.center, isBold: true),
            _tableDataCell('$cartons كرتونة', align: pw.TextAlign.center, isBold: true, color: _cyanAccent),
            _tableDataCell('${_qtyFmt.format(netPerCrt)} كجم', align: pw.TextAlign.center),
            _tableDataCell('${_qtyFmt.format(totalNet)} كجم', align: pw.TextAlign.center, color: _successGreen, isBold: true),
            _tableDataCell('—', align: pw.TextAlign.center),
            _tableDataCell(_currFmt.format(order.fruitCostAllocated), align: pw.TextAlign.center, isBold: true),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'أولاً: بيان تشغيل المحاصيل الخام ومخرجات التعبئة (مدخلات ومخرجات الإنتاج):',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),  // م
            1: pw.FlexColumnWidth(2.6),  // بيان الصنف
            2: pw.FlexColumnWidth(1.4),  // اللوط
            3: pw.FlexColumnWidth(1.6),  // وزن الخام (كجم)
            4: pw.FlexColumnWidth(1.6),  // كراتين الإنتاج (كرتونة)
            5: pw.FlexColumnWidth(1.4),  // صافي الكرتونة (كجم)
            6: pw.FlexColumnWidth(1.6),  // إجمالي الوزن الصافي (كجم)
            7: pw.FlexColumnWidth(1.4),  // الهالك والفرز
            8: pw.FlexColumnWidth(1.6),  // تكلفة الخام
          },
          children: rows,
        ),
      ],
    );
  }

  static pw.Widget _buildMaterialsTable(List<Map<String, dynamic>> materials, String currency) {
    final rows = <pw.TableRow>[];

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _navyPrimary),
        children: [
          _tableHeaderCell('م'),
          _tableHeaderCell('بيان مادة التعبئة والتغليف المستهلكة'),
          _tableHeaderCell('الكمية المستهلكة'),
          _tableHeaderCell('الوحدة'),
          _tableHeaderCell('تكلفة الوحدة ($currency)'),
          _tableHeaderCell('نسبة الفقد (%)'),
          _tableHeaderCell('إجمالي تكلفة المادة ($currency)'),
        ],
      ),
    );

    double totalMaterialsCost = 0.0;
    for (int i = 0; i < materials.length; i++) {
      final m = materials[i];
      final isEven = i % 2 == 0;
      final name = m['product_name']?.toString() ?? m['name']?.toString() ?? 'مادة تعبئة';
      final qty = ((m['used_qty'] ?? m['quantity'] ?? 0) as num).toDouble();
      final unit = m['unit']?.toString() ?? 'قطعة';
      final unitCost = ((m['unit_cost'] ?? m['unit_price'] ?? 0) as num).toDouble();
      final lineCost = qty * unitCost;
      totalMaterialsCost += lineCost;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
          children: [
            _tableDataCell('${i + 1}', align: pw.TextAlign.center),
            _tableDataCell(name, isBold: true),
            _tableDataCell(_qtyFmt.format(qty), align: pw.TextAlign.center, isBold: true),
            _tableDataCell(unit, align: pw.TextAlign.center),
            _tableDataCell(_currFmt.format(unitCost), align: pw.TextAlign.center),
            _tableDataCell('0.0 %', align: pw.TextAlign.center),
            _tableDataCell(_currFmt.format(lineCost), align: pw.TextAlign.center, isBold: true, color: _navyPrimary),
          ],
        ),
      );
    }

    // Totals row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _lightBg),
        children: [
          _tableDataCell('', align: pw.TextAlign.center),
          _tableDataCell('إجمالي مواد ومستلزمات التعبئة والتغليف المستخدمة', isBold: true, color: _navyPrimary),
          _tableDataCell(''),
          _tableDataCell(''),
          _tableDataCell(''),
          _tableDataCell(''),
          _tableDataCell(_currFmt.format(totalMaterialsCost), align: pw.TextAlign.center, isBold: true, color: _navyPrimary),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ثانياً: مواد ومستلزمات التعبئة والتغليف المصروفة على التشغيلة:',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),  // م
            1: pw.FlexColumnWidth(3.5),  // بيان مادة التعبئة
            2: pw.FlexColumnWidth(1.5),  // الكمية
            3: pw.FlexColumnWidth(1.2),  // الوحدة
            4: pw.FlexColumnWidth(1.8),  // تكلفة الوحدة
            5: pw.FlexColumnWidth(1.4),  // الفقد %
            6: pw.FlexColumnWidth(2.0),  // إجمالي التكلفة
          },
          children: rows,
        ),
      ],
    );
  }

  static pw.Widget _buildCostItemsTable(List<Map<String, dynamic>> costItems, String currency) {
    final rows = <pw.TableRow>[];

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _navyPrimary),
        children: [
          _tableHeaderCell('م'),
          _tableHeaderCell('بيان بند التكلفة والمصروف المباشر'),
          _tableHeaderCell('المورد / جهة الصرف'),
          _tableHeaderCell('الكمية / عدد الساعات'),
          _tableHeaderCell('الفئة ($currency)'),
          _tableHeaderCell('إجمالي القيمة المحملة ($currency)'),
        ],
      ),
    );

    double totalDirectCost = 0.0;
    for (int i = 0; i < costItems.length; i++) {
      final c = costItems[i];
      final isEven = i % 2 == 0;
      final name = c['name']?.toString() ?? 'بند تكلفة تشغيلية';
      final supplier = c['supplier_name']?.toString() ?? 'داخلي / عمالة المحطة';
      final qty = ((c['quantity'] ?? 1) as num).toDouble();
      final unitPrice = ((c['unit_price'] ?? c['total'] ?? 0) as num).toDouble();
      final total = ((c['total'] ?? (qty * unitPrice)) as num).toDouble();
      totalDirectCost += total;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
          children: [
            _tableDataCell('${i + 1}', align: pw.TextAlign.center),
            _tableDataCell(name, isBold: true),
            _tableDataCell(supplier, align: pw.TextAlign.center),
            _tableDataCell(_qtyFmt.format(qty), align: pw.TextAlign.center),
            _tableDataCell(_currFmt.format(unitPrice), align: pw.TextAlign.center),
            _tableDataCell(_currFmt.format(total), align: pw.TextAlign.center, isBold: true, color: _navyPrimary),
          ],
        ),
      );
    }

    // Totals row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _lightBg),
        children: [
          _tableDataCell('', align: pw.TextAlign.center),
          _tableDataCell('إجمالي بنود التكاليف المباشرة والتشغيلية', isBold: true, color: _navyPrimary),
          _tableDataCell(''),
          _tableDataCell(''),
          _tableDataCell(''),
          _tableDataCell(_currFmt.format(totalDirectCost), align: pw.TextAlign.center, isBold: true, color: _navyPrimary),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ثالثاً: تكاليف التشغيل والعمالة المباشرة المحملة على أمر التعبئة:',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: _borderColor, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),  // م
            1: pw.FlexColumnWidth(3.5),  // بيان بند التكلفة
            2: pw.FlexColumnWidth(2.5),  // المورد
            3: pw.FlexColumnWidth(1.5),  // الكمية
            4: pw.FlexColumnWidth(1.8),  // الفئة
            5: pw.FlexColumnWidth(2.0),  // إجمالي القيمة
          },
          children: rows,
        ),
      ],
    );
  }

  static pw.Widget _buildVoucherAccountingImpactBox({
    required String? jeNumber,
    required double totalFruitCost,
    required double totalMaterialCost,
    required double totalOperatingCost,
    required double totalAllCost,
    required String currency,
    required int totalCartons,
    required double totalNetWeightKg,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left Box: Cost Breakdown Summary
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4.5),
            decoration: pw.BoxDecoration(
              color: _cardBg,
              border: pw.Border.all(color: _borderColor, width: 0.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ملخص تكاليف أمر التعبئة والتغليف:',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
                ),
                pw.SizedBox(height: 2),
                _summaryCostLine('تكلفة المحاصيل الزراعية الخام:', '${_currFmt.format(totalFruitCost)} $currency'),
                _summaryCostLine('تكلفة مواد ومستلزمات التعبئة والتغليف:', '${_currFmt.format(totalMaterialCost)} $currency'),
                _summaryCostLine('تكاليف التشغيل والعمالة المباشرة:', '${_currFmt.format(totalOperatingCost)} $currency'),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.5))),
                ),
                _summaryCostLine('إجمالي تكلفة أمر التعبئة والتشغيل:', '${_currFmt.format(totalAllCost)} $currency', isBold: true, color: _navyPrimary),
                if (totalCartons > 0)
                  _summaryCostLine('تكلفة الكرتونة المعبأة الواحدة:', '${_currFmt.format(totalAllCost / totalCartons)} $currency / كرتونة', isBold: true, color: _warningAmber),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 6),

        // Right Box: ERP Journal Entry & GL Direction Box
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4.5),
            decoration: pw.BoxDecoration(
              color: _successBg,
              border: pw.Border.all(color: _successGreen, width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'التوجيه المحاسبي وأثر القيد بالدفاتر العامة:',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _successGreen),
                    ),
                    if (jeNumber != null)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: const pw.BoxDecoration(
                          color: _white,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          jeNumber,
                          style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _navyPrimary),
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '• طرف مدين (Dr): حساب مخزن الإنتاج التام 12413 (استلام كراتين جاهزة للتصدير).',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
                pw.Text(
                  '• طرف مدين (Dr): حساب مخزن الفرز والتالف 12414 (تكلفة كميات الفرز المستخرجة إن وجدت).',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
                pw.Text(
                  '• طرف دائن (Cr): حساب مخزن مشتريات خام 12412 (صرف المحصول للتعبئة).',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
                pw.Text(
                  '• طرف دائن (Cr): حساب مخزن مواد التعبئة والتغليف 12411 (صرف الكراتين ومستلزماتها بدون الهالك).',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
                pw.Text(
                  '• طرف دائن (Cr): حسابات وسطاء الهالك (9112 وسيط هالك المحاصيل / 9111 وسيط هالك التعبئة).',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
                pw.Text(
                  '• طرف دائن (Cr): حسابات الموردين وبنود التكاليف الإضافية ومصروفات التشغيل المحملة.',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.8, color: _darkText),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _summaryCostLine(String label, String value, {bool isBold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: isBold ? _boldFont : _font, fontSize: 7, color: _darkText),
          ),
          pw.Text(
            value,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: isBold ? _boldFont : _font, fontSize: 7.5, color: color ?? _darkText),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REGISTER WIDGET BUILDERS (CONSOLIDATED MULTI-ORDER REPORT)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildRegisterReportHeader({
    required String companyName,
    required String dateRangeLabel,
    required String printDate,
    required int pageNumber,
    required int totalPages,
    pw.MemoryImage? logoImage,
    String? filterQuery,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 5),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navyPrimary, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right: Brand & Title
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: _navyPrimary),
                  ),
                  pw.Text(
                    'سجل وبيان أوامر التعبئة والتغليف والتشغيل',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _boldFont, fontSize: 11, color: _navyPrimary),
                  ),
                ],
              ),
            ],
          ),

          // Center: Filter & Period Info
          pw.Column(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: _lightBg,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'الفترة: $dateRangeLabel',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
                ),
              ),
              if (filterQuery != null && filterQuery.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'تصفية البحث: "$filterQuery"',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
                ),
              ],
            ],
          ),

          // Left: Page & Print Info
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'صفحة $pageNumber من $totalPages',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
              ),
              pw.Text(
                'تاريخ التقرير: $printDate',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: _font, fontSize: 7, color: _darkText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRegisterSummaryCards(PackingOrderSummary summary, String currency) {
    return pw.Row(
      children: [
        _buildKpiCard(
          title: 'إجمالي أوامر التعبئة',
          value: '${summary.totalOrders} أمر',
          subtext: 'عدد الأوامر المندرجة بالسجل',
          borderColor: _navyPrimary,
          valueColor: _navyPrimary,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'وزن الخام المدخل (كجم)',
          value: '${_qtyFmt.format(summary.totalRawInputWeightKg)} كجم',
          subtext: 'إجمالي المحصول الخام المدخل',
          borderColor: _navyPrimary,
          valueColor: _navyPrimary,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'كراتين الإنتاج (كرتونة)',
          value: '${summary.totalCartonCount} كرتونة',
          subtext: 'متبقي: ${summary.totalRemainingCartons} كرتونة',
          borderColor: _cyanAccent,
          valueColor: _cyanAccent,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'إجمالي الوزن الصافي (كجم)',
          value: '${_qtyFmt.format(summary.totalNetWeightKg)} كجم',
          subtext: 'القائم: ${_qtyFmt.format(summary.totalGrossWeightKg)} كجم',
          borderColor: _successGreen,
          valueColor: _successGreen,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'إجمالي تكلفة التعبئة',
          value: '${_currFmt.format(summary.totalAllCost)} $currency',
          subtext: 'خام + مواد + تشغيل',
          borderColor: _navyPrimary,
          valueColor: _navyPrimary,
        ),
        pw.SizedBox(width: 4),
        _buildKpiCard(
          title: 'متوسط تكلفة الكرتونة',
          value: '${_currFmt.format(summary.averageCostPerCarton)} $currency',
          subtext: 'للكيلو: ${_currFmt.format(summary.averageCostPerKg)} ج.م',
          borderColor: _warningAmber,
          valueColor: _warningAmber,
        ),
      ],
    );
  }

  static pw.Widget _buildRegisterTable({
    required List<PackingOrderModel> items,
    required int startIndex,
    required String currency,
    required bool isLastPage,
    required PackingOrderSummary summary,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.5),  // م
        1: pw.FlexColumnWidth(1.5),  // رقم الأمر
        2: pw.FlexColumnWidth(1.2),  // التاريخ
        3: pw.FlexColumnWidth(1.8),  // المحطة / المخزن
        4: pw.FlexColumnWidth(2.2),  // بيان الصنف والمحصول
        5: pw.FlexColumnWidth(1.6),  // اللوط / المورد
        6: pw.FlexColumnWidth(1.4),  // وزن الخام (كجم)
        7: pw.FlexColumnWidth(1.4),  // كراتين الإنتاج (كرتونة)
        8: pw.FlexColumnWidth(1.3),  // صافي الكرتونة
        9: pw.FlexColumnWidth(1.5),  // إجمالي الصافي (كجم)
        10: pw.FlexColumnWidth(1.7), // إجمالي التكلفة
        11: pw.FlexColumnWidth(1.3), // القيد
        12: pw.FlexColumnWidth(1.1), // الحالة
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: [
            _tableHeaderCell('م'),
            _tableHeaderCell('رقم الأمر'),
            _tableHeaderCell('التاريخ'),
            _tableHeaderCell('المحطة'),
            _tableHeaderCell('بيان الصنف والمحصول'),
            _tableHeaderCell('اللوط / المورد'),
            _tableHeaderCell('وزن الخام (كجم)'),
            _tableHeaderCell('كراتين الإنتاج'),
            _tableHeaderCell('وزن الكرتونة'),
            _tableHeaderCell('إجمالي الصافي (كجم)'),
            _tableHeaderCell('إجمالي التكلفة ($currency)'),
            _tableHeaderCell('القيد'),
            _tableHeaderCell('الحالة'),
          ],
        ),
        // Item Rows
        ...items.asMap().entries.map((entry) {
          final idx = startIndex + entry.key + 1;
          final o = entry.value;
          final isEven = entry.key % 2 == 0;
          final dateStr = o.packedAt != null
              ? intl.DateFormat('yyyy-MM-dd').format(o.packedAt!)
              : (o.createdAt != null ? intl.DateFormat('yyyy-MM-dd').format(o.createdAt!) : '—');

          double packingCost = o.totalPackingCost;
          if (packingCost >= (o.fruitCostAllocated + o.actualMaterialCost) && packingCost > 0) {
            packingCost = packingCost - o.fruitCostAllocated - o.actualMaterialCost;
          }
          final totalCost = o.fruitCostAllocated + packingCost + o.actualMaterialCost;

          final cartons = o.cartonCount;
          final netWeight = o.totalNetWeight;
          final netPerCrt = o.netWeightPerCarton > 0 ? o.netWeightPerCarton : (cartons > 0 ? netWeight / cartons : 0.0);

          double rawWeight = 0.0;
          if (o.notes != null && o.notes!.isNotEmpty) {
            try {
              final n = jsonDecode(o.notes!) as Map<String, dynamic>;
              rawWeight = (n['total_raw_weight_kg'] as num?)?.toDouble() ?? 0.0;
            } catch (_) {}
          }
          if (rawWeight == 0.0) rawWeight = netWeight;

          final jeLabel = o.journalEntryId != null && o.journalEntryId!.isNotEmpty
              ? 'قيد ${o.journalEntryId}'
              : '—';

          final pName = o.lines.length > 1
              ? '${o.lines.length} أصناف: ${o.lines.map((l) => l.productName).join("، ")}'
              : (o.productName ?? '—');

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? _white : _zebraBg),
            children: [
              _tableDataCell('$idx', align: pw.TextAlign.center),
              _tableDataCell(o.orderNumber, isBold: true, color: _navyPrimary),
              _tableDataCell(dateStr, align: pw.TextAlign.center),
              _tableDataCell(o.stationId != null ? 'محطة ${o.stationId}' : 'محطة مركزية', align: pw.TextAlign.center),
              _tableDataCell(pName, isBold: true),
              _tableDataCell(o.lotNumber ?? o.supplierName ?? '—', align: pw.TextAlign.center),
              _tableDataCell('${_qtyFmt.format(rawWeight)} كجم', align: pw.TextAlign.center, isBold: true),
              _tableDataCell('$cartons كرتونة', align: pw.TextAlign.center, isBold: true, color: _cyanAccent),
              _tableDataCell('${_qtyFmt.format(netPerCrt)} كجم', align: pw.TextAlign.center),
              _tableDataCell('${_qtyFmt.format(netWeight)} كجم', align: pw.TextAlign.center, color: _successGreen, isBold: true),
              _tableDataCell(_currFmt.format(totalCost), align: pw.TextAlign.center, isBold: true),
              _tableDataCell(jeLabel, align: pw.TextAlign.center, color: jeLabel != '—' ? _successGreen : _mutedText),
              _tableDataCell(_statusLabel(o.status), align: pw.TextAlign.center),
            ],
          );
        }),

        // Segregated Totals Row (Last Page)
        if (isLastPage) ...[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _lightBg),
            children: [
              _tableDataCell(''),
              _tableDataCell('الإجمالي الكلي المعتمد بالسجل', isBold: true, color: _navyPrimary),
              _tableDataCell(''),
              _tableDataCell(''),
              _tableDataCell(''),
              _tableDataCell(''),
              // Segregated Raw Weight Total (كجم)
              _tableDataCell(
                '${_qtyFmt.format(summary.totalRawInputWeightKg)} كجم',
                align: pw.TextAlign.center,
                isBold: true,
                color: _navyPrimary,
              ),
              // Segregated Cartons Total (كرتونة)
              _tableDataCell(
                '${summary.totalCartonCount} كرتونة',
                align: pw.TextAlign.center,
                isBold: true,
                color: _cyanAccent,
              ),
              _tableDataCell(''),
              // Segregated Net Weight Total (كجم)
              _tableDataCell(
                '${_qtyFmt.format(summary.totalNetWeightKg)} كجم',
                align: pw.TextAlign.center,
                isBold: true,
                color: _successGreen,
              ),
              // Total Cost
              _tableDataCell(
                _currFmt.format(summary.totalAllCost),
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

  // ──────────────────────────────────────────────────────────────────────────
  // AUDIT & FINANCIAL SIGNATURES BLOCK (STANDARD 3 PILLARS)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildAuditSignaturesBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
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

  static pw.Widget _buildSignatureSlot(String titleAr, String titleEn) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          titleAr,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 7, color: _navyPrimary),
        ),
        pw.SizedBox(height: 0.5),
        pw.Text(
          titleEn,
          style: pw.TextStyle(font: _font, fontSize: 4.5, color: _mutedText),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: 125,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.8)),
          ),
        ),
        pw.SizedBox(height: 1.5),
        pw.Text(
          'التوقيع والختم: ..........................',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
        ),
      ],
    );
  }

  static pw.Widget _buildSystemFooter(String companyName, String printDate, [int? page, int? totalPages]) {
    final pageStr = (page != null && totalPages != null) ? ' | صفحة $page من $totalPages' : '';
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2),
      padding: const pw.EdgeInsets.only(top: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Fruity Farms ERP System - Packing & Processing Module$pageStr',
            style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
          ),
          pw.Text(
            'وثيقة رسمية صادرة آلياً من النظام المحاسبي - $companyName | تاريخ الاستخراج: $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 5.5, color: _mutedText),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeaderCell(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2, horizontal: 2.5),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: _boldFont, fontSize: 6.5, color: _white),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8, horizontal: 2.5),
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
          fontSize: 6.8,
          color: color ?? _darkText,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BACKWARD COMPATIBILITY ADAPTERS (LEGACY SIGNATURE WRAPPERS)
  // ──────────────────────────────────────────────────────────────────────────

  /// Legacy wrapper to maintain backward compatibility with old calls.
  static Future<String> savePdf({
    required String warehouseName,
    required List<Map<String, dynamic>> lotEntries,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    String currency = 'EGP',
  }) async {
    final order = PackingOrderModel(
      orderNumber: 'PO-LEGACY-${DateTime.now().millisecondsSinceEpoch}',
      lotId: '0',
      grade: 'A',
      stationId: warehouseName,
      productName: lotEntries.isNotEmpty ? lotEntries.first['product_name'] as String? : 'محصول',
      lotNumber: lotEntries.isNotEmpty ? lotEntries.first['lot_number'] as String? : '—',
      cartonCount: lotEntries.fold<int>(0, (s, e) => s + ((e['carton_count'] as num?)?.toInt() ?? 0)),
      totalNetWeight: lotEntries.fold<double>(0.0, (s, e) => s + ((e['total_net_weight'] as num?)?.toDouble() ?? 0.0)),
      totalGrossWeight: lotEntries.fold<double>(0.0, (s, e) => s + ((e['total_gross_weight'] as num?)?.toDouble() ?? 0.0)),
      fruitCostAllocated: totalFruitCostAfterWaste,
      actualMaterialCost: totalMaterialCost,
      totalPackingCost: totalAll,
      displayCurrency: currency,
      notes: jsonEncode({
        'materials': materialItems,
        'cost_items': costItems,
        'total_raw_weight_kg': lotEntries.fold<double>(0.0, (s, e) => s + ((e['effective_weight'] as num?)?.toDouble() ?? 0.0)),
      }),
    );
    return saveOrderVoucherPdf(order, warehouseName: warehouseName);
  }

  /// Legacy wrapper to maintain backward compatibility with old calls.
  static Future<void> printPdf({
    required String warehouseName,
    required List<Map<String, dynamic>> lotEntries,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double totalFruitCostBeforeWaste,
    required double totalWasteCost,
    required double totalFruitCostAfterWaste,
    required double totalMaterialCost,
    required double totalMaterialWasteCost,
    required double totalCostItems,
    required double totalAll,
    required double packingCostPerCarton,
    String currency = 'EGP',
  }) async {
    final order = PackingOrderModel(
      orderNumber: 'PO-LEGACY-${DateTime.now().millisecondsSinceEpoch}',
      lotId: '0',
      grade: 'A',
      stationId: warehouseName,
      productName: lotEntries.isNotEmpty ? lotEntries.first['product_name'] as String? : 'محصول',
      lotNumber: lotEntries.isNotEmpty ? lotEntries.first['lot_number'] as String? : '—',
      cartonCount: lotEntries.fold<int>(0, (s, e) => s + ((e['carton_count'] as num?)?.toInt() ?? 0)),
      totalNetWeight: lotEntries.fold<double>(0.0, (s, e) => s + ((e['total_net_weight'] as num?)?.toDouble() ?? 0.0)),
      totalGrossWeight: lotEntries.fold<double>(0.0, (s, e) => s + ((e['total_gross_weight'] as num?)?.toDouble() ?? 0.0)),
      fruitCostAllocated: totalFruitCostAfterWaste,
      actualMaterialCost: totalMaterialCost,
      totalPackingCost: totalAll,
      displayCurrency: currency,
      notes: jsonEncode({
        'materials': materialItems,
        'cost_items': costItems,
        'total_raw_weight_kg': lotEntries.fold<double>(0.0, (s, e) => s + ((e['effective_weight'] as num?)?.toDouble() ?? 0.0)),
      }),
    );
    final bytes = await generateOrderVoucherPdf(order, warehouseName: warehouseName);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'packing_order_${order.orderNumber}',
    );
  }
}
