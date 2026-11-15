import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/account_model.dart';
import 'account_cubit.dart';
import 'account_state.dart';
import '../../ui/widgets/app_text_field.dart';

class AccountFormDialog extends StatelessWidget {
  final AccountModel? account;
  const AccountFormDialog({super.key, this.account});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AccountCubit>();
    final isEditing = account != null;

    final screenWidth = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: const Color(0xCC05192D),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.glassBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 500,
            decoration: AppTheme.glassCard(),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: controller.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_tree_outlined,
                            color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEditing ? 'تعديل حساب' : 'إضافة حساب جديد',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: AppTextField(
                          label: 'كود الحساب',
                          controller: controller.codeController,
                          focusNode: controller.codeFocus,
                          hint: '1100',
                          isRequired: true,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'الكود مطلوب' : null,
                          onSubmitted: (_) => controller.nameFocus.requestFocus(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AppTextField(
                          label: 'اسم الحساب',
                          controller: controller.nameController,
                          focusNode: controller.nameFocus,
                          hint: 'أدخل اسم الحساب',
                          isRequired: true,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'الاسم مطلوب' : null,
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  BlocBuilder<AccountCubit, AccountState>(
                    builder: (context, state) {
                      final saving = controller.formState.isSaving;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: saving ? null : () => Navigator.pop(context),
                            child: const Text('إلغاء'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: saving
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(
                                    isEditing
                                        ? Icons.save_outlined
                                        : Icons.add,
                                    size: 18,
                                  ),
                            label: Text(
                                saving ? 'جاري الحفظ...' : (isEditing ? 'حفظ التعديلات' : 'إضافة')),
                            onPressed: (saving || ReadOnlyGuard.isReadOnly) ? null : () async {
                              if (!await ReadOnlyGuard.checkAsync(context)) return;
                              final ok = await controller.save();
                              if (ok && context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? 'تم تعديل الحساب بنجاح'
                                          : 'تم إضافة الحساب بنجاح',
                                    ),
                                    backgroundColor: Colors.green.shade50,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('فشل الحفظ: الكود موجود مسبقاً أو حدث خطأ'),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
