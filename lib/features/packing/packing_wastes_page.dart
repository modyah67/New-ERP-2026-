import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/theme.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/models/packing_waste_model.dart';
import '../../data/dao/packing_waste_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/services/journal_entry_navigation_service.dart';

class PackingWastesPage extends StatefulWidget {
  const PackingWastesPage({super.key});

  @override
  State<PackingWastesPage> createState() => _PackingWastesPageState();
}

class _PackingWastesPageState extends State<PackingWastesPage> {
  final _dao = PackingWasteDao();
  final _stationDao = StationDao();

  List<PackingWasteModel> _allWastes = [];
  List<PackingWasteModel> _filtered = [];
  Map<int, String> _stationNames = {};

  bool _loading = true;
  String _selectedStatus = 'all'; // all, draft, completed
  final _searchCtrl = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;

  StreamSubscription? _wasteSub;
  StreamSubscription? _stationSub;

  @override
  void initState() {
    super.initState();
    _load();
    _wasteSub = DataChangeEventBus.instance.packingWastesStream.listen((_) => _load());
    _stationSub = DataChangeEventBus.instance.stationsStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _wasteSub?.cancel();
    _stationSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stations = await _stationDao.getAll();
      _stationNames = {
        for (final s in stations)
          if (s.id != null) int.tryParse(s.id!) ?? 0: s.name,
      };
      _allWastes = await _dao.getAll();
    } catch (e) {
      debugPrint('Error loading packing wastes: $e');
    }
    _applyFilters();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();
    _filtered = _allWastes.where((w) {
      if (_selectedStatus != 'all' && w.status != _selectedStatus) {
        return false;
      }
      if (q.isNotEmpty) {
        final matchNum = w.wasteNumber.toLowerCase().contains(q);
        final stationName = _stationNames[w.stationId]?.toLowerCase() ?? '';
        final matchStation = stationName.contains(q);
        if (!matchNum && !matchStation) return false;
      }
      if (_dateFrom != null && w.date.isBefore(_dateFrom!)) {
        return false;
      }
      if (_dateTo != null) {
        final endOfDay = _dateTo!.add(const Duration(days: 1));
        if (w.date.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return AppTheme.warning;
      case 'completed':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'completed':
        return 'مؤكد';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? DateTime.now()) : (_dateTo ?? DateTime.now()),
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
        _applyFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _navigateToForm(),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('إذن هالك جديد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
        body: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                  ),
                )
              : null,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(isDark),
                _buildKpiSummary(isDark),
                _buildSearchBar(isDark),
                Expanded(child: _buildBody(isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_sweep_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('أذون هالك التعبئة',
                        style: TextStyle(
                            color: isDark ? AppTheme.textPrimary : Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    Text('إدارة وتتبع هالك المحاصيل، مواد التعبئة، والفرز',
                        style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: Icon(Icons.refresh_rounded, color: isDark ? AppTheme.textSecondary : Colors.black87),
                tooltip: 'تحديث',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSummary(bool isDark) {
    final totalCount = _allWastes.length;
    final draftCount = _allWastes.where((w) => w.status == 'draft').length;
    final completedCount = _allWastes.where((w) => w.status == 'completed').length;
    final totalAmount = _allWastes.fold(0.0, (s, w) => s + w.totalWasteAmount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildKpiCard('إجمالي الأذون', '$totalCount', Icons.receipt_long, AppTheme.primary, isNarrow, isDark),
              _buildKpiCard('مسودات', '$draftCount', Icons.edit_note, AppTheme.warning, isNarrow, isDark),
              _buildKpiCard('أذون معتمدة', '$completedCount', Icons.check_circle_outline, AppTheme.success, isNarrow, isDark),
              _buildKpiCard('إجمالي قيمة الهالك', '${totalAmount.toStringAsFixed(2)} ج.م', Icons.monetization_on_outlined, const Color(0xFFEC4899), isNarrow, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, bool isNarrow, bool isDark) {
    return Container(
      width: isNarrow ? double.infinity : 200,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1A05192D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? color.withAlpha(50) : const Color(0xFFCBD5E1)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
              ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'بحث برقم الإذن أو المحطة...',
                    hintStyle: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                    prefixIcon: Icon(Icons.search, color: isDark ? AppTheme.textSecondary : Colors.black54, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: isDark ? AppTheme.textSecondary : Colors.black54, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _applyFilters());
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0x2005192D) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                  onChanged: (_) => setState(() => _applyFilters()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStatusFilterChip('الكل', 'all', isDark),
              _buildStatusFilterChip('مسودة', 'draft', isDark),
              _buildStatusFilterChip('مؤكد', 'completed', isDark),
              const SizedBox(width: 8),
              _dateFilterChip(
                icon: Icons.date_range,
                label: _dateFrom != null ? DateFormat('yyyy/MM/dd').format(_dateFrom!) : 'من تاريخ',
                onTap: () => _pickDate(isFrom: true),
                active: _dateFrom != null,
                isDark: isDark,
                onClear: () {
                  setState(() {
                    _dateFrom = null;
                    _applyFilters();
                  });
                },
              ),
              _dateFilterChip(
                icon: Icons.date_range,
                label: _dateTo != null ? DateFormat('yyyy/MM/dd').format(_dateTo!) : 'إلى تاريخ',
                onTap: () => _pickDate(isFrom: false),
                active: _dateTo != null,
                isDark: isDark,
                onClear: () {
                  setState(() {
                    _dateTo = null;
                    _applyFilters();
                  });
                },
              ),
              if (_dateFrom != null || _dateTo != null || _searchCtrl.text.isNotEmpty || _selectedStatus != 'all')
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                      _selectedStatus = 'all';
                      _applyFilters();
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('مسح الفلاتر', style: TextStyle(color: AppTheme.danger, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String status, bool isDark) {
    final active = _selectedStatus == status;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStatus = status;
          _applyFilters();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : (isDark ? AppTheme.surface : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.primary : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: active ? Colors.white : (isDark ? AppTheme.textSecondary : Colors.black87),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _dateFilterChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool active,
    required bool isDark,
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppTheme.primary.withAlpha(30) : const Color(0xFFE0F2FE))
              : (isDark ? AppTheme.surface : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? (isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFF0284C7))
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? AppTheme.textSecondary : Colors.black87)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: active
                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                        : (isDark ? AppTheme.textSecondary : Colors.black87),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            if (active && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 12, color: AppTheme.danger)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 64, color: isDark ? AppTheme.textSecondary.withAlpha(80) : Colors.black26),
            const SizedBox(height: 16),
            Text('لا توجد أذون هالك مطابقة',
                style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filtered.length,
      itemBuilder: (ctx, idx) => _buildWasteCard(_filtered[idx], isDark),
    );
  }

  Widget _buildWasteCard(PackingWasteModel waste, bool isDark) {
    final statusColor = _statusColor(waste.status);
    final stationName = _stationNames[waste.stationId] ?? 'محطة غير محددة';
    final dateStr = DateFormat('yyyy/MM/dd').format(waste.date);
    final isDraft = waste.status == 'draft';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x1F05192D) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withAlpha(60)),
                      ),
                      child: Icon(isDraft ? Icons.edit_note : Icons.verified_outlined, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(waste.wasteNumber,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.warehouse_outlined, size: 14, color: isDark ? AppTheme.textSecondary : Colors.black54),
                              const SizedBox(width: 4),
                              Text(stationName,
                                  style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                              const SizedBox(width: 12),
                              Icon(Icons.calendar_today, size: 14, color: isDark ? AppTheme.textSecondary : Colors.black54),
                              const SizedBox(width: 4),
                              Text(dateStr,
                                  style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(waste.status, statusColor),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _buildAmountSnippet('هالك المحاصيل:', waste.totalCropWasteCost, isDark),
                    _buildAmountSnippet('مخزون الفرز:', waste.totalSortingCost, isDark),
                    _buildAmountSnippet('هالك المواد:', waste.totalMaterialWasteCost, isDark),
                    _buildAmountSnippet('بنود التكلفة:', waste.totalCostItems, isDark),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text('الإجمالي العام: ',
                            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        Text(
                          '${waste.totalWasteAmount.toStringAsFixed(2)} ج.م',
                          style: TextStyle(color: isDark ? AppTheme.primary : const Color(0xFF0284C7), fontSize: 15, fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (isDraft) ...[
                          _buildActionButton(
                            icon: Icons.edit_outlined,
                            label: 'تعديل',
                            color: AppTheme.primary,
                            onTap: () => _navigateToForm(wasteId: waste.id),
                          ),
                          _buildActionButton(
                            icon: Icons.check_circle_outline,
                            label: 'تأكيد',
                            color: AppTheme.success,
                            onTap: () => _confirmWaste(waste),
                          ),
                          _buildActionButton(
                            icon: Icons.delete_outline,
                            label: 'حذف',
                            color: AppTheme.danger,
                            onTap: () => _deleteDraft(waste),
                          ),
                        ] else ...[
                          _buildActionButton(
                            icon: Icons.visibility_outlined,
                            label: 'عرض',
                            color: AppTheme.accent,
                            onTap: () => _navigateToForm(wasteId: waste.id, viewOnly: true),
                          ),
                          if (waste.journalEntryId != null)
                            _buildActionButton(
                              icon: Icons.receipt_long,
                              label: 'القيد',
                              color: const Color(0xFF8B5CF6),
                              onTap: () {
                                JournalEntryNavigationService.openById(context, journalEntryId: waste.journalEntryId!);
                              },
                            ),
                        ],
                      ],
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

  Widget _buildAmountSnippet(String title, double amount, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        const SizedBox(width: 4),
        Text('${amount.toStringAsFixed(2)} ج.م',
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  void _navigateToForm({int? wasteId, bool viewOnly = false}) async {
    final result = await context.push<bool>(
      '/packing/waste/form',
      extra: {'wasteId': wasteId, 'viewOnly': viewOnly},
    );
    if (result == true) {
      _load();
    }
  }

  Future<void> _confirmWaste(PackingWasteModel waste) async {
    if (waste.id == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        title: Text('تأكيد إذن هالك التعبئة', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من تأكيد إذن الهالك ${waste.wasteNumber}؟\nسيتم خصم الكميات من المخزن وإثبات الفرز والقيد المحاسبي بشكل نهائي.',
          style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('تأكيد واعتماد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final error = await _dao.confirmWaste(waste.id!);
    if (mounted) {
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اعتماد إذن الهالك بنجاح'), backgroundColor: AppTheme.success));
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyPackingWastesChanged();
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $error'), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _deleteDraft(PackingWasteModel waste) async {
    if (waste.id == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        title: Text('حذف مسودة إذن الهالك', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف المسودة ${waste.wasteNumber}؟', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('حذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _dao.deleteDraft(waste.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المسودة بنجاح'), backgroundColor: AppTheme.success));
        DataChangeEventBus.instance.notifyPackingWastesChanged();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger));
      }
    }
  }
}
