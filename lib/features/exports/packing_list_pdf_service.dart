import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/models/export_shipment_model.dart';

class PackingListPdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<void> previewPackingList({
    required BuildContext context,
    required ExportShipmentModel shipment,
    required List<Map<String, dynamic>> items,
  }) async {
    final doc = await _generate(shipment, items);
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
    );
  }

  static Future<pw.Document> _generate(
    ExportShipmentModel s,
    List<Map<String, dynamic>> items,
  ) async {
    final doc = pw.Document();
    final fontRegular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(fontRegular);
    final fontBold_ = pw.Font.ttf(fontBold);

    final dateStr = _formatDate(s.shipmentDate);
    final totalQty = items.fold(0, (int sum, i) => sum + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));
    final totalNet = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['net_weight']?.toString() ?? '0') ?? 0));
    final totalGross = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['gross_weight']?.toString() ?? '0') ?? 0));
    final totalPallets = items.fold(0, (int sum, i) => sum + (int.tryParse(i['pallets']?.toString() ?? '0') ?? 0));

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            _pageW,
            _pageH,
            marginTop: 20,
            marginBottom: 20,
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
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(s, dateStr),
              pw.SizedBox(height: 12),
              _buildShipmentInfo(s),
              pw.SizedBox(height: 12),
              _buildItemsTable(items),
              pw.SizedBox(height: 12),
              _buildSummary(s, totalQty, totalNet, totalGross, totalPallets),
            ],
          );
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(ExportShipmentModel s, String dateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Fruity Farms', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Al Musheer Ismail St., Building 1', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                pw.Text('Sheraton, Heliopolis, Cairo, Egypt', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Shipment No: ${s.shipmentNo}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Customer: ${s.customerName ?? '—'}', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 1)),
            ),
            child: pw.Text(
              'PACKING LIST',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildShipmentInfo(ExportShipmentModel s) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          _infoCell('Port of Loading', s.portOfLoading ?? '—'),
          _infoCell('Port of Destination', s.portOfDestination ?? '—'),
          _infoCell('Vessel/Flight', s.vesselName ?? '—'),
          _infoCell('Transport Mode', s.transportMode == 'sea' ? 'Sea' : 'Air'),
        ]),
        pw.TableRow(children: [
          _infoCell('Container No', s.containerNo ?? '—'),
          _infoCell('Container Type', s.containerType ?? '—'),
          _infoCell('BL/AWB No', s.blNumber ?? '—'),
          _infoCell('Incoterm', s.incoterm ?? '—'),
        ]),
      ],
    );
  }

  static pw.Widget _infoCell(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
    final totalQty = items.fold(0, (int sum, i) => sum + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));
    final totalNet = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['net_weight']?.toString() ?? '0') ?? 0));
    final totalGross = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['gross_weight']?.toString() ?? '0') ?? 0));
    final totalPallets = items.fold(0, (int sum, i) => sum + (int.tryParse(i['pallets']?.toString() ?? '0') ?? 0));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.3),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(0.7),
        3: const pw.FlexColumnWidth(0.7),
        4: const pw.FlexColumnWidth(0.7),
        5: const pw.FlexColumnWidth(0.7),
        6: const pw.FlexColumnWidth(0.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _th('#'),
            _th('المنتج'),
            _th('عدد\nالكراتين'),
            _th('وزن\nالكرتونة'),
            _th('الوزن\nالصافي'),
            _th('الوزن\nالإجمالي'),
            _th('عدد\nالبالتات'),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final i = entry.value;
          final idx = entry.key + 1;
          return pw.TableRow(children: [
            _tc(idx.toString()),
            _tc(i['product_name']?.toString() ?? '', align: pw.TextAlign.left),
            _tc(i['quantity']?.toString() ?? '0'),
            _tc(i['weight_per_carton']?.toString() ?? '—'),
            _tc(i['net_weight']?.toString() ?? '0'),
            _tc(i['gross_weight']?.toString() ?? '0'),
            _tc(i['pallets']?.toString() ?? '0'),
          ]);
        }),
        if (items.isEmpty)
          pw.TableRow(children: [
            _tc('1'),
            _tc('—', align: pw.TextAlign.left),
            _tc('0'),
            _tc('—'),
            _tc('0'),
            _tc('0'),
            _tc('0'),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _tc('', bold: true),
            _tc('الإجمالي', bold: true, align: pw.TextAlign.left),
            _tc(totalQty.toString(), bold: true),
            _tc('', bold: true),
            _tc(totalNet.toStringAsFixed(1), bold: true),
            _tc(totalGross.toStringAsFixed(1), bold: true),
            _tc(totalPallets.toString(), bold: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummary(
    ExportShipmentModel s,
    int totalQty,
    double totalNet,
    double totalGross,
    int totalPallets,
  ) {
    return pw.Container(
      width: 350,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Summary', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _summaryRow('إجمالي الكراتين', '$totalQty'),
          _summaryRow('إجمالي الوزن الصافي', '$totalNet kg'),
          _summaryRow('إجمالي الوزن الإجمالي', '$totalGross kg'),
          _summaryRow('إجمالي البالتات', '$totalPallets'),
          pw.SizedBox(height: 4),
          pw.Container(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          _summaryRow('نوع الحاوية', s.containerType ?? '—'),
          _summaryRow('رقم الحاوية', s.containerNo ?? '—'),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 8),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _th(String t, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      alignment: align == pw.TextAlign.left ? pw.Alignment.centerLeft : pw.Alignment.center,
      child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: align),
    );
  }

  static pw.Widget _tc(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      alignment: align == pw.TextAlign.left ? pw.Alignment.centerLeft : pw.Alignment.center,
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
      ),
    );
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }
}
