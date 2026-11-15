import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../core/widgets/password_verification_dialog.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/services/cost_category_service.dart';
import 'station_supplier_form_dialog.dart';
import 'supplier_cost_settlement_view.dart';

class StationSuppliersPage extends StatefulWidget {
  const StationSuppliersPage({super.key});

  @override
  State<StationSuppliersPage> createState() => _StationSuppliersPageState();
}

class _StationSuppliersPageState extends State<StationSuppliersPage>
    with SingleTickerProviderStateMixin {
  final SupplierDao _dao = SupplierDao();
  bool _loading = true;
  List<SupplierModel> _allSuppliers = [];
  String _searchQuery = '';
  String _selectedServiceFilter = 'all';
  String? _selectedSupplierForSettlement;

  late final TabController _tabController;
  late final StreamSubscription<void> _sub;
  late final StreamSubscription<void> _catsSub;
  late final StreamSubscription<void> _poSub;
  final TextEditingController _searchCtrl = TextEditingController();

  List<String> _services = [
    'all',
    ...CostCategoryService.stationSupplierCategories,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSuppliers();
    _loadServices();
    _sub = DataChangeEventBus.instance.suppliersStream.listen((_) {
      _loadSuppliers();
    });
    _catsSub = DataChangeEventBus.instance.costCategoriesStream.listen((_) {
      _loadServices();
    });
    _poSub = DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      _loadSuppliers();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sub.cancel();
    _catsSub.cancel();
    _poSub.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final cats = await CostCategoryService().getStationCategories();
      if (mounted) {
        setState(() {
          _services = ['all', ...cats];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSuppliers() async {
    setState(() => _loading = true);
    try {
      final list = await _dao.getAll(limit: 2000, supplierTypes: ['station']);
      if (mounted) {
        setState(() {
          _allSuppliers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل موردي المحطات: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  List<SupplierModel> get _filteredSuppliers {
    return _allSuppliers.where((s) {
      // 1. Search Query filter
      final q = _searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matchesQuery = s.name.toLowerCase().contains(q) ||
            s.supplierCode.toLowerCase().contains(q) ||
            s.phone.toLowerCase().contains(q) ||
            s.address.toLowerCase().contains(q) ||
            s.categories.any((c) => c.toLowerCase().contains(q));
        if (!matchesQuery) return false;
      }

      // 2. Operational service filter
      if (_selectedServiceFilter != 'all') {
        if (!s.categories.contains(_selectedServiceFilter)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _openAddDialog() async {
    if (!ReadOnlyGuard.check(context)) return;
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StationSupplierFormDialog(),
    );
    if (res == true) {
      _loadSuppliers();
    }
  }

  void _openEditDialog(SupplierModel supplier) async {
    if (!ReadOnlyGuard.check(context)) return;
    final verified = await showPasswordVerificationDialog(
      context,
      title: 'تأكيد كلمة المرور للتعديل',
      subtitle: 'يرجى إدخال كلمة المرور لتعديل بيانات "${supplier.name}"',
      expectedPassword: 'eslam2026',
    );
    if (!verified) return;
    if (!mounted) return;

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StationSupplierFormDialog(supplier: supplier),
    );
    if (res == true) {
      _loadSuppliers();
    }
  }

  void _openStatement(SupplierModel supplier) {
    context.push(
      RoutePaths.supplierStatement,
      extra: supplier.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final displayedList = _filteredSuppliers;

    // Financial KPIs
    double totalCredit = 0.0;
    double totalDebit = 0.0;
    double totalPendingExpected = 0.0;
    for (final s in _allSuppliers) {
      if (s.outstandingBalance > 0) {
        totalCredit += s.outstandingBalance;
      } else {
        totalDebit += s.outstandingBalance.abs();
      }
      totalPendingExpected += (s.pendingExpectedBalance as num?)?.toDouble() ?? 0.0;
    }
    final netControlBalance = totalCredit - totalDebit;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF03121F) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF051B2B) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.factory_rounded, color: Color(0xFFF59E0B), size: 18),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'موردي المحطات',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(RoutePaths.home);
            }
          },
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.print_rounded, color: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488), size: 20),
            tooltip: 'طباعة تقرير مقارنة التكاليف',
            onPressed: () {
              // Switch to settlement tab so user can see print + date filters there
              _tabController.animateTo(1);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.refresh_rounded, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), size: 20),
            tooltip: 'تحديث',
            onPressed: _loadSuppliers,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.add_rounded, color: Color(0xFFF59E0B), size: 24),
            tooltip: 'إضافة مورد محطة',
            onPressed: _openAddDialog,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFF59E0B),
          unselectedLabelColor:
              isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          indicatorColor: const Color(0xFFF59E0B),
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.factory_rounded, size: 16),
              text: 'دليل موردي المحطات',
            ),
            Tab(
              icon: Icon(Icons.price_check_rounded, size: 16),
              text: 'تسوية التكاليف الفعلية',
            ),
          ],
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildSuppliersListTab(
              isDark: isDark,
              displayedList: displayedList,
              totalCredit: totalCredit,
              totalDebit: totalDebit,
              totalPendingExpected: totalPendingExpected,
              netControlBalance: netControlBalance,
            ),
            SupplierCostSettlementView(
              supplierType: 'station',
              preselectedSupplierId: _selectedSupplierForSettlement,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        backgroundColor: const Color(0xFFF59E0B),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('إضافة مورد محطة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }

  Widget _buildSuppliersListTab({
    required bool isDark,
    required List<SupplierModel> displayedList,
    required double totalCredit,
    required double totalDebit,
    required double totalPendingExpected,
    required double netControlBalance,
  }) {
    return Column(
      children: [
            // KPI Summary Cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenW = MediaQuery.of(context).size.width;
                  final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
                  final isMobile = effectiveW < 650;
                  final isWide = effectiveW > 850;

                  final cardSuppliers = _buildKpiCard(
                    title: 'إجمالي موردين المحطات',
                    value: '${_allSuppliers.length}',
                    icon: Icons.factory_rounded,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                  );
                  final cardCredit = _buildKpiCard(
                    title: 'إجمالي الأرصدة الدائنة (له)',
                    value: '${AppUtils.formatNumber(totalCredit)} ج.م',
                    icon: Icons.trending_up_rounded,
                    color: AppTheme.success,
                    isDark: isDark,
                  );
                  final cardPending = _buildKpiCard(
                    title: 'التكاليف قيد المراجعة (معلق)',
                    value: '${AppUtils.formatNumber(totalPendingExpected)} ج.م',
                    icon: Icons.hourglass_top_rounded,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                  );
                  final cardDebit = _buildKpiCard(
                    title: 'إجمالي الأرصدة المدينة (عليه)',
                    value: '${AppUtils.formatNumber(totalDebit)} ج.م',
                    icon: Icons.trending_down_rounded,
                    color: AppTheme.danger,
                    isDark: isDark,
                  );
                  final cardControl = _buildKpiCard(
                    title: 'صافي رصيد حساب التحكم 21117',
                    value: '${AppUtils.formatNumber(netControlBalance)} ج.م',
                    icon: Icons.account_balance_rounded,
                    color: const Color(0xFF06B6D4),
                    isDark: isDark,
                  );

                  if (isMobile) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          SizedBox(width: 170, child: cardSuppliers),
                          const SizedBox(width: 10),
                          SizedBox(width: 190, child: cardCredit),
                          const SizedBox(width: 10),
                          SizedBox(width: 190, child: cardPending),
                          const SizedBox(width: 10),
                          SizedBox(width: 190, child: cardDebit),
                          const SizedBox(width: 10),
                          SizedBox(width: 190, child: cardControl),
                        ],
                      ),
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: cardSuppliers),
                      const SizedBox(width: 10),
                      Expanded(child: cardCredit),
                      const SizedBox(width: 10),
                      Expanded(child: cardPending),
                      if (isWide) ...[
                        const SizedBox(width: 10),
                        Expanded(child: cardDebit),
                        const SizedBox(width: 10),
                        Expanded(child: cardControl),
                      ],
                    ],
                  );
                },
              ),
            ),

            // Search Bar & Filter Chips
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F2338) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Box
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم، كود المورد (80xxx)، رقم الهاتف، أو الخدمة التشغيلية...',
                      hintStyle: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 8),

                  // Service Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _services.map((srv) {
                        final isSelected = _selectedServiceFilter == srv;
                        final label = srv == 'all' ? 'الكل' : srv;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(label,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                )),
                            selected: isSelected,
                            selectedColor: const Color(0xFFF59E0B).withAlpha(60),
                            onSelected: (sel) {
                              if (sel) setState(() => _selectedServiceFilter = srv);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Suppliers List / Table
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                  : displayedList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.factory_outlined,
                                  size: 48, color: isDark ? Colors.white24 : Colors.black26),
                              const SizedBox(height: 10),
                              Text(
                                _searchQuery.isEmpty && _selectedServiceFilter == 'all'
                                    ? 'لا يوجد موردين محطات مسجلين حالياً'
                                    : 'لا توجد نتائج مطابقة لمعايير البحث والفلترة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 14,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_searchQuery.isEmpty && _selectedServiceFilter == 'all')
                                ElevatedButton.icon(
                                  onPressed: _openAddDialog,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('إضافة مورد محطة أول', style: TextStyle(fontFamily: 'Cairo')),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                                ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: displayedList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final s = displayedList[index];
                            final hasBalance = s.outstandingBalance != 0.0;
                            final isCredit = s.outstandingBalance > 0;

                            final actualBadge = _buildActualBalanceBadge(s, isCredit, hasBalance, isDark);
                            final pendingBadge = _buildPendingBalanceBadge(s, isDark);
                            final actions = _buildActionButtons(s);

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
                                ),
                                boxShadow: isDark
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(8),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: LayoutBuilder(
                                builder: (context, cardConstraints) {
                                  final screenW = MediaQuery.of(context).size.width;
                                  final effectiveCardW = cardConstraints.maxWidth.isFinite ? math.min(cardConstraints.maxWidth, screenW) : screenW;
                                  final isMobileCard = effectiveCardW < 750;

                                  if (isMobileCard) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withAlpha(20),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(60)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.factory_rounded, color: Color(0xFFF59E0B), size: 16),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    s.supplierCode,
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Color(0xFFF59E0B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      s.name,
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(
                                                        color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      '21117',
                                                      style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFFF59E0B),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            actions,
                                          ],
                                        ),
                                        if (s.phone.isNotEmpty || s.address.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (s.phone.isNotEmpty) ...[
                                                Icon(Icons.phone_outlined, size: 12, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                const SizedBox(width: 4),
                                                Text(s.phone, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                                                const SizedBox(width: 10),
                                              ],
                                              if (s.address.isNotEmpty) ...[
                                                Icon(Icons.location_on_outlined, size: 12, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    s.address,
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            actualBadge,
                                            pendingBadge,
                                            if (s.categories.isNotEmpty)
                                              ...s.categories.map((c) => Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF59E0B).withAlpha(20),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      c,
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFFF59E0B),
                                                      ),
                                                    ),
                                                  )),
                                          ],
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withAlpha(20),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFF59E0B).withAlpha(60)),
                                        ),
                                        child: Column(
                                          children: [
                                            const Icon(Icons.factory_rounded, color: Color(0xFFF59E0B), size: 20),
                                            const SizedBox(height: 2),
                                            Text(
                                              s.supplierCode,
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Color(0xFFF59E0B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    s.name,
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15.5,
                                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'حساب 21117',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFF59E0B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (s.phone.isNotEmpty) ...[
                                                  Icon(Icons.phone_outlined, size: 13, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Text(s.phone, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                                                  const SizedBox(width: 12),
                                                ],
                                                if (s.address.isNotEmpty) ...[
                                                  Icon(Icons.location_on_outlined, size: 13, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Text(s.address, style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            if (s.categories.isNotEmpty)
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: s.categories.map((c) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF59E0B).withAlpha(20),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      c,
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFFF59E0B),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              )
                                            else
                                              Text('لم يتم تحديد خدمات تشغيلية محددة',
                                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white30 : Colors.black38)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            alignment: WrapAlignment.end,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              actualBadge,
                                              pendingBadge,
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          actions,
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActualBalanceBadge(SupplierModel s, bool isCredit, bool hasBalance, bool isDark) {
    return Tooltip(
      message: 'الرصيد الفعلي النهائي المعتمد بالدفاتر والقيود المحاسبية',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCredit
              ? (isDark ? const Color(0xFF065F46).withAlpha(50) : const Color(0xFFECFDF5))
              : (hasBalance
                  ? (isDark ? const Color(0xFF7F1D1D).withAlpha(50) : const Color(0xFFFEF2F2))
                  : (isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9))),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCredit
                ? AppTheme.success.withAlpha(120)
                : (hasBalance ? AppTheme.danger.withAlpha(120) : (isDark ? Colors.white24 : const Color(0xFFCBD5E1))),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 13,
              color: isCredit
                  ? AppTheme.success
                  : (hasBalance ? AppTheme.danger : (isDark ? Colors.white60 : const Color(0xFF64748B))),
            ),
            const SizedBox(width: 4),
            Text(
              'فعلي: ${s.formattedCurrentBalance}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isCredit
                    ? AppTheme.success
                    : (hasBalance ? AppTheme.danger : (isDark ? Colors.white70 : const Color(0xFF334155))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingBalanceBadge(SupplierModel s, bool isDark) {
    return Tooltip(
      message: s.hasPendingBalance
          ? 'تكاليف تقديرية مسجلة بأوامر التعبئة بانتظار ورود الفواتير والمطابقة الفعلية'
          : 'لا توجد تكاليف تقديرية معلقة بانتظار التسوية',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: s.hasPendingBalance
              ? (isDark ? const Color(0xFF78350F).withAlpha(60) : const Color(0xFFFFFBEB))
              : (isDark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: s.hasPendingBalance
                ? const Color(0xFFF59E0B).withAlpha(140)
                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              s.hasPendingBalance ? Icons.hourglass_top_rounded : Icons.hourglass_empty_rounded,
              size: 13,
              color: s.hasPendingBalance
                  ? const Color(0xFFF59E0B)
                  : (isDark ? Colors.white30 : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 4),
            Text(
              'تقديري معلق: ${s.formattedPendingExpectedBalance}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: s.hasPendingBalance ? FontWeight.bold : FontWeight.normal,
                color: s.hasPendingBalance
                    ? const Color(0xFFD97706)
                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(SupplierModel s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.receipt_long_rounded, size: 20),
          tooltip: 'كشف الحساب',
          color: const Color(0xFF06B6D4),
          onPressed: () => _openStatement(s),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.price_check_rounded, size: 20),
              tooltip: s.hasPendingBalance
                  ? 'تسوية التكاليف الفعلية (توجد بنود معلقة بانتظار التسوية)'
                  : 'تسوية التكاليف الفعلية',
              color: const Color(0xFF0D9488),
              onPressed: () {
                setState(() {
                  _selectedSupplierForSettlement = s.id;
                  _tabController.animateTo(1);
                });
              },
            ),
            if (s.hasPendingBalance)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'تعديل',
          color: const Color(0xFFF59E0B),
          onPressed: () => _openEditDialog(s),
        ),
      ],
    );
  }
}
