import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../data/models/cost_center.dart';

class CostCenterDetailsPdfService {
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  /// Loads bundled Arabic Cairo TrueType fonts from assets
  static Future<void> _loadFonts() async {
    if (_fontRegular != null && _fontBold != null) return;
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _fontRegular = pw.Font.ttf(regData);
      _fontBold = pw.Font.ttf(boldData);
    } catch (_) {
      _fontRegular = await PdfGoogleFonts.cairoRegular();
      _fontBold = await PdfGoogleFonts.cairoBold();
    }
  }

  /// Sanitizes text to remove invisible Unicode directional marks (like \u200E, \u202A, \u202C)
  /// that lack glyphs in fonts and cause square missing glyph boxes in PDF renderers.
  static String clean(dynamic val) {
    if (val == null) return '';
    return val
        .toString()
        .replaceAll('\u200E', '') // Left-to-Right Mark
        .replaceAll('\u200F', '') // Right-to-Left Mark
        .replaceAll('\u202A', '') // Left-to-Right Embedding
        .replaceAll('\u202B', '') // Right-to-Left Embedding
        .replaceAll('\u202C', '') // Pop Directional Formatting
        .replaceAll('\u202D', '') // Left-to-Right Override
        .replaceAll('\u202E', '') // Right-to-Left Override
        .replaceAll('\uFEFF', '') // Zero Width No-Break Space
        .trim();
  }

  static String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return NumberFormat('#,##0.00').format(n);
  }

  static String _fmtQty(dynamic v) {
    if (v == null) return '0';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return NumberFormat('#,##0.##').format(n);
  }

  static String _currencySymbol(String? cur) {
    if (cur == null) return 'EGP';
    switch (cur.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'EGP':
        return 'ج.م';
      default:
        return cur;
    }
  }

  /// Generates the PDF document and launches the system print/preview dialog
  static Future<void> generateAndPrint({
    required BuildContext context,
    required List<Map<String, dynamic>> rows,
    required List<CostCenter> activeCostCenters,
    String? costCenterName,
    String? selectedCurrency,
    String? fromDate,
    String? toDate,
    String? shipmentNo,
    String? categoryLabel,
  }) async {
    await _loadFonts();

    // Load optional company logo
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final doc = pw.Document();

    // Color Palette
    const primaryNavy = PdfColor.fromInt(0xFF0A2540);
    const slateDark = PdfColor.fromInt(0xFF1E293B);
    const slateHeader = PdfColor.fromInt(0xFF0F2646);
    const rowAltBg = PdfColor.fromInt(0xFFF8FAFC);
    const borderSlate = PdfColor.fromInt(0xFFE2E8F0);
    const accentAmber = PdfColor.fromInt(0xFFD97706);
    const accentGreen = PdfColor.fromInt(0xFF059669);

    // Page Theme with full RTL Arabic support
    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4.landscape,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
      theme: pw.ThemeData.withFont(
        base: _fontRegular!,
        bold: _fontBold!,
        italic: _fontRegular!,
        boldItalic: _fontBold!,
      ),
    );

    // Multi-currency calculation
    // Multi-currency & operational vs carried-forward balance calculation
    double totalAmountEgp = 0.0; // Net operational expenses
    double openingBalanceTotalEgp = 0.0; // Carried-forward opening balance

    for (final r in rows) {
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final srcId = r['source_id']?.toString() ?? '';
      final srcType = r['source_type']?.toString() ?? '';
      final item = (r['item_name']?.toString() ?? '').trim();

      // Defensive guard: skip non-positive remainder rollovers
      if (srcType == 'season_rollover' && (srcId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
        continue;
      }

      if (r['is_redundant_rollover'] == true) continue;
      final isRollover = r['is_rollover'] == true ||
          r['source_type'] == 'season_rollover' ||
          r['transaction_type'] == 'carried_forward';
      final isOpening = r['is_opening_balance'] == true ||
          r['source_type'] == 'opening_balance' ||
          isRollover;

      if (isOpening) {
        openingBalanceTotalEgp += amt;
      } else {
        totalAmountEgp += amt;
      }
    }

    final totalQty = rows.fold<double>(
      0.0,
      (sum, r) => sum + ((r['quantity'] as num?)?.toDouble() ?? 0.0),
    );
    final distinctItems = rows
        .map((r) => clean(r['item_name']))
        .where((s) => s.isNotEmpty)
        .toSet()
        .length;

    final Map<String, double> currencyTotals = {};
    for (final r in rows) {
      final cur = (clean(r['currency']).isNotEmpty ? clean(r['currency']) : 'EGP').toUpperCase();
      final tot = (r['total_in_currency'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ??
          0.0;
      currencyTotals[cur] = (currencyTotals[cur] ?? 0.0) + tot;
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) => _buildHeader(
          logoImage: logoImage,
          costCenterName: costCenterName,
          selectedCurrency: selectedCurrency,
          fromDate: fromDate,
          toDate: toDate,
          shipmentNo: shipmentNo,
          categoryLabel: categoryLabel,
          rowCount: rows.length,
          now: now,
          primaryNavy: primaryNavy,
          borderSlate: borderSlate,
        ),
        footer: (context) => _buildFooter(context, now),
        build: (context) => [
          pw.SizedBox(height: 10),
          _buildTable(
            rows: rows,
            activeCostCenters: activeCostCenters,
            slateHeader: slateHeader,
            rowAltBg: rowAltBg,
            borderSlate: borderSlate,
            accentAmber: accentAmber,
            accentGreen: accentGreen,
          ),
          pw.SizedBox(height: 12),
          _buildSummaryBox(
            totalAmountEgp: totalAmountEgp,
            openingBalanceTotalEgp: openingBalanceTotalEgp,
            totalQty: totalQty,
            rowCount: rows.length,
            distinctItems: distinctItems,
            currencyTotals: currencyTotals,
            selectedCurrency: selectedCurrency,
            primaryNavy: primaryNavy,
            slateDark: slateDark,
            borderSlate: borderSlate,
            accentGreen: accentGreen,
            accentAmber: accentAmber,
          ),
        ],
      ),
    );

    final fileTitle = 'تقرير_تكاليف_${clean(costCenterName ?? "عام").replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await Printing.layoutPdf(
      format: PdfPageFormat.a4.landscape,
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: fileTitle,
    );
  }

  /// Top Branded Header & Report Metadata Bar
  static pw.Widget _buildHeader({
    required pw.MemoryImage? logoImage,
    required String? costCenterName,
    required String? selectedCurrency,
    required String? fromDate,
    required String? toDate,
    required String? shipmentNo,
    required String? categoryLabel,
    required int rowCount,
    required String now,
    required PdfColor primaryNavy,
    required PdfColor borderSlate,
  }) {
    final titleText = categoryLabel != null
        ? 'تقرير تفاصيل التكاليف - $categoryLabel'
        : (costCenterName != null
            ? 'تقرير تفاصيل مركز التكلفة - $costCenterName'
            : 'تقرير تفاصيل مراكز التكلفة');

    final dateRangeStr = (fromDate != null && toDate != null)
        ? 'من $fromDate إلى $toDate'
        : (fromDate != null
            ? 'من $fromDate'
            : (toDate != null ? 'إلى $toDate' : 'كافة الفترات'));

    final currencyStr = selectedCurrency != null && selectedCurrency.isNotEmpty
        ? selectedCurrency.toUpperCase()
        : 'كل العملات (All)';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Main Brand Row
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: borderSlate, width: 1.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Company Brand & Logo
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null) ...[
                    pw.Container(
                      width: 44,
                      height: 44,
                      child: pw.Image(logoImage),
                    ),
                    pw.SizedBox(width: 10),
                  ],
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        clean(AppConstants.companyName),
                        style: pw.TextStyle(
                          font: _fontBold,
                          fontSize: 14,
                          color: primaryNavy,
                        ),
                      ),
                      pw.Text(
                        'FRUITY FARMS FOR AGRICULTURAL EXPORT',
                        style: pw.TextStyle(
                          font: _fontRegular,
                          fontSize: 7.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Title Badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: primaryNavy,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  clean(titleText),
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 12,
                    color: PdfColors.white,
                  ),
                ),
              ),

              // Timestamp & System Metadata
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'تاريخ الاستخراج: $now',
                    style: pw.TextStyle(
                      font: _fontRegular,
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  if (shipmentNo != null && shipmentNo.isNotEmpty)
                    pw.Text(
                      'رقم الشحنة: ${clean(shipmentNo)}',
                      style: pw.TextStyle(
                        font: _fontBold,
                        fontSize: 8,
                        color: primaryNavy,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 6),

        // Metadata Strip (Cost Center, Date Range, Currency, Row Count)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF1F5F9),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: borderSlate, width: 0.8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildMetaItem('مركز التكلفة:', clean(costCenterName ?? 'كافة المراكز')),
              _buildMetaItem('الفترة الزمنية:', dateRangeStr),
              _buildMetaItem('العملة:', currencyStr),
              _buildMetaItem('عدد المعاملات:', '$rowCount حركة'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildMetaItem(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: _fontBold,
            fontSize: 8.5,
            color: PdfColors.grey800,
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: _fontRegular,
            fontSize: 8.5,
            color: const PdfColor.fromInt(0xFF0F2646),
          ),
        ),
      ],
    );
  }

  /// Modern Data Table with alternating rows and explicit column widths
  static pw.Widget _buildTable({
    required List<Map<String, dynamic>> rows,
    required List<CostCenter> activeCostCenters,
    required PdfColor slateHeader,
    required PdfColor rowAltBg,
    required PdfColor borderSlate,
    required PdfColor accentAmber,
    required PdfColor accentGreen,
  }) {
    const columnWidths = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(62), // التاريخ (Date)
      1: pw.FixedColumnWidth(72), // رقم الشحنة (Shipment No)
      2: pw.FlexColumnWidth(2.2), // العميل / المورد (Customer / Supplier)
      3: pw.FlexColumnWidth(2.0), // مركز التكلفة (Cost Center)
      4: pw.FlexColumnWidth(2.8), // البيان / الصنف (Item / Variety - wide landscape allocation)
      5: pw.FixedColumnWidth(55), // الكمية (Quantity)
      6: pw.FixedColumnWidth(65), // سعر الوحدة (Unit Price)
      7: pw.FixedColumnWidth(48), // سعر الصرف (Exchange Rate)
      8: pw.FixedColumnWidth(75), // الإجمالي بالعملة (Total in Currency)
      9: pw.FixedColumnWidth(85), // الإجمالي بالمصري (Total in EGP)
    };

    final headers = [
      'التاريخ',
      'رقم الشحنة',
      'العميل / المورد',
      'مركز التكلفة',
      'البيان / الصنف',
      'الكمية',
      'سعر الوحدة',
      'سعر الصرف',
      'الإجمالي بالعملة',
      'الإجمالي (EGP)',
    ];

    return pw.Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: pw.TableBorder(
        bottom: pw.BorderSide(color: borderSlate, width: 0.8),
        horizontalInside: pw.BorderSide(color: borderSlate, width: 0.5),
      ),
      children: [
        // Table Header
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: slateHeader,
            borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
          ),
          children: headers.asMap().entries.map((e) {
            final idx = e.key;
            final text = e.value;
            final isNumeric = idx >= 5;
            final isCenter = idx == 0 || idx == 1 || idx == 7;

            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              alignment: isCenter
                  ? pw.Alignment.center
                  : (isNumeric ? pw.Alignment.centerLeft : pw.Alignment.centerRight),
              child: pw.Text(
                text,
                style: pw.TextStyle(
                  font: _fontBold,
                  fontSize: 8.5,
                  color: PdfColors.white,
                ),
              ),
            );
          }).toList(),
        ),

        // Table Rows
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final isEven = i % 2 == 0;

          final date = clean(r['shipment_date']);
          final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
          final rawShipmentNo = clean(r['shipment_no']);
          final isOpening = r['is_opening_balance'] == true ||
              r['source_type'] == 'opening_balance' ||
              rawShipmentNo == 'رصيد أول المدة' ||
              rawShipmentNo == 'رصيد سابق';
          final isSorting = r['is_sorting_sale'] == true ||
              r['source_type'] == 'sorting_sale' ||
              rawShipmentNo == 'بيع فرز';
          final isExportReturn = r['is_export_return'] == true ||
              r['source_type'] == 'export_return_waste' ||
              r['source_type'] == 'export_return_expense' ||
              rawShipmentNo.startsWith('EXR-');

          final shipmentDisplay = isOpening
              ? 'رصيد أول المدة'
              : (isSorting
                  ? 'بيع فرز'
                  : (isExportReturn
                      ? (rawShipmentNo.isNotEmpty ? rawShipmentNo : 'مرتجع مطار')
                      : rawShipmentNo));

          final custName = clean(r['customer_name']);

          final ccId = r['cost_center_id']?.toString();
          final ccNameFromRow = clean(r['cost_center_name']);
          final cc = ccId != null
              ? CostCenterHelper.fromId(ccId, activeCostCenters)
              : CostCenterHelper.resolve(r, activeCostCenters);
          final ccName = (ccNameFromRow.isNotEmpty &&
                  ccNameFromRow != CostCenterHelper.generalAdmin.nameAr)
              ? ccNameFromRow
              : cc.nameAr;

          final itemName = clean(r['item_name']);
          final rawQty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
          final rawUnitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
          final amountEgp = (r['amount'] as num?)?.toDouble() ?? 0.0;
          final totalInCurrency = (r['total_in_currency'] as num?)?.toDouble() ??
              amountEgp;

          double qty = rawQty;
          double unitPriceForeign = rawUnitPrice;
          if (unitPriceForeign <= 0 && qty.abs() > 0 && totalInCurrency != 0) {
            unitPriceForeign = (totalInCurrency / qty).abs();
          } else if (qty == 0 && unitPriceForeign > 0 && totalInCurrency != 0) {
            qty = totalInCurrency / unitPriceForeign;
          } else if (qty == 0 && unitPriceForeign <= 0 && totalInCurrency != 0) {
            qty = totalInCurrency < 0 ? -1.0 : 1.0;
            unitPriceForeign = totalInCurrency.abs();
          }
          final currency = clean(r['currency']).isNotEmpty
              ? clean(r['currency']).toUpperCase()
              : 'EGP';
          final exRate = (r['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          final actualExRate = exRate == 0 ? 1.0 : exRate;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : rowAltBg,
            ),
            children: [
              // 0: Date
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  dateStr,
                  style: pw.TextStyle(font: _fontRegular, fontSize: 8),
                ),
              ),

              // 1: Shipment No / Badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.center,
                child: isOpening
                    ? pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFFEF3C7),
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'رصيد أول',
                          style: pw.TextStyle(
                            font: _fontBold,
                            fontSize: 7,
                            color: accentAmber,
                          ),
                        ),
                      )
                    : (isSorting
                        ? pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: const pw.BoxDecoration(
                              color: PdfColor.fromInt(0xFFD1FAE5),
                              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                            ),
                            child: pw.Text(
                              'بيع فرز',
                              style: pw.TextStyle(
                                font: _fontBold,
                                fontSize: 7,
                                color: accentGreen,
                              ),
                            ),
                          )
                        : (isExportReturn
                            ? pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: const pw.BoxDecoration(
                                  color: PdfColor.fromInt(0xFFFFEDD5),
                                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                                ),
                                child: pw.Text(
                                  shipmentDisplay,
                                  style: pw.TextStyle(
                                    font: _fontBold,
                                    fontSize: 7,
                                    color: const PdfColor.fromInt(0xFFEA580C),
                                  ),
                                ),
                              )
                            : pw.Text(
                                shipmentDisplay,
                                style: pw.TextStyle(
                                  font: _fontBold,
                                  fontSize: 8,
                                  color: const PdfColor.fromInt(0xFF0284C7),
                                ),
                              ))),
              ),

              // 2: Customer / Supplier
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  custName.isNotEmpty ? custName : '—',
                  style: pw.TextStyle(font: _fontRegular, fontSize: 8),
                  maxLines: 1,
                ),
              ),

              // 3: Cost Center
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  ccName,
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 8,
                    color: const PdfColor.fromInt(0xFF0F172A),
                  ),
                  maxLines: 1,
                ),
              ),

              // 4: Item / Variety
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  itemName.isNotEmpty ? itemName : '—',
                  style: pw.TextStyle(font: _fontRegular, fontSize: 8),
                  maxLines: 1,
                ),
              ),

              // 5: Quantity
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  qty > 0 ? _fmtQty(qty) : '—',
                  style: pw.TextStyle(font: _fontRegular, fontSize: 8),
                ),
              ),

              // 6: Unit Price
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  unitPriceForeign > 0
                      ? '${_currencySymbol(currency)} ${_fmtNum(unitPriceForeign)}'
                      : '—',
                  style: pw.TextStyle(font: _fontRegular, fontSize: 8),
                ),
              ),

              // 7: Exchange Rate
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  actualExRate != 1.0 ? _fmtNum(actualExRate) : '1.00',
                  style: pw.TextStyle(
                    font: _fontRegular,
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                ),
              ),

              // 8: Total in Currency
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  '${_currencySymbol(currency)} ${_fmtNum(totalInCurrency)}',
                  style: pw.TextStyle(
                    font: _fontRegular,
                    fontSize: 8,
                    color: isSorting ? accentGreen : PdfColors.black,
                  ),
                ),
              ),

              // 9: Total in EGP
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  _fmtNum(amountEgp),
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 8.5,
                    color: isSorting
                        ? accentGreen
                        : (amountEgp < 0 ? PdfColors.red700 : const PdfColor.fromInt(0xFF0F2646)),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  /// Structured Bottom Summary Box with multi-currency breakdown and grand total
  static pw.Widget _buildSummaryBox({
    required double totalAmountEgp,
    double openingBalanceTotalEgp = 0.0,
    required double totalQty,
    required int rowCount,
    required int distinctItems,
    required Map<String, double> currencyTotals,
    required String? selectedCurrency,
    required PdfColor primaryNavy,
    required PdfColor slateDark,
    required PdfColor borderSlate,
    required PdfColor accentGreen,
    required PdfColor accentAmber,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF8FAFC),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSlate, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Box 1: Operations Metrics
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ملخص الحركات والكميات:',
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 9,
                    color: slateDark,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    _buildStatPill('المعاملات', '$rowCount حركة'),
                    pw.SizedBox(width: 8),
                    _buildStatPill('الأصناف', '$distinctItems أصناف'),
                    if (totalQty > 0) ...[
                      pw.SizedBox(width: 8),
                      _buildStatPill('إجمالي الكميات', _fmtQty(totalQty)),
                    ],
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 10),

          // Box 2: Multi-Currency Breakdown
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'تفصيل العملات الأجنبية:',
                  style: pw.TextStyle(
                    font: _fontBold,
                    fontSize: 9,
                    color: slateDark,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: currencyTotals.entries
                      .where((e) => e.key != 'EGP' && e.value != 0)
                      .map((e) {
                    final sym = _currencySymbol(e.key);
                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFFEF3C7),
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColor.fromInt(0xFFFDE68A), width: 0.8),
                          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFFDE68A), width: 0.8),
                          left: pw.BorderSide(color: PdfColor.fromInt(0xFFFDE68A), width: 0.8),
                          right: pw.BorderSide(color: PdfColor.fromInt(0xFFFDE68A), width: 0.8),
                        ),
                      ),
                      child: pw.Text(
                        '${e.key}: $sym ${_fmtNum(e.value)}',
                        style: pw.TextStyle(
                          font: _fontBold,
                          fontSize: 8,
                          color: accentAmber,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (!currencyTotals.keys.any((c) => c != 'EGP' && currencyTotals[c] != 0))
                  pw.Text(
                    'كافة العمليات مسجلة بالجنيه المصري (EGP)',
                    style: pw.TextStyle(
                      font: _fontRegular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
              ],
            ),
          ),

          pw.SizedBox(width: 10),

          // Box 3: Operational & Total Ledger in EGP
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: primaryNavy,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                boxShadow: const [
                  pw.BoxShadow(
                    color: PdfColors.grey300,
                    blurRadius: 3,
                    offset: PdfPoint(0, 1),
                  ),
                ],
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    selectedCurrency != null && selectedCurrency != 'EGP'
                        ? 'المعادل بالجنيه المصري'
                        : 'صافي مصاريف التشغيل',
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'EGP ${_fmtNum(totalAmountEgp)}',
                    style: pw.TextStyle(
                      font: _fontBold,
                      fontSize: 12,
                      color: const PdfColor.fromInt(0xFF38BDF8),
                    ),
                  ),
                  if (openingBalanceTotalEgp > 0) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'رصيد مرحل: EGP ${_fmtNum(openingBalanceTotalEgp)}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColor.fromInt(0xFFFDE68A),
                      ),
                    ),
                    pw.Text(
                      'الإجمالي: EGP ${_fmtNum(totalAmountEgp + openingBalanceTotalEgp)}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatPill(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.8),
          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.8),
          left: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.8),
          right: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label: ',
            style: pw.TextStyle(
              font: _fontRegular,
              fontSize: 7.5,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: _fontBold,
              fontSize: 8,
              color: const PdfColor.fromInt(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  /// Professional Footer with dynamic page numbering
  static pw.Widget _buildFooter(pw.Context context, String now) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'نظام فروتي فارمز لإدارة الموارد (Fruity Farms ERP)',
            style: pw.TextStyle(
              font: _fontRegular,
              fontSize: 7.5,
              color: PdfColors.grey600,
            ),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(
              font: _fontBold,
              fontSize: 8,
              color: const PdfColor.fromInt(0xFF0F2646),
            ),
          ),
          pw.Text(
            'تاريخ الإصدار: $now',
            style: pw.TextStyle(
              font: _fontRegular,
              fontSize: 7.5,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}
