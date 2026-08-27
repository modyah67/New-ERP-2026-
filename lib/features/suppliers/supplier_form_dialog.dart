import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/supplier_model.dart';
import 'supplier_cubit.dart';
import 'supplier_state.dart';
import '../../ui/widgets/app_text_field.dart';

class SupplierFormDialog extends StatefulWidget {
  final SupplierModel? supplier;
  const SupplierFormDialog({super.key, this.supplier});

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  late final SupplierCubit _cubit;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _cubit = context.read<SupplierCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.supplier != null) {
        await _cubit.prepareEditForm(widget.supplier!);
      } else {
        await _cubit.prepareAddForm();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    final success = await _cubit.save();
    if (!mounted) return;
    if (success) {
      final messenger = ScaffoldMessenger.of(context);
      final isEditing = widget.supplier != null;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                isEditing ? 'تم تعديل المورد بنجاح' : 'تم إضافة المورد بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('فشل الحفظ: تحقق من صحة البيانات',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplier != null;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 500,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Color(0xB305192D),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Form(
              key: _cubit.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(isEditing),
                  Flexible(
                    child: ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                      children: [
                        const SizedBox(height: 20),
                        AppTextField(
                          label: 'كود المورد',
                          controller: _cubit.codeController,
                          hint: '0001',
                          readOnly: isEditing,
                          isRequired: true,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'كود المورد مطلوب';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: 'اسم المورد / الشركة',
                          controller: _cubit.nameController,
                          focusNode: _cubit.nameFocus,
                          hint: 'أدخل اسم المورد أو الشركة',
                          isRequired: !isEditing,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                            if (v.trim().length < 2) return 'الاسم قصير جداً';
                            return null;
                          },
                          onSubmitted: (_) => _cubit.phoneFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: 'رقم الهاتف',
                          controller: _cubit.phoneController,
                          focusNode: _cubit.phoneFocus,
                          hint: '01xxxxxxxxx',
                          keyboardType: TextInputType.phone,
                          onSubmitted: (_) => _cubit.addressFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: 'العنوان',
                          controller: _cubit.addressController,
                          focusNode: _cubit.addressFocus,
                          hint: 'عنوان المورد',
                          onSubmitted: (_) => _cubit.initialBalanceFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        _buildCurrencyDropdown(),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: 'الرصيد المبدئي',
                          controller: _cubit.initialBalanceController,
                          focusNode: _cubit.initialBalanceFocus,
                          hint: '0.00',
                          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                          isRequired: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'الرصيد المبدئي مطلوب';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        // BlocBuilder<SupplierCubit, SupplierState>(
                        //   builder: (context, state) {
                        //     return Column(
                        //       crossAxisAlignment: CrossAxisAlignment.start,
                        //       children: [
                        //         const Text('طبيعة الرصيد الافتتاحي *', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                        //         const SizedBox(height: 8),
                        //         Row(
                        //           children: [
                        //             Expanded(
                        //               child: RadioListTile<String>(
                        //                 title: const Text('دائن (له)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                        //                 value: 'CREDIT',
                        //                 groupValue: _cubit.initialBalanceDirection,
                        //                 onChanged: _cubit.formState.isEditing ? null : (v) {
                        //                   if (v != null) {
                        //                     setState(() => _cubit.initialBalanceDirection = v);
                        //                   }
                        //                 },
                        //                 activeColor: AppTheme.primary,
                        //                 contentPadding: EdgeInsets.zero,
                        //               ),
                        //             ),
                        //             Expanded(
                        //               child: RadioListTile<String>(
                        //                 title: const Text('مدين (عليه)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                        //                 value: 'DEBIT',
                        //                 groupValue: _cubit.initialBalanceDirection,
                        //                 onChanged: _cubit.formState.isEditing ? null : (v) {
                        //                   if (v != null) {
                        //                     setState(() => _cubit.initialBalanceDirection = v);
                        //                   }
                        //                 },
                        //                 activeColor: AppTheme.primary,
                        //                 contentPadding: EdgeInsets.zero,
                        //               ),
                        //             ),
                        //           ],
                        //         ),
                        //       ],
                        //     );
                        //   },
                        // ),
                      ],
                    ),
                  ),
                  _buildButtons(isEditing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.local_shipping_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                isEditing ? 'تعديل مورد' : 'إضافة مورد جديد',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
          BlocBuilder<SupplierCubit, SupplierState>(
            builder: (context, state) {
              final formState = _cubit.formState;
              if (formState.isSaving) {
                return const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppTheme.primary),
                );
              }
              return IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                onPressed: () => Navigator.pop(context),
                tooltip: 'إغلاق',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyDropdown() {
    const currencies = ['EGP', 'USD', 'EUR', 'GBP'];
    const currencyLabels = {
      'EGP': 'ج.م - جنيه مصري',
      'USD': '\$ - دولار أمريكي',
      'EUR': '€ - يورو',
      'GBP': '£ - جنيه إسترليني',
    };
    return DropdownButtonFormField<String>(
      value: _cubit.selectedCurrency,
      dropdownColor: const Color(0xFF0A1E35),
      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
      hint: const Text('اختر العملة', style: TextStyle(color: Colors.grey, fontFamily: 'Cairo')),
      validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار العملة' : null,
      decoration: InputDecoration(
        labelText: 'عملة المورد *',
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
        prefixIcon: const Icon(Icons.attach_money, color: AppTheme.primary, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
      ),
      items: currencies.map((c) => DropdownMenuItem(
        value: c,
        child: Text(currencyLabels[c] ?? c),
      )).toList(),
      onChanged: _cubit.formState.isEditing
          ? null
          : (v) {
              if (v != null) _cubit.selectedCurrency = v;
            },
    );
  }

  Widget _buildButtons(bool isEditing) {
    return BlocBuilder<SupplierCubit, SupplierState>(
      builder: (context, state) {
        final formState = _cubit.formState;
        final isSaving = formState.isSaving;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child:
                    const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(isEditing ? Icons.save_outlined : Icons.add,
                          size: 18),
                  label: Text(
                    isSaving
                        ? 'جاري الحفظ...'
                        : isEditing
                            ? 'حفظ التعديلات'
                            : 'إضافة المورد',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                  onPressed: isSaving ? null : _save,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
