import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/treasury_model.dart';
import '../../data/models/unified_transaction_model.dart';

class TreasuryPdfService {
  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null && _cairoBold != null) return;
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _cairoRegular = pw.Font.ttf(regData);
      _cairoBold = pw.Font.ttf(boldData);
    } catch (_) {
      _cairoRegular = pw.Font.courier();
      _cairoBold = pw.Font.courierBold();
    }
  }

  static pw.Font get _regularFont => _cairoRegular ?? pw.Font.courier();
  static pw.Font get _boldFont => _cairoBold ?? pw.Font.courierBold();

  static pw.MemoryImage? _bgImage;

  static Future<pw.MemoryImage> _getBgImage() async {
    if (_bgImage != null) return _bgImage!;
    final bgData = await rootBundle.load('assets/images/statment.png');
    _bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    return _bgImage!;
  }

  static Future<Uint8List> buildVoucherBytes(UnifiedTransactionModel tx) async {
    await _loadFonts();
    final pdf = pw.Document();
    final bgImage = await _getBgImage();

    final isIncoming = tx.isIncoming;
    final voucherTitle = isIncoming
        ? (tx.transactionType == 'deposit' ? 'سند إيداع نقدية' : 'سند قبض مالي')
        : 'سند صرف مالي';

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header Block
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Fruity Farms',
                            style: pw.TextStyle(
                                font: _boldFont,
                                fontSize: 20,
                                color: PdfColors.blue900)),
                        pw.Text('شركة فروتي فارمز للتصدير والاستيراد',
                            style: pw.TextStyle(
                                font: _regularFont,
                                fontSize: 10,
                                color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: isIncoming ? PdfColors.green50 : PdfColors.red50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                            color: isIncoming ? PdfColors.green700 : PdfColors.red700),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(voucherTitle,
                              style: pw.TextStyle(
                                  font: _boldFont,
                                  fontSize: 14,
                                  color: isIncoming ? PdfColors.green900 : PdfColors.red900)),
                          pw.SizedBox(height: 2),
                          pw.Text('رقم القيد المحاسبي: ${tx.entryNumber}',
                              style: pw.TextStyle(
                                  font: _boldFont,
                                  fontSize: 11,
                                  color: PdfColors.black)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 16),

                // Transaction Details Table
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(8),
                    color: PdfColors.grey50,
                  ),
                  child: pw.Column(
                    children: [
                      _voucherRow('التاريخ والوقت', AppUtils.formatDate(DateTime.tryParse(tx.createdAt) ?? DateTime.now())),
                      _voucherRow('نوع الحركة', tx.typeLabel),
                      _voucherRow('المصدر / الحساب', tx.accountSourceName),
                      if (tx.categoryName != null && tx.categoryName!.isNotEmpty)
                        _voucherRow('التصنيف المالي', tx.categoryName!),
                      if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty)
                        _voucherRow('رقم المرجع / الشيك', tx.referenceNumber!),
                      _voucherRow('المبلغ المالي', '${tx.currency} ${tx.amount.toStringAsFixed(2)}', isBold: true, valueColor: isIncoming ? PdfColors.green800 : PdfColors.red800),
                      if (tx.description.isNotEmpty)
                        _voucherRow('البيان والتفاصيل', tx.description),
                      if (tx.creatorName != null && tx.creatorName!.isNotEmpty)
                        _voucherRow('المستخدم المنشئ', tx.creatorName!),
                      _voucherRow('حالة الحركة', isIncoming ? 'وارد / معتمد' : 'صادر / معتمد'),
                    ],
                  ),
                ),
                pw.Spacer(),

                // Official Signature Block
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _signatureBox('المستلم / المنفذ'),
                    _signatureBox('أمين الخزينة / المحاسب'),
                    _signatureBox('اعتماد المدير المالي'),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text('نظام إدارة الموارد - Fruity Farms ERP',
                      style: pw.TextStyle(font: _regularFont, fontSize: 9, color: PdfColors.grey600)),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printVoucher(dynamic txInput) async {
    final tx = txInput is TreasuryTransactionModel 
        ? UnifiedTransactionModel.fromTreasuryTx(txInput)
        : (txInput as UnifiedTransactionModel);

    final pdfBytes = await buildVoucherBytes(tx);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Voucher_${tx.entryNumber}',
    );
  }

  static pw.Widget _voucherRow(String title, String value, {bool isBold = false, PdfColor? valueColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(title, style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.grey800)),
          ),
          pw.Text(':', style: pw.TextStyle(font: _boldFont, fontSize: 10)),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: isBold ? _boldFont : _regularFont,
                fontSize: 10,
                color: valueColor ?? PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(String title) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(font: _boldFont, fontSize: 10)),
        pw.SizedBox(height: 30),
        pw.Container(width: 100, height: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        pw.Text('التوقيع: .....................', style: pw.TextStyle(font: _regularFont, fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }

  static Future<Uint8List> generatePdf({
    required String treasuryName,
    required String currency,
    required List<TreasuryTransactionModel> transactions,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    await _loadFonts();
    final pdf = pw.Document();
    final bgImage = await _getBgImage();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('كشف حركات الخزينة - $treasuryName',
                    style: pw.TextStyle(font: _boldFont, fontSize: 16)),
                pw.Text('العملة: $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['رقم الحركة / القيد', 'التاريخ', 'النوع', 'البيان', 'المورد/العميل', 'المبلغ'],
            data: transactions.map((t) {
              String party = '';
              if (t.supplierName != null && t.supplierName!.isNotEmpty) {
                party = t.supplierName!;
              } else if (t.customerName != null && t.customerName!.isNotEmpty) {
                party = t.customerName!;
              }
              return [
                t.entryNumber ?? '#${t.id}',
                AppUtils.formatDate(DateTime.tryParse(t.createdAt) ?? DateTime.now()),
                t.typeLabel,
                t.description ?? '',
                party,
                '${t.currency} ${t.amount.toStringAsFixed(2)}',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(font: _boldFont, fontSize: 10),
            cellStyle: pw.TextStyle(font: _regularFont, fontSize: 9),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Treasury_Report_$treasuryName.pdf');
    return bytes;
  }

  static Future<Uint8List> saveToFile({
    required String treasuryName,
    required String currency,
    required List<TreasuryTransactionModel> transactions,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    return await generatePdf(
      treasuryName: treasuryName,
      currency: currency,
      transactions: transactions,
      fromDate: fromDate,
      toDate: toDate,
    );
  }
}
