import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/statement_row_model.dart';
import 'statement_pdf_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class StatementExcelService {
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

  static String _englishTitle(String arTitle) {
    if (arTitle.contains('الموردين')) return 'Supplier Account Statement';
    if (arTitle.contains('المخلص')) return 'Clearing Agent Account Statement';
    if (arTitle.contains('الشحن')) return 'Shipping Company Account Statement';
    return 'Account Statement';
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
    final isAr = locale == 'ar';
    final headerTitle = isAr ? title : _englishTitle(title);

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<String> headers = isAr
        ? ['رقم المرجع', 'التاريخ', 'النوع', 'البيان', 'الكراتين', 'مدين', 'دائن', 'الرصيد', 'ملاحظة']
        : ['Ref No.', 'Date', 'Type', 'Description', 'Cartons', 'Debit', 'Credit', 'Balance', 'Note'];
    
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Data rows
    for (var r in rows) {
      final note = (notes != null && notes.containsKey(r.transactionNumber)) ? notes[r.transactionNumber]! : '';
      sheetObject.appendRow([
        TextCellValue(r.transactionNumber),
        TextCellValue(r.date),
        TextCellValue(_typeLabel(r.type, locale)),
        TextCellValue(r.description),
        DoubleCellValue(r.piecesCount),
        DoubleCellValue(r.debit),
        DoubleCellValue(r.credit),
        DoubleCellValue(r.balance),
        TextCellValue(note),
      ]);
    }

    // Summary
    sheetObject.appendRow([TextCellValue('')]);
    sheetObject.appendRow([TextCellValue(isAr ? 'إجمالي المدين' : 'Total Debit'), DoubleCellValue(totalDebit)]);
    sheetObject.appendRow([TextCellValue(isAr ? 'إجمالي الدائن' : 'Total Credit'), DoubleCellValue(totalCredit)]);
    sheetObject.appendRow([TextCellValue(isAr ? 'الرصيد النهائي' : 'Final Balance'), DoubleCellValue(finalBalance)]);

    final dir = customDirectory != null ? Directory(customDirectory) : await FileHelper.getExportDirectory();
    final fileName = '${headerTitle}_${vendorName}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final path = '${dir.path}/$fileName';
    final bytes = excel.encode()!;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return path;
  }
}
