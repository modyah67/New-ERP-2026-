import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_cost_breakdown_model.dart';
import '../../core/services/shipment_profitability_service.dart';

class ShipmentCostSheetPdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static const _allowedRoles = ['admin', 'financial_manager', 'accountant'];

  static bool hasAccess(String? role) => _allowedRoles.contains(role);

  static Future<void> previewPdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<ShipmentCostBreakdownModel> breakdown,
    ShipmentProfitabilityResult? profitabilityResult,
  }) async {
    final doc = await _generate(shipment, breakdown, profitabilityResult);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  static Future<pw.Document> _generate(
    ExportShipmentModel s,
    List<ShipmentCostBreakdownModel> breakdown,
    ShipmentProfitabilityResult? profitabilityResult,
  ) async {
    final doc = pw.Document();
    final fontRegular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final fontBase = pw.Font.ttf(fontRegular);
    final fontBold_ = pw.Font.ttf(fontBold);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            _pageW,
            _pageH,
            marginTop: 20,
            marginBottom: 24,
            marginLeft: 24,
            marginRight: 24,
          ),
          theme: pw.ThemeData.withFont(
            base: fontBase,
            bold: fontBold_,
            italic: fontBase,
            boldItalic: fontBold_,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(s),
                pw.SizedBox(height: 10),
                _buildShipmentInfo(s),
                pw.SizedBox(height: 14),
                _buildFruitSection(breakdown, s.currencyCode),
                pw.SizedBox(height: 8),
                _buildPackingSection(breakdown, s.currencyCode),
                pw.SizedBox(height: 8),
                _buildLogisticsSection(breakdown, s.currencyCode),
                pw.SizedBox(height: 8),
                _buildAdminSection(breakdown, s.currencyCode),
                pw.SizedBox(height: 8),
                _buildOtherSection(breakdown, s.currencyCode),
                pw.SizedBox(height: 14),
                _buildSummary(breakdown, s.currencyCode),
                pw.SizedBox(height: 10),
                _buildProfitability(s, breakdown, profitabilityResult),
              ],
            ),
          );
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(ExportShipmentModel s) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('FRUITY FARMS',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('SHIPMENT COST SHEET',
                  style: pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(s.shipmentNo,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildShipmentInfo(ExportShipmentModel s) {
    final dateStr = _formatDate(s.shipmentDate);
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _infoRow3('رقم الشحنة', s.shipmentNo, 'التاريخ', dateStr),
          pw.SizedBox(height: 3),
          _infoRow3('العميل', s.customerName ?? '—', 'الوجهة', s.country ?? '—'),
          pw.SizedBox(height: 3),
          _infoRow3('الحاوية', s.containerNo ?? '—', 'الباخرة', s.vesselName ?? '—'),
          pw.SizedBox(height: 3),
          _infoRow3('Incoterm', s.incoterm ?? '—', 'العملة', s.currency ?? 'USD'),
        ],
      ),
    );
  }

  static pw.Widget _infoRow3(
      String l1, String v1, String l2, String v2) {
    return pw.Row(children: [
      pw.Text(l1,
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 4),
      pw.Text(v1, style: const pw.TextStyle(fontSize: 7)),
      pw.SizedBox(width: 20),
      pw.Text(l2,
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(width: 4),
      pw.Text(v2, style: const pw.TextStyle(fontSize: 7)),
    ]);
  }

  static pw.Widget _buildSectionTitle(String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white)),
    );
  }

  static List<ShipmentCostBreakdownModel> _filter(
      List<ShipmentCostBreakdownModel> b, String type) {
    return b.where((r) => r.costType == type).toList();
  }

  static pw.Widget _buildFruitSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = _filter(b, 'fruit');
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(children: [
      _buildSectionTitle('Fruit Cost', PdfColors.green700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(['Description', 'Quantity', 'Unit Cost', 'Total Cost']),
          ...items.map((r) => _dataRow([
                r.itemName,
                r.quantity.toStringAsFixed(1),
                '${r.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              ])),
          _totalRowCol3(items, 'Total Fruit Cost', currencyCode),
        ],
      ),
    ]);
  }

  static pw.Widget _buildPackingSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = _filter(b, 'packing_material');
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(children: [
      _buildSectionTitle('Packing Materials', PdfColors.blue700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow(['Description', 'Quantity', 'Unit Cost', 'Total Cost']),
          ...items.map((r) => _dataRow([
                r.itemName,
                r.quantity.toStringAsFixed(1),
                '${r.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              ])),
          _totalRowCol3(items, 'Total Packing Material Cost', currencyCode),
        ],
      ),
    ]);
  }

  static pw.Widget _buildLogisticsSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = _filter(b, 'logistics');
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(children: [
      _buildSectionTitle('Logistics Costs', PdfColors.orange700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow2(['Description', 'Amount']),
          ...items.map((r) => _dataRow2([
                r.itemName,
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              ])),
          _totalRow2(items, 'Total Logistics Cost', currencyCode),
        ],
      ),
    ]);
  }

  static pw.Widget _buildAdminSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = _filter(b, 'admin');
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(children: [
      _buildSectionTitle('Administrative Costs', PdfColors.pink700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow2(['Description', 'Amount']),
          ...items.map((r) => _dataRow2([
                r.itemName,
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              ])),
          _totalRow2(items, 'Total Administrative Cost', currencyCode),
        ],
      ),
    ]);
  }

  static pw.Widget _buildOtherSection(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final items = _filter(b, 'other');
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(children: [
      _buildSectionTitle('Other Costs', PdfColors.grey700),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
        },
        children: [
          _headerRow2(['Description', 'Amount']),
          ...items.map((r) => _dataRow2([
                r.itemName,
                '${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}',
              ])),
          _totalRow2(items, 'Total Other Cost', currencyCode),
        ],
      ),
    ]);
  }

  static pw.Widget _buildSummary(List<ShipmentCostBreakdownModel> b, String currencyCode) {
    final fruitTotal = _typeSum(b, 'fruit');
    final packingTotal = _typeSum(b, 'packing_material');
    final logisticsTotal = _typeSum(b, 'logistics');
    final adminTotal = _typeSum(b, 'admin');
    final otherTotal = _typeSum(b, 'other');
    final totalCost = fruitTotal + packingTotal + logisticsTotal + adminTotal + otherTotal;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SUMMARY',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _summaryRow('Total Fruit Cost', '${fruitTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
          _summaryRow('Total Packing Material Cost', '${packingTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
          _summaryRow('Total Logistics Cost', '${logisticsTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
          _summaryRow('Total Administrative Cost', '${adminTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
          _summaryRow('Total Other Cost', '${otherTotal.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}'),
          pw.Container(height: 1, color: PdfColors.grey400, margin: const pw.EdgeInsets.symmetric(vertical: 4)),
          _summaryRow('TOTAL COST', '${totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}', bold: true),
        ],
      ),
    );
  }

  static pw.Widget _buildProfitability(
      ExportShipmentModel s, List<ShipmentCostBreakdownModel> b,
      ShipmentProfitabilityResult? profitabilityResult) {
    // Use ShipmentProfitabilityService values when available
    final revenue = profitabilityResult?.revenueEgp ?? 
        (s.totalRevenueEgp > 0 ? s.totalRevenueEgp : s.cartonsCount * s.exportPricePerCarton * s.exchangeRate);
    final totalCost = profitabilityResult?.totalCost ?? b.fold<double>(0.0, (sum, r) => sum + r.totalCost);
    final netProfit = profitabilityResult?.netProfit ??
        (s.netProfit > 0 ? s.netProfit : revenue - totalCost);
    final netMargin = profitabilityResult?.netMargin ??
        (revenue > 0 ? (netProfit / revenue * 100) : 0.0);
    final grossProfit = profitabilityResult?.grossProfit ??
        (s.grossProfit > 0 ? s.grossProfit : revenue - _typeSum(b, 'fruit') - _typeSum(b, 'packing_material'));
    final grossMargin = profitabilityResult?.grossMargin ??
        (revenue > 0 ? (grossProfit / revenue * 100) : 0.0);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('REVENUE & PROFITABILITY',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _summaryRow('Revenue', '${revenue.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}'),
          _summaryRow('Total Cost', '${totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}'),
          pw.Container(height: 1, color: PdfColors.grey400, margin: const pw.EdgeInsets.symmetric(vertical: 3)),
          _summaryRow('Gross Profit', '${grossProfit.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}',
              bold: true, color: grossProfit >= 0 ? PdfColors.green800 : PdfColors.red800),
          _summaryRow('Net Profit', '${netProfit.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}',
              bold: true, color: netProfit >= 0 ? PdfColors.green800 : PdfColors.red800),
          pw.SizedBox(height: 4),
          _summaryRow('Gross Margin %', '${grossMargin.toStringAsFixed(1)}%'),
          _summaryRow('Net Margin %', '${netMargin.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  static double _typeSum(List<ShipmentCostBreakdownModel> b, String type) =>
      b.where((r) => r.costType == type)
          .fold<double>(0.0, (s, r) => s + r.totalCost);

  static pw.TableRow _headerRow(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells.map((c) => _tableHeader(c)).toList(),
    );
  }

  static pw.TableRow _headerRow2(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _tableHeader(cells[0], alignment: pw.Alignment.centerRight),
        _tableHeader(cells[1]),
      ],
    );
  }

  static pw.TableRow _dataRow(List<String> cells) {
    return pw.TableRow(
      children: cells.map((c) => _tableCell(c)).toList(),
    );
  }

  static pw.TableRow _dataRow2(List<String> cells) {
    return pw.TableRow(
      children: [
        _tableCell(cells[0], alignment: pw.Alignment.centerRight),
        _tableCell(cells[1]),
      ],
    );
  }

  static pw.TableRow _totalRowCol3(List<ShipmentCostBreakdownModel> items, String label, String currencyCode) {
    final total = items.fold<double>(0.0, (s, r) => s + r.totalCost);
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blue50),
      children: [
        _tableCell(label, bold: true, alignment: pw.Alignment.centerRight),
        _tableCell(''),
        _tableCell(''),
        _tableCell('${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}', bold: true),
      ],
    );
  }

  static pw.TableRow _totalRow2(List<ShipmentCostBreakdownModel> items, String label, String currencyCode) {
    final total = items.fold<double>(0.0, (s, r) => s + r.totalCost);
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.orange50),
      children: [
        _tableCell(label, bold: true, alignment: pw.Alignment.centerRight),
        _tableCell('${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(currencyCode)}', bold: true),
      ],
    );
  }

  static pw.Widget _tableHeader(String t, {pw.Alignment? alignment}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      alignment: alignment ?? pw.Alignment.center,
      child: pw.Text(t,
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _tableCell(String t,
      {bool bold = false, pw.Alignment? alignment}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      alignment: alignment ?? pw.Alignment.center,
      child: pw.Text(t,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _summaryRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Row(children: [
      pw.Text(label,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold)),
      pw.Spacer(),
      pw.Text(value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          )),
    ]);
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }
}
