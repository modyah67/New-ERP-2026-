import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
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
    bool isCustody = false,
    double? currentBalance,
  }) async {
    await _loadFonts();
    final pdf = pw.Document();
    final bgImage = await _getBgImage();

    final isCustodyReport = isCustody || treasuryName.contains('عهدة');
    final reportTitle = isCustodyReport
        ? 'تقرير حركات العهدة - $treasuryName'
        : 'تقرير حركات الخزينة - $treasuryName';

    final dateLabel = fromDate != null && toDate != null
        ? 'من تاريخ ${DateFormat('yyyy-MM-dd').format(fromDate)} إلى تاريخ ${DateFormat('yyyy-MM-dd').format(toDate)}'
        : fromDate != null
            ? 'من تاريخ ${DateFormat('yyyy-MM-dd').format(fromDate)}'
            : toDate != null
                ? 'إلى تاريخ ${DateFormat('yyyy-MM-dd').format(toDate)}'
                : 'كافة الحركات المسجلة';

    double totalInflows = 0.0;
    double totalOutflows = 0.0;
    for (final t in transactions) {
      if (t.isIncoming || (t.amount > 0 && !t.isOutgoing)) {
        totalInflows += t.amount.abs();
      } else {
        totalOutflows += t.amount.abs();
      }
    }
    final netMovement = totalInflows - totalOutflows;
    final endingBalance = currentBalance ??
        (transactions.isNotEmpty ? transactions.first.balanceAfter : 0.0);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
          pageFormat: PdfPageFormat.a4.landscape,
          orientation: pw.PageOrientation.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Fruity Farms - شركة فروتي فارمز',
                          style: pw.TextStyle(
                              font: _boldFont,
                              fontSize: 16,
                              color: PdfColors.blue900)),
                      pw.Text('نظام Nova Soft ERP لإدارة الموارد المحاسبية',
                          style: pw.TextStyle(
                              font: _regularFont,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: isCustodyReport
                          ? PdfColors.amber50
                          : PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                        color: isCustodyReport
                            ? PdfColors.amber800
                            : PdfColors.blue800,
                        width: 1.2,
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(reportTitle,
                            style: pw.TextStyle(
                                font: _boldFont,
                                fontSize: 13,
                                color: isCustodyReport
                                    ? PdfColors.amber900
                                    : PdfColors.blue900)),
                        pw.SizedBox(height: 2),
                        pw.Text(dateLabel,
                            style: pw.TextStyle(
                                font: _regularFont,
                                fontSize: 9,
                                color: PdfColors.grey800)),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          'تاريخ الطباعة: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                          style: pw.TextStyle(
                              font: _regularFont,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                      pw.Text('العملة: $currency',
                          style: pw.TextStyle(
                              font: _boldFont,
                              fontSize: 10,
                              color: PdfColors.black)),
                      pw.Text('عدد الحركات: ${transactions.length}',
                          style: pw.TextStyle(
                              font: _boldFont,
                              fontSize: 9,
                              color: PdfColors.blueGrey800)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey400, thickness: 0.8),
              pw.SizedBox(height: 6),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('نظام Nova Soft ERP • مزارع فروتي للتصدير والاستيراد',
                      style: pw.TextStyle(
                          font: _regularFont,
                          fontSize: 8,
                          color: PdfColors.grey600)),
                  pw.Text('صفحة ${context.pageNumber} من ${context.pagesCount}',
                      style: pw.TextStyle(
                          font: _regularFont,
                          fontSize: 8,
                          color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) => [
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: _boldFont, fontSize: 9, color: PdfColors.white),
            cellStyle: pw.TextStyle(font: _regularFont, fontSize: 8),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellHeight: 22,
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.center,
              7: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(30), // #
              1: const pw.FixedColumnWidth(100), // التاريخ والوقت
              2: const pw.FixedColumnWidth(90), // رقم القيد / الحركة
              3: const pw.FixedColumnWidth(85), // نوع الحركة
              4: const pw.FlexColumnWidth(2.8), // البيان والتفاصيل
              5: const pw.FlexColumnWidth(2.0), // المورد / العميل / الجهة
              6: const pw.FixedColumnWidth(95), // المبلغ
              7: const pw.FixedColumnWidth(95), // الرصيد بعد الحركة
            },
            headers: [
              '#',
              'التاريخ والوقت',
              'رقم القيد / الحركة',
              'نوع الحركة',
              'البيان والتفاصيل',
              'المورد / العميل / الجهة',
              'المبلغ',
              'الرصيد بعد الحركة',
            ],
            data: [
              for (int i = 0; i < transactions.length; i++)
                _buildTableRow(i + 1, transactions[i], currency),
            ],
          ),
          pw.SizedBox(height: 12),

          // ── بطاقات الإجماليات وملخص الحركات ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: _buildSummaryBox(
                    title: 'إجمالي الوارد / الإيداعات',
                    value: '+${AppUtils.formatNumber(totalInflows)} $currency',
                    color: PdfColors.green900,
                    bgColor: PdfColors.green50,
                    borderColor: PdfColors.green700,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryBox(
                    title: 'إجمالي الصرف / المدفوعات',
                    value: '-${AppUtils.formatNumber(totalOutflows)} $currency',
                    color: PdfColors.red900,
                    bgColor: PdfColors.red50,
                    borderColor: PdfColors.red700,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryBox(
                    title: 'صافي حركة الفترة',
                    value:
                        '${netMovement >= 0 ? '+' : ''}${AppUtils.formatNumber(netMovement)} $currency',
                    color: netMovement >= 0
                        ? PdfColors.blue900
                        : PdfColors.red900,
                    bgColor: netMovement >= 0
                        ? PdfColors.blue50
                        : PdfColors.red50,
                    borderColor: netMovement >= 0
                        ? PdfColors.blue700
                        : PdfColors.red700,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryBox(
                    title: isCustodyReport
                        ? 'رصيد العهدة الختامي'
                        : 'رصيد الخزينة الختامي',
                    value: '${AppUtils.formatNumber(endingBalance)} $currency',
                    color: PdfColors.indigo900,
                    bgColor: PdfColors.indigo50,
                    borderColor: PdfColors.indigo700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),

          // ── التوقيعات الرسمية ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _reportSignatureBox(
                  isCustodyReport ? 'أمين العهدة / الموظف' : 'أمين الخزينة'),
              _reportSignatureBox('مراجع الحسابات'),
              _reportSignatureBox('اعتماد الإدارة المالية'),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: '${reportTitle.replaceAll(' ', '_')}.pdf',
      format: PdfPageFormat.a4.landscape,
    );
    return bytes;
  }

  static pw.Widget _reportSignatureBox(String role) {
    return pw.Container(
      width: 180,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
        color: PdfColors.white,
      ),
      child: pw.Column(
        children: [
          pw.Text(role,
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 9, color: PdfColors.grey800)),
          pw.SizedBox(height: 24),
          pw.Container(height: 0.5, color: PdfColors.grey300),
          pw.SizedBox(height: 3),
          pw.Text('التوقيع / الختم',
              style: pw.TextStyle(
                  font: _regularFont, fontSize: 7.5, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  static List<String> _buildTableRow(
      int index, TreasuryTransactionModel t, String currency) {
    String party = '';
    if (t.supplierName != null && t.supplierName!.isNotEmpty) {
      party = 'مورد: ${t.supplierName}';
    } else if (t.customerName != null && t.customerName!.isNotEmpty) {
      party = 'عميل: ${t.customerName}';
    } else if (t.shippingCompanyName != null &&
        t.shippingCompanyName!.isNotEmpty) {
      party = 'شحن: ${t.shippingCompanyName}';
    } else if (t.clearingAgentName != null &&
        t.clearingAgentName!.isNotEmpty) {
      party = 'مخلص: ${t.clearingAgentName}';
    } else if (t.shareholderName != null &&
        t.shareholderName!.isNotEmpty) {
      party = 'مساهم: ${t.shareholderName}';
    } else if (t.relatedTreasuryName != null &&
        t.relatedTreasuryName!.isNotEmpty) {
      party = t.relatedTreasuryName!;
    } else if (t.categoryName != null && t.categoryName!.isNotEmpty) {
      party = t.categoryName!;
    } else {
      party = '—';
    }

    final isIncoming = t.isIncoming || (t.amount > 0 && !t.isOutgoing);
    final sign = isIncoming ? '+' : '-';
    final formattedAmount = '$sign${AppUtils.formatNumber(t.amount.abs())}';
    final formattedBalance = AppUtils.formatNumber(t.balanceAfter);

    final dateStr =
        AppUtils.formatDate(DateTime.tryParse(t.createdAt) ?? DateTime.now());
    final ref = t.entryNumber ??
        (t.journalEntryId != null ? 'قيد #${t.journalEntryId}' : '#${t.id}');

    return [
      index.toString(),
      dateStr,
      ref,
      t.typeLabel,
      t.description ?? t.notes ?? '—',
      party,
      formattedAmount,
      formattedBalance,
    ];
  }

  static pw.Widget _buildSummaryBox({
    required String title,
    required String value,
    required PdfColor color,
    required PdfColor bgColor,
    required PdfColor borderColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  font: _regularFont, fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 10, color: color)),
        ],
      ),
    );
  }

  static Future<Uint8List> saveToFile({
    required String treasuryName,
    required String currency,
    required List<TreasuryTransactionModel> transactions,
    DateTime? fromDate,
    DateTime? toDate,
    bool isCustody = false,
    double? currentBalance,
  }) async {
    return await generatePdf(
      treasuryName: treasuryName,
      currency: currency,
      transactions: transactions,
      fromDate: fromDate,
      toDate: toDate,
      isCustody: isCustody,
      currentBalance: currentBalance,
    );
  }
}
