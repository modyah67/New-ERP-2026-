import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/statement_row_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class StatementPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static String _typeLabel(String type, String locale) {
    if (locale == 'ar') {
      switch (type) {
        case 'opening': return 'رصيد سابق';
        case 'purchase': return 'مشتريات';
        case 'shipment': return 'شحنة تصدير';
        case 'payment': return 'سند قبض';
        case 'cheque': return 'شيك وارد';
        case 'cost': return 'تكلفة';
        case 'treasury': return 'حركة خزينة';
        case 'lot_receipt': return 'شراء محصول';
        case 'lot_return': return 'مرتجع شراء محصول';
        default: return type;
      }
    } else {
      switch (type) {
        case 'opening': return 'Opening Balance';
        case 'purchase': return 'Purchase';
        case 'shipment': return 'Export Shipment';
        case 'payment': return 'Payment Received';
        case 'cheque': return 'Cheque Received';
        case 'cost': return 'Cost Item';
        case 'treasury': return 'Treasury Transaction';
        case 'lot_receipt': return 'Crop Purchase';
        case 'lot_return': return 'Crop Purchase Return';
        default: return type;
      }
    }
  }

  static String _translateDesc(String desc, String locale) {
    if (locale != 'en') return desc;
    String t = desc;

    // Structured prefixes
    t = t.replaceAll('مشتريات رقم', 'Purchase No.');
    t = t.replaceAll('دفعة نقدية لمشتريات رقم', 'Cash Payment for Purchase No.');
    if (t == 'مشتريات') t = 'Purchase';
    
    t = t.replaceAll('إيصال استلام من مورد', 'Receipt from Supplier');
    t = t.replaceAll('إيصال صرف للمورد', 'Payment to Supplier');
    if (t == 'استلام محصول' || t == 'شراء محصول') t = 'Crop Purchase';
    
    t = t.replaceAll('تحويل بنكي من', 'Bank Transfer From');
    t = t.replaceAll('تحويل بنكي إلى', 'Bank Transfer To');
    t = t.replaceAll('تحويل بنكي الى', 'Bank Transfer To');
    t = t.replaceAll('تحويل بنكي', 'Bank Transfer');
    
    t = t.replaceAll('شيك وارد رقم', 'Cheque Received No.');
    t = t.replaceAll('شيك صادر رقم', 'Cheque Issued No.');
    t = t.replaceAll('شيك وارد', 'Cheque Received');
    t = t.replaceAll('شيك صادر', 'Cheque Issued');
    t = t.replaceAll('تحصيل شيك من', 'Collect Cheque From');
    t = t.replaceAll('تحصيل شيك رقم', 'Cheque Collected No.');
    t = t.replaceAll('تحصيل شيك', 'Collect Cheque');
    t = t.replaceAll('صرف شيك من', 'Cheque Paid From');
    t = t.replaceAll('صرف شيك رقم', 'Cheque Paid No.');
    t = t.replaceAll('صرف شيك', 'Pay Cheque');
    t = t.replaceAll('دفع شيك', 'Pay Cheque');
    t = t.replaceAll('شيك رقم', 'Cheque No.');
    t = t.replaceAll('شيك', 'Cheque');
    
    t = t.replaceAll(RegExp(r'دفع[ه]*\s*(لـ|الى|إلى)'), 'Cash Payment To ');
    t = t.replaceAll(RegExp(r'دفع[ه]*\s*نقدية'), 'Cash Payment ');
    t = t.replaceAll(RegExp(r'دفع[ه]*'), 'Cash Payment ');
    t = t.replaceAll(RegExp(r'استلام\s*من'), 'Cash Payment From ');
    t = t.replaceAll(RegExp(r'استلام\s*نقدي'), 'Cash Payment ');
    t = t.replaceAll('استلام', 'Receipt ');
    t = t.replaceAll(RegExp(r'صرف\s*من'), 'Cash Payment From ');
    t = t.replaceAll(RegExp(r'صرف\s*(الى|إلى)'), 'Cash Payment To ');
    t = t.replaceAll('صرف', 'Payment ');
    
    t = t.replaceAll('سند قبض', 'Payment Received ');
    t = t.replaceAll('رصيد افتتاحي', 'Opening Balance');
    t = t.replaceAll('رصيد سابق', 'Opening Balance');
    t = t.replaceAll('شحنة تصدير', 'Export Shipment');
    t = t.replaceAll('فاتورة مشتريات', 'Purchase Invoice');
    t = t.replaceAll('مشتريات', 'Purchases');
    t = t.replaceAll('محصول', 'Lot');

    // Common words
    final map = {
      'عقد': 'Contract',
      'سداد': 'Payment',
      'دفعة': 'Payment',
      'فاتورة': 'Invoice',
      'مقدم': 'Advance',
      'باقي': 'Remaining',
      'حساب': 'Account',
      'تسوية': 'Settlement',
      'خصم': 'Discount',
      'اضافة': 'Addition',
      'إضافة': 'Addition',
      'مبيعات': 'Sales',
      'مرتجع': 'Return',
      'نولون': 'Freight',
      'شحن': 'Shipping',
      'جمارك': 'Customs',
      'عمولة': 'Commission',
      'نثريات': 'Petty Cash',
      'مصاريف': 'Expenses',
      'مورد': 'Supplier',
      'عميل': 'Customer',
      'بضاعة': 'Goods',
      'سيارة': 'Car',
      'عربية': 'Truck',
      'نقل': 'Transport',
      'تصدير': 'Export',
      'محلي': 'Local',
      'تعبئة': 'Packing',
      'تغليف': 'Packaging',
      'مواد': 'Materials',
      'مادة': 'Material',
      'رقم': 'No.',
      'خزنه': 'Treasury',
      'خزينة': 'Treasury',
      'الشركه': 'Company',
      'الشركة': 'Company',
      'من': 'From',
      'إلى': 'To',
      'الى': 'To',
      'للمورد': 'to Supplier',
      'للعميل': 'to Customer',
      'للمخلص': 'to Clearing Agent',
      'لشركة الشحن': 'to Shipping Company',
    };

    map.forEach((ar, en) {
      t = t.replaceAll(ar, en);
    });
    
    // Strip remaining Arabic letters for English version
    t = t.replaceAll(RegExp(r'[\u0600-\u06FF]+'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  static pw.TextDirection _dir(String locale) =>
      locale == 'ar' ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  static Future<Uint8List> build({
    required String title,
    required String vendorName,
    required String vendorCode,
    required String currency,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    required String locale,
    Map<String, String>? notes,
    String? openingBalanceNote,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);
    final dir = _dir(locale);
    final isAr = locale == 'ar';

    final headerTitle = isAr ? title : _englishTitle(title);
    final customerLabel = isAr ? 'العميل' : 'Vendor';
    final codeLabel = isAr ? 'الكود' : 'Code';
    final currencyLabel = isAr ? 'العملة' : 'Currency';
    final periodLabel = isAr ? 'الفترة' : 'Period';
    final totalDebitLabel = isAr ? 'إجمالي المدين' : 'Total Debit';
    final totalCreditLabel = isAr ? 'إجمالي الدائن' : 'Total Credit';
    final finalBalanceLabel = isAr ? 'الرصيد النهائي' : 'Final Balance';

    String? translatedObNote = openingBalanceNote;
    final obNote = openingBalanceNote;
    if (!isAr && obNote != null && obNote.contains('ملحوظة: الرصيد السابق')) {
      final amount = obNote.replaceAll(RegExp(r'^ملحوظة:\s*الرصيد السابق\s*=\s*'), '');
      translatedObNote = 'Note: Previous Balance = $amount';
    }

    final headers = isAr
        ? ['رقم المرجع', 'التاريخ', 'النوع', 'البيان', 'الكراتين', 'مدين', 'دائن', 'الرصيد', 'ملاحظة']
        : ['Ref No.', 'Date', 'Type', 'Description', 'Cartons', 'Debit', 'Credit', 'Balance', 'Note'];

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.portrait,
          textDirection: dir,
          margin: const pw.EdgeInsets.only(top: 120, bottom: 70, left: 20, right: 20),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          pw.Container(
            width: double.infinity,
            alignment: pw.Alignment.centerRight,
            child: pw.Directionality(
              textDirection: dir,
              child: pw.Column(
                crossAxisAlignment: isAr ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('$customerLabel: $vendorName',
                      style: pw.TextStyle(font: _boldFont, fontSize: 14, color: PdfColors.black)),
                  pw.Text('$codeLabel: $vendorCode',
                      style: pw.TextStyle(font: _font, fontSize: 12, color: PdfColors.grey700)),
                  pw.Text('$currencyLabel: $currency',
                      style: pw.TextStyle(font: _font, fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            alignment: pw.Alignment.centerRight,
            child: pw.Directionality(
              textDirection: dir,
              child: pw.Text(
                '$periodLabel: ${_fmtDate(fromDate)} - ${_fmtDate(toDate)}',
                style: pw.TextStyle(font: _font, fontSize: 9, color: PdfColors.grey700),
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 8),
          if (translatedObNote != null && translatedObNote.isNotEmpty)
            pw.Directionality(
              textDirection: dir,
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
          _buildTable(rows, currency, notes, headers, locale),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Directionality(
            textDirection: dir,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('$totalDebitLabel: ${totalDebit.toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.red)),
                pw.Text('$totalCreditLabel: ${totalCredit.toStringAsFixed(2)} $currency',
                    style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.green)),
                pw.Text('$finalBalanceLabel: ${finalBalance.abs().toStringAsFixed(2)} $currency',
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
    List<String> headers,
    String locale,
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
      headers: headers,
      data: List.generate(rows.length, (i) {
        final r = rows[i];
        final note = (notes != null && notes.containsKey(r.transactionNumber)) ? notes[r.transactionNumber]! : '';
        return [
          r.transactionNumber,
          r.date,
          _typeLabel(r.type, locale),
          _translateDesc(r.description, locale),
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

  static String _englishTitle(String arTitle) {
    if (arTitle.contains('الموردين')) return 'Supplier Account Statement';
    if (arTitle.contains('المخلص')) return 'Clearing Agent Account Statement';
    if (arTitle.contains('الشحن')) return 'Shipping Company Account Statement';
    return 'Account Statement';
  }

  static Future<void> printPdf({
    required String title,
    required String vendorName,
    required String vendorCode,
    required String currency,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    required String locale,
    Map<String, String>? notes,
    String? openingBalanceNote,
  }) async {
    final bytes = await build(
      title: title, vendorName: vendorName, vendorCode: vendorCode,
      currency: currency, rows: rows, totalDebit: totalDebit,
      totalCredit: totalCredit, finalBalance: finalBalance,
      fromDate: fromDate, toDate: toDate, statementNumber: statementNumber,
      locale: locale, notes: notes, openingBalanceNote: openingBalanceNote,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: '${title}_${vendorName}',
    );
  }

  static Future<String> saveToFile({
    required String title,
    required String vendorName,
    required String vendorCode,
    required String currency,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
    required int statementNumber,
    required String locale,
    Map<String, String>? notes,
    String? openingBalanceNote,
    String? customDirectory,
  }) async {
    final bytes = await build(
      title: title, vendorName: vendorName, vendorCode: vendorCode,
      currency: currency, rows: rows, totalDebit: totalDebit,
      totalCredit: totalCredit, finalBalance: finalBalance,
      fromDate: fromDate, toDate: toDate, statementNumber: statementNumber,
      locale: locale, notes: notes, openingBalanceNote: openingBalanceNote,
    );
    final dir = customDirectory != null ? Directory(customDirectory) : await FileHelper.getExportDirectory();
    final fileName = '${title}_${vendorName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
