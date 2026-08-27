import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/finished_product_dao.dart';
import '../../data/models/finished_product_model.dart';
import 'finished_product_form_dialog.dart';

class FinishedProductsPage extends StatefulWidget {
  const FinishedProductsPage({super.key});

  @override
  State<FinishedProductsPage> createState() => _FinishedProductsPageState();
}

class _FinishedProductsPageState extends State<FinishedProductsPage> {
  final FinishedProductDao _dao = FinishedProductDao();
  final TextEditingController _searchController = TextEditingController();

  List<FinishedProductModel> _items = [];
  List<FinishedProductModel> _filteredItems = [];
  bool _loading = true;
  String _search = '';

  static const _unitLabels = {
    'carton': 'كرتونة',
    'kg': 'كجم',
    'box': 'صندوق',
    'piece': 'قطعة',
    'ton': 'طن',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _dao.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar('خطأ في تحميل البيانات: $e');
    }
  }

  void _applyFilter() {
    if (_search.isEmpty) {
      _filteredItems = List.from(_items);
    } else {
      final q = _search.toLowerCase();
      _filteredItems = _items.where((item) =>
        item.name.toLowerCase().contains(q) ||
        item.code.toLowerCase().contains(q) ||
        (item.barcode?.toLowerCase().contains(q) ?? false)
      ).toList();
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

  Future<void> _delete(FinishedProductModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        title: const Text('حذف منتج نهائي', style: TextStyle(fontFamily: 'Cairo')),
        content: Text('هل تريد حذف "${item.name}"؟', style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
          ),
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

  Future<void> _showForm([FinishedProductModel? item]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinishedProductFormDialog(item: item),
    );
    if (result == true) {
      _load();
    }
  }

  String _unitLabel(String unit) => _unitLabels[unit] ?? unit;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          onPressed: () => _showForm(),
          child: const Icon(Icons.add),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildSearchBar(),
              const SizedBox(height: 16),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.inventory_outlined, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المنتجات النهائية', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                Text('${_items.length} منتج', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.refresh_outlined, color: AppTheme.textSecondary),
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة منتج'),
            onPressed: () => _showForm(),
          ),
        ],
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
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الكود أو الباركود...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          ),
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      final hasSearch = _search.isNotEmpty;
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasSearch ? Icons.search_off_outlined : Icons.inventory_outlined,
                    size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasSearch ? 'لا توجد نتائج' : 'لا توجد منتجات نهائية بعد',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasSearch ? 'جرب كلمة بحث مختلفة' : 'اضغط "+" لإضافة أول منتج',
                    style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                  ),
                  if (!hasSearch) ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة منتج'),
                      onPressed: () => _showForm(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _filteredItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) => _buildTableRow(_filteredItems[index], index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(width: 80, child: Text('الكود', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(child: Text('الاسم', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 110, child: Text('الباركود', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 100, child: Text('سعر البيع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('الوحدة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('الحالة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('إجراءات', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(FinishedProductModel item, int index) {
    final isEven = index % 2 == 0;
    return GestureDetector(
      onTap: () => _showForm(item),
      child: Container(
        color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 80, child: _codeBadge(item.code)),
            Expanded(
              child: Text(item.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15), overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 110,
              child: Text(
                item.barcode ?? '—',
                style: TextStyle(color: item.barcode != null ? Colors.white : AppTheme.textMuted, fontFamily: 'Cairo', fontSize: 13),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                AppUtils.formatCurrency(item.salePrice),
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13, color: AppTheme.success),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _unitLabel(item.unit),
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 80,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: item.isActive
                        ? AppTheme.success.withValues(alpha: 0.15)
                        : AppTheme.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.isActive ? 'نشط' : 'غير نشط',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: item.isActive ? AppTheme.success : AppTheme.danger,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                    tooltip: 'تعديل',
                    onPressed: () => _showForm(item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    tooltip: 'حذف',
                    onPressed: () => _delete(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeBadge(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
      child: Text(code, style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }
}
