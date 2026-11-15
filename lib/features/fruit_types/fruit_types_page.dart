import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_group_model.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/services/inventory_export_service.dart';
import 'fruit_type_form_dialog.dart';
import 'fruit_type_detail_dialog.dart';
import 'widgets/unified_fruit_card.dart';

class FruitTypesPage extends StatefulWidget {
  const FruitTypesPage({super.key});

  @override
  State<FruitTypesPage> createState() => _FruitTypesPageState();
}

class _FruitTypesPageState extends State<FruitTypesPage> {
  final FruitTypeDao _dao = FruitTypeDao();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<FruitTypeModel> _items = [];
  List<FruitTypeModel> _filteredItems = [];
  List<FruitTypeGroupModel> _groups = [];
  Map<String, List<Map<String, dynamic>>> _warehouseDistribution = {};
  bool _loading = true;
  String _search = '';
  // null = الكل, 'weight' = الوزن, 'carton' = الكراتين, 'shared' = المشترك
  String? _selectedPurchaseMode;

  StreamSubscription<void>? _stationsSub;
  StreamSubscription<void>? _cropPurchasesSub;
  StreamSubscription<void>? _itemsSub;
  Timer? _debounceLoad;

  @override
  void initState() {
    super.initState();
    _load();
    _stationsSub = DataChangeEventBus.instance.stationsStream
        .listen((_) => _debouncedLoad());
    _cropPurchasesSub = DataChangeEventBus.instance.cropPurchasesStream
        .listen((_) => _debouncedLoad());
    _itemsSub =
        DataChangeEventBus.instance.itemsStream.listen((_) => _debouncedLoad());
  }

