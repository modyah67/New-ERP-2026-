import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import '../services/fiscal_year_service.dart';
import '../../../core/injection.dart';
import '../../../core/services/tenant_service.dart';

class CreateFiscalYearDialog extends StatefulWidget {
  const CreateFiscalYearDialog({super.key});

  @override
  State<CreateFiscalYearDialog> createState() => _CreateFiscalYearDialogState();
}

class _CreateFiscalYearDialogState extends State<CreateFiscalYearDialog> {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _nameController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _yearController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 10),
      lastDate: DateTime(today.year + 10),
    );
    if (date != null) setState(() => _startDate = date);
  }

  Future<void> _pickEndDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 10),
      lastDate: DateTime(today.year + 10),
    );
    if (date != null) setState(() => _endDate = date);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء سنة مالية'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(
                  labelText: 'رقم السنة (أرقام فقط)',
                  hintText: 'مثال: 2027',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'مطلوب';
                  if (int.tryParse(v.trim()) == null) return 'أدخل رقماً صحيحاً';
                  return null;
                },
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم السنة المالية',
                  hintText: 'مثال: السنة المالية 2027',
                ),
                validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickStartDate,
                      child: Text(_startDate == null ? 'تاريخ البداية' : AppUtils.formatDate(_startDate!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEndDate,
                      child: Text(_endDate == null ? 'تاريخ النهاية' : AppUtils.formatDate(_endDate!)),
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
          child: const Text('إنشاء'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر تواريخ البداية والنهاية')));
      return;
    }
    final year = int.tryParse(_yearController.text.trim()) ?? DateTime.now().year;
    final name = _nameController.text.trim();
    final fy = FiscalYear(
      id: 0,
      year: year,
      name: name,
      startDate: _startDate!,
      endDate: _endDate!,
      status: FiscalYearStatus.active,
      isCurrent: false,
      isClosed: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      companyId: TenantService().tenantId,
    );
    try {
      final service = sl<FiscalYearService>();
      await service.createFiscalYear(fy);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
