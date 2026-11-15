// ignore_for_file: unused_element, unused_field, unused_element_parameter
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/dao/cost_report_dao.dart';
import '../../data/models/cost_center.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../features/auth/auth_cubit.dart';
import 'cost_details_report_page.dart';
import 'widgets/cost_center_form_dialog.dart';
import 'widgets/season_rollover_dialog.dart';

class CostSummaryReportPage extends StatefulWidget {
  const CostSummaryReportPage({super.key});

  @override
  State<CostSummaryReportPage> createState() => _CostSummaryReportPageState();
}

class _CostSummaryReportPageState extends State<CostSummaryReportPage> {
  final _dao = CostReportDao();
  bool _loading = true;
  bool _exportLoading = false;
  List<Map<String, dynamic>> _summary = [];
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _allDetails = [];
  List<String> _customers = [];
  List<Map<String, dynamic>> _costCategories = [];
  List<Map<String, dynamic>> _costCenterBreakdown = [];
  List<CostCenter> _activeCostCenters = [];
  List<CostCenter> _allCostCenters = []; // includes closed seasons
  List<Map<String, dynamic>> _expenseBranches = [];

  String? _selectedCustomer;
  String? _selectedCostCenter;
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _branchSearchCtrl = TextEditingController();
  bool _showOnlyActiveBranches = false;
  StreamSubscription? _eventSubscription;

