import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/transport_supplier_model.dart';
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
  bool _isSubmitting = false;

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
    if (_isSubmitting || _cubit.formState.isSaving) return;
    final allowed = await ReadOnlyGuard.checkAsync(context);
    if (!allowed) return;

    setState(() => _isSubmitting = true);

    try {
      // ── Form Validation Guard: Strict Numerical Boundary Check ──
      final codeText = _cubit.codeController.text.trim();
      final selectedType = _cubit.selectedSupplierType;
      final codeValidationError =
          SupplierModel.validateSupplierCode(codeText, selectedType);
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

      // ── Form Validation Guard: Supplier Name Check ──
      final isTransport = selectedType == 'transport';
      final nameText = _cubit.nameController.text.trim();
      final nameValidationError = isTransport
          ? (nameText.isEmpty ? 'اسم مورد النقل مطلوب' : (nameText.length < 2 ? 'اسم المورد قصير جداً' : null))
          : SupplierModel.validateSupplierName(nameText);
      if (nameValidationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nameValidationError,
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
        _cubit.nameFocus.requestFocus();
        return;
      }

      // ── Collision Check Guard ──
      if (widget.supplier == null || widget.supplier!.supplierCode != codeText) {
        bool exists = await SupplierDao().checkCodeExists(codeText, excludeId: widget.supplier?.id);
        if (!exists && _cubit.selectedSupplierType == 'transport') {
          exists = await TransportSupplierDao().checkCodeExists(codeText);
        }
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
                      'كود المورد ($codeText) مستخدم بالفعل، يرجى اختيار كود آخر',
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
                Text('فشل الحفظ: تحقق من صحة البيانات أو أن الكود غير مكرر',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.toString().replaceAll('Exception: ', ''),
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
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplier != null;
    final isTransport = _cubit.selectedSupplierType == 'transport';
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            width: screenWidth < 540 ? screenWidth * 0.95 : 520,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
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
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      children: [
                        const SizedBox(height: 20),
                        _buildSupplierTypeDropdown(isEditing),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: isTransport ? 'كود مورد النقل' : 'كود المورد',
                          controller: _cubit.codeController,
                          hint: isTransport
                              ? TransportSupplierModel.codeHint
                              : SupplierModel.getCategoryRange(_cubit.selectedSupplierType).hint,
                          prefixIcon: Icon(isTransport ? Icons.qr_code : Icons.tag, size: 20, color: AppTheme.primary),
                          readOnly: isEditing,
                          isRequired: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) => isTransport
                              ? TransportSupplierModel.validateTransportCode(v)
                              : SupplierModel.validateSupplierCode(v, _cubit.selectedSupplierType),
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          label: isTransport ? 'اسم مورد النقل / مقاول الشحن' : 'اسم المورد / الشركة',
                          controller: _cubit.nameController,
                          focusNode: _cubit.nameFocus,
                          prefixIcon: Icon(isTransport ? Icons.local_shipping : Icons.business, size: 20, color: AppTheme.primary),
                          hint: isTransport ? 'أدخل اسم مورد النقل أو مقاول الشحن' : 'أدخل اسم المورد أو الشركة',
                          isRequired: true,
                          validator: (v) {
                            if (isTransport) {
                              if (v == null || v.trim().isEmpty) return 'اسم مورد النقل مطلوب';
                              if (v.trim().length < 2) return 'الاسم قصير جداً';
                              return null;
                            }
                            return SupplierModel.validateSupplierName(v);
                          },
                          onSubmitted: (_) => _cubit.phoneFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        if (isTransport) ...[
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  label: 'رقم الهاتف',
                                  controller: _cubit.phoneController,
                                  focusNode: _cubit.phoneFocus,
                                  hint: '01xxxxxxxxx',
                                  keyboardType: TextInputType.phone,
                                  prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppTheme.primary),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: AppTextField(
                                  label: 'البريد الإلكتروني',
                                  controller: _cubit.emailController,
                                  hint: 'example@domain.com',
                                  keyboardType: TextInputType.emailAddress,
                                  prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppTheme.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildTransportInitialBalanceSection(),
                          const SizedBox(height: 14),
                          AppTextField(
                            controller: _cubit.notesController,
                            label: 'ملاحظات',
                            prefixIcon: const Icon(Icons.notes_outlined, size: 20, color: AppTheme.primary),
                            maxLines: 2,
                          ),
                        ] else ...[
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
                          _buildCurrencySection(),
                          const SizedBox(height: 14),
                          if (_cubit.isMultiCurrency) ...[
                            _buildMultiCurrencyInitialBalancesSection(),
                          ] else ...[
                            _buildSingleCurrencyInitialBalanceSection(),
                          ],
                        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTransport = _cubit.selectedSupplierType == 'transport';
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
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing
                  ? Icons.edit_outlined
                  : (isTransport ? Icons.local_shipping : Icons.business),
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
                isEditing
                    ? (isTransport ? 'تعديل بيانات مورد النقل' : 'تعديل مورد')
                    : (isTransport ? 'إضافة مورد نقل جديد' : 'إضافة مورد جديد'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
          BlocBuilder<SupplierCubit, SupplierState>(
            builder: (context, state) {
              final formState = _cubit.formState;
              final isSaving = formState.isSaving || _isSubmitting;
              if (isSaving) {
                return const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppTheme.primary),
                );
              }
              return IconButton(
                icon: Icon(Icons.close, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary, size: 22),
                onPressed: () => Navigator.pop(context),
                tooltip: 'إغلاق',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierTypeDropdown(bool isEditing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const types = [
      {
        'value': 'crop',
        'label': 'موردين المحاصيل (50000 - 59999)',
        'icon': Icons.eco_outlined,
        'color': Color(0xFF10B981),
      },
      {
        'value': 'packaging',
        'label': 'موردين مواد التعبئة والتغليف (70000 - 74999)',
        'icon': Icons.inventory_2_outlined,
        'color': Color(0xFF38BDF8),
      },
      {
        'value': 'shared',
        'label': 'الموردين المشتركين - محاصيل وتعبئة (75000 - 79999)',
        'icon': Icons.all_inclusive_outlined,
        'color': Color(0xFFF59E0B),
      },
      {
        'value': 'transport',
        'label': 'موردين النقل ومقاولي الشحن (60000 - 69999)',
        'icon': Icons.local_shipping_outlined,
        'color': Color(0xFF6366F1),
      },
    ];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _cubit.selectedSupplierType,
      dropdownColor: isDark ? const Color(0xFF0A1E35) : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 13),
      hint: Text('اختر تصنيف المورد', style: TextStyle(color: isDark ? Colors.grey : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 13)),
      validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار تصنيف المورد' : null,
      decoration: InputDecoration(
        labelText: 'تصنيف المورد *',
        labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 13),
        prefixIcon: const Icon(Icons.category_outlined, color: AppTheme.primary, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
      ),
      selectedItemBuilder: (context) {
        return types.map((t) {
          return Row(
            children: [
              Icon(t['icon'] as IconData, size: 18, color: t['color'] as Color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t['label'] as String,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }).toList();
      },
      items: types.map((t) => DropdownMenuItem<String>(
        value: t['value'] as String,
        child: Row(
          children: [
            Icon(t['icon'] as IconData, size: 18, color: t['color'] as Color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t['label'] as String,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      )).toList(),
      onChanged: isEditing ? null : (v) async {
        if (v != null) {
          await _cubit.onSupplierTypeChanged(v);
          if (mounted) setState(() {});
        }
      },
    );
  }

  Widget _buildTransportInitialBalanceSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withValues(alpha: 0.05),
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
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
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
                          fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontSize: 13),
                      items: const [
                        DropdownMenuItem(
                          value: 'CREDIT',
                          child: Text('دائن (له مستحقات)',
                              style: TextStyle(color: AppTheme.warning)),
                        ),
                        DropdownMenuItem(
                          value: 'DEBIT',
                          child: Text('مدين (عليه مقدمات)',
                              style: TextStyle(color: AppTheme.accent)),
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

  Widget _buildSingleCurrencyInitialBalanceSection() {
    final currency = _cubit.selectedCurrency ?? 'EGP';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'الرصيد المبدئي ($currency)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  label: 'مبلغ الرصيد المبدئي ($currency)',
                  controller: _cubit.initialBalanceController,
                  focusNode: _cubit.initialBalanceFocus,
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  isRequired: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty && double.tryParse(v.trim()) == null) {
                      return 'يرجى إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طبيعة الرصيد *',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
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
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            fontSize: 13,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'CREDIT',
                              child: Text('دائن (له مستحقات)',
                                  style: TextStyle(color: AppTheme.warning)),
                            ),
                            DropdownMenuItem(
                              value: 'DEBIT',
                              child: Text('مدين (عليه مقدمات)',
                                  style: TextStyle(color: AppTheme.accent)),
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
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMultiCurrencyInitialBalancesSection() {
    final supportedCurrencies = _cubit.selectedSupportedCurrencies;
    final totalEgp = _cubit.totalMultiCurrencyInitialBalanceEgp;
    final isCredit = totalEgp >= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1928) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.accent.withValues(alpha: 0.35) : AppTheme.lightBorder,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance, size: 18, color: AppTheme.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأرصدة الافتتاحية بالعملات المحددة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'سجل الرصيد الافتتاحي لكل عملة مع تحديد سعر الصرف مقابل الجنيه المصري',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live Total Preview Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isCredit
                    ? [
                        AppTheme.warning.withValues(alpha: 0.12),
                        isDark ? const Color(0xFF0A233A) : AppTheme.warning.withValues(alpha: 0.04),
                      ]
                    : [
                        AppTheme.accent.withValues(alpha: 0.12),
                        isDark ? const Color(0xFF0A233A) : AppTheme.accent.withValues(alpha: 0.04),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCredit
                    ? AppTheme.warning.withValues(alpha: 0.35)
                    : AppTheme.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCredit ? Icons.trending_up : Icons.trending_down,
                  color: isCredit ? AppTheme.warning : AppTheme.accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إجمالي الرصيد الافتتاحي المجمّع (معادل بالجنية المصري):',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${totalEgp.abs().toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCredit ? AppTheme.warning : AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isCredit ? AppTheme.warning : AppTheme.accent)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCredit ? 'صافي دائن (له)' : 'صافي مدين (عليه)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCredit ? AppTheme.warning : AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Cards per currency
          ...supportedCurrencies.map((currency) {
            final item = _cubit.currencyBalanceItems[currency];
            if (item == null) return const SizedBox.shrink();
            return _buildCurrencyBalanceCard(currency, item);
          }),
        ],
      ),
    );
  }

  Widget _buildCurrencyBalanceCard(String currency, CurrencyBalanceFormItem item) {
    final isEgp = currency == 'EGP';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Currency visual styling
    Color curColor;
    IconData curIcon;
    String curLabel;
    switch (currency) {
      case 'USD':
        curColor = const Color(0xFF38BDF8);
        curIcon = Icons.attach_money;
        curLabel = 'دولار أمريكي (USD)';
        break;
      case 'EUR':
        curColor = const Color(0xFFF59E0B);
        curIcon = Icons.euro;
        curLabel = 'يورو أوروبي (EUR)';
        break;
      case 'GBP':
        curColor = const Color(0xFFA855F7);
        curIcon = Icons.currency_pound;
        curLabel = 'جنيه إسترليني (GBP)';
        break;
      case 'EGP':
      default:
        curColor = const Color(0xFF10B981);
        curIcon = Icons.payments_outlined;
        curLabel = 'جنيه مصري (EGP - عملة الأساس)';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F243A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.amount > 0
              ? curColor.withValues(alpha: 0.4)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of the currency card
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: curColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(curIcon, size: 16, color: curColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  curLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: curColor,
                  ),
                ),
              ),
              // Live calculated converted preview badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Text(
                  'المعادل: ${(item.amountInEgp).toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 1: Amount + Direction
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  label: 'الرصيد الافتتاحي بالعملة ($currency)',
                  controller: item.amountController,
                  hint: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طبيعة الرصيد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF071828) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: item.direction,
                          isExpanded: true,
                          dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            fontSize: 12,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'CREDIT',
                              child: Text('دائن (له)',
                                  style: TextStyle(color: AppTheme.warning)),
                            ),
                            DropdownMenuItem(
                              value: 'DEBIT',
                              child: Text('مدين (عليه)',
                                  style: TextStyle(color: AppTheme.accent)),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                item.direction = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Exchange Rate to EGP (with sync/refresh icon button)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: isEgp
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : AppTheme.lightBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'سعر الصرف ثابت: 1.00 (عملة الأساس المحلية)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: 'سعر الصرف مقابل الجنيه المصري (EGP)',
                              controller: item.exchangeRateController,
                              hint: '50.00',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                              ],
                              onChanged: (_) => setState(() {}),
                              prefixIcon: const Icon(Icons.currency_exchange, size: 16, color: AppTheme.accent),
                              suffixIcon: IconButton(
                                icon: item.isFetchingRate
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                                      )
                                    : const Icon(Icons.sync, size: 18, color: AppTheme.accent),
                                tooltip: 'مزامنة مع أحدث سعر صرف من قاعدة البيانات',
                                onPressed: item.isFetchingRate
                                    ? null
                                    : () async {
                                        await _cubit.refreshRateForCurrency(currency);
                                        if (mounted) setState(() {});
                                      },
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencySection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const allCurrencies = [
      {'code': 'EGP', 'label': 'جنيه مصري', 'symbol': 'ج.م'},
      {'code': 'USD', 'label': 'دولار أمريكي', 'symbol': '\$'},
      {'code': 'EUR', 'label': 'يورو', 'symbol': '€'},
      {'code': 'GBP', 'label': 'جنيه إسترليني', 'symbol': '£'},
    ];

    final isShared = _cubit.selectedSupplierType == 'shared';
    final isCrop = _cubit.selectedSupplierType == 'crop';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _cubit.isMultiCurrency
              ? AppTheme.accent.withValues(alpha: 0.4)
              : (isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Switch header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (_cubit.isMultiCurrency ? AppTheme.accent : AppTheme.primary)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.currency_exchange,
                  size: 18,
                  color: _cubit.isMultiCurrency ? AppTheme.accent : AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'نظام العملات المتعددة (Multi-Currency)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    Text(
                      _cubit.isMultiCurrency
                          ? 'يتيح إصدار فواتير ومعاملات للمورد بأي من العملات المحددة'
                          : 'المورد يتعامل بعملة واحدة أساسية محددة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _cubit.isMultiCurrency,
                activeColor: AppTheme.accent,
                onChanged: (val) {
                  setState(() {
                    _cubit.isMultiCurrency = val;
                    if (val) {
                      _cubit.selectedCurrency = 'MULTI';
                      _cubit.syncCurrencyBalanceItems();
                    } else {
                      _cubit.selectedCurrency = _cubit.selectedSupportedCurrencies.isNotEmpty
                          ? _cubit.selectedSupportedCurrencies.first
                          : 'EGP';
                    }
                  });
                },
              ),
            ],
          ),

          if (_cubit.isMultiCurrency) ...[
            const SizedBox(height: 12),
            Divider(color: isDark ? Colors.white10 : AppTheme.lightBorder, height: 1),
            const SizedBox(height: 10),
            Text(
              'العملات المعتمدة للتعامل مع هذا المورد:',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allCurrencies.map((c) {
                final code = c['code']!;
                final isSelected = _cubit.selectedSupportedCurrencies.contains(code);
                return FilterChip(
                  label: Text(
                    '${c['symbol']} ${c['label']} ($code)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? (isDark ? Colors.white : AppTheme.primary) : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppTheme.primary.withValues(alpha: isDark ? 0.35 : 0.15),
                  backgroundColor: isDark ? const Color(0xFF0F2338) : Colors.white,
                  checkmarkColor: isDark ? Colors.white : AppTheme.primary,
                  side: BorderSide(
                    color: isSelected ? AppTheme.primary : (isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _cubit.toggleSupportedCurrency(code);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Stream Defaults Mapping
            if (isShared) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune, size: 16, color: Color(0xFFF59E0B)),
                        SizedBox(width: 6),
                        Text(
                          'تخصيص العملة الافتراضية لكل تدفق شراء:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _cubit.selectedSupportedCurrencies.contains(_cubit.selectedCropCurrency)
                                ? _cubit.selectedCropCurrency
                                : _cubit.selectedSupportedCurrencies.first,
                            dropdownColor: isDark ? const Color(0xFF0A1E35) : Colors.white,
                            style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'عملة المحاصيل الخام',
                              labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 11),
                              prefixIcon: const Icon(Icons.eco_outlined, size: 16, color: Color(0xFF10B981)),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                            ),
                            items: _cubit.selectedSupportedCurrencies.map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary), overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _cubit.selectedCropCurrency = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _cubit.selectedSupportedCurrencies.contains(_cubit.selectedPackagingCurrency)
                                ? _cubit.selectedPackagingCurrency
                                : _cubit.selectedSupportedCurrencies.first,
                            dropdownColor: isDark ? const Color(0xFF0A1E35) : Colors.white,
                            style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'عملة مواد التعبئة',
                              labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 11),
                              prefixIcon: const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF38BDF8)),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                            ),
                            items: _cubit.selectedSupportedCurrencies.map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary), overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _cubit.selectedPackagingCurrency = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Standard supplier (crop, packaging, etc.) with multi-currency enabled
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _cubit.selectedSupportedCurrencies.contains(isCrop ? _cubit.selectedCropCurrency : _cubit.selectedPackagingCurrency)
                    ? (isCrop ? _cubit.selectedCropCurrency : _cubit.selectedPackagingCurrency)
                    : _cubit.selectedSupportedCurrencies.first,
                dropdownColor: isDark ? const Color(0xFF0A1E35) : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 12),
                decoration: InputDecoration(
                  labelText: isCrop ? 'العملة الافتراضية لفواتير المحاصيل' : 'العملة الافتراضية لفواتير التعبئة',
                  labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo', fontSize: 11),
                  prefixIcon: Icon(
                    isCrop ? Icons.eco_outlined : Icons.inventory_2_outlined,
                    size: 16,
                    color: isCrop ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                  ),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                ),
                items: _cubit.selectedSupportedCurrencies.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text('$c (افتراضي)', style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary), overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      if (isCrop) {
                        _cubit.selectedCropCurrency = val;
                      } else {
                        _cubit.selectedPackagingCurrency = val;
                      }
                    });
                  }
                },
              ),
            ],
          ] else ...[
            // Single currency mode
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: (_cubit.selectedCurrency == null || _cubit.selectedCurrency == 'MULTI')
                  ? 'EGP'
                  : _cubit.selectedCurrency,
              dropdownColor: isDark ? const Color(0xFF0A1E35) : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'العملة الأساسية للمورد *',
                labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, fontFamily: 'Cairo'),
                prefixIcon: const Icon(Icons.attach_money, color: AppTheme.primary, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder)),
              ),
              items: allCurrencies.map((c) => DropdownMenuItem(
                value: c['code'],
                child: Text('${c['symbol']} ${c['label']} (${c['code']})', style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _cubit.selectedCurrency = v);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons(bool isEditing) {
    return BlocBuilder<SupplierCubit, SupplierState>(
      builder: (context, state) {
        final formState = _cubit.formState;
        final isSaving = formState.isSaving || _isSubmitting;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                  side: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.15) : AppTheme.lightBorder,
                  ),
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
                  onPressed: (isSaving || ReadOnlyGuard.isReadOnly) ? null : _save,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
