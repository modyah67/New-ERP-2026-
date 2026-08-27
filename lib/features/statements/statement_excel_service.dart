import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class StatementExcelService {
  static String _typeLabel(String type) {
    switch (type) {
      case 'opening': return 'رصيد سابق';
      case 'purchase': return 'مبيعات';
      case 'shipment': return 'شحنة تصدير';
      case 'payment': return 'سند قبض';
      case 'cheque': return 'شيك وارد';
      case 'cost': return 'تكلفة';
      case 'treasury': return 'حركة خزينة';
      case 'lot_receipt': return 'شراء محصول';
      case 'lot_return': return 'مرتجع شراء محصول';
      default: return type;
    }
  }

  static Future<String> saveToFile(
    BuildContext context, {
    required CustomerModel customer,
    required List<StatementRow> rows,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required DateTime? fromDate,
    required DateTime? toDate,
    int statementNumber = 0,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<String> headers = ['التاريخ', 'البيان', 'النوع', 'الكمية', 'مدين', 'دائن', 'الرصيد'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Data rows
    for (var r in rows) {
      sheetObject.appendRow([
        TextCellValue(r.date),
        TextCellValue(r.description),
        TextCellValue(_typeLabel(r.type)),
        DoubleCellValue(r.quantity),
        DoubleCellValue(r.debit),
        DoubleCellValue(r.credit),
        DoubleCellValue(r.balance),
      ]);
    }

    final totalMeters = rows.fold(0.0, (sum, r) => sum + r.quantity);

    // Summary
    sheetObject.appendRow([TextCellValue('')]);
    sheetObject.appendRow([TextCellValue('إجمالي المدين'), DoubleCellValue(totalDebit)]);
    sheetObject.appendRow([TextCellValue('إجمالي الدائن'), DoubleCellValue(totalCredit)]);
    sheetObject.appendRow([TextCellValue('الرصيد النهائي'), DoubleCellValue(finalBalance)]);
    sheetObject.appendRow([TextCellValue('إجمالي الكمية'), DoubleCellValue(totalMeters)]);

    final dir = await FileHelper.getExportDirectory();
    final fileName = 'CustomerStatement_${customer.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final path = '${dir.path}/$fileName';
    final bytes = excel.encode()!;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return path;
  }
}
