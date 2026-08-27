import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/services/currency_conversion_service.dart';
import 'shipment_constants.dart';

class CommercialInvoicePdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<void> previewCommercialInvoice({
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

    final symbol = _currencySymbol(s.currencyCode);
    final dateStr = _formatDate(s.shipmentDate);
    final invNo = (s.invoiceNumber != null && s.invoiceNumber!.isNotEmpty)
        ? s.invoiceNumber!
        : s.shipmentNo;
    final totalQty = items.fold(0, (int sum, i) => sum + (int.tryParse(i['quantity']?.toString() ?? '0') ?? 0));
    final totalNet = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['net_weight']?.toString() ?? '0') ?? 0));
    final totalGross = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['gross_weight']?.toString() ?? '0') ?? 0));
    final totalAmount = items.fold(0.0, (sum, i) => sum + (double.tryParse(i['amount']?.toString() ?? '0') ?? 0));

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
              _buildHeader(s, invNo, dateStr),
              pw.SizedBox(height: 12),
              _buildConsigneeShipper(s),
              pw.SizedBox(height: 8),
              _buildShipmentDetails(s),
              pw.SizedBox(height: 8),
              _buildItemsTable(s, items, symbol, totalQty, totalNet, totalGross, totalAmount),
              pw.SizedBox(height: 8),
              _buildTotals(s, totalAmount, symbol),
              pw.SizedBox(height: 8),
              _buildFooter(s),
            ],
          );
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildHeader(ExportShipmentModel s, String invNo, String dateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Fruity Farms', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text('Al Musheer Ismail St., Building 1', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                pw.Text('Sheraton, Heliopolis, Cairo, Egypt', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
            pw.Spacer(),
            pw.Container(
              width: 200,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _infoRow('Invoice No:', invNo, 8),
                  pw.SizedBox(height: 2),
                  _infoRow('Date:', dateStr, 8),
                  pw.SizedBox(height: 2),
                  _infoRow('Shipment No:', s.shipmentNo, 8),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            'COMMERCIAL INVOICE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildConsigneeShipper(ExportShipmentModel s) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('CONSIGNEE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(s.customerName ?? '—', style: const pw.TextStyle(fontSize: 9)),
                if (s.destinationAddress != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(s.destinationAddress!, style: const pw.TextStyle(fontSize: 8)),
                ],
                if (s.country != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(s.country!, style: const pw.TextStyle(fontSize: 8)),
                ],
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SHIPPER', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Fruity Farms', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Al Musheer Ismail St., Building No.1', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Sheraton District, Heliopolis, Cairo, Egypt.', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Tel: 01111034064', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Email: export@fruityfarms.co', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildShipmentDetails(ExportShipmentModel s) {
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
          _detailCell('Port of Loading', s.portOfLoading ?? '—'),
          _detailCell('Port of Destination', s.portOfDestination ?? '—'),
          _detailCell('Vessel/Flight', s.vesselName ?? '—'),
          _detailCell('Transport Mode', s.transportMode == 'sea' ? 'Sea' : 'Air'),
        ]),
        pw.TableRow(children: [
          _detailCell('Container No', s.containerNo ?? '—'),
          _detailCell('BL Number', s.blNumber ?? '—'),
          _detailCell('Incoterm', s.incoterm ?? '—'),
          _detailCell('Payment Terms', s.paymentTerms ?? '—'),
        ]),
      ],
    );
  }

  static pw.Widget _detailCell(String label, String value) {
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

  static pw.Widget _buildItemsTable(
    ExportShipmentModel s,
    List<Map<String, dynamic>> items,
    String symbol,
    int totalQty,
    double totalNet,
    double totalGross,
    double totalAmount,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.3),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(0.8),
        4: const pw.FlexColumnWidth(0.8),
        5: const pw.FlexColumnWidth(0.8),
        6: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableHeader('#'),
            _tableHeader('المنتج'),
            _tableHeader('الكمية\n(كرتون)'),
            _tableHeader('الوزن\nالصافي'),
            _tableHeader('الوزن\nالإجمالي'),
            _tableHeader('سعر\nالوحدة'),
            _tableHeader('الإجمالي'),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final i = entry.value;
          final idx = entry.key + 1;
          return pw.TableRow(children: [
            _tableCell(idx.toString()),
            _tableCell(i['product_name']?.toString() ?? '', align: pw.TextAlign.left),
            _tableCell(i['quantity']?.toString() ?? '0'),
            _tableCell(i['net_weight']?.toString() ?? '0'),
            _tableCell(i['gross_weight']?.toString() ?? '0'),
            _tableCell('$symbol ${i['price']?.toString() ?? '0'}'),
            _tableCell('$symbol ${_fmt(i['amount']?.toString() ?? '0')}', bold: true),
          ]);
        }),
        if (items.isEmpty)
          pw.TableRow(children: [
            _tableCell('1'),
            _tableCell(s.shipmentNo, align: pw.TextAlign.left),
            _tableCell('${s.cartonsCount}'),
            _tableCell('${s.netWeight.toInt()}'),
            _tableCell('${s.grossWeight.toInt()}'),
            _tableCell(''),
            _tableCell(''),
          ]),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _tableCell('', bold: true),
            _tableCell('الإجمالي', bold: true, align: pw.TextAlign.left),
            _tableCell(totalQty.toString(), bold: true),
            _tableCell(totalNet.toStringAsFixed(1), bold: true),
            _tableCell(totalGross.toStringAsFixed(1), bold: true),
            _tableCell('', bold: true),
            _tableCell('$symbol ${_fmt(totalAmount.toStringAsFixed(2))}', bold: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTotals(ExportShipmentModel s, double totalAmount, String symbol) {
    final totalEgp = CurrencyConversionService.instance.toBase(totalAmount, s.currencyCode, s.exchangeRate);
    return pw.Container(
      width: 300,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _totalRow('Total Amount', '$symbol ${_fmt(totalAmount.toStringAsFixed(2))} ${s.currencyCode}'),
          pw.SizedBox(height: 4),
          _totalRow('Exchange Rate', '1 ${s.currencyCode} = ${s.exchangeRate} EGP'),
          pw.SizedBox(height: 4),
          pw.Container(height: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          _totalRow('Total EGP', '${_fmt(totalEgp.toStringAsFixed(2))} EGP',
              bold: true, color: PdfColors.blue800),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(ExportShipmentModel s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Terms & Conditions', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                '1. All goods sold FOB as per incoterms 2020.\n'
                '2. Payment terms: ${s.paymentTerms ?? 'TBA'}\n'
                '3. Country of origin: Egypt\n'
                '4. Goods once sold cannot be returned.',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Authorized Signature', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Container(
                  width: 150, height: 1,
                  color: PdfColors.black,
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Stamp', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Container(
                  width: 80, height: 80,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _infoRow(String label, String value, double fontSize) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: fontSize)),
      ],
    );
  }

  static pw.Widget _totalRow(String label, String value, {bool bold = false, PdfColor? color}) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Spacer(),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(String t, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      alignment: align == pw.TextAlign.left ? pw.Alignment.centerLeft : pw.Alignment.center,
      child: pw.Text(
        t,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _tableCell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) {
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
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }

  static String _fmt(String v) {
    final n = double.tryParse(v);
    if (n == null) return v;
    final p = n.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    int c = 0;
    for (int i = p[0].length - 1; i >= 0; i--) {
      buf.write(p[0][i]);
      c++;
      if (c % 3 == 0 && i > 0) buf.write(',');
    }
    return '${buf.toString().split('').reversed.join()}.${p[1]}';
  }
}
