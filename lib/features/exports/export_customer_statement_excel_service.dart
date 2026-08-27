import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ExportCustomerStatementExcelService {
  static String _typeLabel(String type) {
    switch (type) {
      case 'opening': return 'Opening Balance';
      case 'purchase': return 'Purchase';
      case 'shipment': return 'Export Shipment';
      case 'payment': return 'Payment Received';
      case 'cheque': return 'Cheque Received';
      case 'cost': return 'Cost Item';
      case 'treasury': return 'Treasury Transaction';
      case 'lot_receipt': return 'Goods Receipt';
      default: return type;
    }
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
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<String> headers = ['Ref No.', 'Date', 'Type', 'Description', 'Cartons', 'Debit', 'Credit', 'Balance', 'Note'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Data rows
    for (var r in rows) {
      final note = (notes != null && notes.containsKey(r.transactionNumber)) ? notes[r.transactionNumber]! : '';
      sheetObject.appendRow([
        TextCellValue(r.transactionNumber),
        TextCellValue(r.date),
        TextCellValue(_typeLabel(r.type)),
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
    sheetObject.appendRow([TextCellValue('Total Debit'), DoubleCellValue(totalDebit)]);
    sheetObject.appendRow([TextCellValue('Total Credit'), DoubleCellValue(totalCredit)]);
    sheetObject.appendRow([TextCellValue('Final Balance'), DoubleCellValue(finalBalance)]);

    final dir = await FileHelper.getExportDirectory();
    final fileName = 'ExportCustomerStatement_${customer.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final path = '${dir.path}/$fileName';
    final bytes = excel.encode()!;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return path;
  }
}
