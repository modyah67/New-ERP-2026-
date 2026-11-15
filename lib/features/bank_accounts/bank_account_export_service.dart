import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;
import '../../core/utils.dart';
import '../../data/models/bank_account_model.dart';
import '../../data/models/bank_account_transaction_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class BankAccountExportService {
  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null && _cairoBold != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _cairoRegular = pw.Font.ttf(r);
      _cairoBold = pw.Font.ttf(b);
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
    try {
      final bgData = await rootBundle.load('assets/images/statment.png');
      _bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
      return _bgImage!;
    } catch (_) {
      final dummy = Uint8List(0);
      return pw.MemoryImage(dummy);
    }
  }

  static Future<Uint8List> exportPdf({
    required BankAccountModel account,
    required List<BankAccountTransactionModel> transactions,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _regularFont, bold: _boldFont);

    final deposits = transactions.where((t) => t.isDeposit).toList();
    final withdrawals = transactions.where((t) => !t.isDeposit).toList();
    final totalDeposits =
        deposits.fold<double>(0, (s, t) => s + t.amount.abs());
    final totalWithdrawals =
        withdrawals.fold<double>(0, (s, t) => s + t.amount.abs());
    final netMovement = totalDeposits - totalWithdrawals;

    final dateLabel = startDate != null && endDate != null
        ? 'من تاريخ ${DateFormat('yyyy-MM-dd').format(startDate)} إلى تاريخ ${DateFormat('yyyy-MM-dd').format(endDate)}'
        : startDate != null
            ? 'من تاريخ ${DateFormat('yyyy-MM-dd').format(startDate)}'
            : endDate != null
                ? 'إلى تاريخ ${DateFormat('yyyy-MM-dd').format(endDate)}'
                : 'كافة الحركات المسجلة';

    final bgImage = await _getBgImage();
    final reportTitle = 'تقرير حركات الحساب البنكي - ${account.name}';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
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
                      color: PdfColors.teal50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                        color: PdfColors.teal800,
                        width: 1.2,
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(reportTitle,
                            style: pw.TextStyle(
                                font: _boldFont,
                                fontSize: 13,
                                color: PdfColors.teal900)),
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
                      pw.Text('العملة: ${account.currency}',
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
          // Transactions table
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
              2: const pw.FixedColumnWidth(90), // رقم القيد / المرجع
              3: const pw.FixedColumnWidth(85), // نوع الحركة
              4: const pw.FlexColumnWidth(2.8), // البيان والتفاصيل
              5: const pw.FlexColumnWidth(2.0), // المورد / العميل / الجهة
              6: const pw.FixedColumnWidth(95), // المبلغ
              7: const pw.FixedColumnWidth(95), // الرصيد بعد الحركة
            },
            headers: [
              '#',
              'التاريخ والوقت',
              'رقم القيد / المرجع',
              'نوع الحركة',
              'البيان والتفاصيل',
              'المورد / العميل / الجهة',
              'المبلغ',
              'الرصيد بعد الحركة',
            ],
            data: [
              for (int i = 0; i < transactions.length; i++)
                _txRow(i + 1, transactions[i]),
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
                    value:
                        '+${AppUtils.formatNumber(totalDeposits)} ${account.currency}',
                    color: PdfColors.green900,
                    bgColor: PdfColors.green50,
                    borderColor: PdfColors.green700,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryBox(
                    title: 'إجمالي الصرف / المدفوعات',
                    value:
                        '-${AppUtils.formatNumber(totalWithdrawals)} ${account.currency}',
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
                        '${netMovement >= 0 ? '+' : ''}${AppUtils.formatNumber(netMovement)} ${account.currency}',
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
                    title: 'الرصيد الدفتري الحالي',
                    value:
                        '${AppUtils.formatNumber(account.balance)} ${account.currency}',
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
              _signatureBox('المسؤول المالي'),
              _signatureBox('مراجع الحسابات'),
              _signatureBox('اعتماد الإدارة المالية'),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    try {
      final dir = await FileHelper.getExportDirectory();
      final safeName = account.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName =
          'bank_${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
    } catch (_) {}

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: '${reportTitle.replaceAll(' ', '_')}.pdf',
      format: PdfPageFormat.a4.landscape,
    );

    return bytes;
  }

  static List<String> _txRow(int index, BankAccountTransactionModel tx) {
    final isDeposit = tx.isDeposit;
    final date = DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt);
    final partyName = tx.relatedPartyName ?? tx.createdByName ?? '—';
    final ref = tx.referenceNumber ??
        (tx.journalEntryId != null ? 'قيد #${tx.journalEntryId}' : '#${tx.id}');
    final typeLabel = isDeposit ? 'إيداع / وارد' : 'صرف / مسحوبات';
    final sign = isDeposit ? '+' : '-';
    final formattedAmount = '$sign${AppUtils.formatNumber(tx.amount.abs())}';
    final formattedBalance = AppUtils.formatNumber(tx.balanceAfter);

    return [
      index.toString(),
      date,
      ref,
      typeLabel,
      tx.description ?? tx.notes ?? '—',
      partyName,
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
              style: pw.TextStyle(font: _boldFont, fontSize: 10, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(String role) {
    return pw.Container(
      width: 140,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(role,
              style: pw.TextStyle(
                  font: _boldFont, fontSize: 8, color: PdfColors.grey800)),
          pw.SizedBox(height: 22),
          pw.Container(height: 0.5, color: PdfColors.grey300),
          pw.SizedBox(height: 2),
          pw.Text('التوقيع / الختم',
              style: pw.TextStyle(
                  font: _regularFont, fontSize: 7, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  static Future<void> exportExcel({
    required BankAccountModel account,
    required List<BankAccountTransactionModel> transactions,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['الحركات'];
    final headers = ['#', 'التاريخ', 'النوع', 'المبلغ', 'بواسطة', 'المورد/العميل', 'الوصف'];

    // Title rows
    final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('كشف حساب بنكي - ${account.name}');
    titleCell.cellStyle = CellStyle(bold: true);

    final currencyCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
    currencyCell.value = TextCellValue('العملة: ${account.currency} | الرصيد الحالي: ${AppUtils.formatNumber(account.balance)}');

    final dateLabel = startDate != null && endDate != null
        ? 'من ${DateFormat('yyyy-MM-dd').format(startDate)} إلى ${DateFormat('yyyy-MM-dd').format(endDate)}'
        : 'جميع التواريخ';
    final dateCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2));
    dateCell.value = TextCellValue('الفترة: $dateLabel | تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');

    // Header row
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 4));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
    }

    // Data rows
    for (var i = 0; i < transactions.length; i++) {
      final tx = transactions[i];
      final isDeposit = tx.isDeposit;
      final r = i + 5;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue('${i + 1}');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(DateFormat('yyyy-MM-dd').format(tx.createdAt));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(isDeposit ? 'إيداع' : 'صرف');
      final amtCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r));
      amtCell.value = DoubleCellValue(isDeposit ? tx.amount.abs() : -tx.amount.abs());
      amtCell.cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString(isDeposit ? '#FF2E7D32' : '#FFC62828'));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = TextCellValue(tx.createdByName ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = TextCellValue(tx.relatedPartyName ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = TextCellValue(tx.description ?? '—');
    }

    // Summary row
    final sumRow = transactions.length + 6;
    final deposits = transactions.where((t) => t.isDeposit).fold<double>(0, (s, t) => s + t.amount.abs());
    final withdrawals = transactions.where((t) => !t.isDeposit).fold<double>(0, (s, t) => s + t.amount.abs());
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sumRow)).value = TextCellValue('الإجمالي');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: sumRow)).value = TextCellValue('إيداعات');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: sumRow)).value = DoubleCellValue(deposits);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: sumRow)).value = TextCellValue('صرف');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: sumRow)).value = DoubleCellValue(withdrawals);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: sumRow)).value = TextCellValue('الرصيد النهائي: ${AppUtils.formatNumber(account.balance)} ${account.currency}');

    // Auto-width
    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length.toDouble();
      for (var row = 0; row < transactions.length + 6 && row < 200; row++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value;
        if (val != null && val.toString().length > maxLen) {
          maxLen = val.toString().length.toDouble();
        }
      }
      sheet.setColumnWidth(c, maxLen + 4);
    }

    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir == null) return;

    final fileName = 'bank_${account.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = p.join(selectedDir, fileName);
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);
  }
}
