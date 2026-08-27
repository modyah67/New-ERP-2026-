import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ExportCustomerStatementPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static String _accountLabel(String type, String description) {
    final desc = description;
    if (desc.contains('شيك')) return 'BANK TRANSFER';
    if (desc.contains('تحويل بنكي')) return 'BANK TRANSFER';
    if (desc.contains('استلام') || desc.contains('صرف') || desc.contains('دفع')) return 'CASH PAYMENT';
    switch (type) {
      case 'opening': return 'Opening Balance';
      case 'shipment': return 'Export Shipment';
      case 'payment': return 'CASH PAYMENT';
      case 'cheque': return 'BANK TRANSFER';
      default: return type;
    }
  }

  static String _translateDescription(String desc) {
    // Purchases
    if (desc.startsWith('مشتريات رقم')) return desc.replaceFirst('مشتريات رقم', 'Purchase No.');
    if (desc.startsWith('دفعة نقدية لمشتريات رقم')) return desc.replaceFirst('دفعة نقدية لمشتريات رقم', 'Cash Payment for Purchase No.');
    if (desc == 'مشتريات') return 'Purchase';
    if (desc.startsWith('مشتريات')) return desc.replaceFirst('مشتريات', 'Purchase');
    // Receipts from customer
    if (desc.startsWith('إيصال استلام من عميل')) return desc.replaceFirst('إيصال استلام من عميل', 'Receipt from Customer');
    if (desc.startsWith('إيصال صرف لعميل')) return desc.replaceFirst('إيصال صرف لعميل', 'Payment to Customer');
    // Bank transfers
    if (desc.contains('تحويل بنكي من')) return desc.replaceAll('تحويل بنكي من', 'Bank Transfer From');
    if (desc.contains('تحويل بنكي إلى')) return desc.replaceAll('تحويل بنكي إلى', 'Bank Transfer To');
    if (desc.contains('تحويل بنكي الى')) return desc.replaceAll('تحويل بنكي الى', 'Bank Transfer To');
    if (desc.contains('تحويل بنكي')) return desc.replaceAll('تحويل بنكي', 'Bank Transfer');
    // Cheques
    if (desc.contains('شيك وارد رقم')) return desc.replaceAll('شيك وارد رقم', 'Cheque Received No.');
    if (desc.contains('شيك صادر رقم')) return desc.replaceAll('شيك صادر رقم', 'Cheque Issued No.');
    if (desc.contains('شيك وارد')) return desc.replaceAll('شيك وارد', 'Cheque Received');
    if (desc.contains('شيك صادر')) return desc.replaceAll('شيك صادر', 'Cheque Issued');
    if (desc.contains('تحصيل شيك من')) return desc.replaceAll('تحصيل شيك من', 'Collect Cheque From');
    if (desc.contains('تحصيل شيك')) return desc.replaceAll('تحصيل شيك', 'Collect Cheque');
    if (desc.contains('دفع شيك')) return desc.replaceAll('دفع شيك', 'Pay Cheque');
    if (desc.contains('شيك رقم')) return desc.replaceAll('شيك رقم', 'Cheque No.');
    // Cash with direction
    if (desc.contains('دفعه لـ') || desc.contains('دفع لـ') || desc.contains('دفع الى') || desc.contains('دفع إلى')) {
      return _stripArabic(desc.replaceAll(RegExp(r'دفع[ه]*\s*(لـ|الى|إلى)'), 'Cash Payment To'));
    }
    if (desc.contains('دفع')) return _stripArabic(desc.replaceAll(RegExp(r'دفع[ه]*'), 'Cash Payment'));
    if (desc.contains('استلام من')) return _stripArabic(desc.replaceAll(RegExp(r'استلام\s*من'), 'Cash Payment From'));
    if (desc.contains('استلام نقدي')) return _stripArabic(desc.replaceAll(RegExp(r'استلام\s*نقدي'), 'Cash Payment'));
    if (desc.contains('استلام')) return _stripArabic(desc.replaceAll('استلام', 'Cash Payment'));
    if (desc.contains('صرف من')) return _stripArabic(desc.replaceAll(RegExp(r'صرف\s*من'), 'Cash Payment From'));
    if (desc.contains('صرف الى') || desc.contains('صرف إلى')) return _stripArabic(desc.replaceAll(RegExp(r'صرف\s*(الى|إلى)'), 'Cash Payment To'));
    if (desc.contains('صرف')) return _stripArabic(desc.replaceAll('صرف', 'Cash Payment'));
    // Other
    if (desc == 'سند قبض شيك') return 'Payment Received (Cheque)';
    if (desc == 'سند قبض') return 'Payment Received';
    if (desc == 'رصيد افتتاحي') return 'Opening Balance';
    if (desc.contains('رصيد سابق')) return desc.replaceAll('رصيد سابق', 'Opening Balance');
    return desc;
  }

  static String _stripArabic(String s) {
    return s.replaceAll(RegExp(r'[\u0600-\u06FF\u0750-\u077F]+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isObNoteNegative(String note) {
    final eqIdx = note.indexOf('=');
    if (eqIdx < 0) return false;
    final afterEq = note.substring(eqIdx + 1).trim();
    return afterEq.startsWith('-') || afterEq.startsWith('−');
  }

  static pw.Widget _buildObNoteText(String note) {
    final isNeg = _isObNoteNegative(note);
    final textColor = isNeg ? PdfColors.red800 : PdfColors.blue800;
    final eqIdx = note.indexOf('=');
    if (eqIdx < 0 || !isNeg) {
      return pw.Text(note, style: pw.TextStyle(font: _boldFont!, fontSize: 9, color: textColor));
    }
    final prefix = note.substring(0, eqIdx + 1).trim();
    final amount = note.substring(eqIdx + 1).trim();
    return pw.RichText(
      text: pw.TextSpan(children: [
        pw.TextSpan(text: '$prefix ', style: pw.TextStyle(font: _boldFont!, fontSize: 9, color: textColor)),
        pw.TextSpan(text: amount, style: pw.TextStyle(font: _boldFont!, fontSize: 14, color: textColor)),
      ]),
    );
  }

  static Future<Uint8List> build({
    required CustomerModel customer,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    Map<String, String>? notes,
    String? openingBalanceNote,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);
    final currency = customer.currency.isNotEmpty ? customer.currency : 'EGP';

    String? translatedObNote = openingBalanceNote;
    if (openingBalanceNote != null && openingBalanceNote.contains('ملحوظة: الرصيد السابق')) {
      final amount = openingBalanceNote.replaceAll(RegExp(r'^ملحوظة:\s*الرصيد السابق\s*=\s*'), '');
      translatedObNote = 'Note: Previous Balance = $amount';
    }

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.portrait,
          textDirection: pw.TextDirection.ltr,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.SizedBox(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Customer: ${customer.name}',
                        style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
                    pw.Text('Code: ${customer.code}',
                        style: pw.TextStyle(font: _font, fontSize: 12, color: PdfColors.grey700)),
                    pw.Text('Currency: $currency',
                        style: pw.TextStyle(font: _font, fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Text(
              'Period: ${_fmtDate(fromDate)} - ${_fmtDate(toDate)}',
              style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 8),
          if (translatedObNote != null && translatedObNote.isNotEmpty)
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _isObNoteNegative(translatedObNote) ? PdfColors.red50 : PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: _isObNoteNegative(translatedObNote) ? PdfColors.red200 : PdfColors.blue200),
                ),
                child: _buildObNoteText(translatedObNote),
              ),
            ),
          if (translatedObNote != null && translatedObNote.isNotEmpty) pw.SizedBox(height: 8),
          _buildTable(rows, currency, notes),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Debit: ${totalDebit.toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.red)),
                pw.Text('Total Credit: ${totalCredit.toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.green)),
                pw.Text('Final Balance: ${finalBalance.abs().toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 11, color: PdfColors.black)),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _buildTable(
    List<StatementRow> rows,
    String currency,
    Map<String, String>? notes,
  ) {
    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle: pw.TextStyle(font: _boldFont!, fontSize: 8, color: PdfColors.white),
      cellStyle: pw.TextStyle(font: _font!, fontSize: 7, color: PdfColors.black),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellDecoration: (row, col, isHeader) => pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
      columnWidths: {
        0: pw.FlexColumnWidth(55),
        1: pw.FlexColumnWidth(60),
        2: pw.FlexColumnWidth(85),
        3: pw.FlexColumnWidth(100),
        4: pw.FlexColumnWidth(55),
        5: pw.FlexColumnWidth(60),
        6: pw.FlexColumnWidth(60),
        7: pw.FlexColumnWidth(65),
        8: pw.FlexColumnWidth(85),
      },
      headers: [
        'Ref No.',
        'Date',
        'Type',
        'Description',
        'Cartons',
        'Debit',
        'Credit',
        'Balance',
        'Note',
      ],
      data: List.generate(rows.length, (i) {
        final r = rows[i];
        final note = (notes != null && notes.containsKey(r.transactionNumber)) ? notes[r.transactionNumber]! : '';
        return [
          r.transactionNumber.replaceAll(RegExp(r'[\u202A-\u202C\u200E\u200F]'), ''),
          r.date,
          _accountLabel(r.type, r.description),
          _translateDescription(r.description),
          r.piecesCount > 0 ? r.piecesCount.toStringAsFixed(0) : '',
          r.debit > 0 ? '${r.debit.toStringAsFixed(2)} $currency' : '',
          r.credit > 0 ? '${r.credit.toStringAsFixed(2)} $currency' : '',
          '${r.balance.toStringAsFixed(2)} $currency',
          note,
        ];
      }),
    );
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static Future<void> print({
    required CustomerModel customer,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    Map<String, String>? notes,
    String? openingBalanceNote,
  }) async {
    final bytes = await build(
      customer: customer,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      notes: notes,
      openingBalanceNote: openingBalanceNote,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'Customer_Statement_${customer.name}',
    );
  }

  static Future<String> saveToFile({
    required CustomerModel customer,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    Map<String, String>? notes,
    String? openingBalanceNote,
  }) async {
    final bytes = await build(
      customer: customer,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      finalBalance: finalBalance,
      fromDate: fromDate,
      toDate: toDate,
      statementNumber: statementNumber,
      notes: notes,
      openingBalanceNote: openingBalanceNote,
    );
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'Customer_Statement_${customer.name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
