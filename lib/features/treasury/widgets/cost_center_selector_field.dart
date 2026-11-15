import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/cost_center.dart';
import '../../../data/services/cost_center_service.dart';

/// A specialized selector field for binding Treasury Expense Disbursals
/// directly to an ERP Cost Center (Operational or Crop Seasonal Line).
class CostCenterSelectorField extends StatefulWidget {
  final String? selectedCostCenterId;
  final ValueChanged<String?> onSelected;
  final bool isRequired;
  final String? label;
  final CostCenterType? filterType;
  final bool showNoneOption;

  const CostCenterSelectorField({
    super.key,
    required this.selectedCostCenterId,
    required this.onSelected,
    this.isRequired = false,
    this.label,
    this.filterType,
    this.showNoneOption = true,
  });

  static final List<CostCenter> fallbackCenters = [
    // 1. Operational Centers
    CostCenterHelper.generalAdmin,
    CostCenterHelper.packingStation,
    CostCenterHelper.freightLogistics,
    CostCenterHelper.customsClearance,

    // 2. Production Variety Lines
    CostCenterHelper.strawberryLine,
    CostCenterHelper.mangoLine,
    CostCenterHelper.grapesLine,
    CostCenterHelper.citrusLine,
    CostCenterHelper.bananaLine,
    CostCenterHelper.sharedProducts,
  ];

  static void showPicker(
    BuildContext context, {
    required String? selectedId,
    required ValueChanged<String?> onSelected,
    CostCenterType? filterType,
    bool showNoneOption = true,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CostCenterPickerModal(
        selectedId: selectedId,
        onSelected: onSelected,
        filterType: filterType,
        showNoneOption: showNoneOption,
      ),
    );
  }

  @override
  State<CostCenterSelectorField> createState() => _CostCenterSelectorFieldState();
}

class _CostCenterSelectorFieldState extends State<CostCenterSelectorField> {
  CostCenter? _resolvedCenter;

  @override
  void initState() {
    super.initState();
    _resolveCenter();
  }

