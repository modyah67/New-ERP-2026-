import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../models/fiscal_year.dart';
import '../services/fiscal_year_service.dart';
import '../../../core/injection.dart';

class EditFiscalYearDialog extends StatefulWidget {
  final FiscalYear fiscalYear;
  const EditFiscalYearDialog({required this.fiscalYear, super.key});

  @override
  State<EditFiscalYearDialog> createState() => _EditFiscalYearDialogState();
}

class _EditFiscalYearDialogState extends State<EditFiscalYearDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _yearController;
  late TextEditingController _nameController;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(text: widget.fiscalYear.year.toString());
    _nameController = TextEditingController(text: widget.fiscalYear.name);
    _startDate = widget.fiscalYear.startDate;
    _endDate = widget.fiscalYear.endDate;
  }

  @override
  void dispose() {
    _yearController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _startDate = date);
  }

  Future<void> _pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _endDate = date);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل السنة المالية'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(labelText: 'السنة'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickStart,
                      child: Text(_startDate == null ? 'بداية' : AppUtils.formatDate(_startDate!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEnd,
                      child: Text(_endDate == null ? 'نهاية' : AppUtils.formatDate(_endDate!)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر تواريخ')));
      return;
    }
    final updatedFy = widget.fiscalYear.copyWith(
      year: int.parse(_yearController.text.trim()),
      name: _nameController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    );
    try {
      final service = sl<FiscalYearService>();
      await service.updateFiscalYear(updatedFy);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
