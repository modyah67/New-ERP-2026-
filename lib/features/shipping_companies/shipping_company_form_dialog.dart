import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/shipping_company_dao.dart';
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

    // ── Form Validation Guard: Strict Numerical Boundary Check ──
    final codeText = _cubit.codeController.text.trim();
    final codeValidationError =
        ShippingCompanyModel.validateShippingCompanyCode(codeText);
    if (codeValidationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  codeValidationError,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // ── Collision Check Guard ──
    if (widget.company == null || widget.company!.code != codeText) {
      final exists = await ShippingCompanyDao().checkCodeExists(codeText, excludeId: widget.company?.id);
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'كود شركة الشحن ($codeText) مستخدم بالفعل، يرجى اختيار كود آخر',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

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
    final isDark = ThemeCubit.isCurrentDark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 500,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xB305192D) : Colors.white,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
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
                                hint: ShippingCompanyModel.codeHint,
                                readOnly: widget.company != null,
                                isRequired: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                validator: (v) => ShippingCompanyModel.validateShippingCompanyCode(v),
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
                            if (v != null && v.trim().isNotEmpty && double.tryParse(v.trim()) == null) {
                              return 'يرجى إدخال رقم صحيح';
                            }
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
    final isDark = ThemeCubit.isCurrentDark;
    final accentColor = isDark ? AppTheme.accent : AppTheme.lightAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isDark ? 0.1 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.local_shipping_outlined,
              color: accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? 'تعديل شركة شحن' : 'إضافة شركة شحن جديدة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo',
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: isDark ? Colors.white70 : const Color(0xFF475569), size: 22),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(bool isEditing) {
    final isDark = ThemeCubit.isCurrentDark;
    final accentColor = isDark ? AppTheme.accent : AppTheme.lightAccent;

    return BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
      builder: (context, state) {
        final isSaving = _cubit.formState.isSaving;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder,
              ),
            ),
          ),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 12,
            overflowSpacing: 12,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                  side: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.15) : AppTheme.lightBorder,
                  ),
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
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: accentColor.withValues(alpha: 0.3),
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
