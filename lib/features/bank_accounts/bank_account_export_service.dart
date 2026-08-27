import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/models/bank_account_model.dart';
import '../../data/models/bank_account_transaction_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class BankAccountExportService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static Future<void> exportPdf({
    required BankAccountModel account,
    required List<BankAccountTransactionModel> transactions,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);

    final deposits = transactions.where((t) => t.isDeposit).toList();
    final withdrawals = transactions.where((t) => !t.isDeposit).toList();
    final totalDeposits = deposits.fold<double>(0, (s, t) => s + t.amount.abs());
    final totalWithdrawals = withdrawals.fold<double>(0, (s, t) => s + t.amount.abs());

    final dateLabel = startDate != null && endDate != null
        ? 'من ${DateFormat('yyyy-MM-dd').format(startDate)} إلى ${DateFormat('yyyy-MM-dd').format(endDate)}'
        : startDate != null
            ? 'من ${DateFormat('yyyy-MM-dd').format(startDate)}'
            : endDate != null
                ? 'إلى ${DateFormat('yyyy-MM-dd').format(endDate)}'
                : 'جميع التواريخ';

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          // Header
          pw.Text(AppConstants.companyName,
              style: pw.TextStyle(font: _boldFont, fontSize: 18, color: PdfColors.blueGrey)),
          pw.Text('كشف حساب بنكي - ${account.name}',
              style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
          pw.Text('العملة: ${account.currency} | الرصيد الحالي: ${AppUtils.formatNumber(account.balance)} ${account.currency}',
              style: pw.TextStyle(font: _font, fontSize: 11, color: PdfColors.blue800)),
          pw.Text('الفترة: $dateLabel | تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          pw.Text('إجمالي الإيداعات: ${AppUtils.formatNumber(totalDeposits)} | إجمالي الصرف: ${AppUtils.formatNumber(totalWithdrawals)} | عدد الحركات: ${transactions.length}',
              style: pw.TextStyle(font: _font, fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // Transactions table
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(font: _boldFont, fontSize: 9, color: PdfColors.white),
            cellStyle: pw.TextStyle(font: _font, fontSize: 8, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellHeight: 22,
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
            },
            headers: ['#', 'التاريخ', 'النوع', 'المبلغ', 'بواسطة', 'المورد/العميل', 'الوصف'],
            data: [
              for (int i = 0; i < transactions.length; i++)
                _txRow(i + 1, transactions[i]),
            ],
          ),

          // Summary
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('الإجمالي: ', style: pw.TextStyle(font: _boldFont, fontSize: 11)),
              pw.Text('إيداعات: ${AppUtils.formatNumber(totalDeposits)}', style: pw.TextStyle(font: _font, fontSize: 11, color: PdfColors.green700)),
              pw.SizedBox(width: 12),
              pw.Text('صرف: ${AppUtils.formatNumber(totalWithdrawals)}', style: pw.TextStyle(font: _font, fontSize: 11, color: PdfColors.red700)),
              pw.SizedBox(width: 12),
              pw.Text('الرصيد النهائي: ${AppUtils.formatNumber(account.balance)} ${account.currency}', style: pw.TextStyle(font: _boldFont, fontSize: 11, color: PdfColors.blue800)),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'bank_${account.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static List<String> _txRow(int index, BankAccountTransactionModel tx) {
    final isDeposit = tx.isDeposit;
    final date = DateFormat('yyyy-MM-dd').format(tx.createdAt);
    final partyName = tx.relatedPartyName ?? '—';
    return [
      index.toString(),
      date,
      isDeposit ? 'إيداع' : 'صرف',
      '${isDeposit ? '+' : '-'}${AppUtils.formatNumber(tx.amount.abs())}',
      tx.createdByName ?? '—',
      partyName,
      tx.description ?? '—',
    ];
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
