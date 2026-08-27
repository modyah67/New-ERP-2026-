import 'dart:io';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/utils.dart';
import '../../data/models/shareholder_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShareholdersExportService {
  static Future<void> exportShareholdersToExcel(List<ShareholderModel> shareholders) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    sheet.appendRow([
      TextCellValue('الكود'),
      TextCellValue('اسم المساهم'),
      TextCellValue('رصيد EGP'),
      TextCellValue('رصيد USD'),
      TextCellValue('رصيد EUR'),
      TextCellValue('رصيد GBP'),
      TextCellValue('إجمالي الإيداعات EGP'),
      TextCellValue('إجمالي الإيداعات USD'),
      TextCellValue('إجمالي الإيداعات EUR'),
      TextCellValue('إجمالي الإيداعات GBP'),
      TextCellValue('إجمالي السحوبات EGP'),
      TextCellValue('إجمالي السحوبات USD'),
      TextCellValue('إجمالي السحوبات EUR'),
      TextCellValue('إجمالي السحوبات GBP'),
      TextCellValue('تاريخ الإضافة'),
    ]);

    for (final s in shareholders) {
      final balEgp = s.currentBalanceEgp;
      final balUsd = s.currentBalanceUsd;
      final balEur = s.currentBalanceEur;
      final balGbp = s.currentBalanceGbp;


      sheet.appendRow([
        TextCellValue(s.code),
        TextCellValue(s.name),
        TextCellValue(AppUtils.formatNumber(balEgp)),
        TextCellValue(AppUtils.formatNumber(balUsd)),
        TextCellValue(AppUtils.formatNumber(balEur)),
        TextCellValue(AppUtils.formatNumber(balGbp)),
        TextCellValue(AppUtils.formatNumber(s.totalDepositsEgp)),
        TextCellValue(AppUtils.formatNumber(s.totalDepositsUsd)),
        TextCellValue(AppUtils.formatNumber(s.totalDepositsEur)),
        TextCellValue(AppUtils.formatNumber(s.totalDepositsGbp)),
        TextCellValue(AppUtils.formatNumber(s.totalWithdrawalsEgp)),
        TextCellValue(AppUtils.formatNumber(s.totalWithdrawalsUsd)),
        TextCellValue(AppUtils.formatNumber(s.totalWithdrawalsEur)),
        TextCellValue(AppUtils.formatNumber(s.totalWithdrawalsGbp)),
        TextCellValue(AppUtils.formatDate(DateTime.tryParse(s.createdAt) ?? DateTime.now())),
      ]);
    }

    final directory = await FileHelper.getExportDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${directory.path}/shareholders_$timestamp.xlsx';
    
    final file = File(filePath);
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      await OpenFilex.open(filePath);
    }
  }

  static Future<void> exportShareholdersToPdf(List<ShareholderModel> shareholders) async {
    final pdf = pw.Document();
    
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final boldFont = pw.Font.ttf(boldData);
    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('كشف حساب مجمع للمساهمين', style: pw.TextStyle(fontSize: 24, font: boldFont)),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            context: context,
            cellAlignment: pw.Alignment.center,
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(font: boldFont, fontSize: 7),
            cellStyle: pw.TextStyle(font: font, fontSize: 7),
            headers: [
              'الكود',
              'اسم المساهم',
              'رصيد EGP',
              'رصيد USD',
              'رصيد EUR',
              'رصيد GBP',
              'إيداعات EGP',
              'إيداعات USD',
              'إيداعات EUR',
              'إيداعات GBP',
              'سحوبات EGP',
              'سحوبات USD',
              'سحوبات EUR',
              'سحوبات GBP',
            ],
            data: shareholders.map((s) {
              final balEgp = s.currentBalanceEgp;
              final balUsd = s.currentBalanceUsd;
              final balEur = s.currentBalanceEur;
              final balGbp = s.currentBalanceGbp;
              return [
                s.code,
                s.name,
                AppUtils.formatNumber(balEgp),
                AppUtils.formatNumber(balUsd),
                AppUtils.formatNumber(balEur),
                AppUtils.formatNumber(balGbp),
                AppUtils.formatNumber(s.totalDepositsEgp),
                AppUtils.formatNumber(s.totalDepositsUsd),
                AppUtils.formatNumber(s.totalDepositsEur),
                AppUtils.formatNumber(s.totalDepositsGbp),
                AppUtils.formatNumber(s.totalWithdrawalsEgp),
                AppUtils.formatNumber(s.totalWithdrawalsUsd),
                AppUtils.formatNumber(s.totalWithdrawalsEur),
                AppUtils.formatNumber(s.totalWithdrawalsGbp),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final directory = await FileHelper.getExportDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${directory.path}/shareholders_$timestamp.pdf';
    
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(filePath);
  }
}
