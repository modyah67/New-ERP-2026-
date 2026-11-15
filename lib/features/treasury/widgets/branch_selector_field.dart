import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/dao/station_dao.dart';
import '../../../data/models/station_model.dart';

/// A specialized selector field for binding Treasury Expenses, Disbursements,
/// and Custody Transfers to an ERP Station / Branch (الفرع / المحطة).
class BranchSelectorField extends StatefulWidget {
  final dynamic selectedBranchId;
  final ValueChanged<dynamic> onSelected;
  final ValueChanged<StationModel?>? onStationSelected;
  final bool isRequired;
  final String? label;
  final String? hint;

  const BranchSelectorField({
    super.key,
    required this.selectedBranchId,
    required this.onSelected,
    this.onStationSelected,
    this.isRequired = false,
    this.label,
    this.hint,
  });

  @override
  State<BranchSelectorField> createState() => _BranchSelectorFieldState();
}

class _BranchSelectorFieldState extends State<BranchSelectorField> {
  StationModel? _currentStation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStation();
  }

  @override
  void didUpdateWidget(covariant BranchSelectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedBranchId?.toString() != widget.selectedBranchId?.toString()) {
      _loadStation();
    }
  }

  Future<void> _loadStation() async {
    final rawId = widget.selectedBranchId?.toString();
    if (rawId == null || rawId.isEmpty) {
      if (mounted) setState(() => _currentStation = null);
      widget.onStationSelected?.call(null);
      return;
    }

    // Check if current matches
    if (_currentStation?.id?.toString() == rawId) {
      widget.onStationSelected?.call(_currentStation);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final station = await StationDao().getById(rawId);
      if (mounted) {
        setState(() {
          _currentStation = station;
          _isLoading = false;
        });
        widget.onStationSelected?.call(station);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBranchPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BranchPickerModal(
        selectedId: widget.selectedBranchId?.toString(),
        onSelected: (station) {
          widget.onSelected(station?.id);
          widget.onStationSelected?.call(station);
          setState(() => _currentStation = station);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF00B4D8);
    const icon = Icons.storefront_outlined;
    final name = _currentStation?.name ?? widget.hint ?? 'عام (كل الفروع / المحطات)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.business_outlined, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              widget.label ?? 'الفرع / المحطة (Branch / Station)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'Cairo',
              ),
            ),
            if (widget.isRequired)
              const Text(' *', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_currentStation != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _currentStation!.isMain ? 'محطة رئيسية' : 'محطة فرعية',
                  style: const TextStyle(
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
          onTap: () => _showBranchPicker(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2137),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _currentStation != null ? color.withValues(alpha: 0.6) : AppTheme.glassBorder,
                width: _currentStation != null ? 1.5 : 1.0,
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
                  child: const Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _currentStation != null ? Colors.white : AppTheme.textSecondary,
                          fontWeight: _currentStation != null ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      if (_currentStation != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'كود: ${_currentStation!.code}',
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                else if (_currentStation != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      widget.onSelected(null);
                      widget.onStationSelected?.call(null);
                      setState(() => _currentStation = null);
                    },
                    tooltip: 'إلغاء التحديد',
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BranchPickerModal extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<StationModel?> onSelected;

  const _BranchPickerModal({
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_BranchPickerModal> createState() => _BranchPickerModalState();
}

class _BranchPickerModalState extends State<_BranchPickerModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<StationModel> _stations = [];
  List<StationModel> _filteredStations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStations();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    try {
      final list = await StationDao().getAll(limit: 100);
      if (mounted) {
        setState(() {
          _stations = list;
          _filteredStations = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStations = _stations;
      } else {
        _filteredStations = _stations.where((s) {
          final n = s.name.toLowerCase();
          final c = s.code.toLowerCase();
          return n.contains(query) || c.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1E34),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, color: Color(0xFF00B4D8), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تحديد الفرع / المحطة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.glassBorder, height: 1),

          // Search Box
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'بحث باسم الفرع أو كود المحطة...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontFamily: 'Cairo'),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00B4D8), size: 18),
                filled: true,
                fillColor: const Color(0xFF0D2137),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF00B4D8)),
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B4D8)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    children: [
                      // Option: General / None
                      ListTile(
                        onTap: () {
                          widget.onSelected(null);
                          Navigator.of(context).pop();
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.block_outlined, size: 18, color: AppTheme.textMuted),
                        ),
                        title: const Text(
                          'عام (بدون فرع محدد)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'تسجيل المصروف/العهدة على مستوى الشركة العام',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        trailing: widget.selectedId == null || widget.selectedId!.isEmpty
                            ? const Icon(Icons.check_circle, color: Color(0xFF00B4D8), size: 20)
                            : null,
                      ),
                      const Divider(color: AppTheme.glassBorder),

                      if (_filteredStations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'لا توجد فروع أو محطات مطابقة للبحث',
                              style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo'),
                            ),
                          ),
                        ),

                      ..._filteredStations.map((s) {
                        final isSelected = widget.selectedId == s.id?.toString();
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00B4D8).withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00B4D8).withValues(alpha: 0.5)
                                  : AppTheme.glassBorder,
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              widget.onSelected(s);
                              Navigator.of(context).pop();
                            },
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF00B4D8).withValues(alpha: 0.2)
                                    : const Color(0xFF0D2137),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                s.isMain ? Icons.domain : Icons.storefront_outlined,
                                size: 18,
                                color: isSelected ? const Color(0xFF00B4D8) : AppTheme.textSecondary,
                              ),
                            ),
                            title: Text(
                              s.name,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                              ),
                            ),
                            subtitle: Text(
                              'كود: ${s.code} • ${s.isMain ? 'محطة رئيسية' : 'محطة فرعية'}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Color(0xFF00B4D8), size: 20)
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
