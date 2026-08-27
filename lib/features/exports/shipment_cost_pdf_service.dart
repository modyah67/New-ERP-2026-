import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_cost_item_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShipmentCostPdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<void> previewPdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<ShipmentCostItemModel> costItems,
    required double revForeign,
    required double revEgp,
    required double totalCostEgp,
    required double netProfitEgp,
    required double margin,
    required double revPerCartonForeign,
    required double costPerCartonForeign,
    required double grossPerCartonForeign,
    required double revPerCartonEgp,
    required double costPerCartonEgp,
    required double grossPerCartonEgp,
    required String currency,
    double discount = 0,
  }) async {
    final doc = await _generate(
      s: shipment,
      items: costItems,
      revForeign: revForeign,
      revEgp: revEgp,
      totalCostEgp: totalCostEgp,
      netProfitEgp: netProfitEgp,
      margin: margin,
      revPerCartonForeign: revPerCartonForeign,
      costPerCartonForeign: costPerCartonForeign,
      grossPerCartonForeign: grossPerCartonForeign,
      revPerCartonEgp: revPerCartonEgp,
      costPerCartonEgp: costPerCartonEgp,
      grossPerCartonEgp: grossPerCartonEgp,
      currency: currency,
      discount: discount,
    );
    final now = DateTime.now();
    final timeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Shipment_${shipment.shipmentNo.replaceAll('/', '_')}_$timeStr.pdf',
    );
  }

  static Future<void> savePdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<ShipmentCostItemModel> costItems,
    required double revForeign,
    required double revEgp,
    required double totalCostEgp,
    required double netProfitEgp,
    required double margin,
    required double revPerCartonForeign,
    required double costPerCartonForeign,
    required double grossPerCartonForeign,
    required double revPerCartonEgp,
    required double costPerCartonEgp,
    required double grossPerCartonEgp,
    required String currency,
    double discount = 0,
  }) async {
    final doc = await _generate(
      s: shipment,
      items: costItems,
      revForeign: revForeign,
      revEgp: revEgp,
      totalCostEgp: totalCostEgp,
      netProfitEgp: netProfitEgp,
      margin: margin,
      revPerCartonForeign: revPerCartonForeign,
      costPerCartonForeign: costPerCartonForeign,
      grossPerCartonForeign: grossPerCartonForeign,
      revPerCartonEgp: revPerCartonEgp,
      costPerCartonEgp: costPerCartonEgp,
      grossPerCartonEgp: grossPerCartonEgp,
      currency: currency,
      discount: discount,
    );
    final bytes = await doc.save();
    
    final dir = await FileHelper.getExportDirectory();
    final now = DateTime.now();
    final timeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final filename = 'Shipment_Cost_${shipment.shipmentNo.replaceAll('/', '_')}_$timeStr.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الحفظ بنجاح في المستندات: $filename', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static Future<pw.Document> _generate({
    required ExportShipmentModel s,
    required List<ShipmentCostItemModel> items,
    required double revForeign,
    required double revEgp,
    required double totalCostEgp,
    required double netProfitEgp,
    required double margin,
    required double revPerCartonForeign,
    required double costPerCartonForeign,
    required double grossPerCartonForeign,
    required double revPerCartonEgp,
    required double costPerCartonEgp,
    required double grossPerCartonEgp,
    required String currency,
    double discount = 0,
  }) async {
    final doc = pw.Document();
    final fontRegular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(fontRegular);
    final fontBold_ = pw.Font.ttf(fontBold);

    final grouped = _groupByCategory(items);
    final symbol = _currencySymbol(currency);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            _pageW,
            _pageH,
            marginTop: 130, // Space for pre-printed letterhead logo
            marginBottom: 90, // Space for pre-printed letterhead footer
            marginLeft: 24,
            marginRight: 24,
          ),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold_,
            italic: font,
            boldItalic: fontBold_,
          ),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          final children = [
            pw.SizedBox(height: 12),
            _buildInfoSection(s),
            pw.SizedBox(height: 12),
            _buildProductRow(s),
            pw.SizedBox(height: 12),
            ..._buildCostItemsSection(grouped),
            pw.SizedBox(height: 12),
            _buildSummarySection(
              revForeign: revForeign,
              revEgp: revEgp,
              totalCostEgp: totalCostEgp,
              netProfitEgp: netProfitEgp,
              margin: margin,
              revPerCartonForeign: revPerCartonForeign,
              costPerCartonForeign: costPerCartonForeign,
              grossPerCartonForeign: grossPerCartonForeign,
              revPerCartonEgp: revPerCartonEgp,
              costPerCartonEgp: costPerCartonEgp,
              grossPerCartonEgp: grossPerCartonEgp,
              symbol: symbol,
              currency: currency,
              discount: discount,
            ),
          ];

          return children
              .map((c) => pw.Directionality(
                    textDirection: pw.TextDirection.rtl,
                    child: c,
                  ))
              .toList();
        },
      ),
    );

    return doc;
  }

  static Future<pw.Document> generatePdf({
    required ExportShipmentModel s,
    required List<ShipmentCostItemModel> items,
    required double revForeign,
    required double revEgp,
    required double totalCostEgp,
    required double netProfitEgp,
    required double margin,
    required double revPerCartonForeign,
    required double costPerCartonForeign,
    required double grossPerCartonForeign,
    required double revPerCartonEgp,
    required double costPerCartonEgp,
    required double grossPerCartonEgp,
    required String currency,
    double discount = 0,
  }) {
    return _generate(
      s: s, items: items,
      revForeign: revForeign, revEgp: revEgp,
      totalCostEgp: totalCostEgp,
      netProfitEgp: netProfitEgp, margin: margin,
      revPerCartonForeign: revPerCartonForeign,
      costPerCartonForeign: costPerCartonForeign,
      grossPerCartonForeign: grossPerCartonForeign,
      revPerCartonEgp: revPerCartonEgp,
      costPerCartonEgp: costPerCartonEgp,
      grossPerCartonEgp: grossPerCartonEgp,
      currency: currency,
      discount: discount,
    );
  }

  static Map<String, List<ShipmentCostItemModel>> _groupByCategory(
      List<ShipmentCostItemModel> items) {
    final map = <String, List<ShipmentCostItemModel>>{};
    for (final i in items) {
      map.putIfAbsent(i.categoryLabel, () => []).add(i);
    }
    return map;
  }

  static String _categoryLabel(String cat) {
    return cat;
  }

  static pw.Widget _buildInfoSection(ExportShipmentModel s) {
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
          _infoRow('رقم الشحنة', s.shipmentNo),
          pw.SizedBox(height: 3),
          _infoRow('التاريخ', dateStr),
          pw.SizedBox(height: 3),
          _infoRow('العميل', s.customerName ?? '—'),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 6),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  static pw.Widget _buildProductRow(ExportShipmentModel s) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('المنتج'),
            _tableHeader('عدد الكراتين'),
            _tableHeader('الوزن'),
          ],
        ),
        pw.TableRow(children: [
          _tableCell('شحنة ${s.shipmentNo}'),
          _tableCell('${s.cartonsCount}'),
          _tableCell('${s.netWeight} كجم'),
        ]),
      ],
    );
  }

  static List<pw.Widget> _buildCostItemsSection(
      Map<String, List<ShipmentCostItemModel>> grouped) {
    final orderedGroups = grouped.entries.toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(
          'بنود التكلفة',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _tableHeader('البيان'),
              _tableHeader('الكمية'),
              _tableHeader('السعر'),
              _tableHeader('القيمة'),
            ],
          ),
        ],
      ),
      for (final entry in orderedGroups) ...[
        _buildCategoryHeader(entry.key),
        for (final item in entry.value) ...[
          pw.Table(
            border: pw.TableBorder(
              left: const pw.BorderSide(width: 0.5),
              right: const pw.BorderSide(width: 0.5),
              bottom: const pw.BorderSide(width: 0.5),
              verticalInside: const pw.BorderSide(width: 0.5),
              horizontalInside: const pw.BorderSide(width: 0.5),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(children: [
                _tableCell(item.description),
                _tableCell(item.quantity.toString()),
                _tableCell(_fmt(item.unitPrice)),
                _tableCell(_fmt(item.totalPrice),
                    bold: true),
              ]),
            ],
          ),
        ],
      ],
    ];
  }

  static pw.Widget _buildCategoryHeader(String cat) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border(
          left: pw.BorderSide(width: 0.5),
          right: pw.BorderSide(width: 0.5),
          bottom: pw.BorderSide(width: 0.5),
        ),
      ),
      child: pw.Text(
        cat,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildSummarySection({
    required double revForeign,
    required double revEgp,
    required double totalCostEgp,
    required double netProfitEgp,
    required double margin,
    required double revPerCartonForeign,
    required double costPerCartonForeign,
    required double grossPerCartonForeign,
    required double revPerCartonEgp,
    required double costPerCartonEgp,
    required double grossPerCartonEgp,
    required String symbol,
    required String currency,
    double discount = 0,
  }) {
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
          pw.Text(
            'ملخص الربحية',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _summaryRow('إجمالي الإيراد ($currency)', '${_fmt(revForeign)} $symbol'),
          pw.SizedBox(height: 3),
          _summaryRow('إجمالي الإيراد (ج.م)', '${_fmt(revEgp)}'),
          pw.SizedBox(height: 3),
          _summaryRow('إجمالي التكلفة (ج.م)', '${_fmt(totalCostEgp)}'),
          pw.SizedBox(height: 3),
          if (discount != 0) ...[
            _summaryRow('الخصم (ج.م)', '${_fmt(discount)}'),
            pw.SizedBox(height: 3),
          ],
          pw.Container(height: 1, color: PdfColors.grey300),
          pw.SizedBox(height: 3),
          _summaryRow('صافي الربح (ج.م)', '${_fmt(netProfitEgp)}', bold: true),
          pw.SizedBox(height: 3),
          _summaryRow('هامش الربح', '${margin.toStringAsFixed(1)}%'),
          pw.SizedBox(height: 3),
          pw.Container(height: 1, color: PdfColors.grey300),
          pw.SizedBox(height: 3),
          _summaryRow('سعر بيع الكرتونة (بالعملة)', '${_fmt(revPerCartonForeign)} $symbol'),
          pw.SizedBox(height: 3),
          _summaryRow('تكلفة الكرتونة (بالعملة)', '${_fmt(costPerCartonForeign)} $symbol'),
          pw.SizedBox(height: 3),
          _summaryRow('ربح الكرتونة (بالعملة)', '${_fmt(grossPerCartonForeign)} $symbol', bold: true),
          pw.SizedBox(height: 3),
          pw.Container(height: 1, color: PdfColors.grey300),
          pw.SizedBox(height: 3),
          _summaryRow('سعر بيع الكرتونة (ج.م)', '${_fmt(revPerCartonEgp)}'),
          pw.SizedBox(height: 3),
          _summaryRow('تكلفة الكرتونة (ج.م)', '${_fmt(costPerCartonEgp)}'),
          pw.SizedBox(height: 3),
          _summaryRow('ربح الكرتونة (ج.م)', '${_fmt(grossPerCartonEgp)}', bold: true),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value,
      {bool bold = false}) {
    return pw.Row(
      children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Spacer(),
        pw.Text(
          value,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
        ),
      ],
    );
  }

  // ── Primitives ──

  static pw.Widget _tableHeader(String t) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(String t, {bool bold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static String _currencySymbol(String c) {
    switch (c) {
      case 'EUR': return '€';
      case 'USD': return '\$';
      case 'GBP': return '£';
      case 'EGP': return 'ج.م';
      default: return c;
    }
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }

  static String _fmt(double n) {
    final isNegative = n < 0;
    final absN = n.abs();
    final p = absN.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    int c = 0;
    for (int i = p[0].length - 1; i >= 0; i--) {
      buf.write(p[0][i]);
      c++;
      if (c % 3 == 0 && i > 0) buf.write(',');
    }
    final numStr = '${buf.toString().split('').reversed.join()}.${p[1]}';
    return isNegative ? '-$numStr' : numStr;
  }
}
