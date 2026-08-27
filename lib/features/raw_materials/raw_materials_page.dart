import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/services/inventory_export_service.dart';
import '../../core/data_change_event_bus.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'raw_material_form_dialog.dart';

class RawMaterialsPage extends StatefulWidget {
  final bool lowStockOnly;
  const RawMaterialsPage({super.key, this.lowStockOnly = false});

  @override
  State<RawMaterialsPage> createState() => _RawMaterialsPageState();
}

class _RawMaterialsPageState extends State<RawMaterialsPage> {
  final RawMaterialDao _dao = RawMaterialDao();
  final TextEditingController _searchController = TextEditingController();

  List<RawMaterialModel> _items = [];
  List<RawMaterialModel> _filteredItems = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String _search = '';
  String? _selectedCategoryId;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _load();
    _subs.add(DataChangeEventBus.instance.itemsStream.listen((_) => _load()));
    _subs.add(DataChangeEventBus.instance.stationsStream.listen((_) => _load()));
    _subs.add(DataChangeEventBus.instance.purchasesStream.listen((_) => _load()));
    _subs.add(DataChangeEventBus.instance.invoicesStream.listen((_) => _load()));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dao.getAll(categoryId: _selectedCategoryId),
        _dao.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<RawMaterialModel>;
        _categories = results[1] as List<Map<String, dynamic>>;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.toString();
      if (msg.contains('does not exist') || msg.contains('PGRST205')) {
        _showSnackBar(
            'جدول المواد الخام غير موجود. يرجى تشغيل Migration 137 أولاً.');
      } else {
        _showSnackBar('خطأ في تحميل البيانات: $e');
      }
    }
  }

  void _applyFilter() {
    var items = List<RawMaterialModel>.from(_items);
    if (widget.lowStockOnly) {
      items = items.where((item) => item.isLowStock).toList();
    }
    if (_search.isEmpty) {
      _filteredItems = items;
    } else {
      final q = _search.toLowerCase();
      _filteredItems = items
          .where((item) =>
              item.name.toLowerCase().contains(q) ||
              item.code.toLowerCase().contains(q))
          .toList();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _search = value;
      _applyFilter();
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textDirection: TextDirection.rtl)),
    );
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xCC05192D),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 380,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إضافة فئة',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      hintText: 'مثال: مواد تعبئة',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      label: const Text('اسم الفئة',
                          style: TextStyle(fontFamily: 'Cairo')),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.glassBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.glassBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.accent)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء',
                              style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white),
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('إضافة',
                              style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final cat = await _dao.addCategory(result);
        setState(() => _categories.add(cat));
        _showSnackBar('تم إضافة الفئة "$result"');
      } on PostgrestException catch (e) {
        if (e.message.contains('duplicate key') || e.code == '23505') {
          _showSnackBar('هذه الفئة موجودة بالفعل');
        } else {
          _showSnackBar('فشل إضافة الفئة: ${e.message}');
        }
      } catch (e) {
        _showSnackBar('فشل إضافة الفئة: $e');
      }
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        title: const Text('حذف فئة', style: TextStyle(fontFamily: 'Cairo')),
        content: Text('هل تريد حذف الفئة "$name"؟',
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف',
                  style:
                      TextStyle(color: AppTheme.danger, fontFamily: 'Cairo'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _dao.deleteCategory(id);
      setState(() {
        _categories.removeWhere((c) => c['id'].toString() == id);
        if (_selectedCategoryId == id) _selectedCategoryId = null;
      });
      _load();
    } catch (e) {
      _showSnackBar('خطأ في الحذف: $e');
    }
  }

  Future<void> _delete(RawMaterialModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        title:
            const Text('حذف مادة خام', style: TextStyle(fontFamily: 'Cairo')),
        content: Text('هل تريد حذف "${item.name}"؟',
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف',
                  style:
                      TextStyle(color: AppTheme.danger, fontFamily: 'Cairo'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _dao.delete(item.id!);
      if (!mounted) return;
      setState(() {
        _items.remove(item);
        _applyFilter();
      });
      _showSnackBar('تم حذف "${item.name}"');
    } catch (e) {
      _showSnackBar('خطأ في الحذف: $e');
    }
  }

  Future<void> _showForm([RawMaterialModel? item]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RawMaterialFormDialog(item: item),
    );
    if (result == true) _load();
  }

  String _unitLabel(String unit) {
    const labels = {
      'piece': 'قطعة',
      'kg': 'كجم',
      'box': 'كرتونة',
      'roll': 'لفة',
      'bag': 'كيس',
      'meter': 'متر',
      'liter': 'لتر',
    };
    return labels[unit] ?? unit;
  }

  static const Map<String, Color> _currencyColors = {
    'EGP': Color(0xFF16D5FF),
    'USD': Color(0xFF4CAF50),
    'EUR': Color(0xFFFFC107),
    'GBP': Color(0xFFE91E63),
  };

  Map<String, dynamic> _categoryStats(String? categoryId) {
    final items = categoryId == null
        ? _items
        : _items.where((i) => i.categoryId == categoryId).toList();
    double totalQty = 0;
    final Map<String, double> valueByCurrency = {};
    for (final i in items) {
      totalQty += i.quantity;
      final val = i.quantity * i.defaultPurchasePrice;
      valueByCurrency[i.currency] = (valueByCurrency[i.currency] ?? 0) + val;
    }
    return {'quantity': totalQty, 'valueByCurrency': valueByCurrency};
  }

  Widget _buildCurrencyValueWidget(
      Map<String, double> valueByCurrency, bool isSelected) {
    if (valueByCurrency.isEmpty) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('0',
            style: TextStyle(
                color: isSelected ? const Color(0xFF333333) : AppTheme.accent,
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      );
    }
    final entries = valueByCurrency.entries.toList();
    if (entries.length == 1) {
      final color = isSelected
          ? const Color(0xFF333333)
          : (_currencyColors[entries.first.key] ?? AppTheme.accent);
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          '${AppUtils.formatNumber(entries.first.value)} ${entries.first.key}',
          style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: entries.map((e) {
        final color = isSelected
            ? const Color(0xFF333333)
            : (_currencyColors[e.key] ?? AppTheme.accent);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            '${AppUtils.formatNumber(e.value)} ${e.key}',
            style: TextStyle(
                color: color,
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              sliver: SliverToBoxAdapter(child: _buildCategoryFilters()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              sliver: SliverToBoxAdapter(child: _buildSearchBar()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              sliver: _buildGridSliver(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 760;
        final titleSection = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.inventory_outlined,
                  color: AppTheme.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المستلزمات',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                Text(
                  widget.lowStockOnly
                      ? '${_filteredItems.length} صنف منخفض المخزون'
                      : '${_items.length} صنف',
                  style: TextStyle(
                      color: widget.lowStockOnly
                          ? AppTheme.warning
                          : AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 13),
                ),
              ],
            ),
          ],
        );

        final actions = Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.start,
          children: [
            IconButton(
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary))
                  : const Icon(Icons.refresh_outlined,
                      color: AppTheme.textSecondary),
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart_outlined,
                  color: AppTheme.success, size: 20),
              tooltip: 'تصدير Excel',
              onPressed: _exportExcel,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.category_outlined, size: 18),
              label: const Text('إضافة فئة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                foregroundColor: AppTheme.primary,
              ),
              onPressed: _addCategory,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مادة'),
              onPressed: () => _showForm(),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleSection,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }

        return Row(
          children: [
            titleSection,
            const Spacer(),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildCategoryFilters() {
    final allStats = _categoryStats(null);
    final allChips = <Widget>[
      _buildFilterChip(
        'الكل',
        null,
        '${(allStats['quantity'] as double).toStringAsFixed(0)} ${_unitLabel(_items.isNotEmpty ? _items.first.unit : 'piece')}',
        _buildCurrencyValueWidget(
            allStats['valueByCurrency'] as Map<String, double>,
            _selectedCategoryId == null),
      ),
      ..._categories.map((cat) {
        final id = cat['id'].toString();
        final name = cat['name']?.toString() ?? '';
        final stats = _categoryStats(id);
        return _buildFilterChip(
          name,
          id,
          '${(stats['quantity'] as double).toStringAsFixed(0)} ${_unitLabel(_items.isNotEmpty ? _items.first.unit : 'piece')}',
          _buildCurrencyValueWidget(
              stats['valueByCurrency'] as Map<String, double>,
              _selectedCategoryId == id),
        );
      }),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < allChips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            allChips[i],
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label, String? categoryId, String qtyText, Widget valueWidget) {
    final isSelected = _selectedCategoryId == categoryId;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCategoryId = isSelected ? null : categoryId);
          _load();
        },
        onLongPress: categoryId != null
            ? () => _deleteCategory(categoryId, label)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : const Color(0x66000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF333333)
                              : AppTheme.textSecondary,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(qtyText,
                        style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF4D4D4D)
                                : AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  ),
                  valueWidget,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الكود...',
              hintStyle: const TextStyle(
                  color: AppTheme.textSecondary, fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.search,
                  size: 20, color: AppTheme.textSecondary),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 18, color: AppTheme.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSliver() {
    if (_loading) {
      return const SliverFillRemaining(
        child:
            Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_filteredItems.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_outlined,
                  size: 72,
                  color: AppTheme.textSecondary.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                _search.isNotEmpty ? 'لا توجد نتائج' : 'لا توجد مواد خام بعد',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 8),
              Text(
                _search.isNotEmpty
                    ? 'جرب كلمة بحث مختلفة'
                    : 'اضغط "+" لإضافة أول مادة',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent:
              MediaQuery.of(context).size.width < 600 ? 340 : 340,
          mainAxisExtent: MediaQuery.of(context).size.width < 600 ? 300 : 350,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildMaterialCard(_filteredItems[index]),
          childCount: _filteredItems.length,
        ),
      ),
    );
  }

  Widget _buildMaterialCard(RawMaterialModel item) {
    final isOut = item.quantity == 0;
    final isLow = item.isLowStock;
    final stockColor =
        isOut ? AppTheme.danger : (isLow ? AppTheme.warning : AppTheme.success);
    final stockLabel = isOut ? 'نفد' : (isLow ? 'منخفض' : 'متوفر');
    final totalValue = item.quantity * item.defaultPurchasePrice;
    final hasOpening = item.initialQuantity > 0;
    final consumedQty = hasOpening
        ? (item.initialQuantity - item.quantity).clamp(0.0, double.infinity)
        : 0.0;

    return GestureDetector(
      onTap: () => context.push('/raw-materials/${item.id}'),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF0C345C),
              Color(0xFF071E3A),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: stockColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: stockColor.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                  colors: [stockColor, stockColor.withValues(alpha: 0.15)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.accent.withValues(alpha: 0.18),
                            AppTheme.accent.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.2)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.code,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.22),
                          AppTheme.accent.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.15)),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      item.currency,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: stockColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: stockColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: stockColor.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stockLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Cairo',
                            color: stockColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${item.quantity.toStringAsFixed(0)} ${_unitLabel(item.unit)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Cairo',
                          color: stockColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.1),
                      AppTheme.accent.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.15)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monetization_on_outlined,
                          size: 16, color: AppTheme.accent),
                      const SizedBox(width: 6),
                      Text(
                        '${AppUtils.formatNumber(totalValue)} ${item.currency}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontFamily: 'Cairo',
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasOpening)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.12)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history,
                            size: 12, color: AppTheme.warning),
                        const SizedBox(width: 4),
                        Text(
                          'بداية ${item.initialQuantity.toStringAsFixed(0)} ${_unitLabel(item.unit)}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              color: AppTheme.warning,
                              fontWeight: FontWeight.bold),
                        ),
                        if (consumedQty > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '— مستهلك ${consumedQty.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Cairo',
                                color: AppTheme.danger.withValues(alpha: 0.8),
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Cairo',
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا توجد مواد خام للتصدير',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.orange),
      );
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final List<Map<String, dynamic>> items = [];
      for (final e in _items) {
        items.add({
          'name': e.name,
          'code': e.code,
          'unit': e.unit,
          'currency': e.currency,
          'categoryName': e.categoryName ?? 'بدون فئة',
          'quantity': e.quantity,
          'totalValue': e.quantity * (e.defaultPurchasePrice ?? 0.0),
        });
      }
      await InventoryExportService.exportItemsWithBatches(
          title: 'المواد الخام', items: items);
      _dismissLoading();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم التصدير بنجاح',
                  style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _dismissLoading();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _dismissLoading() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    });
  }
}
