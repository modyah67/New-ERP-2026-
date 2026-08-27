import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/shipping_company_model.dart';
import 'shipping_company_cubit.dart';
import 'shipping_company_state.dart';
import '../../ui/widgets/app_text_field.dart';

class ShippingCompanyFormDialog extends StatefulWidget {
  final ShippingCompanyModel? company;
  const ShippingCompanyFormDialog({super.key, this.company});

  @override
  State<ShippingCompanyFormDialog> createState() =>
      _ShippingCompanyFormDialogState();
}

class _ShippingCompanyFormDialogState
    extends State<ShippingCompanyFormDialog> {
  late final ShippingCompanyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<ShippingCompanyCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.company != null) {
        await _cubit.prepareEditForm(widget.company!);
      } else {
        await _cubit.prepareAddForm();
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    final success = await _cubit.save();
    if (!mounted) return;
    if (success) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                widget.company != null
                    ? 'تم تعديل شركة الشحن بنجاح'
                    : 'تم إضافة شركة الشحن بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.company != null;
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
                maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                label: 'كود الشركة',
                                controller: _cubit.codeController,
                                hint: '0001',
                                readOnly: widget.company != null,
                                isRequired: true,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'كود الشركة مطلوب';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'اسم الشركة',
                                controller: _cubit.nameController,
                                isRequired: true,
                                hint: 'أدخل اسم شركة الشحن',
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'الاسم مطلوب';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                label: 'رقم الهاتف',
                                controller: _cubit.phoneController,
                                hint: 'رقم الهاتف',
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'البريد الإلكتروني',
                                controller: _cubit.emailController,
                                hint: 'example@domain.com',
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: 'الرصيد المبدئي',
                          controller: _cubit.initialBalanceController,
                          hint: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
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
                        // BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
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
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _cubit.selectedCurrency,
                          hint: const Text('اختر العملة', style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 13)),
                          validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار العملة' : null,
                          decoration: InputDecoration(
                            labelText: 'العملة *',
                            labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            border: const OutlineInputBorder(),
                            helperText: isEditing ? 'لا يمكن تغييرها بعد الحفظ' : null,
                            helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'EGP', child: Text('جنيه مصري (EGP)')),
                            DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (USD)')),
                            DropdownMenuItem(value: 'EUR', child: Text('يورو (EUR)')),
                            DropdownMenuItem(value: 'GBP', child: Text('جنيه إسترليني (GBP)')),
                          ],
                          onChanged: isEditing
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _cubit.selectedCurrency = v);
                                },
                        ),
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
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.local_shipping_outlined,
              color: AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? 'تعديل شركة شحن' : 'إضافة شركة شحن جديدة',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFamily: 'Cairo'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(bool isEditing) {
    return BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
      builder: (context, state) {
        final isSaving = _cubit.formState.isSaving;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 12,
            overflowSpacing: 12,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: AppTheme.accent.withValues(alpha: 0.3),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(
                        isEditing ? Icons.save_outlined : Icons.add,
                        size: 18),
                label: Text(
                  isSaving
                      ? 'جاري الحفظ...'
                      : isEditing
                          ? 'حفظ التعديلات'
                          : 'إضافة الشركة',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
                onPressed: isSaving ? null : _save,
              ),
            ],
          ),
        );
      },
    );
  }
}
