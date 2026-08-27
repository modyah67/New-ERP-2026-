import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/clearing_agent_model.dart';
import 'clearing_agent_cubit.dart';
import 'clearing_agent_state.dart';
import '../../ui/widgets/app_text_field.dart';

class ClearingAgentFormDialog extends StatefulWidget {
  final ClearingAgentModel? agent;
  const ClearingAgentFormDialog({super.key, this.agent});

  @override
  State<ClearingAgentFormDialog> createState() => _ClearingAgentFormDialogState();
}

class _ClearingAgentFormDialogState extends State<ClearingAgentFormDialog> {
  late final ClearingAgentCubit _cubit;
  final _scrollCtrl = ScrollController();
  final _addressCtrl = TextEditingController();
  bool _addressEditMode = false;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<ClearingAgentCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.agent != null) {
        await _cubit.prepareEditForm(widget.agent!);
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

  void _saveAddress() {
    final text = _addressCtrl.text.trim();
    setState(() {
      _cubit.setSingleAddress(text);
      _addressEditMode = false;
    });
  }

  void _deleteAddress() {
    setState(() {
      _addressCtrl.clear();
      _cubit.setSingleAddress('');
      _addressEditMode = false;
    });
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    final addrText = _addressCtrl.text.trim();
    if (addrText.isNotEmpty || _cubit.addresses.isEmpty) {
      _cubit.setSingleAddress(addrText);
    }
    final success = await _cubit.save();
    if (!mounted) return;
    if (success) {
      final messenger = ScaffoldMessenger.of(context);
      final isEditing = widget.agent != null;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                isEditing ? 'تم تعديل المخلص بنجاح' : 'تم إضافة المخلص بنجاح',
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
    final isEditing = widget.agent != null;
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
            width: screenWidth < 500 ? screenWidth * 0.95 : 640,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
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
                      padding: EdgeInsets.fromLTRB(screenWidth < 500 ? 16 : 28, 0, screenWidth < 500 ? 16 : 28, 28),
                      children: [
                        const SizedBox(height: 20),
                        _buildBrokerTypeSection(),
                        const SizedBox(height: 24),
                        _buildMainInfoSection(),
                        const SizedBox(height: 24),
                        _buildAddressSection(),
                        const SizedBox(height: 24),
                        _buildContactPersonSection(),
                        const SizedBox(height: 24),
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
                            if (v == null || v.trim().isEmpty) return 'الرصيد المبدئي مطلوب';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        // BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
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

  // ── HEADER ──

  Widget _buildHeader(bool isEditing) {
    final isMobile = MediaQuery.of(context).size.width < 400;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28, vertical: isMobile ? 12 : 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.person_add_outlined,
              color: AppTheme.primary, size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                isEditing ? 'تعديل مخلص' : 'إضافة مخلص جديد',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
              ),
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

  // ── BROKER TYPE ──

  Widget _buildBrokerTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('نوع المخلص', Icons.category_outlined, AppTheme.accent),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildBrokerTypeOption('بحري', Icons.sailing_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBrokerTypeOption('جوي', Icons.flight_outlined),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrokerTypeOption(String type, IconData icon) {
    final isSelected = _cubit.brokerType == type;
    return GestureDetector(
      onTap: () => setState(() => _cubit.brokerType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(type,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Cairo',
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── MAIN INFO ──

  Widget _buildMainInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('البيانات الأساسية', Icons.business_center_outlined, AppTheme.primary),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: AppTextField(
              label: 'كود المخلص', 
              controller: _cubit.codeController, 
              hint: '0001', 
              readOnly: widget.agent != null,
              isRequired: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'كود المخلص مطلوب';
                return null;
              },
            )),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'اسم المخلص / الشركة', controller: _cubit.nameController,
                focusNode: _cubit.nameFocus, hint: 'أدخل اسم المخلص',
                isRequired: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
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
                label: 'رقم الهاتف', controller: _cubit.phoneController,
                focusNode: _cubit.phoneFocus, hint: 'رقم الهاتف',
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'البريد الإلكتروني', controller: _cubit.gmailController,
                focusNode: _cubit.gmailFocus, hint: 'example@domain.com',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'المدينة', controller: _cubit.cityController, focusNode: _cubit.cityFocus, hint: 'مثال: القاهرة', readOnly: widget.agent != null)),
            const SizedBox(width: 12),
            Expanded(child: AppTextField(label: 'الدولة', controller: _cubit.countryController, focusNode: _cubit.countryFocus, hint: 'مثال: مصر', readOnly: widget.agent != null)),
          ],
        ),
      ],
    );
  }

  // ── ADDRESS ──

  Widget _buildAddressSection() {
    final hasAddress = _cubit.addresses.isNotEmpty;
    final addressText = hasAddress ? (_cubit.addresses[0]['address_line_1'] ?? '') : '';
    final isCreating = widget.agent == null;
    final isEditingAddr = isCreating && (!hasAddress || _addressEditMode);

    if (!_addressEditMode && hasAddress && _addressCtrl.text.isEmpty) {
      _addressCtrl.text = addressText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('تكملة العنوان', Icons.location_on_outlined, AppTheme.accent),
        const SizedBox(height: 12),
        if (isEditingAddr)
          Row(
            children: [
              Expanded(child: AppTextField(label: 'تكملة العنوان', controller: _addressCtrl, hint: 'أدخل تكملة العنوان')),
              if (hasAddress) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                    onPressed: _deleteAddress,
                    tooltip: 'حذف العنوان',
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saveAddress,
                  child: const Icon(Icons.check, size: 20),
                ),
              ),
            ],
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x80141A24),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(addressText, style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis)),
                if (isCreating) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 32, height: 32, child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary),
                    onPressed: () => setState(() => _addressEditMode = true),
                    tooltip: 'تعديل العنوان',
                  )),
                  SizedBox(width: 32, height: 32, child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppTheme.danger),
                    onPressed: _deleteAddress,
                    tooltip: 'حذف العنوان',
                  )),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ── CONTACT PERSON ──

  Widget _buildContactPersonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('جهة الاتصال المسؤولة (اختياري)', Icons.contact_phone_outlined, Colors.amber),
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
              AppTextField(
                label: 'اسم شخص الاتصال', controller: _cubit.contactNameController,
                focusNode: _cubit.contactNameFocus, hint: 'الاسم الكامل للمندوب / المسؤول',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: AppTextField(label: 'هاتف شخص الاتصال', controller: _cubit.contactPhoneController, focusNode: _cubit.contactPhoneFocus, hint: '01xxxxxxxxx', keyboardType: TextInputType.phone)),
                  const SizedBox(width: 12),
                  Expanded(child: AppTextField(label: 'البريد الإلكتروني لشخص الاتصال', controller: _cubit.contactEmailController, focusNode: _cubit.contactEmailFocus, hint: 'email@example.com', keyboardType: TextInputType.emailAddress)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── BUTTONS ──

  Widget _buildButtons(bool isEditing) {
    return BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
      builder: (context, state) {
        final isSaving = _cubit.formState.isSaving;
        final isMobile = MediaQuery.of(context).size.width < 400;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 28, vertical: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                  icon: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(isEditing ? Icons.save_outlined : Icons.add, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isSaving ? 'جاري الحفظ...' : isEditing ? 'حفظ التعديلات' : 'إضافة المخلص',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
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

  // ── SECTION LABEL ──

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 4, height: 20,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
