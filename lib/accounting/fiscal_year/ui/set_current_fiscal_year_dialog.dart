import 'package:flutter/material.dart';
import '../models/fiscal_year.dart';

class SetCurrentFiscalYearDialog extends StatelessWidget {
  final FiscalYear fiscalYear;
  const SetCurrentFiscalYearDialog({required this.fiscalYear, super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعيين السنة الحالية'),
      content: Text('هل تريد تعيين السنة المالية ${fiscalYear.year} كالسنة الحالية؟'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('نعم')),
      ],
    );
  }
}