  @override
  void didUpdateWidget(covariant CostCenterSelectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCostCenterId != widget.selectedCostCenterId) {
      _resolveCenter();
    }
  }

  Future<void> _resolveCenter() async {
    final id = widget.selectedCostCenterId;
    if (id == null || id.trim().isEmpty) {
      if (mounted) setState(() => _resolvedCenter = null);
      return;
    }

    final target = id.trim().toLowerCase();

    // 1. Try finding in dynamic service first (has latest database cost centers & codes)
    try {
      final all = await CostCenterService.instance.fetchCostCenters();
      final match = all.where((c) {
        final cid = c.id.trim().toLowerCase();
        final ccode = (c.code ?? '').trim().toLowerCase();
        final cdbId = (c.dbId?.toString() ?? '').trim().toLowerCase();
        return cid == target || (ccode.isNotEmpty && ccode == target) || (cdbId.isNotEmpty && cdbId == target);
      }).firstOrNull;
      if (match != null) {
        if (mounted) setState(() => _resolvedCenter = match);
        return;
      }
    } catch (_) {}

    // 2. Fallback to static helper definitions
    final center = CostCenterHelper.fromId(id, CostCenterSelectorField.fallbackCenters);
    if (mounted) setState(() => _resolvedCenter = center);
  }

  void _showCostCenterPicker(BuildContext context) {
    CostCenterSelectorField.showPicker(
      context,
      selectedId: widget.selectedCostCenterId,
      filterType: widget.filterType,
      showNoneOption: widget.showNoneOption,
      onSelected: (id) {
        widget.onSelected(id);
        _resolveCenter();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCenter = _resolvedCenter ??
        (widget.selectedCostCenterId != null && widget.selectedCostCenterId!.isNotEmpty
            ? CostCenterHelper.fromId(widget.selectedCostCenterId)
            : null);

    final color = currentCenter?.color ?? (isDark ? AppTheme.textMuted : const Color(0xFF64748B));
    final icon = currentCenter?.icon ?? Icons.track_changes_outlined;
    final nameAr = currentCenter?.nameAr ?? 'عام (بدون مركز تكلفة محدد)';
    final typeLabel = currentCenter != null
        ? (currentCenter.type == CostCenterType.variety ? 'محصول / موسم' : 'مركز تشغيلي')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.pie_chart_outline_rounded, size: 15, color: AppTheme.warning),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.label ?? 'مركز التكلفة / الموسم (Cost Center / Season)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            if (widget.isRequired)
              const Text(' *', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (currentCenter != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  typeLabel ?? '',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _showCostCenterPicker(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D2137) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: currentCenter != null
                    ? color.withValues(alpha: 0.6)
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                width: currentCenter != null ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nameAr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark
                                    ? (currentCenter != null ? Colors.white : AppTheme.textSecondary)
                                    : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                          if (currentCenter?.season != null && currentCenter!.season!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'موسم ${currentCenter.season}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (currentCenter != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${currentCenter.code ?? currentCenter.id} • ${currentCenter.nameEn}',
                          style: TextStyle(
                            color: isDark ? AppTheme.textMuted.withValues(alpha: 0.8) : Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (currentCenter != null)
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => widget.onSelected(null),
                    tooltip: 'إلغاء التحديد',
                  ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 20, color: isDark ? AppTheme.textMuted : const Color(0xFF475569)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CostCenterPickerModal extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final CostCenterType? filterType;
  final bool showNoneOption;

  const _CostCenterPickerModal({
    required this.selectedId,
    required this.onSelected,
    this.filterType,
    this.showNoneOption = true,
  });

  @override
  State<_CostCenterPickerModal> createState() => _CostCenterPickerModalState();
}

class _CostCenterPickerModalState extends State<_CostCenterPickerModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<CostCenter> _centers = [];
  List<CostCenter> _filteredCenters = [];
  bool _isLoading = true;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _loadCenters();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isCenterSelected(CostCenter c) {
    if (_selectedId == null || _selectedId!.trim().isEmpty) return false;
    final sel = _selectedId!.trim().toLowerCase();
    final cid = c.id.trim().toLowerCase();
    final ccode = (c.code ?? '').trim().toLowerCase();
    final cdbId = (c.dbId?.toString() ?? '').trim().toLowerCase();

    return cid == sel || (ccode.isNotEmpty && ccode == sel) || (cdbId.isNotEmpty && cdbId == sel);
  }

  void _selectCenter(CostCenter? c) {
    final newId = c?.id;
    setState(() {
      _selectedId = newId;
    });
    widget.onSelected(newId);
    Navigator.of(context).pop();
  }

  Future<void> _loadCenters() async {
    try {
      final dynamicList = await CostCenterService.instance.fetchCostCenters();
      var list = dynamicList.isNotEmpty ? dynamicList : CostCenterSelectorField.fallbackCenters;
      if (widget.filterType != null) {
        list = list.where((c) => c.type == widget.filterType).toList();
      }
      if (mounted) {
        setState(() {
          _centers = list;
          _filteredCenters = _centers;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        var list = CostCenterSelectorField.fallbackCenters;
        if (widget.filterType != null) {
          list = list.where((c) => c.type == widget.filterType).toList();
        }
        setState(() {
          _centers = list;
          _filteredCenters = _centers;
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredCenters = _centers;
      } else {
        _filteredCenters = _centers.where((c) {
          final ar = c.nameAr.toLowerCase();
          final en = c.nameEn.toLowerCase();
          final cd = (c.code ?? c.id).toLowerCase();
          final sea = (c.season ?? '').toLowerCase();
          final crop = (c.cropName ?? '').toLowerCase();
          return ar.contains(q) || en.contains(q) || cd.contains(q) || sea.contains(q) || crop.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showOperational = widget.filterType == null || widget.filterType == CostCenterType.operational;
    final showVarieties = widget.filterType == null || widget.filterType == CostCenterType.variety;

    final operational = showOperational
        ? _filteredCenters.where((c) => c.type == CostCenterType.operational).toList()
        : <CostCenter>[];
    final varieties = showVarieties
        ? _filteredCenters.where((c) => c.type == CostCenterType.variety).toList()
        : <CostCenter>[];

    final modalTitle = widget.filterType == CostCenterType.variety
        ? 'تحديد خط الإنتاج / المحصول الزراعي'
        : widget.filterType == CostCenterType.operational
            ? 'تحديد مركز التكلفة التشغيلي'
            : 'تحديد مركز التكلفة / الموسم';

    final searchHint = widget.filterType == CostCenterType.variety
        ? 'بحث باسم المحصول أو الموسم (مثل: مانجو، فراولة، 2026-2027)...'
        : 'بحث باسم المحصول أو الموسم أو مركز التكلفة...';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1E34) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
              width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  widget.filterType == CostCenterType.variety ? Icons.eco_outlined : Icons.pie_chart_outline_rounded,
                  color: widget.filterType == CostCenterType.variety ? const Color(0xFF10B981) : AppTheme.warning,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    modalTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 1),

          // Search Box
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
              decoration: InputDecoration(
                hintText: searchHint,
                hintStyle: TextStyle(
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
                prefixIcon: Icon(
                  Icons.search,
                  color: widget.filterType == CostCenterType.variety ? const Color(0xFF10B981) : AppTheme.warning,
                  size: 18,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF0D2137) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: AppTheme.warning),
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.warning))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Production / Seasonal Crops Section first (Agricultural priority)
                        if (varieties.isNotEmpty) ...[
                          _buildSectionHeader(
                            'خطوط الإنتاج والمحاصيل الزراعية (Crop Seasons)',
                            Icons.eco_outlined,
                            const Color(0xFF10B981),
                          ),
                          const SizedBox(height: 8),
                          ...varieties.map((c) => _buildCenterTile(context, c)),
                          const SizedBox(height: 16),
                        ],

                        // Operational Centers Section
                        if (operational.isNotEmpty) ...[
                          _buildSectionHeader(
                            'مراكز التكلفة التشغيلية (Operational Lines)',
                            Icons.business_center_outlined,
                            const Color(0xFF3B82F6),
                          ),
                          const SizedBox(height: 8),
                          ...operational.map((c) => _buildCenterTile(context, c)),
                          const SizedBox(height: 16),
                        ],

                        // Optional None / General option
                        if (widget.showNoneOption) ...[
                          ListTile(
                            onTap: () => _selectCenter(null),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.block_outlined, size: 18, color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                            ),
                            title: Text(
                              'بدون مركز تكلفة محدد (عام)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppTheme.textSecondary : Colors.black,
                              ),
                            ),
                            trailing: (_selectedId == null || _selectedId!.trim().isEmpty)
                                ? const Icon(Icons.check_circle, color: AppTheme.primary, size: 20)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color headerColor) {
    return Row(
      children: [
        Icon(icon, size: 15, color: headerColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: headerColor,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildCenterTile(BuildContext context, CostCenter c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _isCenterSelected(c);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? c.color.withValues(alpha: isDark ? 0.12 : 0.15)
            : (isDark ? const Color(0xFF0D2137) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? c.color
              : (isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        onTap: () => _selectCenter(c),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: c.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(c.icon, size: 18, color: c.color),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                c.nameAr,
                style: TextStyle(
                  color: isSelected
                      ? (isDark ? Colors.white : c.color)
                      : (isDark ? AppTheme.textPrimary : Colors.black),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            if (c.season != null && c.season!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'موسم ${c.season}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
            if (c.seasonStatus == 'closed') ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'مغلق',
                  style: TextStyle(
                    fontSize: 8,
                    color: AppTheme.danger,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${c.code ?? c.id} • ${c.nameEn}',
          style: TextStyle(
            color: isDark ? AppTheme.textMuted.withValues(alpha: 0.7) : Colors.black87,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: c.color, size: 20)
            : Icon(Icons.radio_button_unchecked, color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8), size: 16),
      ),
    );
  }
}
