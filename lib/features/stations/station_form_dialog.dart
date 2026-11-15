import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/station_dao.dart';
import '../../data/models/station_model.dart';
import 'station_cubit.dart';
import 'station_state.dart';

class StationFormDialog extends StatefulWidget {
  final StationModel? station;
  const StationFormDialog({super.key, this.station});

  @override
  State<StationFormDialog> createState() => _StationFormDialogState();
}

class _StationFormDialogState extends State<StationFormDialog> {
  late final StationCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<StationCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.station != null) {
        await _cubit.prepareEditForm(widget.station!);
      } else {
        await _cubit.prepareAddForm();
      }
    });
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;

    // ── Form Validation Guard: Strict Numerical Boundary Check ──
    final codeText = _cubit.codeController.text.trim();
    final codeValidationError = StationModel.validateStationCode(codeText);
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
    if (widget.station == null || widget.station!.code != codeText) {
      final exists = await StationDao().checkCodeExists(codeText, excludeId: widget.station?.id);
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
                    'كود المحطة ($codeText) مستخدم بالفعل، يرجى اختيار كود آخر',
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                widget.station != null ? 'تم تعديل المحطة بنجاح' : 'تم إضافة المحطة بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('فشل الحفظ: تحقق من صحة البيانات', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
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
    final isEditing = widget.station != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = ThemeCubit.isCurrentDark;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
      ),
      child: BlocBuilder<StationCubit, StationState>(
        builder: (context, state) {
          return Container(
            width: screenWidth < 500 ? screenWidth * 0.90 : 450,
            padding: EdgeInsets.all(screenWidth < 500 ? 16 : 24),
            child: Form(
              key: _cubit.formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEditing ? Icons.edit_outlined : Icons.add_location_alt_outlined,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            isEditing ? 'تعديل المحطة' : 'إضافة محطة جديدة',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _cubit.codeController,
                    validator: (v) => StationModel.validateStationCode(v),
                    decoration: InputDecoration(
                      labelText: 'كود المحطة',
                      hintText: StationModel.codeHint,
                      labelStyle: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                      hintStyle: TextStyle(
                        color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.5) : const Color(0xFF64748B),
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      ),
                      enabled: false,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cubit.nameController,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'اسم المحطة مطلوب';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'اسم المحطة *',
                      hintText: 'مثال: المحطة الرئيسية',
                      labelStyle: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                      hintStyle: TextStyle(
                        color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.5) : const Color(0xFF64748B),
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0x3805192D) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? AppTheme.textSecondary : Colors.black,
                            side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: state is StationFormState && state.isSaving ? null : () => Navigator.pop(context),
                          child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: state is StationFormState && state.isSaving ? null : _save,
                          icon: state is StationFormState && state.isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(isEditing ? Icons.save_outlined : Icons.add, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              state is StationFormState && state.isSaving ? 'جاري الحفظ...' : isEditing ? 'حفظ التعديلات' : 'إضافة المحطة',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}