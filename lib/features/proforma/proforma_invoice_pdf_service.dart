import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'proforma_invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../exports/shipment_constants.dart';

class ProformaInvoicePdfService {
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<pw.Document> generate(
    ProformaInvoiceModel s, {
    required List<ProformaInvoiceItem> items,
    CustomerModel? customer,
    ClearingAgentModel? clearingAgent,
  }) async {
    final doc = pw.Document();
    final fontRegular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(fontRegular);
    final fontBold_ = pw.Font.ttf(fontBold);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    final symbol = _currencySymbol(s.currency);
    final dateStr = _formatDate(s.invoiceDate);
    final totalQty = items.fold<int>(0, (sum, i) => sum + i.quantity.toInt());
    final totalNet = items.fold<double>(0, (sum, i) => sum + i.netWeight);
    final totalGross = items.fold<double>(0, (sum, i) => sum + i.grossWeight);
    final totalAmount = items.fold<double>(0, (sum, i) => sum + i.computedTotal);
    final totalPallets = items.fold<int>(0, (sum, i) => sum + i.palletsCount);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            _pageW, _pageH,
            marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0,
          ),
          theme: pw.ThemeData.withFont(
            base: font, bold: fontBold_, italic: font, boldItalic: fontBold_,
          ),
          buildBackground: (pw.Context ctx) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        header: (pw.Context ctx) {
          return pw.SizedBox(height: 78);
        },
        footer: (pw.Context ctx) {
          return pw.SizedBox(height: 61);
        },
        build: (pw.Context context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildInvoiceTitle(),
                  pw.SizedBox(height: 3),
                  _buildDateInvoiceTable(dateStr, s.invoiceNo),
                  pw.SizedBox(height: 3),
                  _buildConsigneeShipper(s, customer),
                  _buildNotifyAndShipping(s, clearingAgent, s.transportMode == 'sea'),
                  pw.SizedBox(height: 3),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 0),
              child: _buildItemsTable(s, items, symbol, totalQty, totalNet, totalGross, totalAmount, totalPallets),
            ),
            pw.SizedBox(height: 5),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 0),
              child: _buildBottomSection(s),
            ),
          ];
        },
      ),
    );
    return doc;
  }

  static pw.Widget _buildInvoiceTitle() {
    return pw.Center(
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1)),
        ),
        padding: const pw.EdgeInsets.only(bottom: 1),
        child: pw.Text(
          'invoice',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  static pw.Widget _buildDateInvoiceTable(String dateStr, String invoiceNo) {
    return pw.Container(
      width: 262,
      child: pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(131),
          1: const pw.FlexColumnWidth(131),
        },
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        children: [
          pw.TableRow(children: [
            _dateCell('Date', bold: false, fontSize: 8),
            _dateCell('Invoice No', bold: false, fontSize: 8),
          ]),
          pw.TableRow(children: [
            _dateCell(dateStr, bold: true, fontSize: 9),
            _dateCell(invoiceNo, bold: true, fontSize: 9),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _buildConsigneeShipper(
      ProformaInvoiceModel s, CustomerModel? customer) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 240,
          child: _buildBox(
            header: 'Consignee',
            child: _buildConsigneeBody(s, customer),
          ),
        ),
        pw.SizedBox(
          width: 283,
          child: _buildBox(
            header: 'Shipper',
            child: _buildShipperBody(),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildConsigneeBody(
      ProformaInvoiceModel s, CustomerModel? customer) {
    if (customer == null && s.customerName == null) {
      return pw.SizedBox(height: 8);
    }

    final lines = <Map<String, dynamic>>[];

    if (customer != null) {
      lines.add({'text': customer.name, 'bold': true});
      String address = s.destinationAddress ?? '';
      if (address.trim().isEmpty && customer.addresses.isNotEmpty) {
        final a = customer.addresses.first;
        address = (a['full_address'] ?? a['address_line_1'] ?? a['address'] ?? '').toString();
      }
      if (address.isNotEmpty) lines.add({'text': address});
      if (customer.city.isNotEmpty) lines.add({'text': customer.city});
      if (s.country != null && s.country!.isNotEmpty) {
        lines.add({'text': s.country!});
      } else if (customer.country.isNotEmpty) {
        lines.add({'text': customer.country});
      }
      if (customer.contactPersonName.isNotEmpty) {
        lines.add({'text': 'Contact Person : ${customer.contactPersonName}', 'boldLabel': true});
      }
      final displayPhone = customer.contactPersonPhone.isNotEmpty ? customer.contactPersonPhone : customer.phone;
      if (displayPhone.isNotEmpty) lines.add({'text': 'Tel: $displayPhone'});
      final displayEmail = customer.contactPersonEmail.isNotEmpty ? customer.contactPersonEmail : customer.gmail;
      if (displayEmail.isNotEmpty) lines.add({'text': 'E-Mail: $displayEmail'});
      if (customer.vatNumber.isNotEmpty) lines.add({'text': 'VAT NO: ${customer.vatNumber}'});
      if (customer.eoriNo.isNotEmpty) lines.add({'text': 'EORI NO: ${customer.eoriNo}'});
    } else {
      lines.add({'text': s.customerName ?? '—', 'bold': true});
      if (s.country != null && s.country!.isNotEmpty) lines.add({'text': s.country!});
      if (s.destinationAddress != null && s.destinationAddress!.trim().isNotEmpty) {
        lines.add({'text': s.destinationAddress!});
      }
    }

    final fs = _dynamicFontSize(lines.length, 8.0, 6.0);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines.map((l) {
        final isBold = l['bold'] == true;
        final isBoldLabel = l['boldLabel'] == true;
        if (isBoldLabel) {
          final t = l['text'] as String;
          final colonIdx = t.indexOf(':');
          if (colonIdx >= 0) {
            return _richLine(t.substring(0, colonIdx + 2), t.substring(colonIdx + 2),
                boldLabel: true, labelSize: fs);
          }
        }
        return _textLine(l['text'] as String, bold: isBold, fontSize: isBold ? fs + 1 : fs);
      }).toList(),
    );
  }

  static pw.Widget _buildShipperBody() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _textLine('Fruity Farms', bold: true, fontSize: 9),
        pw.SizedBox(height: 3),
        _textLine('Al Musheer Ahmed Ismail St., Building No.1', fontSize: 8),
        pw.SizedBox(height: 3),
        _textLine('Sheraton District, Heliopolis, Cairo, Egypt.', fontSize: 8),
        _textLine('Tel : 01111034064', fontSize: 8),
        _textLine('E-mail : export@fruityfarms.co', fontSize: 8),
      ],
    );
  }

  static pw.Widget _buildNotifyAndShipping(
      ProformaInvoiceModel s, ClearingAgentModel? agent, bool isSea) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 240,
          child: _buildBox(
            header: 'Notify',
            child: _buildNotifyBody(agent),
          ),
        ),
        pw.SizedBox(
          width: 283,
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.5),
            ),
            child: isSea
                ? pw.Column(children: [
                    _shippingRow('BL No.:', s.blNumber ?? 'TBA'),
                    _shippingRow('Vessel Name:', s.vesselName ?? 'TBA'),
                    _shippingRow('Cntr. No.:', s.containerNo ?? 'TBA'),
                    _shippingRow('Data Logger No.:', s.dataLoggerNo ?? 'TBA', showBorder: false),
                  ])
                : pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                    columnWidths: {0: const pw.FlexColumnWidth(283)},
                    children: [
                      pw.TableRow(children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2.1),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                          ),
                          child: pw.Center(
                            child: pw.Text('AWB',
                                style: pw.TextStyle(
                                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Container(
                          constraints: const pw.BoxConstraints(minHeight: 68),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: pw.Center(
                            child: pw.Text(
                              s.blNumber ?? 'TBA',
                              style: pw.TextStyle(
                                  fontSize: 11, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildNotifyBody(ClearingAgentModel? agent) {
    if (agent == null || agent.name.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _textLine('Air Agent', bold: true, fontSize: 8),
          _textLine('Clearer', fontSize: 8),
          _textLine('Giza', fontSize: 8),
          _textLine('Egypt', fontSize: 8),
        ],
      );
    }

    final lines = <Map<String, dynamic>>[];
    lines.add({'text': agent.name, 'bold': true});
    if (agent.code.isNotEmpty) lines.add({'text': 'Code: ${agent.code}'});
    for (final a in agent.addresses) {
      final addr = a['full_address']?.toString() ?? a['address_line_1']?.toString() ?? a['address']?.toString() ?? '';
      if (addr.isNotEmpty) lines.add({'text': addr});
    }
    if (agent.city.isNotEmpty) lines.add({'text': agent.city});
    if (agent.country.isNotEmpty) lines.add({'text': agent.country});
    if (agent.phone.isNotEmpty) lines.add({'text': 'Tel: ${agent.phone}'});
    if (agent.gmail.isNotEmpty) lines.add({'text': 'E-Mail: ${agent.gmail}'});
    if (agent.contactPersonName.isNotEmpty) {
      lines.add({'text': 'Contact Person : ${agent.contactPersonName}', 'boldLabel': true});
    }
    if (agent.contactPersonPhone.isNotEmpty) {
      lines.add({'text': 'Contact Tel: ${agent.contactPersonPhone}'});
    }
    if (agent.contactPersonEmail.isNotEmpty) {
      lines.add({'text': 'Contact E-Mail: ${agent.contactPersonEmail}'});
    }

    final fs = _dynamicFontSize(lines.length, 8.0, 6.0);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines.map((l) {
        final isBold = l['bold'] == true;
        final isBoldLabel = l['boldLabel'] == true;
        if (isBoldLabel) {
          final t = l['text'] as String;
          final colonIdx = t.indexOf(':');
          if (colonIdx >= 0) {
            return _richLine(t.substring(0, colonIdx + 2), t.substring(colonIdx + 2),
                boldLabel: true, labelSize: fs);
          }
        }
        return _textLine(l['text'] as String, bold: isBold, fontSize: isBold ? fs + 1 : fs);
      }).toList(),
    );
  }

  static pw.Widget _shippingRow(String label, String value,
      {bool showBorder = true}) {
    return pw.Container(
      width: double.infinity,
      constraints: const pw.BoxConstraints(minHeight: 18),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: showBorder
          ? const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)))
          : null,
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ]),
      ),
    );
  }

  static pw.Widget _buildBox(
      {required String header, required pw.Widget child}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 16),
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              header,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: child,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(
    ProformaInvoiceModel s,
    List<ProformaInvoiceItem> items,
    String symbol,
    int totalQty,
    double totalNet,
    double totalGross,
    double totalAmount,
    int totalPallets,
  ) {
    final cw = {
      0: const pw.FlexColumnWidth(190),
      1: const pw.FlexColumnWidth(50),
      2: const pw.FlexColumnWidth(62),
      3: const pw.FlexColumnWidth(56),
      4: const pw.FlexColumnWidth(62),
      5: const pw.FlexColumnWidth(103),
    };
    final tb = pw.TableBorder(
      top: const pw.BorderSide(width: 0.5),
      bottom: const pw.BorderSide(width: 0.5),
      left: const pw.BorderSide(width: 0.5),
      right: const pw.BorderSide(width: 0.5),
      verticalInside: const pw.BorderSide(width: 0.5),
      horizontalInside: const pw.BorderSide(width: 0.5),
    );

    return pw.Column(children: [
      pw.Table(
        border: tb,
        columnWidths: cw,
        children: [
          pw.TableRow(children: [
            _tableHeader('Product Description', align: pw.TextAlign.left),
            _tableHeader('Qty-Crtn'),
            _tableHeader('Price/Crtn'),
            _tableHeader('Total\nNet WT'),
            _tableHeader('Total Gross\nWT'),
            _tableHeader('Amount'),
          ]),
          ...items.map((item) => pw.TableRow(children: [
                _tableItemCell(
                  item.productName,
                  sub: 'Net Weight: ${item.quantity > 0 ? (item.netWeight / item.quantity).toStringAsFixed(1) : item.netWeight.toStringAsFixed(1)} KG',
                ),
                _tableCell('${item.quantity.toInt()}'),
                _tableCell('$symbol ${item.pricePerCarton.toStringAsFixed(2)}'),
                _tableCell('${item.netWeight.toStringAsFixed(1)}'),
                _tableCell('${item.grossWeight.toStringAsFixed(1)}'),
                _tableCell(
                  '$symbol ${item.computedTotal.toStringAsFixed(2)}',
                  bold: true,
                ),
              ])),
          if (items.isEmpty)
            pw.TableRow(children: [
              _tableCell(''),
              _tableCell('0'),
              _tableCell(''),
              _tableCell('0'),
              _tableCell('0'),
              _tableCell(''),
            ]),
        ],
      ),
      // Pallets row
      if (totalPallets > 0)
        pw.Container(
          width: double.infinity,
          constraints: const pw.BoxConstraints(minHeight: 16),
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: const pw.BorderSide(width: 0.5),
              right: const pw.BorderSide(width: 0.5),
              bottom: const pw.BorderSide(width: 0.5),
            ),
          ),
          child: pw.Center(
            child: pw.Text(
              '$totalPallets Pallets',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ),
      // Total row
      pw.Table(
        border: pw.TableBorder(
          top: const pw.BorderSide(width: 1),
          bottom: const pw.BorderSide(width: 0.5),
          left: const pw.BorderSide(width: 0.5),
          right: const pw.BorderSide(width: 0.5),
          verticalInside: const pw.BorderSide(width: 0.5),
        ),
        columnWidths: cw,
        children: [
          pw.TableRow(children: [
            _tableCell('Total', bold: true, fontSize: 9, align: pw.TextAlign.left, paddingLeft: 6),
            _tableCellUnderline('$totalQty', bold: true, fontSize: 9),
            _tableCell(''),
            _tableCellUnderline('${totalNet.toStringAsFixed(0)}', bold: true, fontSize: 9),
            _tableCellUnderline('${totalGross.toStringAsFixed(0)}', bold: true, fontSize: 9),
            _tableCellUnderline('$symbol ${totalAmount.toStringAsFixed(2)}', bold: true, fontSize: 10),
          ])
        ],
      ),
    ]);
  }

  static pw.Widget _buildBottomSection(ProformaInvoiceModel s) {
    final tl = s.transportMode == 'sea' ? "By Sea" : 'By Air';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 140,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.5),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 0.3),
          child: pw.Center(
            child: pw.Text(
              'TERMS OF SALE AND OTHER COMMENTS',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Container(
          width: 280,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.5),
          ),
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _textLine('TERMS AND CONDITIONS', bold: true, fontSize: 7),
              pw.SizedBox(height: 1),
              _textLine('Fruity Farms', bold: true, fontSize: 5),
              pw.SizedBox(height: 1),
              _termsRow('Port Of Loading  :', s.portOfLoading ?? 'TBA'),
              pw.SizedBox(height: 1),
              _termsRow('Port Of Destination  :', s.portOfDestination ?? 'TBA'),
              pw.SizedBox(height: 1),
              if (s.paymentTerms != null && s.paymentTerms!.isNotEmpty) ...[
                _termsRow('Terms of Payment  :', s.paymentTerms!),
                pw.SizedBox(height: 1),
              ],
              _termsRow('Mode Of Transport  :', tl),
              pw.SizedBox(height: 1),
              _textLine(
                'All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account',
                fontSize: 5,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 2),
        _textLine(
          'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
          fontSize: 5,
        ),
        pw.SizedBox(height: 2),
        _buildBankAndStamp(s),
      ],
    );
  }

  static pw.Widget _buildBankAndStamp(ProformaInvoiceModel s) {
    final bank = BankDetails.forCurrency(s.currency ?? 'EUR');
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(
        width: 250,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 100,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                ),
                child: _textLine('Bank Details', bold: true, fontSize: 7),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(6, 3, 6, 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (bank != null) ...[
                      _bankLine('Bank Name:', bank.bankName),
                      _bankLine('Bank Address:',
                          '${bank.bankAddress}, El Nozha, Cairo Governorate, Egypt'),
                      _bankLine('Account Name:', bank.accountName),
                      _bankLine('Account Number:', bank.accountNumber),
                      _bankLine('IBAN no.:', bank.iban),
                      _bankLine('Swift Code:', bank.swiftCode),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  // ── Primitives ──

  static pw.Widget _dateCell(String t, {bool bold = false, double fontSize = 8}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        alignment: pw.Alignment.center,
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static pw.Widget _textLine(String t, {bool bold = false, double fontSize = 8}) =>
      pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );

  static double _dynamicFontSize(int lineCount, double maxFs, double minFs) {
    if (lineCount <= 5) return maxFs;
    if (lineCount >= 12) return minFs;
    return maxFs - (maxFs - minFs) * (lineCount - 5) / 7;
  }

  static pw.Widget _richLine(String label, String value,
          {bool boldLabel = false, double labelSize = 8}) =>
      pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
            text: label,
            style: pw.TextStyle(
              fontSize: labelSize,
              fontWeight: boldLabel ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(fontSize: labelSize),
          ),
        ]),
      );

  static pw.Widget _tableHeader(String t,
          {pw.TextAlign align = pw.TextAlign.center}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        alignment: align == pw.TextAlign.left
            ? pw.Alignment.centerLeft
            : pw.Alignment.center,
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            fontStyle: pw.FontStyle.italic,
          ),
          textAlign: align,
        ),
      );

  static pw.Widget _tableCell(
    String t, {
    bool bold = false,
    double fontSize = 8,
    pw.TextAlign align = pw.TextAlign.center,
    double paddingLeft = 3,
  }) =>
      pw.Container(
        padding: pw.EdgeInsets.fromLTRB(paddingLeft, 5, 3, 5),
        alignment: align == pw.TextAlign.left
            ? pw.Alignment.centerLeft
            : (align == pw.TextAlign.right
                ? pw.Alignment.centerRight
                : pw.Alignment.center),
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static pw.Widget _tableItemCell(String t, {String? sub}) => pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(3, 5, 3, 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              t,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
            if (sub != null)
              pw.Text(sub, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );

  static pw.Widget _tableCellUnderline(String t,
          {bool bold = false, double fontSize = 9}) =>
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(3, 4, 3, 4),
        alignment: pw.Alignment.center,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.6)),
        ),
        child: pw.Text(
          t,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static pw.Widget _termsRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 1),
        child: pw.Row(children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 3),
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(bottom: 0.1),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 5)),
          ),
        ]),
      );

  static pw.Widget _bankLine(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 5),
          ),
        ],
      ),
    );
  }

  static String _currencySymbol(String? c) {
    switch (c) {
      case 'EUR': return '€';
      case 'USD': return '\$';
      case 'GBP': return '£';
      case 'EGP': return 'ج.م';
      default: return c ?? '';
    }
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day}-${m[dt.month - 1]}-${dt.year}';
  }
}
