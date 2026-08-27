import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/finished_product_dao.dart';
import '../../data/models/finished_product_model.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_dropdown.dart';

class FinishedProductFormDialog extends StatefulWidget {
  final FinishedProductModel? item;
  const FinishedProductFormDialog({super.key, this.item});

  @override
  State<FinishedProductFormDialog> createState() => _FinishedProductFormDialogState();
}

class _FinishedProductFormDialogState extends State<FinishedProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dao = FinishedProductDao();
  final _scrollCtrl = ScrollController();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _categoryController;
  late final TextEditingController _packingRecipeController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _notesController;

  late final FocusNode _nameFocus;
  late final FocusNode _barcodeFocus;
  late final FocusNode _categoryFocus;
  late final FocusNode _packingRecipeFocus;
  late final FocusNode _salePriceFocus;
  late final FocusNode _notesFocus;

  String _unit = 'carton';
  bool _isActive = true;
  bool _saving = false;

  static const _unitOptions = [
    ('carton', 'كرتونة'),
    ('kg', 'كجم'),
    ('box', 'صندوق'),
    ('piece', 'قطعة'),
    ('ton', 'طن'),
  ];

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _nameController = TextEditingController();
    _barcodeController = TextEditingController();
    _categoryController = TextEditingController();
    _packingRecipeController = TextEditingController();
    _salePriceController = TextEditingController();
    _notesController = TextEditingController();

    _nameFocus = FocusNode();
    _barcodeFocus = FocusNode();
    _categoryFocus = FocusNode();
    _packingRecipeFocus = FocusNode();
    _salePriceFocus = FocusNode();
    _notesFocus = FocusNode();

    if (widget.item != null) {
      final item = widget.item!;
      _codeController.text = item.code;
      _nameController.text = item.name;
      _barcodeController.text = item.barcode ?? '';
      _categoryController.text = item.category ?? '';
      _packingRecipeController.text = item.packingRecipeId ?? '';
      _salePriceController.text = item.salePrice.toStringAsFixed(2);
      _unit = item.unit;
      _isActive = item.isActive;
      _notesController.text = item.notes ?? '';
    } else {
      _generateCode();
      _salePriceController.text = '0.00';
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
    _barcodeController.dispose();
    _categoryController.dispose();
    _packingRecipeController.dispose();
    _salePriceController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _barcodeFocus.dispose();
    _categoryFocus.dispose();
    _packingRecipeFocus.dispose();
    _salePriceFocus.dispose();
    _notesFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final item = FinishedProductModel(
        id: widget.item?.id,
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
        category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
        packingRecipeId: _packingRecipeController.text.trim().isEmpty ? null : _packingRecipeController.text.trim(),
        salePrice: double.tryParse(_salePriceController.text) ?? 0,
        unit: _unit,
        isActive: _isActive,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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
                widget.item != null ? 'تم تعديل المنتج النهائي بنجاح' : 'تم إضافة المنتج النهائي بنجاح',
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
            width: screenWidth < 500 ? screenWidth * 0.95 : 560,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
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
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  label: 'كود المنتج',
                                  controller: _codeController,
                                  hint: 'FP001',
                                  readOnly: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppTextField(
                                  label: 'اسم المنتج',
                                  controller: _nameController,
                                  focusNode: _nameFocus,
                                  hint: 'أدخل اسم المنتج',
                                  isRequired: true,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                                    return null;
                                  },
                                  onSubmitted: (_) => _barcodeFocus.requestFocus(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  label: 'الباركود',
                                  controller: _barcodeController,
                                  focusNode: _barcodeFocus,
                                  hint: 'اختياري',
                                  onSubmitted: (_) => _categoryFocus.requestFocus(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppTextField(
                                  label: 'التصنيف',
                                  controller: _categoryController,
                                  focusNode: _categoryFocus,
                                  hint: 'اختياري',
                                  onSubmitted: (_) => _packingRecipeFocus.requestFocus(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'وصفة التعبئة',
                            controller: _packingRecipeController,
                            focusNode: _packingRecipeFocus,
                            hint: 'اختياري - رقم الوصفة',
                            onSubmitted: (_) => _salePriceFocus.requestFocus(),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  label: 'سعر البيع',
                                  controller: _salePriceController,
                                  focusNode: _salePriceFocus,
                                  hint: '0.00',
                                  keyboardType: TextInputType.number,
                                  isRequired: true,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'سعر البيع مطلوب';
                                    final price = double.tryParse(v);
                                    if (price == null || price < 0) return 'سعر غير صالح';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppDropdown<String>(
                                  label: 'الوحدة',
                                  selectedItem: _unit,
                                  items: _unitOptions.map((e) => e.$1).toList(),
                                  itemAsString: (unit) {
                                    final idx = _unitOptions.indexWhere((e) => e.$1 == unit);
                                    return idx >= 0 ? _unitOptions[idx].$2 : unit;
                                  },
                                  onChanged: (v) {
                                    if (v != null) setState(() => _unit = v);
                                  },
                                  isRequired: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                const Text('نشط', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                                const Spacer(),
                                Switch(
                                  value: _isActive,
                                  activeColor: AppTheme.primary,
                                  onChanged: (v) => setState(() => _isActive = v),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'ملاحظات',
                            controller: _notesController,
                            focusNode: _notesFocus,
                            hint: 'ملاحظات إضافية...',
                            maxLines: 3,
                            textInputAction: TextInputAction.done,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
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
              isEditing ? Icons.edit_outlined : Icons.inventory_outlined,
              color: AppTheme.primary, size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? 'تعديل منتج نهائي' : 'إضافة منتج نهائي جديد',
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

  Widget _buildButtons(bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: AppTheme.primary.withValues(alpha: 0.3),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEditing ? Icons.save_outlined : Icons.add, size: 18),
              label: Text(
                _saving ? 'جاري الحفظ...' : isEditing ? 'حفظ التعديلات' : 'إضافة المنتج',
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
