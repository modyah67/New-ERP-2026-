import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../models/fiscal_year.dart';

class ReopenFiscalYearDialog extends StatefulWidget {
  final FiscalYear fiscalYear;

  const ReopenFiscalYearDialog({
    required this.fiscalYear,
    super.key,
  });

  @override
  State<ReopenFiscalYearDialog> createState() => _ReopenFiscalYearDialogState();
}

class _ReopenFiscalYearDialogState extends State<ReopenFiscalYearDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final reason = _reasonController.text.trim();
      Navigator.of(context).pop(reason.isEmpty ? 'إعادة فتح السنة المالية' : reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('تأكيد إعادة الفتح'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل تريد إعادة فتح السنة المالية ${widget.fiscalYear.year}؟',
              style: AppTheme.body,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب إعادة الفتح (مطلوب)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: AppTheme.primary, width: 2),
                ),
              ),
              maxLines: 2,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'يرجى إدخال سبب إعادة الفتح';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('إعادة فتح'),
        ),
      ],
    );
  }
}
