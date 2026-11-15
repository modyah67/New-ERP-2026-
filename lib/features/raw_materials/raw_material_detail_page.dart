import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/ui_utils.dart';
import '../../data/dao/raw_material_dao.dart';
import 'raw_material_card_pdf_service.dart';

class RawMaterialDetailPage extends StatefulWidget {
  final String materialId;
  const RawMaterialDetailPage({super.key, required this.materialId});

  @override
  State<RawMaterialDetailPage> createState() => _RawMaterialDetailPageState();
}

class _RawMaterialDetailPageState extends State<RawMaterialDetailPage> {
  final _dao = RawMaterialDao();
  bool _loading = true;

  String _name = '';
  String _code = '';
  String _unit = '';
  String _currency = 'EGP';
  String _categoryName = '';
  double _quantity = 0;
  double _minimumStock = 3000;
  double _estimatedValue = 0;
  double _avgCost = 0;
  double _initialQuantity = 0;
  double _initialAvgPrice = 0;

  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _allBatches = [];

  // ── Stock Ledger State ─────────────────────
  int _selectedTab = 0; // 0: FIFO & Overview, 1: Stock Ledger
  List<Map<String, dynamic>> _stockLedger = [];
  String _ledgerTypeFilter = 'all'; // all, opening, purchase, packing, transfer
  String? _selectedWarehouse;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
    setState(() {
      _loading = true;
      _batches = [];
      _stockLedger = [];
    });
    try {
      final item = await _dao.getById(widget.materialId);
      final batchData = await _dao.getBatchesForMaterial(widget.materialId);
      final ledgerData = await _dao.getStockLedger(widget.materialId);

      debugPrint('📦 RawMaterialDetail _load: materialId=${widget.materialId}');
      debugPrint('   item=${item?.name} code=${item?.code}');
      debugPrint('   batches count=${(batchData['batches'] as List?)?.length ?? 0}');
      debugPrint('   ledger count=${ledgerData.length}');

      if (!mounted) return;
      setState(() {
        _name = item?.name ?? '';
        _code = item?.code ?? '';
        _unit = item?.unit ?? '';
        _currency = item?.currency ?? 'EGP';
        _categoryName = item?.categoryName ?? '';
        _quantity = item?.quantity ?? 0;
        _minimumStock = item?.minimumStock ?? 3000;
        _initialQuantity = item?.initialQuantity ?? 0;
        _initialAvgPrice = item?.initialAvgPrice ?? 0;
        _estimatedValue = (batchData['totalValue'] as num?)?.toDouble() ?? 0;
        _avgCost = (batchData['avgCost'] as num?)?.toDouble() ?? 0;
        final allBatches = (batchData['batches'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _allBatches = allBatches;
        _batches = allBatches.where((b) => ((b['remaining_quantity'] as num?)?.toDouble() ?? 0) > 0).toList();
        _stockLedger = ledgerData;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('❌ RawMaterialDetail _load error: $e');
      debugPrint('   $st');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _unitLabel(String unit) {
    const labels = {
      'piece': 'قطعة', 'kg': 'كجم', 'box': 'كرتونة',
      'roll': 'لفة', 'bag': 'كيس', 'meter': 'متر', 'liter': 'لتر',
    };
    return labels[unit] ?? unit;
  }

  Future<void> _exportPdf() async {
    final isLow = _quantity < _minimumStock && _quantity > 0;
    final isOut = _quantity == 0;
    final stockLabel = isOut ? 'نفد' : (isLow ? 'منخفض' : 'متوفر');

    try {
      await RawMaterialCardPdfService.generateAndPrint(
        itemName: _name,
        itemCode: _code,
        categoryName: _categoryName,
        unit: _unitLabel(_unit),
        currency: _currency,
        initialQuantity: _initialQuantity,
        initialAvgPrice: _initialAvgPrice,
        currentQuantity: _quantity,
        minimumStock: _minimumStock,
        estimatedValue: _estimatedValue,
        avgCost: _avgCost,
        statusLabel: stockLabel,
        batches: _batches,
      );
    } catch (e) {
      if (mounted) {
        UIUtils.showErrorSnackbar(context, 'فشل في طباعة كارت الصنف: $e');
      }
    }
  }

  Future<void> _savePdf() async {
    final isLow = _quantity < _minimumStock && _quantity > 0;
    final isOut = _quantity == 0;
    final stockLabel = isOut ? 'نفد' : (isLow ? 'منخفض' : 'متوفر');

    try {
      await RawMaterialCardPdfService.saveToFile(
        context,
        itemName: _name,
        itemCode: _code,
        categoryName: _categoryName,
        unit: _unitLabel(_unit),
        currency: _currency,
        initialQuantity: _initialQuantity,
        initialAvgPrice: _initialAvgPrice,
        currentQuantity: _quantity,
        minimumStock: _minimumStock,
        estimatedValue: _estimatedValue,
        avgCost: _avgCost,
        statusLabel: stockLabel,
        batches: _batches,
      );
    } catch (e) {
      if (mounted) {
        UIUtils.showErrorSnackbar(context, 'فشل في حفظ كارت الصنف: $e');
      }
    }
  }

  // ── Stock Ledger Filtered List ───────────────
  List<Map<String, dynamic>> get _filteredLedger {
    final query = _searchQuery.trim().toLowerCase();
    return _stockLedger.where((e) {
      // Warehouse filter
      if (_selectedWarehouse != null && _selectedWarehouse!.isNotEmpty) {
        if (e['warehouse']?.toString() != _selectedWarehouse) return false;
      }
      // Type filter
      if (_ledgerTypeFilter != 'all') {
        if (_ledgerTypeFilter == 'transfer') {
          if (e['type'] != 'transfer_in' && e['type'] != 'transfer_out') return false;
        } else {
          if (e['type'] != _ledgerTypeFilter) return false;
        }
      }
      // Date filter
      if (_filterStartDate != null) {
        final d = e['date'] is DateTime ? e['date'] as DateTime : DateTime.tryParse(e['date']?.toString() ?? '');
        if (d != null && d.isBefore(_filterStartDate!)) return false;
      }
      if (_filterEndDate != null) {
        final d = e['date'] is DateTime ? e['date'] as DateTime : DateTime.tryParse(e['date']?.toString() ?? '');
        final endOfDay = DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day, 23, 59, 59);
        if (d != null && d.isAfter(endOfDay)) return false;
      }
      // Search query
      if (query.isNotEmpty) {
        final ref = (e['ref']?.toString() ?? '').toLowerCase();
        final wh = (e['warehouse']?.toString() ?? '').toLowerCase();
        final typeLbl = (e['type_label']?.toString() ?? '').toLowerCase();
        if (!ref.contains(query) && !wh.contains(query) && !typeLbl.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Set<String> get _availableWarehouses {
    final s = <String>{};
    for (final e in _stockLedger) {
      final wh = e['warehouse']?.toString().trim();
      if (wh != null && wh.isNotEmpty) {
        s.add(wh);
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLow = _quantity < _minimumStock && _quantity > 0;
    final isOut = _quantity == 0;
    final stockColor = isOut ? AppTheme.danger : (isLow ? AppTheme.warning : AppTheme.success);
    final stockLabel = isOut ? 'نفد' : (isLow ? 'منخفض' : 'متوفر');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: _loading
            ? Center(child: CircularProgressIndicator(color: isDark ? AppTheme.primary : AppTheme.lightPrimary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isDark),
                    const SizedBox(height: 20),
                    _buildTabs(isDark),
                    const SizedBox(height: 20),
                    if (_selectedTab == 0) ...[
                      _buildStockOverview(stockColor, stockLabel, isDark),
                      if (isLow) ...[
                        const SizedBox(height: 12),
                        _buildLowStockWarning(isDark),
                      ],
                      const SizedBox(height: 24),
                      _buildBatchesSection(isDark),
                    ] else ...[
                      _buildStockLedgerSection(isDark),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// Reusable card container adapting seamlessly between light and dark modes
  Widget _buildCardContainer({
    required Widget child,
    required bool isDark,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    double borderRadius = 20,
  }) {
    if (isDark) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: AppTheme.glassCard(),
            child: child,
          ),
        ),
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Tabs Bar ──────────────────────────────
  Widget _buildTabs(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1)),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = MediaQuery.of(context).size.width;
          final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
          final isMobile = effectiveW < 650;

          return Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  index: 0,
                  title: isMobile ? 'الدفعات (FIFO)' : 'نظرة المخزون والدفعات (FIFO)',
                  icon: Icons.inventory_2_outlined,
                  count: _batches.length,
                  isDark: isDark,
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTabButton(
                  index: 1,
                  title: isMobile ? 'سجل الحركات' : 'سجل الحركات (Stock Ledger)',
                  icon: Icons.receipt_long_outlined,
                  count: _stockLedger.length,
                  isDark: isDark,
                  isMobile: isMobile,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String title,
    required IconData icon,
    required int count,
    required bool isDark,
    bool isMobile = false,
  }) {
    final isSelected = _selectedTab == index;
    final activeBg = isDark
        ? AppTheme.primary.withValues(alpha: 0.18)
        : const Color(0xFFE0F2FE);
    final activeBorder = isDark
        ? AppTheme.primary.withValues(alpha: 0.4)
        : const Color(0xFF0284C7);
    final textColor = isDark
        ? (isSelected ? Colors.white : AppTheme.textSecondary)
        : Colors.black;
    final iconColor = isDark
        ? (isSelected ? AppTheme.primary : AppTheme.textSecondary)
        : (isSelected ? const Color(0xFF0284C7) : Colors.black);

    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeBorder : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: isDark ? (isSelected ? FontWeight.bold : FontWeight.normal) : FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark
                    ? (isSelected ? AppTheme.primary.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06))
                    : (isSelected ? const Color(0xFFBAE6FD) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(12),
                border: isDark ? null : Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? (isSelected ? AppTheme.primary : AppTheme.textMuted)
                      : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stock Ledger Section ───────────────────
  Widget _buildStockLedgerSection(bool isDark) {
    final filtered = _filteredLedger;

    // Calculate dynamic totals for filtered entries
    double totalIn = 0;
    double totalOut = 0;
    for (final e in filtered) {
      totalIn += (e['in_qty'] as num?)?.toDouble() ?? 0.0;
      totalOut += (e['out_qty'] as num?)?.toDouble() ?? 0.0;
    }
    final netBalance = totalIn - totalOut;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLedgerSummaryCards(totalIn, totalOut, netBalance, filtered.length, isDark),
        const SizedBox(height: 20),
        _buildLedgerFilters(isDark),
        const SizedBox(height: 20),
        _buildLedgerTable(filtered, isDark),
      ],
    );
  }

  Widget _buildLedgerSummaryCards(double totalIn, double totalOut, double netBalance, int count, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.of(context).size.width;
        final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
        final isMobile = effectiveW < 750;

        final cards = [
          _buildSummaryMetricCard(
            title: 'إجمالي الوارد (+)',
            value: '${AppUtils.formatNumber(totalIn)} ${_unitLabel(_unit)}',
            icon: Icons.south_west_rounded,
            color: AppTheme.success,
            isDark: isDark,
          ),
          _buildSummaryMetricCard(
            title: 'إجمالي المنصرف (-)',
            value: '${AppUtils.formatNumber(totalOut)} ${_unitLabel(_unit)}',
            icon: Icons.north_east_rounded,
            color: AppTheme.danger,
            isDark: isDark,
          ),
          _buildSummaryMetricCard(
            title: _selectedWarehouse != null ? 'رصيد المخزن المحدد' : 'صافي الرصيد الحالي',
            value: '${AppUtils.formatNumber(netBalance)} ${_unitLabel(_unit)}',
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.primary,
            isDark: isDark,
          ),
          _buildSummaryMetricCard(
            title: 'عدد الحركات',
            value: '$count حركة',
            icon: Icons.receipt_long_outlined,
            color: AppTheme.accent,
            isDark: isDark,
          ),
        ];

        if (isMobile) {
          return SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 215,
                child: cards[i],
              ),
            ),
          );
        }

        return Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: c,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildSummaryMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.18) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? color : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerFilters(bool isDark) {
    return _buildCardContainer(
      isDark: isDark,
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Movement Type Chips
          Row(
            children: [
              Text(
                'نوع الحركة:',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textSecondary : Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTypeChip('all', 'الكل', isDark),
                      const SizedBox(width: 8),
                      _buildTypeChip('opening', 'رصيد افتتاحي', isDark),
                      const SizedBox(width: 8),
                      _buildTypeChip('purchase', 'مشتريات موردين', isDark),
                      const SizedBox(width: 8),
                      _buildTypeChip('packing', 'منصرف تعبئة', isDark),
                      const SizedBox(width: 8),
                      _buildTypeChip('transfer', 'تحويلات مخازن', isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Row 2: Warehouse dropdown, Date picker, Search bar
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Warehouse filter dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1),
                    width: 1.2,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedWarehouse,
                    dropdownColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                    icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppTheme.accent : Colors.black),
                    hint: Text(
                      'كافة المخازن',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.white70 : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'كافة المخازن والمحطات',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      ..._availableWarehouses.map(
                        (wh) => DropdownMenuItem<String?>(
                          value: wh,
                          child: Text(
                            wh,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedWarehouse = val),
                  ),
                ),
              ),
              // Date range picker button
              OutlinedButton.icon(
                onPressed: () => _pickDateRange(isDark),
                icon: Icon(Icons.date_range_rounded, size: 16, color: isDark ? AppTheme.accent : Colors.black),
                label: Text(
                  _filterStartDate != null && _filterEndDate != null
                      ? '${AppUtils.formatDate(_filterStartDate!)} - ${AppUtils.formatDate(_filterEndDate!)}'
                      : 'تحديد الفترة الزمنية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1),
                    width: 1.2,
                  ),
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              if (_filterStartDate != null || _filterEndDate != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                  tooltip: 'إلغاء فلتر التاريخ',
                  onPressed: () => setState(() {
                    _filterStartDate = null;
                    _filterEndDate = null;
                  }),
                ),
              // Search text field
              SizedBox(
                width: 250,
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'بحث في رقم الفاتورة أو المستند...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8),
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black54, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? AppTheme.primary : AppTheme.lightPrimary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String key, String label, bool isDark) {
    final isSelected = _ledgerTypeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _ledgerTypeFilter = key),
      selectedColor: isDark ? AppTheme.primary : const Color(0xFF0284C7),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: isSelected || !isDark ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(
        color: isSelected
            ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
            : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1)),
      ),
    );
  }

  Future<void> _pickDateRange(bool isDark) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _filterStartDate != null && _filterEndDate != null
          ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primary,
                    surface: Color(0xFF1E2638),
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.lightPrimary,
                    surface: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _filterStartDate = picked.start;
        _filterEndDate = picked.end;
      });
    }
  }

  Widget _buildLedgerTable(List<Map<String, dynamic>> items, bool isDark) {
    return _buildCardContainer(
      isDark: isDark,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.table_chart_outlined, color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تفاصيل الحركات التاريخية (Stock Ledger)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'عرض ${items.length} حركة',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : Colors.black,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.inventory_rounded, size: 48, color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8)),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد حركات مسجلة تطابق محددات البحث والفلاتر',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLedgerTableHeader(isDark),
                  Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                  ..._buildRecalculatedRows(items, isDark),
                  _buildLedgerTableFooter(items, isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRecalculatedRows(List<Map<String, dynamic>> items, bool isDark) {
    // If a specific warehouse is filtered, calculate running balance specifically for that warehouse
    final isSpecificWh = _selectedWarehouse != null && _selectedWarehouse!.isNotEmpty;
    double whRunning = 0;

    return items.asMap().entries.map((e) {
      final item = e.value;
      final index = e.key;

      double balanceToDisplay;
      if (isSpecificWh) {
        final inQ = (item['in_qty'] as num?)?.toDouble() ?? 0.0;
        final outQ = (item['out_qty'] as num?)?.toDouble() ?? 0.0;
        whRunning += (inQ - outQ);
        balanceToDisplay = AppUtils.roundDouble(whRunning);
      } else {
        balanceToDisplay = (item['balance'] as num?)?.toDouble() ?? 0.0;
      }

      return _buildLedgerRow(item, index, balanceToDisplay, isDark);
    }).toList();
  }

  Widget _buildLedgerTableHeader(bool isDark) {
    final textColor = isDark ? AppTheme.textSecondary : Colors.black;
    final fontWeight = isDark ? FontWeight.w600 : FontWeight.bold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          SizedBox(width: 35, child: Text('#', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 120, child: Text('التاريخ والوقت', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 125, child: Text('نوع الحركة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 170, child: Text('المرجع / المستند', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 110, child: Text('المخزن / المحطة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 90, child: Text('وارد (+)', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 90, child: Text('منصرف (-)', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 90, child: Text('سعر الوحدة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('القيمة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 110, child: Text('الرصيد بعد الحركة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildLedgerRow(Map<String, dynamic> row, int index, double displayBalance, bool isDark) {
    final type = row['type']?.toString() ?? '';
    final typeLabel = row['type_label']?.toString() ?? '';
    final ref = row['ref']?.toString() ?? '—';
    final warehouse = row['warehouse']?.toString() ?? '—';
    final inQty = (row['in_qty'] as num?)?.toDouble() ?? 0.0;
    final outQty = (row['out_qty'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (row['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final totalCost = (row['total_cost'] as num?)?.toDouble() ?? 0.0;
    final formattedDate = _formatDateTime(row['date']);
    final isEven = index % 2 == 0;

    final cellColor = isDark ? null : Colors.black;
    final cellFontWeight = isDark ? FontWeight.normal : FontWeight.bold;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isEven ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.04))
            : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 35, child: Text('${index + 1}', style: TextStyle(color: cellColor ?? AppTheme.textSecondary, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 120, child: Text(formattedDate, style: TextStyle(color: cellColor ?? Colors.white70, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 125, child: Center(child: _buildMovementBadge(type, typeLabel, isDark))),
          SizedBox(width: 170, child: Text(ref, style: TextStyle(color: cellColor ?? Colors.white, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 110, child: Text(warehouse, style: TextStyle(color: cellColor ?? AppTheme.info, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 12), overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 90,
            child: Text(
              inQty > 0 ? '+${AppUtils.formatNumber(inQty)}' : '—',
              style: TextStyle(
                color: cellColor ?? (inQty > 0 ? AppTheme.success : AppTheme.textMuted),
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              outQty > 0 ? '-${AppUtils.formatNumber(outQty)}' : '—',
              style: TextStyle(
                color: cellColor ?? (outQty > 0 ? AppTheme.danger : AppTheme.textMuted),
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              unitCost > 0 ? '${AppUtils.formatNumber(unitCost)} $_currency' : '—',
              style: TextStyle(color: cellColor ?? Colors.white70, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              totalCost > 0 ? '${AppUtils.formatNumber(totalCost)} $_currency' : '—',
              style: TextStyle(color: cellColor ?? AppTheme.textSecondary, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 110,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFCBD5E1)),
              ),
              child: Text(
                '${AppUtils.formatNumber(displayBalance)} ${_unitLabel(_unit)}',
                style: TextStyle(
                  color: cellColor ?? AppTheme.accent,
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementBadge(String type, String label, bool isDark) {
    Color color;
    IconData icon;

    switch (type) {
      case 'opening':
        color = const Color(0xFFF59E0B); // Amber
        icon = Icons.flag_outlined;
        break;
      case 'purchase':
        color = const Color(0xFF10B981); // Emerald
        icon = Icons.arrow_downward_rounded;
        break;
      case 'packing':
        color = const Color(0xFFEF4444); // Red
        icon = Icons.arrow_upward_rounded;
        break;
      case 'transfer_in':
        color = const Color(0xFF3B82F6); // Blue
        icon = Icons.input_rounded;
        break;
      case 'transfer_out':
        color = const Color(0xFF8B5CF6); // Purple
        icon = Icons.output_rounded;
        break;
      default:
        color = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
        icon = Icons.swap_horiz_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? color : Colors.black,
                fontSize: 10.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTableFooter(List<Map<String, dynamic>> items, bool isDark) {
    double sumIn = 0;
    double sumOut = 0;
    double sumVal = 0;
    for (final e in items) {
      sumIn += (e['in_qty'] as num?)?.toDouble() ?? 0.0;
      sumOut += (e['out_qty'] as num?)?.toDouble() ?? 0.0;
      sumVal += (e['total_cost'] as num?)?.toDouble() ?? 0.0;
    }

    final textColor = isDark ? null : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 35),
          SizedBox(
            width: 120,
            child: Text(
              'الإجمالي',
              style: TextStyle(color: textColor ?? AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
            ),
          ),
          const SizedBox(width: 125),
          const SizedBox(width: 170),
          const SizedBox(width: 110),
          SizedBox(
            width: 90,
            child: Text(
              '+${AppUtils.formatNumber(sumIn)}',
              style: TextStyle(color: textColor ?? AppTheme.success, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '-${AppUtils.formatNumber(sumOut)}',
              style: TextStyle(color: textColor ?? AppTheme.danger, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 90),
          SizedBox(
            width: 100,
            child: Text(
              '${AppUtils.formatNumber(sumVal)} $_currency',
              style: TextStyle(color: textColor ?? AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${AppUtils.formatNumber(sumIn - sumOut)} ${_unitLabel(_unit)}',
              style: TextStyle(color: textColor ?? AppTheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Existing Components (Header, Overview, Batches) ─────────
  Widget _buildHeader(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.of(context).size.width;
        final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
        final isMobile = effectiveW < 750;

        final titleSection = Row(
          children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                ),
                child: Icon(Icons.arrow_forward_ios, color: isDark ? Colors.white70 : Colors.black, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.accent.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFFBAE6FD)),
              ),
              child: Icon(Icons.inventory_outlined, color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        _code,
                        style: TextStyle(
                          color: isDark ? AppTheme.accent : Colors.black,
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_categoryName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            _categoryName,
                            style: TextStyle(
                              color: isDark ? AppTheme.primary : Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white70 : Colors.black),
              tooltip: 'تحديث البيانات',
              onPressed: _load,
            ),
          ],
        );

        final actionButtons = Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text(
                  'طباعة كارت الصنف',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _savePdf,
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label: Text(
                  'حفظ PDF',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFF00B4D8) : const Color(0xFF0284C7),
                  side: BorderSide(color: isDark ? const Color(0xFF00B4D8) : const Color(0xFF0284C7)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        );

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleSection,
              const SizedBox(height: 12),
              actionButtons,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleSection),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text(
                'طباعة كارت الصنف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _savePdf,
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: Text(
                'حفظ PDF',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? const Color(0xFF00B4D8) : const Color(0xFF0284C7),
                side: BorderSide(color: isDark ? const Color(0xFF00B4D8) : const Color(0xFF0284C7)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStockOverview(Color stockColor, String stockLabel, bool isDark) {
    final consumedQty = (_initialQuantity - _quantity).clamp(0.0, double.infinity);
    final consumedValue = consumedQty * _initialAvgPrice;
    final hasOpening = _initialQuantity > 0;

    final openingBatch = _allBatches.where((b) {
      final bn = b['batch_number']?.toString() ?? '';
      return bn.startsWith('OPENING');
    }).toList();
    final openingRemaining = openingBatch.fold<double>(0, (s, b) => s + ((b['remaining_quantity'] as num?)?.toDouble() ?? 0));
    final showOpening = hasOpening && openingRemaining > 0;

    return _buildCardContainer(
      isDark: isDark,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warehouse_outlined, color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'نظرة المخزون',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),

          if (showOpening) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? null : const Color(0xFFF8FAFC),
                gradient: isDark
                    ? LinearGradient(
                        colors: [
                          AppTheme.accent.withValues(alpha: 0.08),
                          AppTheme.accent.withValues(alpha: 0.02),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppTheme.accent.withValues(alpha: 0.15) : const Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, size: 16, color: isDark ? AppTheme.accent : Colors.black),
                      const SizedBox(width: 6),
                      Text(
                        'الرصيد المبدأي',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.accent : Colors.black,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildMiniStat('الكمية', '${openingRemaining.toStringAsFixed(0)} ${_unitLabel(_unit)}', AppTheme.accent, isDark),
                      const SizedBox(width: 16),
                      _buildMiniStat('السعر', '${AppUtils.formatNumber(_initialAvgPrice)} $_currency', AppTheme.accent, isDark),
                      const SizedBox(width: 16),
                      _buildMiniStat('القيمة', '${AppUtils.formatNumber(openingRemaining * _initialAvgPrice)} $_currency', AppTheme.accent, isDark),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('المتبقي', '${_quantity.toStringAsFixed(0)} ${_unitLabel(_unit)}', stockColor, isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('القيمة التقديرية', '${AppUtils.formatNumber(_estimatedValue)} $_currency', AppTheme.primary, isDark)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('متوسط التكلفة', '${AppUtils.formatNumber(_avgCost)} $_currency', AppTheme.accent, isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('الحالة', stockLabel, stockColor, isDark)),
            ],
          ),

          if (hasOpening && consumedQty > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('المستهلك', '${consumedQty.toStringAsFixed(0)} ${_unitLabel(_unit)}', AppTheme.danger, isDark)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('قيمة المستهلك', '${AppUtils.formatNumber(consumedValue)} $_currency', AppTheme.danger, isDark)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            color: isDark ? AppTheme.textMuted : Colors.black,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? color : Colors.black,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.15) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDark && label == 'الحالة') ...[
                  Container(
                    width: 8, height: 8,
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                ],
                Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? color : Colors.black,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockWarning(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.warning.withValues(alpha: 0.08) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.warning.withValues(alpha: 0.3) : const Color(0xFFF59E0B),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: isDark ? AppTheme.warning : const Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الكمية أقل من ${_minimumStock.toStringAsFixed(0)} — يجب إعادة الطلب',
              style: TextStyle(
                color: isDark ? AppTheme.warning : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchesSection(bool isDark) {
    return _buildCardContainer(
      isDark: isDark,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_shipping_outlined, color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'الدفعات (FIFO)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'كل دفعة بسعر وتاريخ مختلف — أول دفعة تستخدم أولاً',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.7) : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 16),
          if (_batches.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'لا توجد دفعات بعد',
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  _buildBatchTableHeader(isDark),
                  Divider(height: 1, color: isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
                  ..._batches.asMap().entries.map((e) => _buildBatchRow(e.value, e.key, isDark)),
                  _buildBatchFooter(isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBatchTableHeader(bool isDark) {
    final textColor = isDark ? AppTheme.textSecondary : Colors.black;
    final fontWeight = isDark ? FontWeight.w600 : FontWeight.bold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text('#', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 80, child: Text('التاريخ', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 100, child: Text('المخزن', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 130, child: Text('المورد / الفاتورة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12))),
          SizedBox(width: 80, child: Text('الكمية المتاحة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('سعر الصرف', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('سعر الوحدة', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('القيمة الإجمالية', style: TextStyle(color: textColor, fontWeight: fontWeight, fontFamily: 'Cairo', fontSize: 12), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildBatchRow(Map<String, dynamic> batch, int index, bool isDark) {
    final rem = (batch['remaining_quantity'] as num?)?.toDouble() ?? 0;
    final cost = (batch['purchase_cost'] as num?)?.toDouble() ?? 0;
    final exchangeRate = (batch['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    final totalRem = rem * cost;
    final date = _toLocalDate(batch['created_at']);
    final station = batch['station_name']?.toString() ?? '';
    final supplierName = batch['supplier_name']?.toString() ?? '';
    final invoiceNumber = batch['invoice_number']?.toString() ?? '';
    String sourceDesc = supplierName.isNotEmpty ? supplierName : (batch['source_type'] == 'opening' ? 'رصيد افتتاحي' : 'مشتريات');
    if (invoiceNumber.isNotEmpty) sourceDesc += ' | $invoiceNumber';
    final isEven = index % 2 == 0;

    final cellColor = isDark ? null : Colors.black;
    final cellFontWeight = isDark ? FontWeight.normal : FontWeight.bold;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (isEven ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.04))
            : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text('${index + 1}', style: TextStyle(color: cellColor ?? AppTheme.textSecondary, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(width: 80, child: Text(date, style: TextStyle(color: cellColor ?? Colors.white, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(width: 100, child: Text(station.isNotEmpty ? station : 'المخزن', style: TextStyle(color: cellColor ?? AppTheme.info, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 130, child: Text(sourceDesc, style: TextStyle(color: cellColor ?? Colors.white, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 80,
            child: Text(
              rem.toStringAsFixed(0),
              style: TextStyle(
                color: cellColor ?? (rem > 0 ? AppTheme.success : AppTheme.textSecondary),
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              exchangeRate == 1.0 ? '—' : exchangeRate.toStringAsFixed(4),
              style: TextStyle(
                color: cellColor ?? (exchangeRate == 1.0 ? AppTheme.textSecondary : AppTheme.info),
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: cellFontWeight,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${AppUtils.formatNumber(cost)} $_currency',
              style: TextStyle(color: cellColor ?? Colors.white, fontWeight: cellFontWeight, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              '${AppUtils.formatNumber(totalRem)} $_currency',
              style: TextStyle(
                color: cellColor ?? AppTheme.accent,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchFooter(bool isDark) {
    final totalRem = _batches.fold<double>(0, (s, b) => s + ((b['remaining_quantity'] as num?)?.toDouble() ?? 0));
    final totalRemVal = _batches.fold<double>(0, (s, b) {
      final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0;
      final cost = (b['purchase_cost'] as num?)?.toDouble() ?? 0;
      return s + rem * cost;
    });

    final textColor = isDark ? AppTheme.accent : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 30),
          SizedBox(width: 80, child: Text('الإجمالي', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13))),
          const SizedBox(width: 100),
          const SizedBox(width: 130),
          SizedBox(width: 80, child: Text(totalRem.toStringAsFixed(0), style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13), textAlign: TextAlign.center)),
          const SizedBox(width: 70),
          const SizedBox(width: 80),
          SizedBox(width: 100, child: Text('${AppUtils.formatNumber(totalRemVal)} $_currency', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13), textAlign: TextAlign.center)),
        ],
      ),
    );
  }


  String _formatDateTime(dynamic raw) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.tryParse(raw.toString());
    }
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  String _toLocalDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString().substring(0, raw.toString().length >= 10 ? 10 : raw.toString().length);
    }
  }
}
