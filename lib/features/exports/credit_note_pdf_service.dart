import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/export_shipment_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class CreditNotePdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<void> savePdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
  }) async {
    final doc = await _generate(shipment);
    final bytes = await doc.save();
    
    final dir = await FileHelper.getExportDirectory();
    final safeName = shipment.shipmentNo.replaceAll(RegExp(r'[\\/]'), '_');
    final fileName = 'Credit_Note_$safeName.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الإشعار في:\n${file.path}'),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  static Future<void> previewPdf({
    required BuildContext context,
    required ExportShipmentModel shipment,
  }) async {
    final doc = await _generate(shipment);
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Credit_Note_${shipment.shipmentNo}.pdf',
    );
  }

  static String _numberToWords(double amount) {
    if (amount == 0) return 'Zero';
    final int dollars = amount.floor();
    final int cents = ((amount - dollars) * 100).round();

    final ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    String convert(int n) {
      if (n < 20) return ones[n];
      if (n < 100) return tens[n ~/ 10] + (n % 10 != 0 ? ' ' + ones[n % 10] : '');
      if (n < 1000) return ones[n ~/ 100] + ' Hundred' + (n % 100 != 0 ? ' ${convert(n % 100)}' : '');
      if (n < 1000000) return '${convert(n ~/ 1000)} Thousand' + (n % 1000 != 0 ? ' ${convert(n % 1000)}' : '');
      return n.toString();
    }

    String result = convert(dollars);
    if (cents > 0) {
      result += ' and ${convert(cents)} Cents';
    }
    return result;
  }

  static String _currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'USD': return r'$';
      case 'EUR': return '€';
      case 'EGP': return 'EGP';
      case 'GBP': return '£';
      default: return code;
    }
  }

  static String _currencyName(String code) {
    switch (code.toUpperCase()) {
      case 'USD': return 'Dollars';
      case 'EUR': return 'Euros';
      case 'EGP': return 'Pounds';
      case 'GBP': return 'Pounds';
      default: return code;
    }
  }

  static Future<Map<String, dynamic>?> _getCustomer(String? id) async {
    if (id == null) return null;
    try {
      final res = await Supabase.instance.client.from('customers').select().eq('id', id).maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Document> _generate(ExportShipmentModel s) async {
    final doc = pw.Document();
    
    // Load fonts safely
    late final pw.Font fontBase;
    late final pw.Font fontBold_;
    try {
      final fontRegular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      fontBase = pw.Font.ttf(fontRegular);
      fontBold_ = pw.Font.ttf(fontBold);
    } catch (_) {
      fontBase = pw.Font.helvetica();
      fontBold_ = pw.Font.helveticaBold();
    }
    
    pw.MemoryImage? bgImage;
    try {
      bgImage = pw.MemoryImage(
        (await rootBundle.load('assets/images/statment.png')).buffer.asUint8List(),
      );
    } catch (_) {}

    final customer = await _getCustomer(s.customerId);
    
    final symbol = _currencySymbol(s.currencyCode);
    final curName = _currencyName(s.currencyCode);
    
    // Date
    final dt = s.shipmentDate ?? DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${dt.day}-${months[dt.month - 1]}-${dt.year.toString().substring(2)}';
    
    final invoiceNo = s.invoiceNumber ?? s.shipmentNo;
    final awbNo = s.blNumber ?? s.containerNo ?? s.shipmentNo;
    
    // Customer Details
    final cName = customer?['name'] ?? s.customerName ?? '';
    final cCity = customer?['city'] ?? '';
    final cCountry = customer?['country'] ?? s.country ?? '';
    final addressObj = (customer?['addresses'] is List && (customer!['addresses'] as List).isNotEmpty) 
        ? customer['addresses'][0] : null;
    final cAddrLine = addressObj?['address_line_1'] ?? addressObj?['address'] ?? '';
    final fullAddress = [cAddrLine, cCity, cCountry].where((e) => e.isNotEmpty).join(' - ');
    
    final cContact = customer?['contact_person_name'] ?? s.contactPerson ?? '';
    final cPhone = customer?['contact_person_phone'] ?? customer?['phone'] ?? '';
    final cEmail = customer?['contact_person_email'] ?? customer?['gmail'] ?? '';
    final cEori = customer?['eori_no'] ?? '';
    final cVat = customer?['vat_no'] ?? customer?['vat_number'] ?? '';

    // Calculations
    double pricePerKg = 0.0;
    if (s.netWeight > 0 && s.totalRevenueForeign > 0) {
      pricePerKg = s.totalRevenueForeign / s.netWeight;
    }
    double discount = s.discountAmount;
    double netWgt = 0.0;
    if (pricePerKg > 0) {
      netWgt = discount / pricePerKg;
    }
    
    double displayAmount = discount;
    double displayPricePerKg = pricePerKg;
    
    final amountWords = 'Only ${_numberToWords(displayAmount)} $curName';

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(_pageW, _pageH, marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0),
        theme: pw.ThemeData.withFont(
          base: fontBase,
          bold: fontBold_,
          italic: fontBase,
          boldItalic: fontBold_,
        ),
        build: (pw.Context context) {
          return pw.Stack(children: [
            if (bgImage != null) pw.Positioned.fill(child: pw.Image(bgImage, fit: pw.BoxFit.fill)),
            pw.Positioned.fill(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(40, 140, 40, 40),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text('CREDIT NOTE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                  ),
                  pw.SizedBox(height: 30),
                  
                  // Top Info section
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // Left Column
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _rowText('Date:', dateStr),
                          pw.SizedBox(height: 10),
                          _rowText('For Invoice No:', invoiceNo),
                          pw.SizedBox(height: 15),
                          _rowText('Furnished To:', cName, isBold: true),
                          pw.SizedBox(height: 2),
                          _rowText('Address:', fullAddress),
                          pw.SizedBox(height: 2),
                          if (cContact.isNotEmpty) _rowText('', 'Contact Person: $cContact'),
                          pw.SizedBox(height: 2),
                          if (cPhone.isNotEmpty) _rowText('', 'Tel: $cPhone'),
                          pw.SizedBox(height: 2),
                          if (cEmail.isNotEmpty) _rowText('', 'Email contact : $cEmail'),
                          pw.SizedBox(height: 2),
                          if (cEori.isNotEmpty) _rowText('', 'EORI Number $cEori', isBold: true, underline: true),
                          pw.SizedBox(height: 2),
                          if (cVat.isNotEmpty) _rowText('', 'VAT Number $cVat', isBold: true, underline: true),
                        ],
                      ),
                      ),
                      
                      // Right Column (CR No, AWB No)
                      pw.Container(
                        width: 180,
                        child: pw.Table(
                          border: pw.TableBorder.all(color: PdfColors.black, width: 1.2),
                          children: [
                            pw.TableRow(
                              children: [
                                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('CR No.:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('CR $invoiceNo', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                              ]
                            ),
                            pw.TableRow(
                              children: [
                                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(s.transportMode == 'sea' ? 'BL No.' : 'AWB No', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red), textAlign: pw.TextAlign.center)),
                                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(awbNo, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                              ]
                            ),
                          ]
                        ),
                      )
                    ]
                  ),
                  
                  pw.SizedBox(height: 30),
                  
                  // Main Table
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 1.2),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(10),
                      1: const pw.FlexColumnWidth(12),
                      2: const pw.FlexColumnWidth(12),
                      3: const pw.FlexColumnWidth(25),
                      4: const pw.FlexColumnWidth(12),
                      5: const pw.FlexColumnWidth(12),
                    },
                    children: [
                      // Header
                      pw.TableRow(
                        children: [
                          _th('QTY'),
                          _th('Net WGT'),
                          _th('Price/KG'),
                          _th('Description'),
                          _th('Amount'),
                          _th('Remarks'),
                        ]
                      ),
                      // Data
                      pw.TableRow(
                        children: [
                          _td('-', height: 150),
                          _td(netWgt.toStringAsFixed(3).replaceAll(RegExp(r'([.]*0)(?!.*\d)'), ''), height: 150),
                          _td('$symbol ${displayPricePerKg.toStringAsFixed(2)}', height: 150),
                          _td('-', height: 150),
                          _td(displayAmount.toStringAsFixed(2), height: 150),
                          _td('', height: 150),
                        ]
                      ),
                    ]
                  ),
                  // Footer Row matching the columns perfectly
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(width: 1.2, color: PdfColors.black),
                        left: pw.BorderSide(width: 1.2, color: PdfColors.black),
                        right: pw.BorderSide(width: 1.2, color: PdfColors.black),
                      )
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 59, // 10+12+12+25
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(amountWords, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          )
                        ),
                        pw.Container(width: 1.2, height: 25, color: PdfColors.black),
                        pw.Expanded(
                          flex: 12,
                          child: pw.Center(child: pw.Text('$symbol ${displayAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10))),
                        ),
                        pw.Container(width: 1.2, height: 25, color: PdfColors.black),
                        pw.Expanded(
                          flex: 12,
                          child: pw.Container(),
                        ),
                      ]
                    )
                  ),
                ],
              ),
            ),
            ),
          ]);
        },
      ),
    );
    return doc;
  }

  static pw.Widget _rowText(String label, String value, {bool isBold = false, bool underline = false}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 85,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.Expanded(
          child: pw.Text(
            value, 
            style: pw.TextStyle(
              fontSize: 10, 
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              decoration: underline ? pw.TextDecoration.underline : pw.TextDecoration.none,
            ),
          ),
        ),
      ]
    );
  }

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: pw.Text(text, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _td(String text, {double? height}) {
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: pw.Text(text, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
    );
  }
}