  String _fmtCurrency(double v) {
    return 'EGP ${NumberFormat('#,##0.00').format(v)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });

    _eventSubscription = DataChangeEventBus.instance.costCentersStream.listen((_) {
      CostReportDao.clearCostCenterCache();
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _branchSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _fromCtrl.text.isNotEmpty ? _fromCtrl.text : null;
      final to = _toCtrl.text.isNotEmpty ? _toCtrl.text : null;

      // 1. Fetch metadata and cost centers in parallel (lightweight)
      final metaResults = await Future.wait([
        _dao.getAllCostCenters(),
        _dao.getDistinctCustomers(),
        Supabase.instance.client
            .from('cost_report_categories')
            .select('id, name, type, account_id, cost_center_id')
            .order('name'),
      ]);

      final allCenters = metaResults[0] as List<CostCenter>;
      final activeCenters = allCenters.where((c) => !c.isClosed).toList();
      final customers = metaResults[1] as List<String>;
      final rawCats = metaResults[2] as List;
      final costCategories = rawCats.map((e) => Map<String, dynamic>.from(e)).toList();

      // 2. Fetch baseline details EXACTLY ONCE (Unconstrained across cost centers)
      final allBaselineDetails = await _dao.getDetails(
        fromDate: from,
        toDate: to,
        customer: _selectedCustomer,
        costCenter: null,
        activeCenters: activeCenters,
        allCenters: allCenters,
      );

      final breakdownDetails = allBaselineDetails;

      // Filter in-memory with zero redundant DB queries if a specific cost center is selected
      List<Map<String, dynamic>> allDetails = allBaselineDetails;
      if (_selectedCostCenter != null && _selectedCostCenter!.isNotEmpty && _selectedCostCenter != 'all') {
        final cleanCc = _selectedCostCenter!.trim();
        allDetails = allBaselineDetails.where((r) {
          final rCcId = r['cost_center_id']?.toString().trim();
          final rCcName = r['cost_center_name']?.toString().trim();
          final rCode = r['cost_center_code']?.toString().trim();
          return rCcId == cleanCc || rCcName == cleanCc || rCode == cleanCc;
        }).toList();
      }

      await Future.delayed(Duration.zero);

      // 3. Derive summary, breakdown, and expense branches in memory with zero redundant DB hits
      final summary = await _dao.getSummary(
        preloadedDetails: allDetails,
        fromDate: from,
        toDate: to,
        customer: _selectedCustomer,
        costCenter: _selectedCostCenter,
        activeCenters: activeCenters,
        allCenters: allCenters,
      );

      await Future.delayed(Duration.zero);

      final breakdown = await _dao.getCostCenterBreakdown(
        fromDate: from,
        toDate: to,
        customer: _selectedCustomer,
        preloadedDetails: breakdownDetails,
        allCenters: allCenters,
        activeCenters: activeCenters,
      );

      await Future.delayed(Duration.zero);

      final branches = await _dao.getExpenseBranchVariance(
        costCenterId: _selectedCostCenter,
        fromDate: from,
        toDate: to,
        customer: _selectedCustomer,
        preloadedDetails: allDetails,
        activeCenters: activeCenters,
        allCenters: allCenters,
        preloadedCategories: costCategories,
      );

      if (mounted) {
        setState(() {
          _summary = summary;
          _allDetails = allDetails;
          _recent = allDetails.take(15).toList();
          _customers = customers;
          _costCategories = costCategories;
          _costCenterBreakdown = breakdown;
          _activeCostCenters = activeCenters;
          _allCostCenters = allCenters;
          _expenseBranches = branches;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ CostSummaryReportPage _load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(
                  primary: AppTheme.primary, surface: AppTheme.background)
              : const ColorScheme.light(
                  primary: AppTheme.primary,
                  surface: Colors.white,
                  onSurface: Color(0xFF0F172A)),
        ),
        child: child!,
      ),
    );
    if (d != null) {
      ctrl.text =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        body: Container(
          decoration: isDark ? AppTheme.backgroundGradient : null,
          color: isDark ? null : const Color(0xFFF8FAFC),
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  _buildFilters(),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _buildContent(),
                  ),
                ],
              ),
              if (_exportLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
                        Text('جاري إنشاء التقرير...',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Cairo')),
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

  void _openAddCostCenterDialog() {
    CostCenterFormDialog.show(
      context,
      onSaved: (_) {
        CostReportDao.clearCostCenterCache();
        _load();
      },
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.sizeOf(context).width;
        final isMobile = constraints.maxWidth < 750 || screenW < 750;
        final isVeryNarrow = isMobile;
        final topPad = MediaQuery.of(context).padding.top + (isMobile ? 54.0 : 12.0);
        return Container(
          padding: EdgeInsets.only(
              top: topPad,
              bottom: 12,
              left: 12,
              right: 12),
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            border: Border(
                bottom:
                    BorderSide(color: isDark ? AppTheme.glassBorder.withValues(alpha: 40) : const Color(0xFFE2E8F0))),
          ),
          child: isVeryNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: AppTheme.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'مراكز التكلفة والتقارير',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              SeasonRolloverDialog.show(
                                context,
                                activeCostCenters: _activeCostCenters,
                                onRolloverCompleted: () {
                                  CostReportDao.clearCostCenterCache();
                                  _load();
                                },
                              );
                            },
                            icon: const Icon(Icons.published_with_changes_rounded, size: 14, color: Color(0xFFF59E0B)),
                            label: const Text(
                              'ترحيل موسم',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFF59E0B)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openAddCostCenterDialog,
                            icon: const Icon(Icons.add_circle_outline, size: 14),
                            label: const Text(
                              'مركز تكلفة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(Icons.analytics_outlined, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'مراكز التكلفة والتقارير',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        SeasonRolloverDialog.show(
                          context,
                          activeCostCenters: _activeCostCenters,
                          onRolloverCompleted: () {
                            CostReportDao.clearCostCenterCache();
                            _load();
                          },
                        );
                      },
                      icon: const Icon(Icons.published_with_changes_rounded, size: 16, color: Color(0xFFF59E0B)),
                      label: Text(
                        isMobile ? 'ترحيل موسم' : 'إقفال وترحيل الموسم',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _openAddCostCenterDialog,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: Text(
                        isMobile ? 'مركز تكلفة' : 'إنشاء مركز تكلفة',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: _exportLoading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.primary, size: 16),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final resetBtn = (_fromCtrl.text.isNotEmpty ||
            _toCtrl.text.isNotEmpty ||
            _selectedCostCenter != null)
        ? Tooltip(
            message: 'إعادة ضبط الفلاتر',
            child: GestureDetector(
              onTap: () {
                _fromCtrl.clear();
                _toCtrl.clear();
                setState(() => _selectedCostCenter = null);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off_outlined, size: 14, color: Colors.redAccent),
                    SizedBox(width: 4),
                    Text('إلغاء الفلتر',
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Cairo',
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          )
        : null;

    final refreshBtn = Tooltip(
      message: 'تحديث البيانات',
      child: GestureDetector(
        onTap: _load,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Icon(Icons.refresh_rounded,
              color: isDark ? Colors.white : const Color(0xFF475569), size: 16),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.sizeOf(context).width;
        final isMobile = constraints.maxWidth < 850 || screenW < 850;

        if (isMobile) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardBg.withValues(alpha: 0.5) : Colors.white,
              border: Border(
                  bottom:
                      BorderSide(color: isDark ? AppTheme.glassBorder.withValues(alpha: 25) : const Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _filterBtn(_fromCtrl, 'من تاريخ')),
                    const SizedBox(width: 8),
                    Expanded(child: _filterBtn(_toCtrl, 'إلى تاريخ')),
                    const SizedBox(width: 8),
                    refreshBtn,
                    if (resetBtn != null) ...[
                      const SizedBox(width: 6),
                      resetBtn,
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _costCenterDropdown(),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardBg.withValues(alpha: 0.5) : Colors.white,
            border: Border(
                bottom:
                    BorderSide(color: isDark ? AppTheme.glassBorder.withValues(alpha: 25) : const Color(0xFFE2E8F0))),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterBtn(_fromCtrl, 'من تاريخ'),
              _filterBtn(_toCtrl, 'إلى تاريخ'),
              _costCenterDropdown(),
              if (resetBtn != null) resetBtn,
              refreshBtn,
            ],
          ),
        );
      },
    );
  }

  Widget _costCenterDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final seenIds = <String>{};
    final uniqueList = <CostCenter>[];
    for (final cc in _allCostCenters) {
      final code = (cc.code ?? cc.id).trim();
      // Strictly exclude Level 3 (3 digits) and Level 4 (4 digits)
      if (code.length == 3 || code.length == 4) continue;
      if (seenIds.add(cc.id)) {
        uniqueList.add(cc);
      }
    }

    if (_selectedCostCenter != null && !seenIds.contains(_selectedCostCenter)) {
      uniqueList.add(
        CostCenter(
          id: _selectedCostCenter!,
          nameAr: _selectedCostCenter!,
          nameEn: _selectedCostCenter!,
          type: CostCenterType.variety,
          color: CostCenterHelper.resolveColor(null, _selectedCostCenter!),
          icon: Icons.hub_outlined,
          code: _selectedCostCenter,
        ),
      );
    }

    final screenW = MediaQuery.sizeOf(context).width;
    final maxDropdownW = screenW < 850 ? double.infinity : 340.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxDropdownW),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: _selectedCostCenter != null
              ? AppTheme.primary.withValues(alpha: 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _selectedCostCenter != null
                ? AppTheme.primary
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _selectedCostCenter,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF0F2238) : Colors.white,
            icon: const Icon(Icons.arrow_drop_down,
                color: AppTheme.primary, size: 18),
            hint: Row(
              children: [
                const Icon(Icons.hub_outlined, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'مراكز التكلفة والمحاصيل',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                      fontSize: 11,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
            selectedItemBuilder: (context) {
              return [
                Row(
                  children: [
                    Icon(Icons.all_inclusive, size: 14, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'جميع مراكز التكلفة والمحاصيل (الكل)',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
                ...uniqueList.map((cc) {
                  final ccIsClosed = cc.isClosed;
                  return Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cc.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ccIsClosed
                          ? const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF64748B))
                          : Icon(cc.icon, size: 14, color: cc.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cc.nameAr,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ];
            },
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Row(
                  children: [
                    Icon(Icons.all_inclusive, size: 14, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('جميع مراكز التكلفة والمحاصيل (الكل)',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontSize: 12,
                              fontFamily: 'Cairo')),
                    ),
                  ],
                ),
              ),
              ...uniqueList.map((cc) {
                final ccIsClosed = cc.isClosed;
                final isVariety = cc.type == CostCenterType.variety;
                final badgeText = isVariety
                    ? 'محصول'
                    : ((cc.code?.startsWith('3') == true) ? 'فرع مصروفات' : 'تشغيلي');
                return DropdownMenuItem<String?>(
                  value: cc.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cc.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ccIsClosed
                          ? const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF64748B))
                          : Icon(cc.icon, size: 14, color: cc.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cc.nameAr,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: cc.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: cc.color,
                            fontSize: 9,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (val) {
              setState(() => _selectedCostCenter = val);
              _load();
            },
          ),
        ),
      ),
    );
  }

  Widget _filterBtn(TextEditingController ctrl, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'اختيار تاريخ',
      child: GestureDetector(
        onTap: () => _pickDate(ctrl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range, size: 14, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(ctrl.text.isEmpty ? hint : ctrl.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: ctrl.text.isEmpty
                          ? (isDark ? Colors.white54 : const Color(0xFF64748B))
                          : (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getMajorCategory(Map<String, dynamic> row) {
    final cat = (row['category'] as String? ?? '').trim();
    final name = (row['item_name'] as String? ?? '').trim();
    final code = (row['account_code'] ?? row['code'] ?? row['category_code'] ?? '').toString().trim();
    final accName = (row['account_name'] ?? '').toString().trim();

    return CostReportDao.resolveExpenseBranchName(
      category: cat,
      itemName: name,
      accountCode: code.isNotEmpty ? code : null,
      accountName: accName.isNotEmpty ? accName : null,
    );
  }

  Widget _buildContent() {
    final totalAmount =
        _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
    final totalTx =
        _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
    final highest = _summary.isNotEmpty ? _summary.first : null;
    final highestLabel =
        highest != null ? (highest['item_name'] as String) : '—';
    final lowest = _summary.length > 1 ? _summary.last : null;
    final lowestLabel = lowest != null ? (lowest['item_name'] as String) : '—';
    final lowestAmt = lowest != null ? (lowest['total_amount'] as double) : 0.0;

    double totalOpeningBalance = 0.0;
    for (final cc in _costCenterBreakdown) {
      final ob = (cc['opening_balance'] as num?)?.toDouble() ??
          (cc['carried_forward_amount'] as num?)?.toDouble() ??
          0.0;
      totalOpeningBalance += ob;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 400;
        return SingleChildScrollView(
          padding:
              EdgeInsets.fromLTRB(isSmall ? 12 : 20, 16, isSmall ? 12 : 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKpiRow(
                  totalAmount, totalTx, highestLabel, lowestLabel, lowestAmt,
                  openingBalance: totalOpeningBalance),
              const SizedBox(height: 20),
              // Crop and operational cost centers cards
              _buildCostCentersSection(totalAmount),
              const SizedBox(height: 20),
              _buildMainCategoriesCards(totalAmount),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCostCentersSection(double grandTotal) {
    return _buildCostCentersSectionLegacy(grandTotal);
  }

  Widget _buildCostCentersSectionLegacy(double grandTotal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 950;
            final actionButtons = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_selectedCostCenter != null)
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedCostCenter = null);
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 12, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                          const SizedBox(width: 4),
                          Text('عرض الكل',
                              style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontSize: 11,
                                  fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ),
                _actionBtn(Icons.add_circle_outline, 'إضافة مركز تكلفة', _openAddCostCenterDialog),
              ],
            );

            final titleWidget = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.eco_rounded,
                      color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مراكز تكلفة المحاصيل والخطوط الإنتاجية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      Text(
                        _selectedCostCenter != null
                            ? 'مفلتر حالياً: ${CostCenterHelper.fromId(_selectedCostCenter, _activeCostCenters).nameAr}'
                            : 'اضغط على بطاقة المحصول لتصفية مصروفات وحسابات هذا المحصول تحديداً',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedCostCenter != null
                              ? AppTheme.primary
                              : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  const SizedBox(height: 10),
                  actionButtons,
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 12),
                actionButtons,
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        if (_costCenterBreakdown.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.cardBg : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub_outlined, color: isDark ? Colors.white38 : const Color(0xFF94A3B8), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد مراكز تكلفة مسجلة حالياً',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك إنشاء مراكز تكلفة محصولية لكل موسم زراعي (مثل: مانجو موسم 2026-2027) أو مراكز تشغيلية وإدارية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _openAddCostCenterDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'إنشاء مركز تكلفة الآن',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossAxisCount = w > 900
                  ? 3
                  : w > 580
                      ? 2
                      : 1;
              final itemWidth = crossAxisCount == 1
                  ? w
                  : ((w - (crossAxisCount - 1) * 10) / crossAxisCount).floorToDouble();

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _costCenterBreakdown.map((cc) {
                  final id = cc['id'] as String;
                  final name = cc['name'] as String;
                  final type = cc['type'] as String;
                  final color = (cc['color'] as Color?) ?? AppTheme.primary;
                  final icon = (cc['icon'] as IconData?) ?? Icons.hub_outlined;
                  final total = (cc['total_amount'] as num?)?.toDouble() ?? 0.0;
                  final ob = (cc['opening_balance'] as num?)?.toDouble() ??
                      (cc['carried_forward_amount'] as num?)?.toDouble() ??
                      0.0;
                  final txCount = (cc['transaction_count'] as num?)?.toInt() ?? 0;
                  final pct = (cc['percentage'] as num?)?.toDouble() ?? 0.0;
                  final isSelected = _selectedCostCenter == id;
                  // ── Season Locking ─────────────────────────────────────────────
                  final isClosed = (cc['is_closed'] as bool?) ?? false;
                  final effectiveColor = isClosed ? color.withValues(alpha: 0.4) : color;

                  return SizedBox(
                    width: itemWidth,
                    height: isClosed ? 140 : (ob > 0 ? 134 : 124),
                    child: InkWell(
                      // CLOSED centers: open read-only details view instead of filtering
                      onTap: isClosed
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CostDetailsReportPage(
                                  costCenter: id,
                                  costCenterLabel: name,
                                ),
                              ),
                            )
                          : () {
                              setState(() {
                                if (_selectedCostCenter == id) {
                                  _selectedCostCenter = null;
                                } else {
                                  _selectedCostCenter = id;
                                }
                              });
                              _load();
                            },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          // Closed centers get a darkened, muted appearance
                          color: isClosed
                              ? (isDark ? const Color(0xFF0B1929) : const Color(0xFFF1F5F9))
                              : (isSelected
                                  ? effectiveColor.withValues(alpha: isDark ? 0.12 : 0.08)
                                  : (isDark ? AppTheme.cardBg : Colors.white)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isClosed
                                ? (isDark ? const Color(0xFF3D5266) : const Color(0xFFCBD5E1))
                                : (isSelected
                                    ? effectiveColor
                                    : (isDark ? effectiveColor.withValues(alpha: 0.25) : const Color(0xFFE2E8F0))),
                            width: isSelected ? 1.8 : 1.0,
                          ),
                          boxShadow: isSelected && !isClosed
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : (isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ── Lock Banner (closed seasons only) ───────────────────────────────
                            if (isClosed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF334155).withValues(alpha: 0.5)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF64748B).withValues(alpha: 0.6)
                                            : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_rounded,
                                          size: 11,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
                                      const SizedBox(width: 5),
                                      Text(
                                        'موسم مقفل \u2014 للاطلاع فقط',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Card Header: Icon + Name + Type + Drill-down
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: effectiveColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(icon, color: effectiveColor, size: 14),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: effectiveColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    type,
                                    style: TextStyle(
                                      color: effectiveColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'عرض تفاصيل هذا المركز',
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CostDetailsReportPage(
                                            costCenter: id,
                                            costCenterLabel: name,
                                          ),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 11,
                                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Card Financial Metrics
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'EGP ${_fmt(total)}',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    if (ob > 0)
                                      Text(
                                        'مرحل: EGP ${_fmt(ob)}',
                                        style: const TextStyle(
                                          color: Color(0xFFF59E0B),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  '${pct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),

                            // Percentage Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (pct / 100.0).clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFFE2E8F0),
                                valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
                              ),
                            ),

                            // Card Footer
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$txCount معاملة',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                    fontSize: 10,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                Text(
                                  isClosed ? 'عرض التفاصيل ←' : (isSelected ? 'نشط (مفلتر)' : 'انقر للتصفية'),
                                  style: TextStyle(
                                    color: isClosed
                                        ? const Color(0xFF64748B)
                                        : (isSelected
                                            ? effectiveColor
                                            : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                                    fontSize: 9.5,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildKpiRow(
      double total, int tx, String highest, String lowest, double lowestAmt,
      {double openingBalance = 0.0}) {
    final hasOpening = openingBalance != 0.0;
    final totalLedger = total + openingBalance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 480;

        final cards = [
          _kpiCard(
              hasOpening ? 'مصاريف التشغيل للموسم' : 'إجمالي التكاليف',
              'EGP ${_fmt(total)}',
              AppTheme.primary,
              Icons.monetization_on_outlined),
          if (hasOpening)
            _kpiCard('أرصدة افتتاحية مرحلة', 'EGP ${_fmt(openingBalance)}',
                const Color(0xFFF59E0B), Icons.history_rounded),
          if (hasOpening)
            _kpiCard('الإجمالي الدفتري العام', 'EGP ${_fmt(totalLedger)}',
                const Color(0xFF10B981), Icons.account_balance_wallet_outlined),
          _kpiCard('عدد المعاملات التشغيلية', '$tx', AppTheme.info,
              Icons.receipt_long_outlined),
        ];

        if (isSmall) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: cards[i]),
                    if (i + 1 < cards.length) ...[
                      const SizedBox(width: 8),
                      Expanded(child: cards[i + 1]),
                    ],
                  ],
                ),
              ],
            ],
          );
        }

        if (width < 850) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map((c) => SizedBox(width: (width - 10) / 2, child: c))
                .toList(),
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 200;
        return Container(
          padding: EdgeInsets.fromLTRB(isSmall ? 10 : 14, isSmall ? 10 : 14,
              isSmall ? 10 : 14, isSmall ? 10 : 14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardBg : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? color.withValues(alpha: 0.25) : const Color(0xFFCBD5E1),
            ),
            boxShadow: [
              BoxShadow(
                  color: isDark ? color.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.04),
                  blurRadius: isDark ? 24 : 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.15 : 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: isSmall ? 14 : 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF475569),
                            fontSize: isSmall ? 10 : 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: label == 'إجمالي التكاليف' ? 24 : 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    )),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighestCosts() {
    if (_allDetails.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: const Center(
          child: Text('لا توجد بيانات',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        ),
      );
    }

    final Map<String, Map<String, dynamic>> highest = {};
    for (final row in _allDetails) {
      final majorCat = _getMajorCategory(row);
      final amt = (row['amount'] as num?)?.toDouble() ?? 0;
      if (!highest.containsKey(majorCat) ||
          amt > ((highest[majorCat]!['amount'] as num?)?.toDouble() ?? 0)) {
        highest[majorCat] = row;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                Icon(Icons.trending_up, color: AppTheme.warning, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('أعلى التكاليف (حسب البند)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...highest.entries.map((entry) {
            final catName = entry.key;
            final row = entry.value;
            final itemName = row['item_name'] as String? ?? '';
            final shipNo = row['shipment_no'] as String? ?? '';
            final amt = (row['amount'] as num?)?.toDouble() ?? 0;
            return _highestCostItem(catName, itemName, shipNo, amt);
          }),
        ],
      ),
    );
  }

  Widget _highestCostItem(
      String catName, String itemName, String shipNo, double amt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 350) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  Text(_fmt(amt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                      'أعلى تكلفة هي $itemName ${shipNo.isNotEmpty ? 'في الشحنة رقم \u202A$shipNo\u202C' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(catName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(height: 4),
                    Text(
                        'أعلى تكلفة هي $itemName ${shipNo.isNotEmpty ? 'في الشحنة رقم \u202A$shipNo\u202C' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_fmt(amt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          );
        },
      ),
    );
  }

  IconData _getBranchIcon(String branchName) {
    final norm = branchName.trim();
    if (norm.contains('مهندس') || norm.contains('engineer')) return Icons.engineering_rounded;
    if (norm.contains('لوجستيك') || norm.contains('نقل') || norm.contains('transport')) return Icons.local_shipping_rounded;
    if (norm.contains('مواد التعبئة') || norm.contains('material')) return Icons.inventory_2_rounded;
    if (norm.contains('تعبئة') || norm.contains('packing')) return Icons.all_inbox_rounded;
    if (norm.contains('محاصيل') || norm.contains('crop') || norm.contains('fruit')) return Icons.eco_rounded;
    if (norm.contains('شحن') || norm.contains('freight') || norm.contains('shipping')) return Icons.directions_boat_rounded;
    if (norm.contains('تخليص') || norm.contains('clearance')) return Icons.assignment_turned_in_rounded;
    if (norm.contains('إدارية') || norm.contains('admin')) return Icons.business_rounded;
    if (norm.contains('فرز') || norm.contains('sorting')) return Icons.filter_alt_rounded;
    return Icons.account_balance_wallet_rounded;
  }

  Color _getBranchColor(String branchName) {
    final norm = branchName.trim();
    if (norm.contains('مهندس') || norm.contains('engineer')) return const Color(0xFF0284C7);
    if (norm.contains('لوجستيك') || norm.contains('نقل') || norm.contains('transport')) return const Color(0xFFF59E0B);
    if (norm.contains('مواد التعبئة') || norm.contains('material')) return const Color(0xFF8B5CF6);
    if (norm.contains('تعبئة') || norm.contains('packing')) return const Color(0xFF06B6D4);
    if (norm.contains('محاصيل') || norm.contains('crop') || norm.contains('fruit')) return const Color(0xFF10B981);
    if (norm.contains('شحن') || norm.contains('freight') || norm.contains('shipping')) return const Color(0xFF3B82F6);
    if (norm.contains('تخليص') || norm.contains('clearance')) return const Color(0xFFEC4899);
    if (norm.contains('إدارية') || norm.contains('admin')) return const Color(0xFF64748B);
    if (norm.contains('فرز') || norm.contains('sorting')) return const Color(0xFF14B8A6);
    return AppTheme.primary;
  }

  Widget _buildMainCategoriesCards(double total) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Group details by major category as fallback / enrichment
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in _allDetails) {
      final majorCat = _getMajorCategory(row);
      grouped.putIfAbsent(majorCat, () => []).add(row);
    }

    final Map<String, Map<String, dynamic>> branchMap = {};

    // 1. Populate from _expenseBranches (loaded dynamically from accounts + live transactions)
    for (final eb in _expenseBranches) {
      final bName = eb['branch_name']?.toString() ?? '';
      final catCode = (eb['category_code'] ?? '').toString().trim();
      
      // Strictly exclude Level 3 (3 digits) and Level 4 (4 digits)
      if (catCode.length == 3 || catCode.length == 4) continue;
      if (!catCode.startsWith('3') && catCode != '31251' && catCode != 'engineer_expenses' && !bName.contains('مهندس')) continue;

      final key = (catCode == 'engineer_expenses' || bName.contains('مهندس')) ? '31251' : catCode;
      final mapEntry = Map<String, dynamic>.from(eb);
      if (key == '31251') {
        mapEntry['branch_name'] = '31251 - مصاريف مهندسين';
        mapEntry['category_code'] = '31251';
      }
      mapEntry['level'] = 5;
      branchMap[key] = mapEntry;
    }

    // 2. Ensure primary Level 5 account '31251 - مصاريف مهندسين' always exists
    if (!branchMap.containsKey('31251')) {
      final rows = grouped['31251 - مصاريف مهندسين'] ?? grouped['مصاريف المهندسين'] ?? [];
      double act = 0.0;
      double est = 0.0;
      int settled = 0;
      int pending = 0;
      for (final r in rows) {
        final a = (r['actual_amount'] as num?)?.toDouble() ?? (r['amount'] as num?)?.toDouble() ?? 0.0;
        final e = (r['expected_amount'] as num?)?.toDouble() ?? a;
        final status = r['cost_status']?.toString();
        act += a;
        est += e;
        if (status == 'settled' || r['actual_amount'] != null) {
          settled++;
        } else {
          pending++;
        }
      }
      final varAmt = act - est;
      final varPct = est > 0 ? (varAmt / est) * 100 : 0.0;

      branchMap['31251'] = {
        'branch_name': '31251 - مصاريف مهندسين',
        'category_code': '31251',
        'estimated_cost': est,
        'actual_cost': act,
        'variance_amount': varAmt,
        'variance_percentage': varPct,
        'transaction_count': rows.length,
        'settled_count': settled,
        'pending_count': pending,
        'level': 5,
      };
    }

    // 3. Add any Level 5 entries from grouped
    for (final entry in grouped.entries) {
      final name = entry.key;
      final catCode = CostReportDao.branchToCategoryCode(name);
      if (catCode.length == 3 || catCode.length == 4) continue;
      if (!catCode.startsWith('3') && catCode != '31251') continue;

      final key = catCode == 'engineer_expenses' ? '31251' : catCode;
      if (!branchMap.containsKey(key)) {
        final rows = entry.value;
        double act = 0.0;
        double est = 0.0;
        int settled = 0;
        int pending = 0;
        for (final r in rows) {
          final a = (r['actual_amount'] as num?)?.toDouble() ?? (r['amount'] as num?)?.toDouble() ?? 0.0;
          final e = (r['expected_amount'] as num?)?.toDouble() ?? a;
          final status = r['cost_status']?.toString();
          act += a;
          est += e;
          if (status == 'settled' || r['actual_amount'] != null) {
            settled++;
          } else {
            pending++;
          }
        }
        branchMap[key] = {
          'branch_name': name,
          'category_code': key,
          'estimated_cost': est,
          'actual_cost': act,
          'variance_amount': act - est,
          'variance_percentage': est > 0 ? ((act - est) / est) * 100 : 0.0,
          'transaction_count': rows.length,
          'settled_count': settled,
          'pending_count': pending,
          'level': 5,
        };
      }
    }

    // Order branches: 31251 first, then ascending by code
    final allBranches = branchMap.values.toList()..sort((a, b) {
      final aCode = (a['category_code'] ?? '').toString();
      final bCode = (b['category_code'] ?? '').toString();
      if (aCode == '31251') return -1;
      if (bCode == '31251') return 1;
      return aCode.compareTo(bCode);
    });

    // 4. Compute totals strictly for Level 5
    double totalEstimated = 0.0;
    double totalActual = 0.0;
    int totalPendingSettlement = 0;
    int totalWithTransactions = 0;

    for (final b in allBranches) {
      final est = (b['estimated_cost'] as num?)?.toDouble() ?? 0.0;
      final act = (b['actual_cost'] as num?)?.toDouble() ?? 0.0;
      final tx = (b['transaction_count'] as num?)?.toInt() ?? 0;
      totalEstimated += est;
      totalActual += act;
      totalPendingSettlement += (b['pending_count'] as num?)?.toInt() ?? 0;
      if (tx > 0 || act > 0 || est > 0) {
        totalWithTransactions++;
      }
    }

    final totalVariance = totalActual - totalEstimated;
    final totalVariancePct = totalEstimated > 0
        ? (totalVariance / totalEstimated) * 100
        : 0.0;

    // 5. Filter branches according to search query and active toggle
    final search = _branchSearchCtrl.text.trim().toLowerCase();
    final displayedBranches = allBranches.where((b) {
      final bName = (b['branch_name'] ?? '').toString().toLowerCase();
      final bCode = (b['category_code'] ?? '').toString().toLowerCase();
      final tx = (b['transaction_count'] as num?)?.toInt() ?? 0;
      final act = (b['actual_cost'] as num?)?.toDouble() ?? 0.0;
      final est = (b['estimated_cost'] as num?)?.toDouble() ?? 0.0;

      if (_showOnlyActiveBranches && tx == 0 && act == 0 && est == 0 && bCode != '31251') {
        return false;
      }
      if (search.isNotEmpty) {
        return bName.contains(search) || bCode.contains(search);
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        LayoutBuilder(
          builder: (context, sectionConstraints) {
            final isMobile = sectionConstraints.maxWidth < 950;
            final titleWidget = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_tree_outlined,
                      color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فروع وحسابات المصروفات (المستوى 5 - كود 3)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      Text(
                        _selectedCostCenter != null
                            ? 'مقارنة الميزانيات والانحراف للمركز: ${CostCenterHelper.fromId(_selectedCostCenter, _activeCostCenters).nameAr}'
                            : 'مقارنة التقديري بالفعلي والانحراف لكافة حسابات وفروع المصروفات التي تبدأ بالكود 3',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final pendingBadge = totalPendingSettlement > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.pending_actions_rounded, size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 5),
                        Text(
                          '$totalPendingSettlement بند قيد التسوية',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  )
                : null;

            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  if (pendingBadge != null) ...[
                    const SizedBox(height: 8),
                    pendingBadge,
                  ],
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleWidget),
                if (pendingBadge != null) ...[
                  const SizedBox(width: 8),
                  pendingBadge,
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // Variance KPI Hero Card
        _buildVarianceKpiBanner(
          isDark: isDark,
          totalEstimated: totalEstimated,
          totalActual: totalActual,
          netVariance: totalVariance,
          variancePct: totalVariancePct,
        ),
        const SizedBox(height: 16),

        // Search & Filter controls for expense branches
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.glassBorder.withValues(alpha: 40) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: TextField(
                  controller: _branchSearchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ابحث في فروع المصروفات بالكود أو الاسم (مثل 31113، 31251، مرتبات)...',
                    hintStyle: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.primary),
                    suffixIcon: _branchSearchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _branchSearchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: !_showOnlyActiveBranches,
              onSelected: (val) {
                if (val) setState(() => _showOnlyActiveBranches = false);
              },
              label: Text('جميع الفروع (${allBranches.length})',
                  style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
              selectedColor: AppTheme.primary.withValues(alpha: 0.2),
              checkmarkColor: AppTheme.primary,
            ),
            const SizedBox(width: 6),
            FilterChip(
              selected: _showOnlyActiveBranches,
              onSelected: (val) {
                setState(() => _showOnlyActiveBranches = val);
              },
              label: Text('ذات الحركات ($totalWithTransactions)',
                  style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
              selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
              checkmarkColor: const Color(0xFF10B981),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Expense Branch Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isMobile = w < 650;
            final cardWidth = isMobile ? w : (w - 12) / 2;

            if (displayedBranches.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 40, color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد فروع مصروفات مطابقة للبحث',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: displayedBranches.map((branch) {
                final bName = branch['branch_name']?.toString() ?? '';
                final est = (branch['estimated_cost'] as num?)?.toDouble() ?? 0.0;
                final act = (branch['actual_cost'] as num?)?.toDouble() ?? 0.0;
                final varianceAmt = (branch['variance_amount'] as num?)?.toDouble() ?? (act - est);
                final variancePct = (branch['variance_percentage'] as num?)?.toDouble() ??
                    (est > 0 ? ((act - est) / est) * 100 : 0.0);
                final txCount = (branch['transaction_count'] as num?)?.toInt() ?? 0;
                final pendingCount = (branch['pending_count'] as num?)?.toInt() ?? 0;

                final color = _getBranchColor(bName);
                final icon = _getBranchIcon(bName);

                // Progress ratio: actual / estimated
                final progressRatio = est > 0 ? (act / est) : (act > 0 ? 1.0 : 0.0);
                final isOverrun = act > est && est > 0;
                final isSaving = act < est && est > 0;

                final statusColor = pendingCount > 0
                    ? const Color(0xFFF59E0B)
                    : (act > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B));
                final statusLabel = pendingCount > 0
                    ? 'قيد التسوية ($pendingCount معلق)'
                    : (act > 0 ? 'مسوى بالكامل' : 'مقدر معلق');

                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CostDetailsReportPage(
                            majorCategory: bName,
                            costCenter: _selectedCostCenter,
                            costCenterLabel: _selectedCostCenter != null
                                ? CostCenterHelper.fromId(_selectedCostCenter, _activeCostCenters).nameAr
                                : null,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.cardBg : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.glassBorder.withValues(alpha: 40)
                              : const Color(0xFFCBD5E1),
                        ),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card Header: Icon, Name, and Status Chip
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(icon, color: color, size: 19),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        bName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'مستوى 5',
                                        style: TextStyle(
                                          color: AppTheme.primary,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 3-Metric Comparison Grid (Estimated vs Actual vs Variance)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Estimated
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'المقدر',
                                        style: TextStyle(
                                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                          fontSize: 10,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'EGP ${_fmt(est)}',
                                          style: TextStyle(
                                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                // Actual
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الفعلي',
                                        style: TextStyle(
                                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                          fontSize: 10,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'EGP ${_fmt(act)}',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                // Variance & %
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الانحراف',
                                        style: TextStyle(
                                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                          fontSize: 10,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '${varianceAmt >= 0 ? '+' : ''}${_fmt(varianceAmt)}',
                                          style: TextStyle(
                                            color: isOverrun
                                                ? const Color(0xFFEF4444)
                                                : (isSaving
                                                    ? const Color(0xFF10B981)
                                                    : (isDark ? Colors.white70 : const Color(0xFF475569))),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Progress Bar & Percentage Pill
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                est > 0
                                    ? 'نسبة التنفيذ: ${(progressRatio * 100).toStringAsFixed(1)}%'
                                    : (act > 0 ? 'تكلفة فعلية غير مقدرة' : 'لا توجد تكلفة'),
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                  fontSize: 10.5,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOverrun
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                      : (isSaving
                                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                          : (isDark ? Colors.white10 : const Color(0xFFF1F5F9))),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  est > 0
                                      ? (isOverrun
                                          ? '+${variancePct.abs().toStringAsFixed(1)}% تجاوز'
                                          : (isSaving
                                              ? '-${variancePct.abs().toStringAsFixed(1)}% وفر'
                                              : 'متطابق'))
                                      : '—',
                                  style: TextStyle(
                                    color: isOverrun
                                        ? const Color(0xFFEF4444)
                                        : (isSaving
                                            ? const Color(0xFF10B981)
                                            : (isDark ? Colors.white60 : const Color(0xFF64748B))),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progressRatio.clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isOverrun
                                    ? const Color(0xFFEF4444)
                                    : (isSaving ? const Color(0xFF10B981) : color),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Card Footer: Transactions Count + Drill-down Action
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$txCount معاملة مسجلة',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  fontSize: 10,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'عرض التفاصيل',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_back_ios_new_rounded, size: 10, color: color),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVarianceKpiBanner({
    required bool isDark,
    required double totalEstimated,
    required double totalActual,
    required double netVariance,
    required double variancePct,
  }) {
    final isOverrun = netVariance > 0;
    final isSaving = netVariance < 0;

    final varianceColor = isOverrun
        ? const Color(0xFFEF4444)
        : (isSaving ? const Color(0xFF10B981) : const Color(0xFF3B82F6));

    final varianceStatusLabel = isOverrun
        ? 'تجاوز في الميزانية التقديرية (+)'
        : (isSaving ? 'وفورات تشغيلية محققة (-)' : 'مطابق للميزانية التقديرية');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppTheme.primary.withValues(alpha: 0.25)
              : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.blueGrey).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 600;

          final items = [
            _varianceBannerMetric(
              label: 'إجمالي المقدر',
              value: 'EGP ${_fmt(totalEstimated)}',
              color: const Color(0xFF64748B),
              icon: Icons.assignment_outlined,
              isDark: isDark,
            ),
            _varianceBannerMetric(
              label: 'إجمالي الفعلي',
              value: 'EGP ${_fmt(totalActual)}',
              color: AppTheme.primary,
              icon: Icons.account_balance_wallet_outlined,
              isDark: isDark,
            ),
            _varianceBannerMetric(
              label: 'صافي الانحراف',
              value: '${netVariance >= 0 ? '+' : ''}EGP ${_fmt(netVariance.abs())}',
              subtitle: varianceStatusLabel,
              color: varianceColor,
              icon: isOverrun
                  ? Icons.trending_up_rounded
                  : (isSaving ? Icons.trending_down_rounded : Icons.check_circle_outline_rounded),
              isDark: isDark,
            ),
            _varianceBannerMetric(
              label: 'نسبة الانحراف',
              value: '${variancePct >= 0 ? '+' : ''}${variancePct.toStringAsFixed(1)}%',
              color: varianceColor,
              icon: Icons.percent_rounded,
              isDark: isDark,
            ),
          ];

          if (isSmall) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: items[0]),
                    const SizedBox(width: 10),
                    Expanded(child: items[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: items[2]),
                    const SizedBox(width: 10),
                    Expanded(child: items[3]),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: items[0]),
              Container(width: 1, height: 42, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              Expanded(child: items[1]),
              Container(width: 1, height: 42, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              Expanded(child: items[2]),
              Container(width: 1, height: 42, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              Expanded(child: items[3]),
            ],
          );
        },
      ),
    );
  }

  Widget _varianceBannerMetric({
    required String label,
    required String value,
    String? subtitle,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ],
      ),
    );
  }



  // ── Report helpers ──

  String _generatedBy() {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) {
      return auth.fullName ?? auth.email ?? 'مستخدم';
    }
    return 'مستخدم';
  }

  String _dateRangeLabel() {
    final from = _fromCtrl.text;
    final to = _toCtrl.text;
    if (from.isEmpty && to.isEmpty) return 'الكل';
    if (from.isEmpty) return 'حتى $to';
    if (to.isEmpty) return 'من $from';
    return 'من $from إلى $to';
  }

  Future<void> _exportPdf() async {
    setState(() => _exportLoading = true);
    try {
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
      final totalTx =
          _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final user = _generatedBy();

      final font = await PdfGoogleFonts.cairoRegular();
      final fontBold = await PdfGoogleFonts.cairoBold();
      final bgData = await rootBundle.load('assets/images/statment.png');
      final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),
          ),
          build: (ctx) => [
            _pdfHeader(font, fontBold, now, user),
            _pdfSummary(font, fontBold, totalAmount, totalTx),
            _pdfCostDistribution(font, fontBold, totalAmount),
            _pdfCostItems(font, fontBold, totalAmount),
            _pdfTransactions(font, fontBold),
          ],
        ),
      );
      await Printing.sharePdf(
          bytes: await doc.save(),
          filename: 'cost_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) _showSnack('تم تصدير PDF بنجاح');
    } catch (e) {
      if (mounted) _showSnack('فشل تصدير PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _printReport() async {
    setState(() => _exportLoading = true);
    try {
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));
      final totalTx =
          _summary.fold<int>(0, (s, e) => s + (e['transaction_count'] as int));
      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final user = _generatedBy();

      final font = await PdfGoogleFonts.cairoRegular();
      final fontBold = await PdfGoogleFonts.cairoBold();
      final bgData = await rootBundle.load('assets/images/statment.png');
      final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            margin: const pw.EdgeInsets.all(20),
            buildBackground: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),
          ),
          build: (ctx) => [
            _pdfHeader(font, fontBold, now, user),
            _pdfSummary(font, fontBold, totalAmount, totalTx),
            _pdfCostDistribution(font, fontBold, totalAmount),
            _pdfCostItems(font, fontBold, totalAmount),
            _pdfTransactions(font, fontBold),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => doc.save());
      if (mounted) _showSnack('تم إرسال التقرير للطباعة');
    } catch (e) {
      if (mounted) _showSnack('فشلت الطباعة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportLoading = true);
    try {
      final excel = Excel.createExcel();
      final totalAmount =
          _summary.fold<double>(0, (s, e) => s + (e['total_amount'] as double));

      // Sheet 1: Summary
      final sheet1 = excel['ملخص'];
      _excelRow(sheet1, ['بند التكلفة', 'المبلغ', 'النسبة', 'عدد المعاملات'],
          bold: true);
      for (final e in _summary) {
        final name = e['item_name'] as String;
        final amt = e['total_amount'] as double;
        final tx = e['transaction_count'] as int;
        final pct = totalAmount > 0 ? amt / totalAmount * 100 : 0.0;
        _excelRow(sheet1,
            [name, _fmtCurrency(amt), '${pct.toStringAsFixed(1)}%', '$tx']);
      }
      _excelRow(sheet1, ['الإجمالي', _fmtCurrency(totalAmount), '', '']);

      // Sheet 2: Cost Items (detailed - same as summary)
      final sheet2 = excel['بنود التكاليف'];
      _excelRow(sheet2, ['بند التكلفة', 'المبلغ', 'النسبة', 'عدد المعاملات'],
          bold: true);
      for (final e in _summary) {
        final name = e['item_name'] as String;
        final amt = e['total_amount'] as double;
        final tx = e['transaction_count'] as int;
        final pct = totalAmount > 0 ? amt / totalAmount * 100 : 0.0;
        _excelRow(sheet2,
            [name, _fmtCurrency(amt), '${pct.toStringAsFixed(1)}%', '$tx']);
      }
      _excelRow(sheet2, ['الإجمالي', _fmtCurrency(totalAmount), '', '']);

      final sheet3 = excel['المعاملات'];
      _excelRow(
          sheet3,
          [
            'التاريخ',
            'رقم الشحنة',
            'العميل',
            'بند التكلفة',
            'الكمية',
            'سعر الوحدة',
            'سعر الصرف',
            'الإجمالي بالعملة',
            'الإجمالي بالمصري',
            'البيان'
          ],
          bold: true);
      for (final r in _recent) {
        final date = r['shipment_date']?.toString() ?? '';
        final cat = r['category'] as String? ?? '';
        final amt = (r['amount'] as num?)?.toDouble() ?? 0;
        final exRate = (r['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final actualExRate = exRate == 0 ? 1.0 : exRate;
        final totalCur = (r['total_in_currency'] as num?)?.toDouble() ?? amt;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
        final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0;
        final currCode = r['currency']?.toString() ?? 'EGP';
        final currName = currCode.toUpperCase() == 'EGP'
            ? 'EGP'
            : currCode.toUpperCase() == 'EUR'
                ? 'EURO'
                : currCode.toUpperCase() == 'USD'
                    ? 'USD'
                    : currCode.toUpperCase() == 'GBP'
                        ? 'GBP'
                        : currCode;

        _excelRow(sheet3, [
          date.length >= 10 ? date.substring(0, 10) : date,
          r['shipment_no']?.toString() ?? '',
          r['customer_name']?.toString() ?? '',
          r['item_name']?.toString() ?? cat,
          qty.toString(),
          '$currName ${CurrencyConversionService.instance.fromBase(unitPrice, currCode, actualExRate).toStringAsFixed(2)}',
          actualExRate.toStringAsFixed(2),
          '$currName ${totalCur.toStringAsFixed(2)}',
          _fmtCurrency(amt),
          r['description']?.toString() ?? '',
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل إنشاء ملف Excel');
      final fileName =
          'cost_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await Printing.sharePdf(
          bytes: Uint8List.fromList(bytes), filename: fileName);
      if (mounted) _showSnack('تم تصدير Excel بنجاح');
    } catch (e) {
      if (mounted) _showSnack('فشل تصدير Excel: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  void _excelRow(Sheet sheet, List<String> values, {bool bold = false}) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }

  // ── PDF builders ──

  pw.Widget _pdfHeader(
      pw.Font font, pw.Font fontBold, String now, String user) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(AppConstants.companyName,
            style: pw.TextStyle(
                font: fontBold, fontSize: 18, color: PdfColors.blueGrey)),
        pw.Text('تقرير التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 14, color: PdfColors.black)),
        pw.SizedBox(height: 4),
        pw.Text('تاريخ التقرير: $now',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text('المستخدم: $user',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text('نطاق التاريخ: ${_dateRangeLabel()}',
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        if (_selectedCustomer != null)
          pw.Text('العميل: $_selectedCustomer',
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _pdfSummary(pw.Font font, pw.Font fontBold, double total, int tx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ملخص التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _pdfStatCard(font, fontBold, 'الإجمالي', _fmtCurrency(total)),
            _pdfStatCard(font, fontBold, 'المعاملات', '$tx'),
            _pdfStatCard(
                font,
                fontBold,
                'أعلى بند',
                _summary.isNotEmpty
                    ? (_summary.first['item_name'] as String)
                    : '—'),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfStatCard(
      pw.Font font, pw.Font fontBold, String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  font: fontBold, fontSize: 12, color: PdfColors.black)),
        ],
      ),
    );
  }

  pw.Widget _pdfCostDistribution(pw.Font font, pw.Font fontBold, double total) {
    if (_summary.isEmpty || total <= 0) return pw.SizedBox();
    final barColors = [
      PdfColors.blueGrey,
      PdfColors.teal,
      PdfColors.amber,
      PdfColors.red,
      PdfColors.purple,
      PdfColors.green,
      PdfColors.orange,
      PdfColors.indigo,
      PdfColors.pink,
      PdfColors.cyan,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('توزيع التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        ...List.generate(_summary.length, (i) {
          final e = _summary[i];
          final name = e['item_name'] as String;
          final amt = e['total_amount'] as double;
          final tx = e['transaction_count'] as int;
          final pct = amt / total * 100;
          final color = barColors[i % barColors.length];
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                        width: 8,
                        height: 8,
                        decoration: pw.BoxDecoration(
                            color: color, shape: pw.BoxShape.circle)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                        child: pw.Text(name,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: PdfColors.black))),
                    pw.Text(_fmtCurrency(amt),
                        style: pw.TextStyle(
                            font: font, fontSize: 9, color: PdfColors.black)),
                    pw.SizedBox(width: 8),
                    pw.SizedBox(
                        width: 40,
                        child: pw.Text('${pct.toStringAsFixed(1)}%',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: PdfColors.black))),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Container(
                  height: 8,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey300,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(
                    width: pct / 100 * 460,
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text('$tx معاملة',
                    style: pw.TextStyle(
                        font: font, fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          );
        }),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي:',
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
            pw.Text(_fmtCurrency(total),
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfCostItems(pw.Font font, pw.Font fontBold, double total) {
    final headers = ['بند التكلفة', 'المبلغ', 'النسبة', 'المعاملات'];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('بنود التكاليف',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerAlignment: pw.Alignment.center,
          cellAlignment: pw.Alignment.centerRight,
          headerStyle: pw.TextStyle(
              font: fontBold, fontSize: 10, color: PdfColors.white),
          cellStyle:
              pw.TextStyle(font: font, fontSize: 9, color: PdfColors.black),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
          cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
          headers: headers,
          data: _summary.map((e) {
            final name = e['item_name'] as String;
            final amt = e['total_amount'] as double;
            final tx = e['transaction_count'] as int;
            final pct = total > 0 ? amt / total * 100 : 0.0;
            return [
              name,
              _fmtCurrency(amt),
              '${pct.toStringAsFixed(1)}%',
              '$tx'
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي:',
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
            pw.Text(_fmtCurrency(total),
                style: pw.TextStyle(
                    font: fontBold, fontSize: 10, color: PdfColors.black)),
          ],
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _pdfTransactions(pw.Font font, pw.Font fontBold) {
    final headers = [
      'التاريخ',
      'رقم الشحنة',
      'العميل',
      'بند التكلفة',
      'المبلغ',
      'البيان'
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('المعاملات',
            style: pw.TextStyle(
                font: fontBold, fontSize: 13, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        if (_recent.isEmpty)
          pw.Text('لا توجد معاملات',
              style: pw.TextStyle(
                  font: font, fontSize: 10, color: PdfColors.grey700))
        else
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: fontBold, fontSize: 9, color: PdfColors.white),
            cellStyle:
                pw.TextStyle(font: font, fontSize: 8, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
            headers: headers,
            data: _recent.map((r) {
              final date = r['shipment_date']?.toString() ?? '';
              final cat = r['category'] as String? ?? '';
              final amt = (r['amount'] as num?)?.toDouble() ?? 0;
              return [
                date.length >= 10 ? date.substring(0, 10) : date,
                r['shipment_no']?.toString() ?? '',
                r['customer_name']?.toString() ?? '',
                r['item_name']?.toString() ?? cat,
                _fmtCurrency(amt),
                r['description']?.toString() ?? '',
              ];
            }).toList(),
          ),
      ],
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}

class _TxCell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool accent;
  final bool muted;
  final TextAlign align;
  const _TxCell(this.text,
      {this.bold = false,
      this.accent = false,
      this.muted = false,
      this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: accent
              ? AppTheme.primary
              : muted
                  ? Colors.white54
                  : Colors.white,
        ));
  }
}
