import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/models/statement_row_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class StatementPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null && _boldFont != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _font = pw.Font.ttf(r);
      _boldFont = pw.Font.ttf(b);
    } catch (_) {
      try {
        final regFile = File('assets/fonts/Cairo-Regular.ttf');
        final boldFile = File('assets/fonts/Cairo-Bold.ttf');
        if (regFile.existsSync() && boldFile.existsSync()) {
          _font = pw.Font.ttf(regFile.readAsBytesSync().buffer.asByteData());
          _boldFont = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } else {
          _font = await PdfGoogleFonts.cairoRegular();
          _boldFont = await PdfGoogleFonts.cairoBold();
        }
      } catch (_) {
        _font = await PdfGoogleFonts.cairoRegular();
        _boldFont = await PdfGoogleFonts.cairoBold();
      }
    }
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
    String? entityLabel,
  }) async {
    await _loadFonts();
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: _font!, bold: _boldFont!);
    final dir = _dir(locale);
    final isAr = locale == 'ar';

    final headerTitle = isAr ? title : _englishTitle(title);

    // Dynamic Entity Label Resolution
    final String resolvedEntityLabel;
    if (entityLabel != null && entityLabel.isNotEmpty) {
      resolvedEntityLabel = entityLabel;
    } else {
      final t = title.toLowerCase();
      final n = vendorName.toLowerCase();
      final c = vendorCode.trim();

      if (t.contains('مورد') || t.contains('supplier') || t.contains('vendor') ||
          c.startsWith('211') || c.startsWith('210') || n.contains('مورد')) {
        resolvedEntityLabel = isAr ? 'المورد' : 'Supplier';
      } else if (t.contains('عميل') || t.contains('customer') || t.contains('client') ||
          c.startsWith('125') || c.startsWith('123') || n.contains('عميل')) {
        resolvedEntityLabel = isAr ? 'العميل' : 'Customer';
      } else if (t.contains('شحن') || t.contains('shipping') || n.contains('شحن')) {
        resolvedEntityLabel = isAr ? 'شركة الشحن' : 'Shipping Company';
      } else if (t.contains('مخلص') || t.contains('clearing') || n.contains('مخلص')) {
        resolvedEntityLabel = isAr ? 'المخلص الجمركي' : 'Clearing Agent';
      } else if (t.contains('مساهم') || t.contains('shareholder') || n.contains('مساهم')) {
        resolvedEntityLabel = isAr ? 'المساهم' : 'Shareholder';
      } else {
        resolvedEntityLabel = isAr ? 'الجهة' : 'Entity';
      }
    }

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
        ? ['رقم المرجع', 'التاريخ', 'النوع', 'البيان', 'العملة الأجنبية', 'مدين (ج.م)', 'دائن (ج.م)', 'الرصيد (ج.م)', 'ملاحظة']
        : ['Ref No.', 'Date', 'Type', 'Description', 'Foreign Cur.', 'Debit (EGP)', 'Credit (EGP)', 'Balance (EGP)', 'Note'];

    pw.MemoryImage? bgImage;
    try {
      final bgData = await rootBundle.load('assets/images/statment.png');
      bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    } catch (_) {
      try {
        final f = File('assets/images/statment.png');
        if (f.existsSync()) {
          bgImage = pw.MemoryImage(f.readAsBytesSync());
        }
      } catch (_) {}
    }

    final pageTheme = pw.PageTheme(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      orientation: pw.PageOrientation.landscape,
      textDirection: dir,
      margin: const pw.EdgeInsets.only(top: 85, bottom: 40, left: 24, right: 24),
      buildBackground: bgImage != null
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(bgImage!, fit: pw.BoxFit.cover),
              )
          : null,
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (ctx) => [
          // Document Title
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 6),
            alignment: isAr ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            child: pw.Text(
              headerTitle,
              textDirection: dir,
              style: pw.TextStyle(font: _boldFont, fontSize: 13, color: PdfColors.blueGrey900),
            ),
          ),
          // Landscape Meta Header
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            child: pw.Directionality(
              textDirection: dir,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('$resolvedEntityLabel: ',
                          style: pw.TextStyle(font: _font, fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(vendorName,
                          style: pw.TextStyle(font: _boldFont, fontSize: 11, color: PdfColors.black)),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('$codeLabel: ',
                          style: pw.TextStyle(font: _font, fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(vendorCode.isNotEmpty ? vendorCode : '-',
                          style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.black)),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('$currencyLabel: ',
                          style: pw.TextStyle(font: _font, fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(currency.isNotEmpty ? currency : '-',
                          style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.black)),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('$periodLabel: ',
                          style: pw.TextStyle(font: _font, fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(
                        (fromDate != null || toDate != null)
                            ? '${_fmtDate(fromDate)} - ${_fmtDate(toDate)}'
                            : (isAr ? 'كافة المعاملات' : 'All Periods'),
                        style: pw.TextStyle(font: _boldFont, fontSize: 9.5, color: PdfColors.black),
                      ),
                    ],
                  ),
                  if (statementNumber > 0)
                    pw.Row(
                      children: [
                        pw.Text(isAr ? 'رقم الكشف: ' : 'Statement #: ',
                            style: pw.TextStyle(font: _font, fontSize: 9.5, color: PdfColors.grey700)),
                        pw.Text('#$statementNumber',
                            style: pw.TextStyle(font: _boldFont, fontSize: 10, color: PdfColors.black)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          if (translatedObNote != null && translatedObNote.isNotEmpty)
            pw.Directionality(
              textDirection: dir,
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _isObNoteNegative(translatedObNote) ? PdfColors.red50 : PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: _isObNoteNegative(translatedObNote) ? PdfColors.red200 : PdfColors.blue200),
                ),
                child: _buildObNoteText(translatedObNote),
              ),
            ),
          if (translatedObNote != null && translatedObNote.isNotEmpty) pw.SizedBox(height: 8),
          _buildTable(rows, currency, notes, headers, locale),
          pw.SizedBox(height: 10),
          // Landscape Summary Footer Strip
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            child: pw.Directionality(
              textDirection: dir,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$totalDebitLabel: ${totalDebit > 0 ? totalDebit.toStringAsFixed(2) : "0.00"} ${isAr ? "ج.م" : "EGP"}',
                      style: pw.TextStyle(font: _boldFont, fontSize: 10.5, color: PdfColors.red)),
                  pw.Text('$totalCreditLabel: ${totalCredit > 0 ? totalCredit.toStringAsFixed(2) : "0.00"} ${isAr ? "ج.م" : "EGP"}',
                      style: pw.TextStyle(font: _boldFont, fontSize: 10.5, color: PdfColors.green)),
                  pw.Text(
                    '$finalBalanceLabel: ${finalBalance.abs().toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"} ${finalBalance > 0 ? (isAr ? "(له)" : "(Cr)") : finalBalance < 0 ? (isAr ? "(عليه)" : "(Dr)") : ""}',
                    style: pw.TextStyle(font: _boldFont, fontSize: 11.5, color: PdfColors.black),
                  ),
                ],
              ),
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
    final isAr = locale == 'ar';
    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle: pw.TextStyle(font: _boldFont!, fontSize: 8, color: PdfColors.white),
      cellStyle: pw.TextStyle(font: _font!, fontSize: 7.5, color: PdfColors.black),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      columnWidths: {
        0: const pw.FlexColumnWidth(55),  // Ref No.
        1: const pw.FlexColumnWidth(50),  // Date
        2: const pw.FlexColumnWidth(60),  // Type
        3: const pw.FlexColumnWidth(130), // Description (plenty of room in landscape!)
        4: const pw.FlexColumnWidth(75),  // Foreign Currency
        5: const pw.FlexColumnWidth(60),  // Debit (EGP)
        6: const pw.FlexColumnWidth(60),  // Credit (EGP)
        7: const pw.FlexColumnWidth(65),  // Balance (EGP)
        8: const pw.FlexColumnWidth(55),  // Note
      },
      headers: headers,
      data: List.generate(rows.length, (i) {
        final r = rows[i];
        final rawNote = (notes != null && notes.containsKey(r.transactionNumber))
            ? notes[r.transactionNumber]!
            : '';
        final note = rawNote.trim().isNotEmpty
            ? rawNote.trim()
            : (r.accountName.trim().isNotEmpty && r.accountName != '-' && r.accountName != 'null')
                ? r.accountName.trim()
                : '-';

        final ref = r.transactionNumber.trim().isNotEmpty
            ? r.transactionNumber.trim()
            : (r.referenceId != null && r.referenceId!.trim().isNotEmpty && r.referenceId != '-')
                ? r.referenceId!.trim()
                : '-';

        final date = r.date.trim().isNotEmpty ? r.date.trim() : '-';
        final type = _typeLabel(r.type, locale).trim().isNotEmpty ? _typeLabel(r.type, locale).trim() : '-';
        final desc = _translateDesc(r.description, locale).trim().isNotEmpty
            ? _translateDesc(r.description, locale).trim()
            : '-';

        final foreignCurClean = r.isForeignCurrency ? r.foreignDisplayCompact : '-';
        final debit = r.debit > 0 ? '${r.debit.toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"}' : '-';
        final credit = r.credit > 0 ? '${r.credit.toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"}' : '-';
        final balSign = r.balance > 0 ? (isAr ? ' (له)' : ' (Cr)') : r.balance < 0 ? (isAr ? ' (عليه)' : ' (Dr)') : '';
        final balance = r.balance != 0
            ? '${r.balance.abs().toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"}$balSign'
            : '0.00 (متزن)';

        return [
          ref,
          date,
          type,
          desc,
          foreignCurClean,
          debit,
          credit,
          balance,
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
    if (arTitle.contains('الموردين') || arTitle.contains('مورد')) return 'Supplier Account Statement';
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
    String? entityLabel,
  }) async {
    final bytes = await build(
      title: title, vendorName: vendorName, vendorCode: vendorCode,
      currency: currency, rows: rows, totalDebit: totalDebit,
      totalCredit: totalCredit, finalBalance: finalBalance,
      fromDate: fromDate, toDate: toDate, statementNumber: statementNumber,
      locale: locale, notes: notes, openingBalanceNote: openingBalanceNote,
      entityLabel: entityLabel,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: '${title}_$vendorName',
      format: PdfPageFormat.a4.landscape,
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
    String? entityLabel,
  }) async {
    final bytes = await build(
      title: title, vendorName: vendorName, vendorCode: vendorCode,
      currency: currency, rows: rows, totalDebit: totalDebit,
      totalCredit: totalCredit, finalBalance: finalBalance,
      fromDate: fromDate, toDate: toDate, statementNumber: statementNumber,
      locale: locale, notes: notes, openingBalanceNote: openingBalanceNote,
      entityLabel: entityLabel,
    );
    final dir = customDirectory != null ? Directory(customDirectory) : await FileHelper.getExportDirectory();
    final fileName = '${title}_${vendorName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