  void _debouncedLoad() {
    _debounceLoad?.cancel();
    _debounceLoad = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounceLoad?.cancel();
    _stationsSub?.cancel();
    _cropPurchasesSub?.cancel();
    _itemsSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _dao.getAllWithPrices(),
        _dao.getWarehouseDistribution(),
        _dao.getStockByFruitTypeId(),
      ]);
      if (!mounted) return;
      final items = results[0] as List<FruitTypeModel>;
      final warehouseDist = results[1] as Map<String, List<Map<String, dynamic>>>;
      final stockByTypeId = results[2] as Map<int, double>;

      for (final item in items) {
        final idInt = int.tryParse(item.id ?? '');
        final directStock = idInt != null ? stockByTypeId[idInt] : null;
        if (directStock != null) {
          item.totalStockQuantity = directStock;
        } else {
          List<Map<String, dynamic>> distList = [];
          if (item.id != null && warehouseDist.containsKey('fruit_${item.id}')) {
            distList = warehouseDist['fruit_${item.id}']!;
          } else if (item.name.isNotEmpty && warehouseDist.containsKey(item.name)) {
            distList = warehouseDist[item.name]!;
          } else {
            final cleanName = item.name.trim().toLowerCase();
            if (cleanName.isNotEmpty && warehouseDist.containsKey(cleanName)) {
              distList = warehouseDist[cleanName]!;
            }
          }
          
          distList = distList.toSet().toList();

          if (distList.isNotEmpty) {
            final sumQty = distList.fold<double>(
                0.0, (s, d) => s + ((d['quantity'] as num?)?.toDouble() ?? 0.0));
            item.totalStockQuantity = sumQty;
          } else {
            item.totalStockQuantity = 0.0;
          }
        }
      }
      setState(() {
        _items = items;
        _warehouseDistribution = warehouseDist;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar('خطأ في تحميل البيانات');
    }
  }

  void _applyFilter() {
    _filteredItems = _items.where((item) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final base = FruitTypeGroupModel.extractBaseName(item.name).toLowerCase();
        if (!item.name.toLowerCase().contains(q) &&
            !item.code.toLowerCase().contains(q) &&
            !base.contains(q)) {
          return false;
        }
      }
      if (_selectedPurchaseMode == 'shared') {
        // Only include items whose base name appears in a dual-mode group
        // We'll compute this during group building below
        return true; // filtered further in group building
      }
      if (_selectedPurchaseMode != null) {
        final itemMode = item.purchaseMode ?? item.latestPurchaseMode;
        if (itemMode != _selectedPurchaseMode) return false;
      }
      return true;
    }).toList();

    // Build groups from all items (or filtered items for non-shared tabs)
    final sourceForGroups = (_selectedPurchaseMode == null || _selectedPurchaseMode == 'shared')
        ? _items
        : _filteredItems;
    final allGroups = FruitTypeGroupModel.groupFromItems(sourceForGroups);

    // Apply search filter to groups
    List<FruitTypeGroupModel> filtered = allGroups;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      filtered = allGroups.where((g) {
        if (g.baseName.toLowerCase().contains(q)) return true;
        return g.allItems.any((it) =>
            it.name.toLowerCase().contains(q) ||
            it.code.toLowerCase().contains(q));
      }).toList();
    }

    // Filter by selected purchase mode
    if (_selectedPurchaseMode == 'shared') {
      filtered = filtered.where((g) => g.isDualMode).toList();
    } else if (_selectedPurchaseMode == 'weight') {
      filtered = filtered.where((g) => g.hasWeight && !g.isDualMode).toList();
    } else if (_selectedPurchaseMode == 'carton') {
      filtered = filtered.where((g) => g.hasCarton && !g.isDualMode).toList();
    }

    _groups = filtered;
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

  Future<void> _showForm([FruitTypeModel? item]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FruitTypeFormDialog(item: item),
    );
    if (result == true) {
      _load();
    }
  }

  List<Map<String, dynamic>> _getDistributionForItem(FruitTypeModel item) {
    List<Map<String, dynamic>> dist = [];
    if (item.id != null && _warehouseDistribution.containsKey('fruit_${item.id}')) {
      dist = _warehouseDistribution['fruit_${item.id}']!;
    } else if (item.name.isNotEmpty && _warehouseDistribution.containsKey(item.name)) {
      dist = _warehouseDistribution[item.name]!;
    } else {
      final cleanName = item.name.trim().toLowerCase();
      if (cleanName.isNotEmpty && _warehouseDistribution.containsKey(cleanName)) {
        dist = _warehouseDistribution[cleanName]!;
      }
    }
    
    // Deduplicate identical entries (same object references) caused by DAO key collisions
    return dist.toSet().toList();
  }

  void _showDetail(FruitTypeModel item) {
    final distribution = _getDistributionForItem(item);
    showDialog(
      context: context,
      builder: (_) =>
          FruitTypeDetailDialog(fruitType: item, distribution: distribution),
    );
  }

  // ── إحصائيات إجمالية ──

  double get _totalQuantityAll =>
      _items.fold<double>(0, (s, e) => s + (_totalQuantityForItem(e)));

  Map<String, double> get _totalValueByCurrency {
    final map = <String, double>{};
    for (final e in _items) {
      final curr = e.currency;
      final sv = e.totalStockValue;
      final val = (sv != null && sv > 0)
          ? sv
          : _totalQuantityForItem(e) *
              (e.averagePurchasePrice ?? e.latestPurchasePrice ?? 0);
      map[curr] = (map[curr] ?? 0) + val;
    }
    return map;
  }

  double _totalQuantityForItem(FruitTypeModel item) {
    final dist = _getDistributionForItem(item);
    if (dist.isNotEmpty) {
      return dist.fold<double>(
          0, (sum, d) => sum + ((d['quantity'] as num?)?.toDouble() ?? 0.0));
    }
    if (item.totalStockQuantity != null) {
      return item.totalStockQuantity!;
    }
    return item.totalQuantity ?? 0.0;
  }

  int _warehouseCountForItem(FruitTypeModel item) {
    final dist = _getDistributionForItem(item);
    return dist.where((d) => (d['quantity'] as double? ?? 0) > 0).length;
  }

  String _formatQty(double? qty) {
    if (qty == null || qty == 0) return '0';
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(1);
  }

  String _formatPrice(double? price, {String? currency}) {
    if (price == null) return '—';
    final curr = currency ?? 'EGP';
    return '${AppUtils.formatNumber(price)} $curr';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 16),
              _buildSummaryStrip(isDark),
              const SizedBox(height: 12),
              _buildPurchaseModeTabs(isDark),
              const SizedBox(height: 12),
              _buildSearchBar(isDark),
              const SizedBox(height: 16),
              Expanded(child: _buildGrid(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final titleSection = Row(
          mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFBAE6FD),
                ),
              ),
              child: Icon(Icons.eco, color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 24),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'أصناف الفاكهة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  Text(
                    '${_items.length} صنف',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? AppTheme.primary : AppTheme.lightPrimary,
                      ),
                    )
                  : Icon(Icons.refresh_outlined,
                      color: isDark ? AppTheme.textSecondary : Colors.black),
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
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة صنف',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
            Flexible(child: titleSection),
            const Spacer(),
            actions,
          ],
        );
      },
    );
  }

  // ── شريط الإحصائيات العلوي ──

  Widget _buildSummaryStrip(bool isDark) {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildSummaryChip(
            icon: Icons.eco,
            label: 'إجمالي الأصناف',
            value: '${_items.length}',
            color: AppTheme.primary,
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          _buildSummaryChip(
            icon: Icons.inventory_2_outlined,
            label: 'إجمالي الكمية',
            value: '${_formatQty(_totalQuantityAll)} كجم',
            color: AppTheme.warning,
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          ..._buildValueChips(isDark),
          const SizedBox(width: 10),
          _buildSummaryChip(
            icon: Icons.warehouse_outlined,
            label: 'المخازن المستخدمة',
            value: '${_items.fold<Set<String>>(<String>{}, (s, e) {
              final dist = _getDistributionForItem(e);
              for (final d in dist) {
                if ((d['quantity'] as double? ?? 0) > 0) {
                  s.add(d['station_id']?.toString() ?? '');
                }
              }
              return s;
            }).length}',
            color: AppTheme.info,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: isDark ? color : Colors.black,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1.15,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const Map<String, Color> _currencyColors = {
    'EGP': AppTheme.accent,
    'USD': AppTheme.success,
    'EUR': AppTheme.warning,
    'GBP': Color(0xFFE91E63),
  };

  List<Widget> _buildValueChips(bool isDark) {
    final vbc = _totalValueByCurrency;
    if (vbc.isEmpty) {
      return [
        _buildSummaryChip(
          icon: Icons.monetization_on_outlined,
          label: 'قيمة المخزون',
          value: '—',
          color: AppTheme.accent,
          isDark: isDark,
        )
      ];
    }
    final widgets = <Widget>[];
    final entries = vbc.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final color = _currencyColors[e.key] ?? AppTheme.accent;
      widgets.add(_buildSummaryChip(
        icon: Icons.monetization_on_outlined,
        label: 'قيمة ${e.key}',
        value: '${AppUtils.formatNumber(e.value)} ${e.key}',
        color: color,
        isDark: isDark,
      ));
      if (i < entries.length - 1) {
        widgets.add(const SizedBox(width: 10));
      }
    }
    return widgets;
  }

  // ── فلتر طريقة الشراء ──

  Widget _buildPurchaseModeTabs(bool isDark) {
    final allGroups = FruitTypeGroupModel.groupFromItems(_items);
    final weightCount = allGroups.where((g) => g.hasWeight && !g.isDualMode).length;
    final cartonCount = allGroups.where((g) => g.hasCarton && !g.isDualMode).length;
    final sharedCount = allGroups.where((g) => g.isDualMode).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTab(
            label: 'الكل',
            count: allGroups.length,
            isSelected: _selectedPurchaseMode == null,
            color: AppTheme.primary,
            icon: Icons.apps_outlined,
            isDark: isDark,
            onTap: () {
              setState(() => _selectedPurchaseMode = null);
              _applyFilter();
            },
          ),
          const SizedBox(width: 8),
          _buildModeTab(
            label: 'الوزن',
            count: weightCount,
            isSelected: _selectedPurchaseMode == 'weight',
            color: AppTheme.success,
            icon: Icons.scale_outlined,
            isDark: isDark,
            onTap: () {
              setState(() => _selectedPurchaseMode = 'weight');
              _applyFilter();
            },
          ),
          const SizedBox(width: 8),
          _buildModeTab(
            label: 'الكراتين',
            count: cartonCount,
            isSelected: _selectedPurchaseMode == 'carton',
            color: AppTheme.accent,
            icon: Icons.inventory_2_outlined,
            isDark: isDark,
            onTap: () {
              setState(() => _selectedPurchaseMode = 'carton');
              _applyFilter();
            },
          ),
          const SizedBox(width: 8),
          _buildModeTab(
            label: 'مشترك',
            count: sharedCount,
            isSelected: _selectedPurchaseMode == 'shared',
            color: AppTheme.warning,
            icon: Icons.alt_route,
            isDark: isDark,
            onTap: () {
              setState(() => _selectedPurchaseMode = 'shared');
              _applyFilter();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeBg = isDark ? color.withValues(alpha: 0.15) : const Color(0xFFE0F2FE);
    final activeBorder = isDark ? color : const Color(0xFF0284C7);
    final inactiveBorder = isDark ? AppTheme.border : const Color(0xFFCBD5E1);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : (isDark ? Colors.transparent : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeBorder : inactiveBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: !isDark && !isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark
                  ? (isSelected ? color : AppTheme.textSecondary)
                  : (isSelected ? const Color(0xFF0284C7) : Colors.black),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: isDark ? (isSelected ? FontWeight.bold : FontWeight.w500) : FontWeight.bold,
                color: isDark ? (isSelected ? color : AppTheme.textSecondary) : Colors.black,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? (isSelected ? color.withValues(alpha: 0.2) : AppTheme.border.withValues(alpha: 0.3))
                    : (isSelected ? const Color(0xFFBAE6FD) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(8),
                border: isDark ? null : Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? (isSelected ? color : AppTheme.textSecondary) : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search Bar ──

  Widget _buildSearchBar(bool isDark) {
    if (isDark) {
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
            child: _buildSearchTextField(isDark),
          ),
        ),
      );
    }
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildSearchTextField(isDark),
    );
  }

  Widget _buildSearchTextField(bool isDark) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: _onSearchChanged,
      textDirection: TextDirection.rtl,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
        fontSize: 14,
        fontFamily: 'Cairo',
      ),
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        hintStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
          fontFamily: 'Cairo',
          fontSize: 13,
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: isDark ? AppTheme.textSecondary : Colors.black54,
        ),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear,
                  size: 18,
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                ),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // ── Grid ──

  Widget _buildGrid(bool isDark) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: isDark ? AppTheme.primary : AppTheme.lightPrimary),
      );
    }

    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _search.isNotEmpty ? Icons.search_off_outlined : Icons.eco,
              size: 72,
              color: isDark
                  ? AppTheme.textSecondary.withValues(alpha: 0.3)
                  : const Color(0xFF94A3B8).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _search.isNotEmpty ? 'لا توجد نتائج' : 'لا توجد أصناف فاكهة بعد',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _search.isNotEmpty
                  ? 'جرب كلمة بحث مختلفة'
                  : 'اضغط "+" لإضافة أول صنف',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            if (_search.isEmpty) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة صنف',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showForm(),
              ),
            ],
          ],
        ),
      );
    }


    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 750;

    // Dual-mode cards need more vertical space
    final hasDual = _groups.any((g) => g.isDualMode);
    final double aspectRatio;
    if (isMobile) {
      aspectRatio = hasDual ? 0.82 : 1.25;
    } else {
      aspectRatio = hasDual ? 0.75 : 0.90;
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? 800 : 380,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _groups.length,
      itemBuilder: (context, index) => _buildGroupCard(_groups[index], index),
    );
  }

  // ── Unified Group Card ──

  Widget _buildGroupCard(FruitTypeGroupModel group, int index) {
    return UnifiedFruitCard(
      group: group,
      index: index,
      getTotalQuantity: _totalQuantityForItem,
      getWarehouseCount: _warehouseCountForItem,
      onTapItem: _showDetail,
    );
  }

  // ── KEPT for backward compat (Excel export still uses _items) ──
  // ignore: unused_element
  Widget _buildFruitCard(FruitTypeModel item, int index) {
    final totalQty = _totalQuantityForItem(item);
    final hasStock = totalQty > 0;
    final unitPrice = item.averagePurchasePrice ?? item.latestPurchasePrice ?? 0.0;
    final totalValue = totalQty > 0
        ? (item.totalStockValue != null &&
                item.totalStockValue! > 0 &&
                (item.totalStockQuantity == null ||
                    (item.totalStockQuantity! - totalQty).abs() < 0.01)
            ? item.totalStockValue!
            : totalQty * unitPrice)
        : 0.0;
    final isCartonMode =
        (item.purchaseMode ?? item.latestPurchaseMode) == 'carton';
    final unitLabel = isCartonMode ? 'كرتونة' : 'كجم';

    final stockColor = !hasStock
        ? AppTheme.danger
        : (totalQty < 1000 ? AppTheme.warning : AppTheme.success);
    final stockLabel =
        !hasStock ? 'لا يوجد مخزون' : (totalQty < 1000 ? 'منخفض' : 'متوفر');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + (index * 25)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)), child: child),
      ),
      child: GestureDetector(
        onTap: () => _showDetail(item),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF0C345C), Color(0xFF071E3A)],
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
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.18),
                            AppTheme.primary.withValues(alpha: 0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        item.code,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
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
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.15)),
                      ),
                      child: Center(
                        child: Text(
                          item.name.isNotEmpty
                              ? item.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _avatarColor(item.name),
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // اسم الصنف
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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

              // حالة المخزون + الكمية
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: stockColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: stockColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                stockLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Cairo',
                                  color: stockColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCartonMode) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'كرتونة',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontFamily: 'Cairo',
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatQty(totalQty)} $unitLabel',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Cairo',
                        color: stockColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // القيمة الإجمالية
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monetization_on_outlined,
                          size: 14, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatPrice(totalValue > 0 ? totalValue : null,
                                currency: item.currency),
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCartonInfoRow(FruitTypeModel item, int whCount) {
    final netWt = item.latestWeightPerCartonKg!;
    final grossWt = item.latestGrossWeightPerCartonKg;
    final price = item.latestPricePerCarton;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الوزن الصافي',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_formatQty(netWt)} كجم',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: AppTheme.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
            width: 1, height: 24, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'الإجمالي',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  grossWt != null && grossWt > 0
                      ? '${_formatQty(grossWt)} كجم'
                      : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: grossWt != null && grossWt > 0
                        ? AppTheme.info
                        : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
            width: 1, height: 24, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'سعر الكرتونة',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  price != null
                      ? _formatPrice(price, currency: item.currency)
                      : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: price != null ? AppTheme.accent : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildWeightInfoRow(FruitTypeModel item, bool hasPrice, int whCount) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'آخر سعر',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  hasPrice
                      ? _formatPrice(item.latestPurchasePrice,
                          currency: item.currency)
                      : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: hasPrice ? AppTheme.success : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
            width: 1, height: 24, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'متوسط',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatPrice(item.averagePurchasePrice,
                      currency: item.currency),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Cairo',
                    color: item.averagePurchasePrice != null
                        ? AppTheme.info
                        : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
            width: 1, height: 24, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'المخازن',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: 'Cairo',
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              Text(
                '$whCount',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Cairo',
                  color: whCount > 0 ? AppTheme.accent : AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
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



  Future<void> _exportExcel() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا توجد أصناف للتصدير',
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
        final isCarton = (e.purchaseMode ?? e.latestPurchaseMode) == 'carton';
        final mode = e.purchaseMode ?? e.latestPurchaseMode ?? 'weight';
        final qty = _totalQuantityForItem(e);
        final price =
            (e.averagePurchasePrice ?? e.latestPurchasePrice ?? 0.0).toDouble();
        final value = e.totalStockValue != null && e.totalStockValue! > 0
            ? e.totalStockValue!
            : qty * price;
        items.add({
          'name': e.name,
          'code': e.code,
          'categoryName': mode == 'carton' ? 'بالكراتين' : 'بالوزن',
          'unit': isCarton ? 'كرتونة' : 'كجم',
          'currency': e.currency,
          'quantity': qty,
          'totalValue': value,
        });
      }
      await InventoryExportService.exportItemsWithBatches(
          title: 'أصناف الفاكهة', items: items);
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
