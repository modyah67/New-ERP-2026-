// lib/core/consolidated_statement_pdf_service.dart
// Upgraded Landscape A4 Consolidated Statement PDF Service with Deep Navy Theme,
// Alternating Row Shading, RTL Arabic Typography, and Multi-Currency Breakdown.

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
import '../../data/models/supplier_model.dart';
import '../features/suppliers/supplier_state.dart';
import '../features/statements/supplier_consolidated_statement_pdf_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ConsolidatedStatementPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static final _navyPrimary = PdfColor.fromHex('#1A365D');
  static final _accentTeal  = PdfColor.fromHex('#0D9488');
  static final _cardBg      = PdfColor.fromHex('#F8FAFC');
  static final _zebraBg     = PdfColor.fromHex('#F1F5F9');
  static final _textDark    = PdfColor.fromHex('#0F172A');
  static final _textMuted   = PdfColor.fromHex('#64748B');
  static final _borderColor = PdfColor.fromHex('#CBD5E1');
  static final _borderLight = PdfColor.fromHex('#E2E8F0');

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
  }

  /// Builds a Landscape A4 consolidated statement document with multi-currency summary.
  static Future<Uint8List> build({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final hasExtra = extraColumnHeader != null && extraColumnKey != null;

    // Build per-currency totals
    final Map<String, double> totalsByCurrency = {};
    final Map<String, int> countsByCurrency = {};
    for (final r in rows) {
      final curr = r['currency'] ?? 'EGP';
      final bal = double.tryParse(r['balance'] ?? '0') ?? 0;
      totalsByCurrency[curr] = (totalsByCurrency[curr] ?? 0) + bal;
      countsByCurrency[curr] = (countsByCurrency[curr] ?? 0) + 1;
    }
    final sortedCurrencies = totalsByCurrency.keys.toList()..sort();

    final headers = ['#', 'الكود', 'الاسم', 'العملة', 'الرصيد'];
    if (hasExtra) headers.insert(3, extraColumnHeader);

    final printDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        header: (context) {
          if (context.pageNumber > 1) {
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
                    '$title | ${AppConstants.companyName}',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _navyPrimary),
                  ),
                  pw.Text(
                    'تاريخ الطباعة: $printDate',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 7.5, color: _textMuted),
                  ),
                ],
              ),
            );
          }
          return pw.SizedBox.shrink();
        },
        footer: (context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Divider(color: _borderColor, thickness: 0.5),
            pw.SizedBox(height: 3),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$title | ${AppConstants.companyName}',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7.5, color: _textMuted),
                ),
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
                    style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
                  ),
                ),
                pw.Text(
                  'طبع بتاريخ: $printDate',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7.5, color: _textMuted),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // Company Header Banner
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    AppConstants.companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _boldFont, fontSize: 15, color: _navyPrimary),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'نظام إدارة الموارد والمحاسبة المالية (Fruity Farms ERP)',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 8.5, color: _textMuted),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  title,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 11.5, color: PdfColors.white),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),

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

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('تاريخ التقرير: $printDate',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7.5, color: _textMuted)),
              pw.Text('إجمالي السجلات: ${rows.length}',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary)),
              pw.Text('العملة الأساسية: الجنيه المصري (EGP)',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _font, fontSize: 7.5, color: _textMuted)),
            ],
          ),
          pw.SizedBox(height: 8),

          // Multi-Currency KPI Summary Cards
          if (sortedCurrencies.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: pw.BoxDecoration(
                color: _cardBg,
                border: pw.Border.all(color: _borderColor, width: 0.65),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('إجمالي الأرصدة حسب العملة:',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _navyPrimary)),
                      pw.SizedBox(height: 1),
                      pw.Text('Multi-Currency Totals',
                          style: pw.TextStyle(font: _font, fontSize: 6.0, color: _textMuted)),
                    ],
                  ),
                  pw.Row(
                    children: sortedCurrencies.map((curr) {
                      final val = totalsByCurrency[curr] ?? 0;
                      final count = countsByCurrency[curr] ?? 0;
                      final isNeg = val < 0;
                      return pw.Container(
                        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: pw.BoxDecoration(
                          color: isNeg ? PdfColor.fromHex('#FEE2E2') : PdfColors.white,
                          border: pw.Border.all(color: _borderLight, width: 0.5),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              curr,
                              style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
                            ),
                            pw.SizedBox(width: 4),
                            pw.Text(
                              AppUtils.formatNumber(val.abs()),
                              style: pw.TextStyle(
                                font: _boldFont,
                                fontSize: 8.0,
                                color: isNeg ? PdfColor.fromHex('#B91C1C') : PdfColor.fromHex('#15803D'),
                              ),
                            ),
                            pw.SizedBox(width: 3),
                            pw.Text(
                              '($count)',
                              style: pw.TextStyle(font: _font, fontSize: 6.5, color: _textMuted),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
          ],

          _buildTable(headers, rows, hasExtra, extraColumnKey),
          pw.SizedBox(height: 12),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildTable(
    List<String> headers,
    List<Map<String, String>> rows,
    bool hasExtra,
    String? extraColumnKey,
  ) {
    final colCount = headers.length;

    final List<double> colWidths;
    if (hasExtra) {
      colWidths = [30, 70, 200, 70, 60, 110];
    } else {
      colWidths = [30, 80, 260, 60, 130];
    }

    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: PdfColors.white),
      cellStyle: pw.TextStyle(font: _font, fontSize: 7.5, color: _textDark),
      headerDecoration: pw.BoxDecoration(color: _navyPrimary),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      oddRowDecoration: pw.BoxDecoration(color: _zebraBg),
      columnWidths: {
        for (int i = 0; i < colCount; i++) i: pw.FlexColumnWidth(colWidths[i.clamp(0, colWidths.length - 1)]),
      },
      headers: headers,
      data: List.generate(rows.length, (i) {
        final r = rows[i];
        final cells = [
          '${i + 1}',
          r['code'] ?? '',
          r['name'] ?? '',
          r['currency'] ?? 'EGP',
          r['balance'] ?? '',
        ];
        if (hasExtra) {
          cells.insert(4, r[extraColumnKey] ?? '');
        }
        return cells;
      }),
    );
  }

  static Future<void> print({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    final bytes = await build(
      title: title,
      rows: rows,
      totalBalance: totalBalance,
      extraColumnHeader: extraColumnHeader,
      extraColumnKey: extraColumnKey,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: title,
      format: PdfPageFormat.a4.landscape,
    );
  }

  static Future<String> saveToFile({
    required String title,
    required List<Map<String, String>> rows,
    required double totalBalance,
    String? extraColumnHeader,
    String? extraColumnKey,
  }) async {
    final bytes = await build(
      title: title,
      rows: rows,
      totalBalance: totalBalance,
      extraColumnHeader: extraColumnHeader,
      extraColumnKey: extraColumnKey,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = '${title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DEDICATED SUPPLIER FORWARDING METHODS
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> generateAndPrintSuppliers({
    required List<SupplierModel> suppliers,
    Map<String, CurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    int? cropCount,
    int? packagingCount,
    int? sharedCount,
    Map<String, double>? exchangeRates,
    String? companyName,
  }) =>
      SupplierConsolidatedStatementPdfService.generateAndPrint(
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

  static Future<File> saveSuppliersToFile(
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
  }) =>
      SupplierConsolidatedStatementPdfService.saveToFile(
        context,
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
}
