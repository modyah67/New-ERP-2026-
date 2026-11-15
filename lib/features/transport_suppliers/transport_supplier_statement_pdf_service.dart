// lib/features/transport_suppliers/transport_supplier_statement_pdf_service.dart
// Professional Landscape A4 Statement PDF Service for Transport Suppliers

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
import '../../data/models/transport_transaction_model.dart';
import '../../data/dao/settings_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class TransportSupplierStatementPdfService {
  TransportSupplierStatementPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Deep Navy & Cyan Logistics Theme)
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
  static const _redText     = PdfColor.fromInt(0xFFB91C1C); // Red 700
  static const _redBg       = PdfColor.fromInt(0xFFFEE2E2); // Red 100
  static const _amberText   = PdfColor.fromInt(0xFFB45309); // Amber 700

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
    required TransportSupplierModel supplier,
    required List<TransportTransactionModel> transactions,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    Map<String, String>? settings,
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
      supplier: supplier,
      transactions: transactions,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      settings: resolvedSettings,
    );
  }

  /// Generates and opens the standard system print / export dialog in Landscape mode.
  static Future<void> generateAndPrint({
    required TransportSupplierModel supplier,
    required List<TransportTransactionModel> transactions,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    final bytes = await generatePdfBytes(
      supplier: supplier,
      transactions: transactions,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
    );
    final docTitle = _formattedFileName('كشف_حساب_مقاول_نقل_${supplier.name}');
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Saves the landscape PDF directly to the user's export storage.
  static Future<File> saveToFile(
    BuildContext context, {
    required TransportSupplierModel supplier,
    required List<TransportTransactionModel> transactions,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    final bytes = await generatePdfBytes(
      supplier: supplier,
      transactions: transactions,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = _formattedFileName('كشف_حساب_مقاول_نقل_${supplier.name}');
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ كشف الحساب بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDER
  // ──────────────────────────────────────────────────────────────────────────

  static Future<Uint8List> _build({
    required TransportSupplierModel supplier,
    required List<TransportTransactionModel> transactions,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
    required Map<String, String> settings,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final companyName = settings['company_name'] ?? AppConstants.companyName;
    final printDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final resolvedStatementNumber = statementNumber > 0
        ? statementNumber
        : (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000000;

    final currency = transactions.isNotEmpty ? transactions.first.currency : 'EGP';

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
                child: pw.Image(bgImage!, fit: pw.BoxFit.cover),
              )
          : null,
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) {
          if (context.pageNumber > 1) {
            return _buildSubsequentHeader(
              supplier: supplier,
              companyName: companyName,
              printDate: printDate,
              pageNumber: context.pageNumber,
            );
          }
          return pw.SizedBox.shrink();
        },
        build: (ctx) => [
          _buildTopBanner(
            companyName: companyName,
            statementNumber: resolvedStatementNumber,
            printDate: printDate,
          ),
          pw.SizedBox(height: 10),
          _buildSupplierInfo(
            supplier: supplier,
            fromDate: fromDate,
            toDate: toDate,
            currency: currency,
            rowCount: transactions.length,
          ),
          pw.SizedBox(height: 12),
          _buildTable(
            transactions: transactions,
            openingBalance: openingBalance,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            currency: currency,
            supplier: supplier,
          ),
          pw.SizedBox(height: 14),
          _buildSummary(
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            currency: currency,
          ),
          pw.SizedBox(height: 14),
          _buildSignatureSection(),
        ],
        footer: (ctx) => _buildFooter(ctx, supplier, companyName, printDate),
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER COMPONENTS
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildTopBanner({
    required String companyName,
    required int statementNumber,
    required String printDate,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const pw.BoxDecoration(
        color: _navyPrimary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Right side (Company branding)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 14,
                  color: _white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'نظام إدارة العمليات واللوجستيات | Fruity Farms ERP',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  color: PdfColors.blueGrey100,
                ),
              ),
            ],
          ),

          // Center (Title Badge)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: _cyanAccent,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'كشف حساب مقاول النقل والشحن',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 12,
                    color: _white,
                  ),
                ),
                pw.Text(
                  'TRANSPORT SUPPLIER ACCOUNT STATEMENT',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 6,
                    color: _navyPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Left side (Meta statement info)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    '#$statementNumber',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: _white),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    'رقم الكشف:',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.blueGrey100),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    printDate,
                    style: pw.TextStyle(font: _font, fontSize: 7.5, color: _white),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    'تاريخ الطباعة:',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: _font, fontSize: 7.5, color: PdfColors.blueGrey100),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSubsequentHeader({
    required TransportSupplierModel supplier,
    required String companyName,
    required String printDate,
    required int pageNumber,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.7)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'كشف حساب مقاول النقل: ${supplier.name} (${supplier.code.isNotEmpty ? supplier.code : "-"}) | $companyName',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _navyPrimary),
          ),
          pw.Text(
            'صفحة $pageNumber | تاريخ الطباعة: $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VENDOR META INFORMATION CARD (Landscape Grid)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSupplierInfo({
    required TransportSupplierModel supplier,
    required DateTime? fromDate,
    required DateTime? toDate,
    required String currency,
    required int rowCount,
  }) {
    final periodText = (fromDate != null && toDate != null)
        ? 'من ${AppUtils.formatDate(fromDate)} إلى ${AppUtils.formatDate(toDate)}'
        : (fromDate != null)
            ? 'من ${AppUtils.formatDate(fromDate)} وحتى تاريخه'
            : (toDate != null)
                ? 'حتى تاريخ ${AppUtils.formatDate(toDate)}'
                : 'كافة المعاملات المسجلة';

    final phoneClean = (supplier.phone.trim().isNotEmpty && supplier.phone.trim() != '-')
        ? supplier.phone.trim()
        : '—';

    final codeClean = supplier.code.trim().isNotEmpty
        ? supplier.code.trim()
        : '—';

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
          // 1. Supplier Name & Code
          _metaCell(
            label: 'اسم مقاول النقل',
            englishLabel: 'Transporter Name',
            value: supplier.name,
            isBold: true,
          ),
          _vDiv(),

          // 2. Transporter Code
          _metaCell(
            label: 'كود المقاول',
            englishLabel: 'Code',
            value: codeClean,
          ),
          _vDiv(),

          // 3. Contact Phone
          _metaCell(
            label: 'رقم الهاتف',
            englishLabel: 'Phone',
            value: phoneClean,
          ),
          _vDiv(),

          // 4. Currency
          _metaCell(
            label: 'عملة الحساب',
            englishLabel: 'Currency',
            value: currency,
            isBold: true,
            valueColor: _navyPrimary,
          ),
          _vDiv(),

          // 5. Accounting Period
          _metaCell(
            label: 'الفترة المحاسبية',
            englishLabel: 'Period',
            value: periodText,
          ),
          _vDiv(),

          // 6. Truck Stock / Transactions Count
          _metaCell(
            label: 'رصيد النقلات الحالية',
            englishLabel: 'Trucks / Records',
            value: '${supplier.truckBalance % 1 == 0 ? supplier.truckBalance.toInt() : supplier.truckBalance} نقلة (${rowCount + 1} حركة)',
            valueColor: _cyanAccent,
            isBold: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaCell({
    required String label,
    required String englishLabel,
    required String value,
    bool isBold = false,
    PdfColor? valueColor,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: _font,
              fontSize: 6.5,
              color: _mutedText,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: isBold ? _boldFont : _font,
              fontSize: 8.5,
              color: valueColor ?? _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _vDiv() {
    return pw.Container(
      width: 0.6,
      height: 24,
      color: _borderColor,
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 7-COLUMN LANDSCAPE DATA TABLE (Matching Screen UI)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildTable({
    required List<TransportTransactionModel> transactions,
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required String currency,
    required TransportSupplierModel supplier,
  }) {
    // Column widths in Landscape (794pt total width)
    // 0: Date (0.10), 1: Type (0.14), 2: Trips (0.10), 3: Description & Route (0.30),
    // 4: Debit/Paid (0.12), 5: Credit/Due (0.12), 6: Cumulative Balance (0.12)
    const columnWidths = {
      0: pw.FlexColumnWidth(0.10), // Date / التاريخ
      1: pw.FlexColumnWidth(0.14), // Type / نوع الحركة
      2: pw.FlexColumnWidth(0.10), // Trips / حركة النقلات
      3: pw.FlexColumnWidth(0.30), // Description & Route / البيان والمسار
      4: pw.FlexColumnWidth(0.12), // Debit / مسدد (مدين)
      5: pw.FlexColumnWidth(0.12), // Credit / مستحق (دائن)
      6: pw.FlexColumnWidth(0.12), // Balance / الرصيد التراكمي
    };

    const headers = [
      'التاريخ\nDate',
      'نوع الحركة\nType',
      'حركة النقلات\nTrips',
      'البيان / الوصف وخط السير\nDescription & Route',
      'مسدد (مدين)\nPaid (Debit)',
      'مستحق (دائن)\nDue (Credit)',
      'الرصيد التراكمي\nBalance',
    ];

    double runningBalance = openingBalance;

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      children: [
        // Table Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navyPrimary),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: pw.Text(
                h,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _boldFont,
                  fontSize: 7.5,
                  color: _white,
                ),
              ),
            );
          }).toList(),
        ),

        // Row 1: Opening Balance Row (رصيد افتتاحي / سابق)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cardBg),
          children: [
            _cell('—'),
            _cell('رصيد افتتاحي / سابق', isBold: true, color: _navyPrimary),
            _cell(
              supplier.initialTruckBalance > 0
                  ? '${supplier.initialTruckBalance % 1 == 0 ? supplier.initialTruckBalance.toInt() : supplier.initialTruckBalance} نقلة'
                  : '—',
              color: _cyanAccent,
              isBold: true,
            ),
            _cell(
              'الرصيد المستحق قبل بداية الفترة',
              align: pw.TextAlign.right,
              color: _mutedText,
            ),
            _cell('—'),
            _cell('—'),
            _cell(
              '${AppUtils.formatNumber(openingBalance.abs())} ${openingBalance > 0 ? "(له)" : openingBalance < 0 ? "(عليه)" : ""}',
              isBold: true,
              color: openingBalance > 0 ? _greenText : openingBalance < 0 ? _redText : _darkText,
            ),
          ],
        ),

        // Transaction Rows
        ...transactions.asMap().entries.map((entry) {
          final i = entry.key;
          final tx = entry.value;
          runningBalance += (tx.credit - tx.debit);

          final isEven = i % 2 == 0;
          final isConsump = tx.isConsumption;

          final dateClean = tx.date.trim().isNotEmpty ? tx.date.trim() : '—';
          final typeClean = tx.typeLabel.trim().isNotEmpty ? tx.typeLabel.trim() : '—';

          // Trips formatted cleanly
          String tripsClean = '—';
          if (tx.truckCount > 0) {
            final cntStr = tx.truckCount % 1 == 0 ? tx.truckCount.toInt().toString() : tx.truckCount.toString();
            tripsClean = isConsump ? '-$cntStr نقلة' : '+$cntStr نقلة';
          }

          // Description & Route combined
          final desc = tx.description?.trim();
          String? route;
          if (tx.routeFrom != null &&
              tx.routeTo != null &&
              tx.routeFrom!.trim().isNotEmpty &&
              tx.routeTo!.trim().isNotEmpty) {
            route = '${tx.routeFrom!.trim()} إلى ${tx.routeTo!.trim()}';
          } else if (tx.routeDisplay != null) {
            route = tx.routeDisplay!.replaceAll('➔', 'إلى');
          }

          String fullDesc = '';
          if (desc != null && desc.isNotEmpty && desc != '—') {
            fullDesc = desc;
          }
          if (route != null && route.isNotEmpty) {
            fullDesc = fullDesc.isNotEmpty ? '$fullDesc [خط السير: $route]' : 'خط السير: $route';
          }
          if (isConsump) {
            fullDesc = fullDesc.isNotEmpty
                ? '$fullDesc (استهلاك تشغيلي بدون أثر مالي)'
                : 'استهلاك تشغيلي بدون أثر مالي';
          }
          if (fullDesc.isEmpty) fullDesc = '—';

          final debitClean = tx.debit > 0 ? AppUtils.formatNumber(tx.debit) : '—';
          final creditClean = tx.credit > 0 ? AppUtils.formatNumber(tx.credit) : '—';
          final balSign = runningBalance > 0
              ? ' (له)'
              : runningBalance < 0
                  ? ' (عليه)'
                  : '';
          final balanceClean = '${AppUtils.formatNumber(runningBalance.abs())}$balSign';

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? _white : _cardBg,
            ),
            children: [
              _cell(dateClean),
              _cell(
                typeClean,
                isBold: true,
                color: isConsump
                    ? _cyanAccent
                    : tx.isInvoice
                        ? _amberText
                        : _greenText,
              ),
              _cell(
                tripsClean,
                isBold: tx.truckCount > 0,
                color: isConsump ? _amberText : (tx.truckCount > 0 ? _greenText : _mutedText),
              ),
              _cell(fullDesc, align: pw.TextAlign.right),
              _cell(
                debitClean,
                color: tx.debit > 0 ? _redText : _mutedText,
                isBold: tx.debit > 0,
              ),
              _cell(
                creditClean,
                color: tx.credit > 0 ? _greenText : _mutedText,
                isBold: tx.credit > 0,
              ),
              _cell(
                balanceClean,
                isBold: true,
                color: runningBalance > 0
                    ? _greenText
                    : runningBalance < 0
                        ? _redText
                        : _darkText,
              ),
            ],
          );
        }),

        // Embedded Table Totals Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightBg),
          children: [
            _cell('المجموع', isBold: true, color: _navyPrimary),
            _cell('—', isBold: true),
            _cell('—', isBold: true),
            _cell(
              'إجمالي حركات الفترة (${transactions.length} حركة)',
              isBold: true,
              align: pw.TextAlign.right,
              color: _navyPrimary,
            ),
            _cell(
              totalDebit > 0 ? AppUtils.formatNumber(totalDebit) : '0.00',
              isBold: true,
              color: _redText,
            ),
            _cell(
              totalCredit > 0 ? AppUtils.formatNumber(totalCredit) : '0.00',
              isBold: true,
              color: _greenText,
            ),
            _cell(
              '${AppUtils.formatNumber(finalBalance.abs())} ${finalBalance > 0 ? "(له)" : finalBalance < 0 ? "(عليه)" : ""}',
              isBold: true,
              color: finalBalance > 0 ? _greenText : finalBalance < 0 ? _redText : _navyPrimary,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    PdfColor? color,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
          font: isBold ? _boldFont : _font,
          fontSize: 7.5,
          color: color ?? _darkText,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EXECUTIVE KPI SUMMARY FOOTER (Landscape 3-Card Strip)
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSummary({
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required String currency,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Card 1: Total Paid / Debit (مسدد - مدين)
        _buildSummaryCard(
          title: 'إجمالي المسدد (مدين)',
          englishTitle: 'Total Paid (Debit)',
          value: '${AppUtils.formatNumber(totalDebit)} $currency',
          subText: 'سندات صرف نقدية وبنكية مسددة للمقاول',
          accentColor: _redText,
          bgColor: _redBg,
        ),
        pw.SizedBox(width: 8),

        // Card 2: Total Due / Credit (مستحق - دائن)
        _buildSummaryCard(
          title: 'إجمالي النقل المستحق (دائن)',
          englishTitle: 'Total Due (Credit)',
          value: '${AppUtils.formatNumber(totalCredit)} $currency',
          subText: 'فواتير واستحقاقات نقل المحصول والأوامر',
          accentColor: _greenText,
          bgColor: _greenBg,
        ),
        pw.SizedBox(width: 8),

        // Card 3: Final Net Balance (الرصيد النهائي المستحق)
        _buildSummaryCard(
          title: 'الرصيد النهائي المستحق',
          englishTitle: 'Final Net Balance',
          value: '${AppUtils.formatNumber(finalBalance.abs())} $currency',
          subText: finalBalance > 0
              ? 'مستحق للمقاول (دائن / له)'
              : finalBalance < 0
                  ? 'مستحق على المقاول (مدين / عليه)'
                  : 'الحساب متزن تماماً (خالص)',
          accentColor: finalBalance > 0
              ? _greenText
              : finalBalance < 0
                  ? _redText
                  : _navyPrimary,
          bgColor: finalBalance > 0
              ? _greenBg
              : finalBalance < 0
                  ? _redBg
                  : _cardBg,
          isHero: true,
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryCard({
    required String title,
    required String englishTitle,
    required String value,
    required String subText,
    required PdfColor accentColor,
    required PdfColor bgColor,
    bool isHero = false,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _white,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _borderColor, width: 0.65),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  title,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
                ),
                pw.Text(
                  englishTitle,
                  style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: _boldFont,
                fontSize: isHero ? 12 : 10.5,
                color: accentColor,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: pw.BoxDecoration(
                color: bgColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Text(
                subText,
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SIGNATURES SECTION
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildSignatureSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _signatureColumn('إعداد المحاسب المسؤول', 'Accountant'),
          _signatureColumn('المراجعة والاعتماد المالي', 'Financial Auditor'),
          _signatureColumn('استلام وختم مقاول النقل', 'Transporter Acknowledgment'),
        ],
      ),
    );
  }

  static pw.Widget _signatureColumn(String arTitle, String enTitle) {
    return pw.Column(
      children: [
        pw.Text(
          arTitle,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: _boldFont, fontSize: 8, color: _navyPrimary),
        ),
        pw.Text(
          enTitle,
          style: pw.TextStyle(font: _font, fontSize: 6, color: _mutedText),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          width: 140,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 1, style: pw.BorderStyle.dashed)),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER COMPONENT
  // ──────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildFooter(
    pw.Context ctx,
    TransportSupplierModel supplier,
    String companyName,
    String printDate,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderColor, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم استخراج هذا التقرير آلياً من نظام إدارة العمليات والحسابات (Fruity Farms ERP) | $printDate',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _font, fontSize: 7, color: _mutedText),
          ),
          pw.Text(
            'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
          ),
        ],
      ),
    );
  }
}
