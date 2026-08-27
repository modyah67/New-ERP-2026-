import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../../core/utils.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class AccountStatementExcelService {
  static Future<String> saveToFile({
    required AccountModel account,
    required List<Map<String, dynamic>> rows,
    required double totalDebit,
    required double totalCredit,
    required double openingBalance,
    required double finalBalance,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<String> headers = ['رقم القيد', 'التاريخ', 'النوع', 'المبلغ', 'رصيد قبل', 'رصيد بعد', 'البيان'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Opening Balance Row
    sheetObject.appendRow([
      TextCellValue('—'),
      TextCellValue('—'),
      TextCellValue('رصيد افتتاحي'),
      TextCellValue('—'),
      TextCellValue('—'),
      DoubleCellValue(openingBalance),
      TextCellValue('الرصيد السابق للفترة المحددة'),
    ]);

    // Data rows
    for (var row in rows) {
      final tx = row['tx'] as TransactionModel;
      final isDebit = row['isDebit'] as bool;
      final balBefore = row['balanceBefore'] as double;
      final balAfter = row['balanceAfter'] as double;

      sheetObject.appendRow([
        TextCellValue(tx.entryNumber?.toString() ?? '—'),
        TextCellValue(AppUtils.formatDate(DateTime.tryParse(tx.transactionDate) ?? DateTime.now())),
        TextCellValue(isDebit ? 'مدين' : 'دائن'),
        DoubleCellValue(tx.amount),
        DoubleCellValue(balBefore),
        DoubleCellValue(balAfter),
        TextCellValue(tx.description),
      ]);
    }

    // Summary
    sheetObject.appendRow([TextCellValue('')]);
    sheetObject.appendRow([TextCellValue('إجمالي المدين'), DoubleCellValue(totalDebit)]);
    sheetObject.appendRow([TextCellValue('إجمالي الدائن'), DoubleCellValue(totalCredit)]);
    sheetObject.appendRow([TextCellValue('الرصيد النهائي'), DoubleCellValue(finalBalance)]);

    final dir = await FileHelper.getExportDirectory();
    final fileName = 'AccountStatement_${account.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final path = '${dir.path}/$fileName';
    final bytes = excel.encode()!;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return path;
  }
}
