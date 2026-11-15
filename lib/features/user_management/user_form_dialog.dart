import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../data/models/user_model.dart';
import 'user_management_cubit.dart';
import 'user_management_state.dart';

class UserFormDialog extends StatefulWidget {
  final UserModel? user;
  const UserFormDialog({super.key, this.user});

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.user != null;
    _nameCtrl = TextEditingController(text: widget.user?.fullName ?? '');
    _emailCtrl = TextEditingController(text: widget.user?.email ?? '');
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final dialogBg = AppTheme.getCardBg(context);
    final fieldFill = isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9);
    final borderColor = AppTheme.getBorderColor(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);

    final fieldStyle = TextStyle(color: textPrimary, fontFamily: 'Cairo');
    final labelStyle = TextStyle(color: textSecondary, fontFamily: 'Cairo');
    final borderSide = BorderSide(color: borderColor);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: borderSide,
    );

    return AlertDialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor),
      ),
      title: Text(
        _isEdit ? 'تعديل المستخدم' : 'إضافة موظف جديد',
        style: TextStyle(color: textPrimary, fontFamily: 'Cairo'),
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'الاسم الكامل',
                  labelStyle: labelStyle,
                  filled: true,
                  fillColor: fieldFill,
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                ),
                style: fieldStyle,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                enabled: !_isEdit,
                decoration: InputDecoration(
                  labelText: 'البريد الإلكتروني (لتسجيل الدخول)',
                  labelStyle: labelStyle,
                  filled: true,
                  fillColor: fieldFill,
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                ),
                style: fieldStyle,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'البريد الإلكتروني مطلوب';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) {
                    return 'البريد الإلكتروني غير صالح';
                  }
                  return null;
                },
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    labelStyle: labelStyle,
                    filled: true,
                    fillColor: fieldFill,
                    border: fieldBorder,
                    enabledBorder: fieldBorder,
                  ),
                  style: fieldStyle,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'كلمة المرور مطلوبة';
                    }
                    if (v.length < 8) {
                      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء',
              style: TextStyle(color: textSecondary)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            _isEdit ? 'حفظ' : 'إضافة',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final cubit = context.read<UserManagementCubit>();
    final state = cubit.state;

    if (!_isEdit && state is UserManagementLoaded) {
      final email = _emailCtrl.text.trim();
      final exists = state.users.any((u) => u.email?.toLowerCase() == email.toLowerCase());
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هذا البريد الإلكتروني مسجل بالفعل', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    if (_isEdit) {
      cubit.updateUser(
        userId: widget.user!.id!,
        fullName: _nameCtrl.text.trim(),
      );
    } else {
      cubit.createEmployee(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text.trim(),
      );
    }

    Navigator.pop(context);
  }
}
