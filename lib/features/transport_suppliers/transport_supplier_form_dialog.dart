import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/transport_supplier_model.dart';
import 'transport_supplier_cubit.dart';
import '../../ui/widgets/app_text_field.dart';

class TransportSupplierFormDialog extends StatefulWidget {
  final TransportSupplierModel? supplier;
  const TransportSupplierFormDialog({super.key, this.supplier});

  @override
  State<TransportSupplierFormDialog> createState() =>
      _TransportSupplierFormDialogState();
}

class _TransportSupplierFormDialogState
    extends State<TransportSupplierFormDialog> {
  late final TransportSupplierCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<TransportSupplierCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.supplier != null) {
        await _cubit.prepareEditForm(widget.supplier!);
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
        TransportSupplierModel.validateTransportCode(codeText);
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
    if (widget.supplier == null || widget.supplier!.code != codeText) {
      final exists = await TransportSupplierDao().checkCodeExists(codeText, excludeId: widget.supplier?.id);
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
                    'كود مورد النقل ($codeText) مستخدم بالفعل، يرجى اختيار كود آخر',
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

    final success = await _cubit.saveSupplier();
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
                widget.supplier != null
                    ? 'تم تعديل مورد النقل بنجاح'
                    : 'تم إضافة مورد النقل بنجاح',
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
    final isEditing = widget.supplier != null;
    final isDark = ThemeCubit.isCurrentDark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 540 ? screenWidth * 0.95 : 520,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.90),
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        AppTextField(
                          controller: _cubit.codeController,
                          label: 'كود المورد',
                          prefixIcon: const Icon(Icons.qr_code, size: 20, color: AppTheme.primary),
                          hint: TransportSupplierModel.codeHint,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) => TransportSupplierModel.validateTransportCode(v),
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          controller: _cubit.nameController,
                          label: 'اسم مورد النقل / مقاول الشحن',
                          prefixIcon: const Icon(Icons.local_shipping, size: 20, color: AppTheme.primary),
                          isRequired: true,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'يرجى إدخال اسم المورد';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _cubit.phoneController,
                                label: 'رقم الهاتف',
                                prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppTheme.primary),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: AppTextField(
                                controller: _cubit.emailController,
                                label: 'البريد الإلكتروني',
                                prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppTheme.primary),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildInitialBalanceSection(),
                        const SizedBox(height: 18),
                        AppTextField(
                          controller: _cubit.notesController,
                          label: 'ملاحظات',
                          prefixIcon: const Icon(Icons.notes_outlined, size: 20, color: AppTheme.primary),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 28),
                        _buildActionButtons(isEditing),
                      ],
                    ),
                  ),
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
    final primaryColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return Container(
      padding: const EdgeInsets.all(20),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withValues(alpha: isDark ? 0.2 : 0.15),
                  primaryColor.withValues(alpha: isDark ? 0.08 : 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: primaryColor.withValues(alpha: isDark ? 0.4 : 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.local_shipping,
              color: primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing
                      ? 'تعديل بيانات مورد النقل'
                      : 'إضافة مورد نقل جديد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isEditing
                      ? 'تحديث بيانات مقاول الشحن والنقل'
                      : 'تسجيل مقاول نقل وربطه بشجرة الحسابات تلقائياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
            hoverColor: isDark ? Colors.white10 : Colors.black12,
          ),
        ],
      ),
    );
  }

  Widget _buildInitialBalanceSection() {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الرصيد الافتتاحي (ج.م)',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: _cubit.initialBalanceController,
                  label: 'المبلغ المالي الافتتاحي (ج.م)',
                  hint: '0.00',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppTheme.primary),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F2338) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _cubit.initialBalanceDirection,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
                      style: TextStyle(
                          fontFamily: 'Cairo', color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
                      items: [
                        DropdownMenuItem(
                          value: 'CREDIT',
                          child: Text('دائن (له مستحقات)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isDark ? AppTheme.warning : const Color(0xFFD97706), fontWeight: FontWeight.bold)),
                        ),
                        DropdownMenuItem(
                          value: 'DEBIT',
                          child: Text('مدين (عليه مقدمات)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isDark ? AppTheme.accent : const Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _cubit.initialBalanceDirection = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _cubit.initialTruckBalanceController,
            label: 'مخزون النقلات الافتتاحي (عدد النقلات المتاحة مسبقاً)',
            hint: 'مثال: 5 أو 0.5',
            prefixIcon: const Icon(Icons.local_shipping_outlined, size: 20, color: Color(0xFF00B4D8)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isEditing) {
    final isDark = ThemeCubit.isCurrentDark;
    final primaryColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'إلغاء',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
            shadowColor: primaryColor.withAlpha(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isEditing ? Icons.save : Icons.add, size: 18),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'حفظ التعديلات' : 'إضافة المورد',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
