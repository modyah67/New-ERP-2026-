import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_model.dart';
import '../../ui/widgets/app_text_field.dart';

class FruitTypeFormDialog extends StatefulWidget {
  final FruitTypeModel? item;
  const FruitTypeFormDialog({super.key, this.item});

  @override
  State<FruitTypeFormDialog> createState() => _FruitTypeFormDialogState();
}

class _FruitTypeFormDialogState extends State<FruitTypeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dao = FruitTypeDao();
  final _scrollCtrl = ScrollController();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;

  late final FocusNode _nameFocus;
  String? _currency;
  String? _purchaseMode;

  bool _saving = false;

  static const _currencies = ['EGP', 'USD', 'EUR', 'GBP'];
  static const _currencyLabels = {
    'EGP': 'جنيه مصري',
    'USD': 'دولار',
    'EUR': 'يورو',
    'GBP': 'جنيه إسترليني',
  };

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _nameController = TextEditingController();
    _nameFocus = FocusNode();

    if (widget.item != null) {
      final item = widget.item!;
      _codeController.text = item.code;
      _nameController.text = item.name;
      _currency = item.currency;
      _purchaseMode = item.purchaseMode;
    } else {
      _generateCode();
    }
  }

  Future<void> _generateCode() async {
    final code = await _dao.generateCode();
    if (mounted) {
      setState(() => _codeController.text = code);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_currency == null || _currency!.isEmpty) return;
    if (_purchaseMode == null || _purchaseMode!.isEmpty) return;
    setState(() => _saving = true);

    try {
      final item = FruitTypeModel(
        id: widget.item?.id,
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        color: null,
        sortOrder: widget.item?.sortOrder ?? 0,
        isActive: widget.item?.isActive ?? true,
        currency: _currency!,
        purchaseMode: _purchaseMode,
      );

      if (widget.item != null) {
        await _dao.update(item);
      } else {
        await _dao.insert(item);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                widget.item != null ? 'تم تعديل صنف الفاكهة بنجاح' : 'تم إضافة صنف الفاكهة بنجاح',
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
    final isEditing = widget.item != null;
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
            width: screenWidth < 500 ? screenWidth * 0.95 : 520,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            decoration: const BoxDecoration(
              color: Color(0xB305192D),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(isEditing),
                    Flexible(
                      child: ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  label: 'كود الصنف',
                                  controller: _codeController,
                                  hint: '1',
                                  isRequired: true,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'كود الصنف مطلوب';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppTextField(
                                  label: 'اسم الصنف',
                                  controller: _nameController,
                                  focusNode: _nameFocus,
                                  hint: 'أدخل اسم الصنف',
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
                          const Text('العملة *', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _currency,
                            isExpanded: true,
                            validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار العملة' : null,
                            decoration: InputDecoration(
                              hintText: 'اختر العملة',
                              hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accent)),
                            ),
                            items: _currencies.map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(_currencyLabels[c] ?? c, style: const TextStyle(fontFamily: 'Cairo')),
                            )).toList(),
                            onChanged: (v) { setState(() => _currency = v); },
                          ),
                          const SizedBox(height: 14),
                          const Text('طريقة الشراء *', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _purchaseMode,
                            isExpanded: true,
                            validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار طريقة الشراء' : null,
                            decoration: InputDecoration(
                              hintText: 'اختر طريقة الشراء',
                              hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accent)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'weight', child: Text('الوزن', style: TextStyle(fontFamily: 'Cairo'))),
                              DropdownMenuItem(value: 'carton', child: Text('الكراتين', style: TextStyle(fontFamily: 'Cairo'))),
                            ],
                            onChanged: (v) { setState(() => _purchaseMode = v); },
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
      ),
    );
  }

  Widget _buildHeader(bool isEditing) {
    final name = _nameController.text.trim();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _avatarColor(name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? 'تعديل صنف فاكهة' : 'إضافة صنف فاكهة جديد',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
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

  Color _avatarColor(String name) {
    final colors = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF97316),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Widget _buildButtons(bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
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
                elevation: 4,
                shadowColor: AppTheme.primary.withValues(alpha: 0.3),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEditing ? Icons.save_outlined : Icons.add, size: 18),
              label: Text(
                _saving ? 'جاري الحفظ...' : isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              ),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
