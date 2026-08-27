import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/models/export_shipment_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import 'shipment_constants.dart';

class InvoicePdfService {
  // ── Page constants ──
  static const _pageW = 595.0;
  static const _pageH = 841.0;

  static Future<pw.Document> generate(
    ExportShipmentModel s, {
    List<Map<String, dynamic>> itemsData = const [],
    CustomerModel? customer,
    ClearingAgentModel? clearingAgent,
  }) async {
    final doc = pw.Document();
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

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat(
            _pageW,
            _pageH,
            marginTop: 0,
            marginBottom: 0,
            marginLeft: 0,
            marginRight: 0,
          ),
          theme: pw.ThemeData.withFont(
            base: fontBase,
            bold: fontBold_,
            italic: fontBase,
            boldItalic: fontBold_,
          ),
          buildBackground: (pw.Context ctx) {
            if (bgImage != null) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(bgImage, fit: pw.BoxFit.cover),
              );
            }
            return pw.SizedBox();
          },
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
                children: _buildContent(s, itemsData, customer, clearingAgent),
              ),
            ),
          ];
        },
      ),
    );
    return doc;
  }

  // ════════════════════════════════════════════════════
  // CONTENT LAYOUT
  // ════════════════════════════════════════════════════
  static List<pw.Widget> _buildContent(
    ExportShipmentModel s,
    List<Map<String, dynamic>> items,
    CustomerModel? customer,
    ClearingAgentModel? agent,
  ) {
    final symbol = _currencySymbol(s.currency);
    final dateStr = _formatDate(s.shipmentDate);
    final invNo = (s.invoiceNumber != null && s.invoiceNumber!.isNotEmpty)
        ? s.invoiceNumber!
        : s.shipmentNo;

    return [
      // Section 2 — "Invoice" title
      _buildInvoiceTitle(),
      pw.SizedBox(height: 3),

      // Section 3 — Date/Invoice table
      _buildDateInvoiceTable(dateStr, invNo),
      pw.SizedBox(height: 3),

      // Section 4 — Consignee/Shipper
      _buildConsigneeShipper(s, customer),

      // Section 5 — Notify/Shipping (ملتصق بالسابق زي الصورة)
      _buildNotifyAndShipping(s, agent, s.transportMode == 'sea'),
      pw.SizedBox(height: 3),

      // Section 6 — Items Table
      _buildItemsTable(s, items, symbol),
      pw.SizedBox(height: 5),

      // Sections 7+8+9 — Terms + Bank/Stamp + Footer
      _buildBottomSection(s),
    ];
  }

  // ════════════════════════════════════════════════════
  // SECTION 2 — "Invoice" title
  // ════════════════════════════════════════════════════
  static pw.Widget _buildInvoiceTitle() {
    return pw.Center(
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1)),
        ),
        padding: const pw.EdgeInsets.only(bottom: 1),
        child: pw.Text(
          'Invoice',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════
  // SECTION 3 — Date / Invoice No table
  // ════════════════════════════════════════════════════
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

  // ════════════════════════════════════════════════════
  // SECTION 4 — Consignee / Shipper
  // ════════════════════════════════════════════════════
  static pw.Widget _buildConsigneeShipper(
      ExportShipmentModel s, CustomerModel? customer) {
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
      ExportShipmentModel s, CustomerModel? customer) {
    if (customer == null && s.customerName == null) {
      return pw.SizedBox(height: 8);
    }

    if (customer == null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [_textLine(s.customerName!, bold: true, fontSize: 9)],
      );
    }

    // Collect all non-empty lines for dynamic font sizing
    final lines = <Map<String, dynamic>>[];
    lines.add({'text': customer.name, 'bold': true});

    final address = s.destinationAddress ?? customer.addresses.firstOrNull?['address_line_1']?.toString() ?? '';
    if (address.isNotEmpty) lines.add({'text': address});

    if (customer.city.isNotEmpty) lines.add({'text': customer.city});
    if (s.country != null && s.country!.isNotEmpty) {
      lines.add({'text': s.country!});
    } else if (customer.country.isNotEmpty) {
      lines.add({'text': customer.country});
    }
    if (customer.phone.isNotEmpty) lines.add({'text': 'Tel: ${customer.phone}'});
    if (customer.gmail.isNotEmpty) lines.add({'text': 'E-Mail: ${customer.gmail}'});
    if (customer.vatNumber.isNotEmpty) lines.add({'text': 'VAT No: ${customer.vatNumber}'});
    if (customer.eoriNo.isNotEmpty) lines.add({'text': 'EORI No: ${customer.eoriNo}'});
    if (customer.contactPersonName.isNotEmpty) {
      lines.add({'text': 'Contact Person : ${customer.contactPersonName}', 'boldLabel': true});
    }
    if (customer.contactPersonPhone.isNotEmpty) {
      lines.add({'text': 'Contact Tel: ${customer.contactPersonPhone}'});
    }
    if (customer.contactPersonEmail.isNotEmpty) {
      lines.add({'text': 'Contact E-Mail: ${customer.contactPersonEmail}'});
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

  // ════════════════════════════════════════════════════
  // SECTION 5 — Notify / Shipping Details
  // ════════════════════════════════════════════════════
  static pw.Widget _buildNotifyAndShipping(
      ExportShipmentModel s, ClearingAgentModel? agent, bool isSea) {
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
                    _shippingRow(
                      'Data Logger No.:',
                      s.dataLoggerNo ?? 'TBA',
                      showBorder: false,
                    ),
                  ])
                : pw.Table(
                    border:
                        pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                    columnWidths: {0: const pw.FlexColumnWidth(283)},
                    children: [
                      pw.TableRow(children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 2.1),
                          decoration: const pw.BoxDecoration(
                            border:
                                pw.Border(bottom: pw.BorderSide(width: 0.5)),
                          ),
                          child: pw.Center(
                            child: pw.Text('AWB',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Container(
                          constraints: const pw.BoxConstraints(minHeight: 68),
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
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
          _textLine('Morgan Cargo PTY (ltd)', bold: true, fontSize: 8),
          _textLine('Warehouse, Perishable Cargo', fontSize: 8),
          _textLine('Triangle,', fontSize: 8),
          _textLine('Northern Perimeter Road,', fontSize: 8),
          _textLine('OR Tambo International Airport,', fontSize: 8),
          _textLine('Johannesburg, 1627', fontSize: 8),
          _textLine('South Africa', fontSize: 8),
        ],
      );
    }

    // Collect all non-empty lines
    final lines = <Map<String, dynamic>>[];
    lines.add({'text': agent.name, 'bold': true});
    for (final a in agent.addresses) {
      final addr = a['address_line_1']?.toString() ?? '';
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

  // ════════════════════════════════════════════════════
  // Reusable box with header (Sections 4 & 5)
  // ════════════════════════════════════════════════════
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

  // ════════════════════════════════════════════════════
  // SECTION 6 — Items Table
  // ════════════════════════════════════════════════════
  static pw.Widget _buildItemsTable(
      ExportShipmentModel s, List<Map<String, dynamic>> items, String symbol) {
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
                  item['product_name']?.toString() ?? item['name']?.toString() ?? '',
                  sub: 'Net Weight: ${item['netWt']?.toString() ?? '0'} KG',
                ),
                _tableCell(item['qty']?.toString() ?? '0'),
                _tableCell('$symbol ${item['exportPricePerCarton']?.toString() ?? item['price']?.toString() ?? '0'}'),
                _tableCell(item['netWt']?.toString() ?? '0'),
                _tableCell(item['grossWt']?.toString() ?? '0'),
                _tableCell(
                  '${symbol} ${_fmt(item['amount']?.toString() ?? '0')}',
                  bold: true,
                ),
              ])),
          if (items.isEmpty)
            pw.TableRow(children: [
              _tableCell(''),
              _tableCell('${s.cartonsCount}'),
              _tableCell(''),
              _tableCell('${s.netWeight.toInt()}'),
              _tableCell('${s.grossWeight.toInt()}'),
              _tableCell(''),
            ]),
        ],
      ),
      // Pallets row (sea only)
      if (s.transportMode == 'sea' && s.palletsCount > 0)
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
              '${s.palletsCount} Pallets',
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
            _tableCell('Total',
                bold: true,
                fontSize: 9,
                align: pw.TextAlign.left,
                paddingLeft: 6),
            _tableCellUnderline('${s.cartonsCount}', bold: true, fontSize: 9),
            _tableCell(''),
            _tableCellUnderline('${s.netWeight.toInt()}',
                bold: true, fontSize: 9),
            _tableCellUnderline('${s.grossWeight.toInt()}',
                bold: true, fontSize: 9),
            _tableCellUnderline('${symbol} ${_fmt(_tot(items))}',
                bold: true, fontSize: 10),
          ])
        ],
      ),
    ]);
  }

  static String _tot(List<Map<String, dynamic>> items) {
    double t = 0;
    for (final i in items) {
      t += double.tryParse(i['amount']?.toString() ?? '0') ?? 0;
    }
    return t.toStringAsFixed(2);
  }

  // ════════════════════════════════════════════════════
  // SECTION 7 — Terms of Sale
  // ════════════════════════════════════════════════════
  static pw.Widget _buildTermsSection(ExportShipmentModel s) {
    final tl = s.transportMode == 'sea' ? "By Sea X 1 40' Reefer" : 'By Air';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
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
        // Content box
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
      ],
    );
  }

  // ════════════════════════════════════════════════════
  // SECTION 8 — Bank Details + Stamp
  // ════════════════════════════════════════════════════
  static pw.Widget _buildBankAndStamp(ExportShipmentModel s) {
    final bank = BankDetails.forCurrency(s.currency ?? 'EUR');
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // Bank Details — left half
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
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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

    // Stamp — right side
  }

  // ════════════════════════════════════════════════════
  // SECTION 9 — Footer
  // ════════════════════════════════════════════════════
  // static pw.Widget _buildFooter() {
  //   return pw.Container(
  //     width: double.infinity,
  //     padding: const pw.EdgeInsets.only(top: 4),
  //     decoration: const pw.BoxDecoration(
  //       border: pw.Border(top: pw.BorderSide(width: 0.5)),
  //     ),
  //     child: pw.Column(
  //       crossAxisAlignment: pw.CrossAxisAlignment.start,
  //       children: [
  //         pw.Text(
  //           'Al Musheer Ismael St., Building No. 1, Sheraton Dist. Heliopolis, Cairo, Egypt.',
  //           style: const pw.TextStyle(fontSize: 7),
  //         ),
  //         pw.Text(
  //           'Email: info@fruityfarms.co | Web: fruityfarms.co',
  //           style: const pw.TextStyle(fontSize: 7),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // ════════════════════════════════════════════════════
  // Combined bottom section (7 + 8 + 9)
  // ════════════════════════════════════════════════════
  static pw.Widget _buildBottomSection(ExportShipmentModel s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildTermsSection(s),
        pw.SizedBox(height: 2),
        pw.Text(
          'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
          style: const pw.TextStyle(fontSize: 5),
        ),
        pw.SizedBox(height: 2),
        _buildBankAndStamp(s),
      ],
    );
  }

  // ════════════════════════════════════════════════════
  // PRIMITIVES
  // ════════════════════════════════════════════════════

  static pw.Widget _dateCell(String t,
          {bool bold = false, double fontSize = 8}) =>
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

  static pw.Widget _textLine(String t,
          {bool bold = false, double fontSize = 8}) =>
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

  // Table header — Bold Italic 8pt center
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

  // Table data cell — Regular 8pt, pad 5pt vertical
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

  // Table product item cell — Bold 8pt name + Regular 8pt sub
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

  // Table underlined cell — Bold 9/10pt
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

  // Terms row — Bold 7pt label + Regular 7pt underlined value
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

  // Bank detail row — 7pt
  static pw.Widget _bankLine(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(
              fontSize: 5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(
              fontSize: 5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──
  static String _currencySymbol(String? c) {
    switch (c) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      case 'EGP':
        return 'ج.م';
      default:
        return c ?? '';
    }
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
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
