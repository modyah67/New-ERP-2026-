import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/dao/packing_recipe_dao.dart';
import '../../data/models/packing_recipe_model.dart';
import '../../data/models/raw_material_model.dart';

class PackingRecipePage extends StatefulWidget {
  const PackingRecipePage({super.key});

  @override
  State<PackingRecipePage> createState() => _PackingRecipePageState();
}

class _PackingRecipePageState extends State<PackingRecipePage> {
  final _dao = PackingRecipeDao();
  List<RawMaterialModel> _rawMaterials = [];
  List<PackingRecipeModel> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dao.getRawMaterials(),
        _dao.getAll(),
      ]);
      if (mounted) {
        setState(() {
          _rawMaterials = results[0] as List<RawMaterialModel>;
          _recipes = results[1] as List<PackingRecipeModel>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _rawMaterialPrice(String? rawMaterialId) {
    final mat = _rawMaterials.cast<RawMaterialModel?>().firstWhere(
      (m) => m?.id == rawMaterialId,
      orElse: () => null,
    );
    return mat?.defaultPurchasePrice ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: isDark
                  ? [AppTheme.background, const Color(0xFF0D2137), AppTheme.background]
                  : [const Color(0xFFF8FAFC), const Color(0xFFEDF2F7), const Color(0xFFF8FAFC)],
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : CustomScrollView(
                  slivers: [
                    _buildSliverHeader(isDark),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: _recipes.isEmpty
                          ? _buildEmptyState(isDark)
                          : _buildRecipeList(isDark),
                    ),
                  ],
                ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppTheme.primary,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('وصفة جديدة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildSliverHeader(bool isDark) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      pinned: true,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
            ),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 12),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_forward, color: isDark ? Colors.white : Colors.black87),
                onPressed: () => context.pop(),
              ),
              Text('وصفات التعبئة',
                  style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: isDark ? AppTheme.textSecondary.withAlpha(80) : Colors.black26),
            const SizedBox(height: 16),
            Text('لا توجد وصفات تعبئة',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                )),
            const SizedBox(height: 8),
            Text('أضف وصفة لكل منتج ودرجة',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeList(bool isDark) {
    final grouped = <String, List<PackingRecipeModel>>{};
    for (final r in _recipes) {
      final key = '${r.name ?? 'وصفة'} — درجة ${r.grade}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(r);
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final entry = grouped.entries.elementAt(index);
          return _buildGroupCard(entry.key, entry.value, isDark);
        },
        childCount: grouped.length,
      ),
    );
  }

  Widget _buildGroupCard(String title, List<PackingRecipeModel> items, bool isDark) {
    final totalCostPerCarton = items.fold<double>(0.0, (s, r) {
      return s + r.quantityPerCarton * _rawMaterialPrice(r.rawMaterialId);
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark ? null : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        )),
                    Row(children: [
                      Text('تكلفة الكرتونة: ',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          )),
                      Text('${totalCostPerCarton.toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                            color: isDark ? AppTheme.success : const Color(0xFF16A34A),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          )),
                    ]),
                  ],
                ),
                const SizedBox(height: 8),
                ...items.map((r) => _buildRecipeRow(r, isDark)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _openEditor(items: items),
                        icon: Icon(Icons.edit, size: 16, color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
                        label: Text('تعديل',
                            style: TextStyle(
                              color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDeleteGroup(items),
                      icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                      label: const Text('حذف',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeRow(PackingRecipeModel r, bool isDark) {
    final unitPrice = _rawMaterialPrice(r.rawMaterialId);
    final lineCost = r.quantityPerCarton * unitPrice;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(r.rawMaterialName ?? '',
              style: TextStyle(
                color: isDark ? AppTheme.textPrimary : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              )),
        ),
        Text('${r.quantityPerCarton.toStringAsFixed(1)} ${r.unit} × ${unitPrice.toStringAsFixed(2)}',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            )),
        const SizedBox(width: 8),
        Text('${lineCost.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              color: isDark ? AppTheme.success : const Color(0xFF16A34A),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            )),
      ]),
    );
  }

  Future<void> _confirmDeleteGroup(List<PackingRecipeModel> items) async {
    final first = items.first;
    final recipeName = first.name ?? 'الوصفة';
    final grade = first.grade;
    final title = '$recipeName — درجة $grade';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDialogDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDialogDark ? const Color(0xCC05192D) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: isDialogDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          title: Text('حذف الوصفة',
              style: TextStyle(
                color: isDialogDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              )),
          content: Text('هل أنت متأكد من حذف وصفة "$title"؟\n\nلا يمكن حذف الوصفة إذا كانت مستخدمة في أي شحنة.',
              style: TextStyle(
                color: isDialogDark ? AppTheme.textSecondary : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء',
                  style: TextStyle(
                    color: isDialogDark ? AppTheme.textSecondary : Colors.black87,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  )),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (first.name == null) return;
    final error = await _dao.deleteGroupWithCheck(first.name!);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ $error'), backgroundColor: AppTheme.danger, duration: const Duration(seconds: 4)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم حذف الوصفة'), backgroundColor: AppTheme.success, duration: Duration(seconds: 2)),
    );
    _load();
  }

  Future<void> _openEditor({List<PackingRecipeModel>? items}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecipeEditorSheet(
        rawMaterials: _rawMaterials,
        existingItems: items,
      ),
    );
    if (result == true) _load();
  }
}

