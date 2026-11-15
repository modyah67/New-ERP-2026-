import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/models/customer_model.dart';
import 'customer_cubit.dart';
import 'customer_state.dart';
import '../../ui/widgets/app_text_field.dart';

class CustomerFormDialog extends StatefulWidget {
  final CustomerModel? customer;
  const CustomerFormDialog({super.key, this.customer});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  late final CustomerCubit _cubit;
  final _scrollCtrl = ScrollController();

  // ── Address controller ──
  final _addressCtrl = TextEditingController();
  bool _addressEditMode = false;
  int? _editingAddressIndex;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<CustomerCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.customer != null) {
        await _cubit.prepareEditForm(widget.customer!);
      } else {
        await _cubit.prepareAddForm();
      }
      if (mounted) {
        _addressCtrl.clear();
        if (_cubit.addresses.isNotEmpty) {
          _addressCtrl.text = _cubit.addresses[0]['address_line_1'] ?? '';
        }
        _addressEditMode = false;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;

    // ── Form Validation Guard: Strict Numerical Boundary Check ──
    final codeText = _cubit.codeController.text.trim();
    final codeValidationError = CustomerModel.validateCustomerCode(codeText);
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
    if (widget.customer == null || widget.customer!.code != codeText) {
      final exists = await CustomerDao().checkCodeExists(codeText, excludeId: widget.customer?.id);
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
                    'كود العميل ($codeText) مستخدم بالفعل، يرجى اختيار كود آخر',
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

    final isExport = _cubit.selectedCustomerType == 'export';
    if (isExport && _addressEditMode && _addressCtrl.text.trim().isNotEmpty) {
      final text = _addressCtrl.text.trim();
      setState(() {
        if (_editingAddressIndex != null) {
          _cubit.updateAddressField(_editingAddressIndex!, 'address_line_1', text);
        } else {
          _cubit.addQuickAddress(text);
        }
        _addressEditMode = false;
        _editingAddressIndex = null;
        _addressCtrl.clear();
      });
    }
    final success = await _cubit.save();
    if (!mounted) return;
    if (success) {
      final messenger = ScaffoldMessenger.of(context);
      final isEditing = widget.customer != null;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                isEditing ? 'تم تعديل العميل بنجاح' : 'تم إضافة العميل بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExport = _cubit.selectedCustomerType == 'export';
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
            width: screenWidth < 500 ? screenWidth * 0.95 : 640,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                  // ── Header ──
                  _buildHeader(isEditing),

                  // ── Scrollable content ──
                  Flexible(
                    child: ListView(
                      controller: _scrollCtrl,
                      padding: EdgeInsets.fromLTRB(screenWidth < 500 ? 16 : 28, 0, screenWidth < 500 ? 16 : 28, 28),
                      children: [
                        const SizedBox(height: 20),

                        // 1️⃣ البيانات الأساسية للعميل
                        _buildMainCustomerInfoSection(isEditing, isExport),
                        const SizedBox(height: 24),

                        // ── الأقسام التفصيلية المخصصة لعملاء التصدير فقط ──
                        if (isExport) ...[
                          // 2️⃣ عناوين العميل الديناميكية (مقرات الشحن والتفريغ)
                          _buildAddressesSection(),
                          const SizedBox(height: 24),

                          // 3️⃣ جهة الاتصال (Contact Person)
                          _buildContactPersonSection(isEditing),
                          const SizedBox(height: 24),

                          // 4️⃣ البيانات الجمركية والضريبية
                          _buildTaxSection(isEditing),
                          const SizedBox(height: 24),
                        ],

                        // 5️⃣ الرصيد المبدئي
                        _sectionLabel('الرصيد المبدئي',
                            Icons.account_balance_wallet_outlined, AppTheme.accent),
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
                        // BlocBuilder<CustomerCubit, CustomerState>(
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
                        //           ],
                        //         ),
                        //       ],
                        //     );
                        //   },
                        // ),
                      ],
                    ),
                  ),

                  // ── Buttons (fixed) ──
                  _buildButtons(isEditing),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ──

  Widget _buildHeader(bool isEditing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 400;
    final primaryColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28, vertical: isMobile ? 12 : 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : AppTheme.lightBorder),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.person_add_outlined,
              color: primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                isEditing ? 'تعديل عميل' : 'إضافة عميل جديد',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 22, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── 1️⃣ MAIN CUSTOMER INFO SECTION ──

  Widget _buildMainCustomerInfoSection(bool isEditing, bool isExport) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('البيانات الأساسية للعميل',
            Icons.business_center_outlined, AppTheme.primary),
        const SizedBox(height: 14),

        Row(
          children: [
            // Code (always read-only)
            Expanded(
              child: AppTextField(
                label: 'كود العميل',
                controller: _cubit.codeController,
                hint: CustomerModel.codeHint,
                readOnly: isEditing,
                isRequired: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => CustomerModel.validateCustomerCode(v),
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: AppTextField(
                label: 'اسم العميل / الشركة',
                controller: _cubit.nameController,
                focusNode: _cubit.nameFocus,
                hint: 'أدخل اسم الشركة أو العميل الكامل',
                isRequired: !isEditing,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                  if (v.trim().length < 2) return 'الاسم قصير جداً';
                  return null;
                },
                onSubmitted: (_) => _cubit.phoneFocus.requestFocus(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            // نوع العميل (Customer Type)
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _cubit.selectedCustomerType,
                dropdownColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0A1E38) : Colors.white,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  labelText: 'نوع العميل *',
                  labelStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                  ),
                  helperText: widget.customer != null ? 'مرتبط بالحساب الماستر' : 'توجيه شجرة الحسابات',
                  helperStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textMuted : AppTheme.lightTextSecondary,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        const Icon(Icons.flight_takeoff, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'عميل تصدير (12511)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'local',
                    child: Row(
                      children: [
                        const Icon(Icons.storefront, size: 18, color: Colors.greenAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'عميل محلي (12512)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: widget.customer != null
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _cubit.selectedCustomerType = v;
                            if (v == 'local') {
                              _cubit.selectedCurrency = 'EGP';
                            }
                          });
                        }
                      },
              ),
            ),
            const SizedBox(width: 12),
            // العملة
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: !isExport ? 'EGP' : _cubit.selectedCurrency,
                dropdownColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0A1E38) : Colors.white,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
                hint: const Text('اختر العملة', style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 13)),
                validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار العملة' : null,
                decoration: InputDecoration(
                  labelText: 'العملة *',
                  labelStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                  ),
                  helperText: widget.customer != null
                      ? 'لا يمكن تغييرها بعد الحفظ'
                      : (!isExport ? 'العميل المحلي يتعامل بالجنيه المصري (EGP) فقط' : null),
                  helperStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textMuted : AppTheme.lightTextSecondary,
                  ),
                ),
                items: [
                  DropdownMenuItem(value: 'EGP', child: Text('جنيه مصري (EGP)', style: TextStyle(fontFamily: 'Cairo', color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary))),
                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (USD)', style: TextStyle(fontFamily: 'Cairo', color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary))),
                  DropdownMenuItem(value: 'EUR', child: Text('يورو (EUR)', style: TextStyle(fontFamily: 'Cairo', color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary))),
                  DropdownMenuItem(value: 'GBP', child: Text('جنيه إسترليني (GBP)', style: TextStyle(fontFamily: 'Cairo', color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppTheme.lightTextPrimary))),
                ],
                onChanged: (widget.customer != null || !isExport)
                    ? null
                    : (v) {
                        if (v != null) setState(() => _cubit.selectedCurrency = v);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            // Phone
            Expanded(
              child: AppTextField(
                label: 'رقم الهاتف الأساسي',
                controller: _cubit.phoneController,
                focusNode: _cubit.phoneFocus,
                hint: 'رقم هاتف المنشأة أو العميل',
                keyboardType: TextInputType.phone,
                onSubmitted: (_) => _cubit.gmailFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 12),
            // Email (Main Company Email)
            Expanded(
              child: AppTextField(
                label: 'البريد الإلكتروني للعميل',
                controller: _cubit.gmailController,
                focusNode: _cubit.gmailFocus,
                hint: 'example@domain.com',
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) {
                  if (isExport) {
                    _cubit.cityFocus.requestFocus();
                  } else {
                    FocusScope.of(context).unfocus();
                  }
                },
              ),
            ),
          ],
        ),

        // بيانات الموقع (المدينة والدولة) - تظهر فقط لعملاء التصدير
        if (isExport) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'المدينة (الرئيسية)',
                  controller: _cubit.cityController,
                  focusNode: _cubit.cityFocus,
                  hint: 'مثال: القاهرة',
                  readOnly: isEditing,
                  isRequired: true,
                  validator: (v) {
                    if (isExport && (v == null || v.trim().isEmpty)) {
                      return 'هذا الحقل مطلوب';
                    }
                    return null;
                  },
                  onSubmitted: (_) => _cubit.countryFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'الدولة (الرئيسية)',
                  controller: _cubit.countryController,
                  focusNode: _cubit.countryFocus,
                  hint: 'مثال: مصر',
                  readOnly: isEditing,
                  isRequired: true,
                  validator: (v) {
                    if (isExport && (v == null || v.trim().isEmpty)) {
                      return 'هذا الحقل مطلوب';
                    }
                    return null;
                  },
                  onSubmitted: (_) => _cubit.contactNameFocus.requestFocus(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── 2️⃣ ADDRESS SECTION ──

  Widget _buildAddressesSection() {
    final hasAddresses = _cubit.addresses.isNotEmpty;
    final isNewCustomer = widget.customer == null;
    final isAddingNew = isNewCustomer && !hasAddresses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('عناوين الشحن والتفريغ',
            Icons.location_on_outlined, AppTheme.accent),
        const SizedBox(height: 12),

        // Show existing addresses as read-only list
        if (hasAddresses)
          ...List.generate(_cubit.addresses.length, (i) {
            final addr = _cubit.addresses[i];
            final addrText = addr['address_line_1']?.toString() ?? '';
            final city = addr['city']?.toString() ?? '';
            final country = addr['country']?.toString() ?? '';
            final fullParts = [addrText, city, country].where((s) => s.isNotEmpty).join(', ');
            if (fullParts.isEmpty && !_addressEditMode) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0x80141A24) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.06) : AppTheme.lightBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (addrText.isNotEmpty)
                            Text(addrText,
                                style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : AppTheme.lightTextPrimary, fontSize: 14, fontFamily: 'Cairo'),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (city.isNotEmpty || country.isNotEmpty)
                            Text([city, country].where((s) => s.isNotEmpty).join(', '),
                                style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textMuted : AppTheme.lightTextSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                    if (isNewCustomer) ...[
                      SizedBox(
                        width: 32, height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary),
                          onPressed: () {
                            _addressCtrl.text = addrText;
                            setState(() {
                              _addressEditMode = true;
                              _editingAddressIndex = i;
                            });
                          },
                          tooltip: 'تعديل العنوان',
                        ),
                      ),
                      SizedBox(
                        width: 32, height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppTheme.danger),
                          onPressed: () {
                            setState(() {
                              _cubit.removeAddress(i);
                              if (_editingAddressIndex == i) {
                                _addressEditMode = false;
                                _addressCtrl.clear();
                              }
                            });
                          },
                          tooltip: 'حذف العنوان',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

        // Add address form (when adding new or editing existing)
        if (_addressEditMode || isAddingNew)
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'تكملة العنوان',
                  controller: _addressCtrl,
                  hint: 'أدخل تكملة العنوان',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.close, size: 20, color: AppTheme.danger),
                  onPressed: () {
                    setState(() {
                      _addressEditMode = false;
                      _editingAddressIndex = null;
                      _addressCtrl.clear();
                    });
                  },
                  tooltip: 'إلغاء',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final text = _addressCtrl.text.trim();
                    if (text.isEmpty) return;
                    setState(() {
                      if (_addressEditMode && _editingAddressIndex != null) {
                        _cubit.updateAddressField(_editingAddressIndex!, 'address_line_1', text);
                      } else {
                        _cubit.addQuickAddress(text);
                      }
                      _addressEditMode = false;
                      _editingAddressIndex = null;
                      _addressCtrl.clear();
                    });
                  },
                  child: const Icon(Icons.check, size: 20),
                ),
              ),
            ],
          ),

        // "إضافة عنوان آخر" button
        if (!_addressEditMode && !isAddingNew)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _addressEditMode = true;
                  _editingAddressIndex = null;
                  _addressCtrl.clear();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline, size: 18, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Text('إضافة عنوان آخر',
                        style: TextStyle(color: AppTheme.primary, fontSize: 13, fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 3️⃣ CONTACT PERSON SECTION ──

  Widget _buildContactPersonSection(bool isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('جهة الاتصال المسؤولة (اختياري)',
            Icons.contact_phone_outlined, Colors.amber),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              // الاسم فقط
              AppTextField(
                label: 'اسم شخص الاتصال',
                controller: _cubit.contactNameController,
                focusNode: _cubit.contactNameFocus,
                hint: 'الاسم الكامل للمندوب / المسؤول',
                onSubmitted: (_) => _cubit.contactPhoneFocus.requestFocus(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // الهاتف
                  Expanded(
                    child: AppTextField(
                      label: 'هاتف شخص الاتصال',
                      controller: _cubit.contactPhoneController,
                      focusNode: _cubit.contactPhoneFocus,
                      hint: '01xxxxxxxxx',
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) =>
                          _cubit.contactEmailFocus.requestFocus(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // البريد الإلكتروني
                  Expanded(
                    child: AppTextField(
                      label: 'البريد الإلكتروني لشخص الاتصال',
                      controller: _cubit.contactEmailController,
                      focusNode: _cubit.contactEmailFocus,
                      hint: 'email@example.com',
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _cubit.vatFocus.requestFocus(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4️⃣ TAX / CUSTOMS SECTION ──

  Widget _buildTaxSection(bool isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('البيانات الجمركية والضريبية (اختياري)',
            Icons.receipt_long_outlined, Colors.purple),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child:               AppTextField(
                label: 'رقم ضريبة القيمة المضافة (VAT NO)',
                controller: _cubit.vatController,
                focusNode: _cubit.vatFocus,
                hint: 'مثال: 123-456-789',
                onSubmitted: (_) => _cubit.eoriFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'رقم السجل الجمركي (EORI NO)',
                controller: _cubit.eoriController,
                focusNode: _cubit.eoriFocus,
                hint: 'مثال: EG123456789000',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── BUTTONS ──

  Widget _buildButtons(bool isEditing) {
    return BlocBuilder<CustomerCubit, CustomerState>(
      builder: (context, state) {
        final formState = _cubit.formState;
        final isSaving = formState.isSaving;
        final isMobile = MediaQuery.of(context).size.width < 400;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 28, vertical: 16),
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
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                    side: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.15) : AppTheme.lightBorder,
                    ),
                    padding:
                        EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child:
                      const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(horizontal: isMobile ? 12 : 28, vertical: 14),
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
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isSaving
                          ? 'جاري الحفظ...'
                          : isEditing
                              ? 'حفظ التعديلات'
                              : 'إضافة العميل',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
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

  // ── SECTION LABEL HELPER ──

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cairo',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