class _RecipeEditorSheet extends StatefulWidget {
  final List<RawMaterialModel> rawMaterials;
  final List<PackingRecipeModel>? existingItems;
  const _RecipeEditorSheet({required this.rawMaterials, this.existingItems});

  @override
  State<_RecipeEditorSheet> createState() => _RecipeEditorSheetState();
}

class _RecipeEditorSheetState extends State<_RecipeEditorSheet> {
  final _dao = PackingRecipeDao();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  String _selectedGrade = 'A';
  final _items = <_RecipeLine>[];

  @override
  void initState() {
    super.initState();
    if (widget.existingItems != null && widget.existingItems!.isNotEmpty) {
      final first = widget.existingItems!.first;
      _nameController.text = first.name ?? '';
      _selectedGrade = first.grade;
      for (final r in widget.existingItems!) {
        _items.add(_RecipeLine(
          rawMaterialId: r.rawMaterialId,
          quantity: r.quantityPerCarton,
          unit: r.unit,
        ));
      }
    } else {
      _items.add(_RecipeLine());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF005192D) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(100) : const Color(0xFFCBD5E1))),
          ),
          child: Form(
            key: _formKey,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x0AFFFFFF) : const Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(30) : const Color(0xFFE2E8F0))),
                ),
                child: Row(children: [
                  IconButton(
                    icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text('وصفة التعبئة',
                      style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      )),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('اسم الوصفة', isDark: isDark),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم الوصفة' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedGrade,
                      decoration: _inputDecoration('الدرجة', isDark: isDark),
                      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                      items: ['A', 'B', 'C'].map((g) => DropdownMenuItem(
                        value: g,
                        child: Text('درجة $g',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            )),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedGrade = v!),
                      validator: (v) => v == null ? 'اختر الدرجة' : null,
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Text('مواد التعبئة',
                          style: TextStyle(
                            color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          )),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _items.add(_RecipeLine())),
                        icon: Icon(Icons.add, size: 18, color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
                        label: Text('إضافة مادة',
                            style: TextStyle(
                              color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ..._items.asMap().entries.map((entry) => _buildMaterialRow(entry.key, entry.value, isDark: isDark)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('حفظ الوصفة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialRow(int index, _RecipeLine line, {required bool isDark}) {
    final selected = line.rawMaterialId != null
        ? widget.rawMaterials.cast<RawMaterialModel?>().firstWhere(
            (m) => m?.id == line.rawMaterialId,
            orElse: () => null,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: line.rawMaterialId,
                decoration: _inputDecoration('المادة', isDark: isDark),
                dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                items: widget.rawMaterials.map((m) => DropdownMenuItem<String>(
                  value: m.id,
                  child: Text('${m.code} - ${m.name}',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      )),
                )).toList(),
                onChanged: (v) => setState(() => line.rawMaterialId = v),
              ),
              if (selected != null && selected.defaultPurchasePrice > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Text('${selected.defaultPurchasePrice.toStringAsFixed(2)} ج.م/الوحدة',
                      style: TextStyle(
                        color: isDark ? AppTheme.success : const Color(0xFF16A34A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      )),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: line.quantity > 0 ? line.quantity.toString() : null,
            decoration: _inputDecoration('الكمية', isDark: isDark),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 12,
            ),
            onChanged: (v) => line.quantity = double.tryParse(v) ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: TextFormField(
            initialValue: line.unit,
            decoration: _inputDecoration('الوحدة', isDark: isDark),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 12,
            ),
            onChanged: (v) => line.unit = v,
          ),
        ),
        if (_items.length > 1) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger, size: 20),
            onPressed: () => setState(() => _items.removeAt(index)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ]),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final recipeName = _nameController.text.trim();
    if (recipeName.isEmpty) return;

    final recipes = _items
        .where((l) => l.rawMaterialId != null && l.rawMaterialId!.isNotEmpty && l.quantity > 0)
        .map((l) => PackingRecipeModel(
              name: recipeName,
              grade: _selectedGrade,
              rawMaterialId: l.rawMaterialId,
              quantityPerCarton: l.quantity,
              unit: l.unit,
              isActive: true,
            ))
        .toList();

    final error = await _dao.saveAllWithCheck(recipeName, _selectedGrade, recipes);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ $error'), backgroundColor: AppTheme.danger, duration: const Duration(seconds: 4)),
      );
      return;
    }

    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الوصفة'), backgroundColor: AppTheme.success, duration: Duration(seconds: 2)),
    );
  }

  InputDecoration _inputDecoration(String label, {bool isDark = true}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? AppTheme.textSecondary : Colors.black87,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo',
      ),
      filled: true,
      fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? AppTheme.primary : const Color(0xFF0284C7), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      isDense: true,
    );
  }
}

class _RecipeLine {
  String? rawMaterialId;
  double quantity;
  String unit;

  _RecipeLine({this.rawMaterialId, this.quantity = 0, this.unit = 'قطعة'});
}
