import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/theme.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/dao/packing_order_dao.dart';
import 'packing_order_cost_adjustment_dialog.dart';
import '../auth/auth_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/packing_excel_exporter.dart';
import 'packing_order_pdf_service.dart';
import 'packing_order_details_dialog.dart';
import 'widgets/packing_cost_variance_settlement_modal.dart';

class PackingOrdersPage extends StatefulWidget {
  const PackingOrdersPage({super.key});

  @override
  State<PackingOrdersPage> createState() => _PackingOrdersPageState();
}

class _PackingOrdersPageState extends State<PackingOrdersPage> {
  final _dao = PackingOrderDao();
  List<PackingOrderModel> _allOrders = [];
  List<PackingOrderModel> _filtered = [];
  final Set<int> _ordersInShipment = {};
  final Set<int> _ordersWithSoldSorting = {};
  final Set<int> _ordersWithDistributedShipment = {};
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _filterNeedsRefresh = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
      case 'pending':
        return AppTheme.warning;
      case 'crops_confirmed':
        return AppTheme.primary;
      case 'packaging_confirmed':
        return const Color(0xFF0284C7);
      case 'costs_confirmed':
        return const Color(0xFFD97706);
      case 'final_approved':
      case 'completed':
        return AppTheme.success;
      case 'in_progress':
        return const Color(0xFF3B82F6);
      case 'cancelled':
        return AppTheme.danger;
      case 'returned':
        return const Color(0xFFEA580C);
      default:
        return AppTheme.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
      case 'pending':
        return 'مسودة';
      case 'crops_confirmed':
        return 'مؤكد المحاصيل';
      case 'packaging_confirmed':
        return 'مؤكد مواد التعبئة';
      case 'costs_confirmed':
        return 'مؤكد التكاليف';
      case 'final_approved':
      case 'completed':
        return 'معتمد نهائياً';
      case 'in_progress':
        return 'قيد التشغيل';
      case 'cancelled':
        return 'ملغي';
      case 'returned':
        return 'مرتجع';
      default:
        return status;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      try {
        _allOrders = await _dao.getAll();
      } catch (e) {
        await Future.delayed(const Duration(milliseconds: 600));
        _allOrders = await _dao.getAll();
      }
      _ordersInShipment.clear();
      _ordersInShipment.addAll(await _dao.getOrdersUsedInShipments());
      _ordersWithSoldSorting.clear();
      _ordersWithSoldSorting.addAll(await _dao.getOrdersWithSoldSorting());
      _ordersWithDistributedShipment.clear();
      _ordersWithDistributedShipment.addAll(await _dao.getOrdersWithDistributedShipments());
    } catch (e) {
      debugPrint('⚠️ Error loading packing orders: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحميل أوامر التعبئة: $e', textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
            action: SnackBarAction(label: 'إعادة المحاولة', textColor: Colors.white, onPressed: _load),
          ),
        );
      }
    }
    _applyFilters();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();
    _filtered = _allOrders.where((o) {
      if (q.isNotEmpty) {
        final matchOrder = o.orderNumber.toLowerCase().contains(q);
        final matchProduct = (o.productName ?? '').toLowerCase().contains(q);
        final matchLot = (o.lotNumber ?? '').toLowerCase().contains(q);
        final matchShipment = (o.exportShipmentNo ?? '').toLowerCase().contains(q);
        final matchCustomer = (o.customerName ?? '').toLowerCase().contains(q);
        if (!matchOrder && !matchProduct && !matchLot && !matchShipment && !matchCustomer) return false;
      }
      if (_dateFrom != null && o.createdAt != null) {
        if (o.createdAt!.isBefore(_dateFrom!)) return false;
      }
      if (_dateTo != null && o.createdAt != null) {
        final endOfDay = _dateTo!.add(const Duration(days: 1));
        if (o.createdAt!.isAfter(endOfDay)) return false;
      }
      if (_filterNeedsRefresh && !o.needsPriceRefresh) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          isFrom ? (_dateFrom ?? DateTime.now()) : (_dateTo ?? DateTime.now()),
      firstDate: DateTime(2024),
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
        body: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.background,
                      Color(0xFF0D2137),
                      AppTheme.background
                    ],
                  ),
                )
              : null,
          child: Column(children: [
            _buildHeader(isDark),
            _buildSearchBar(isDark),
            Expanded(child: _buildBody(isDark)),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(null),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('أمر تعبئة جديد',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 20,
              right: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(
                bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.checklist_outlined,
                  color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('أوامر التعبئة',
                  style: TextStyle(
                      color: isDark ? AppTheme.textPrimary : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'طباعة وسجل أوامر التعبئة والتغليف (PDF)',
              child: GestureDetector(
                onTap: _exportPdfAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.primary.withAlpha(60) : const Color(0xFF0284C7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf,
                          color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'طباعة السجل (PDF)',
                        style: TextStyle(
                          color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'تحديث قائمة أوامر التعبئة',
              child: GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  ),
                  child: Icon(Icons.refresh_rounded,
                      color: isDark ? AppTheme.textSecondary : Colors.black87, size: 20),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'بحث بكود الطلب، المنتج، رقم الشحنة، أو اسم العميل...',
            hintStyle: TextStyle(
                color: isDark ? AppTheme.textMuted : Colors.black54, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
            prefixIcon: Icon(Icons.search,
                color: isDark ? AppTheme.textSecondary : Colors.black54, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        color: isDark ? AppTheme.textSecondary : Colors.black54, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _applyFilters();
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark ? const Color(0x2005192D) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() {
            _applyFilters();
          }),
        ),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _dateFilterChip(
                icon: Icons.date_range,
                label: _dateFrom != null
                    ? DateFormat('yyyy/MM/dd').format(_dateFrom!)
                    : 'من تاريخ',
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
                label: _dateTo != null
                    ? DateFormat('yyyy/MM/dd').format(_dateTo!)
                    : 'إلى تاريخ',
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
              if (_dateFrom != null ||
                  _dateTo != null ||
                  _searchCtrl.text.isNotEmpty ||
                  _filterNeedsRefresh)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() {
                      _dateFrom = null;
                      _dateTo = null;
                      _filterNeedsRefresh = false;
                      _applyFilters();
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text('مسح الكل',
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
      ]),
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
              : (isDark ? AppTheme.primary.withAlpha(10) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? (isDark ? AppTheme.primary.withAlpha(60) : const Color(0xFF0284C7))
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
                  fontFamily: 'Cairo',
                )),
            if (active && onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close,
                      size: 12, color: AppTheme.danger)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_filtered.isEmpty) return _buildEmptyState(isDark);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _filtered.map((o) => _buildOrderCard(o, isDark)).toList(),
      ),
    );
  }

  Widget _buildOrderCard(PackingOrderModel order, bool isDark) {
    final statusColor = _statusColor(order.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: order.needsPriceRefresh
                      ? Colors.yellow.withAlpha(200)
                      : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  width: order.needsPriceRefresh ? 2.0 : 1.0),
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
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _buildStatusBadge(order.status, statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Text(order.orderNumber,
                                style: TextStyle(
                                    color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Cairo')),
                            if (order.lines.length > 1) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.neonCyan.withAlpha(30) : const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: isDark ? AppTheme.neonCyan.withAlpha(80) : const Color(0xFF0284C7)),
                                ),
                                child: Text(
                                  '${order.lines.length} محاصيل',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!order.isFinalApproved && order.status != 'completed') ...[
                        _buildFinalApprovalButton(order),
                        const SizedBox(width: 6),
                      ],
                      if (!order.isFinalApproved && order.status != 'completed') ...[
                        const SizedBox(width: 6),
                        _buildEditButton(order),
                      ],
                      if (order.needsPriceRefresh) ...[
                        const SizedBox(width: 6),
                        _buildRefreshButton(order),
                      ],
                      if (order.status != 'draft' &&
                          order.status != 'pending') ...[
                        const SizedBox(width: 6),
                        _buildJournalButton(order),
                      ],
                      const SizedBox(width: 6),
                      _buildPdfButton(order),
                      if (order.status != 'draft' &&
                          order.status != 'pending') ...[
                        const SizedBox(width: 6),
                        _buildExportButton(order),
                      ],
                      if (order.isFinalApproved || order.status == 'completed') ...[
                        const SizedBox(width: 6),
                        _buildViewButton(order),
                      ],
                      if (order.status != 'draft' &&
                          order.status != 'pending') ...[
                        const SizedBox(width: 6),
                        _buildVarianceSettlementButton(order),
                      ],
                      if (order.status != 'draft' &&
                          order.status != 'pending' &&
                          context.watch<AuthCubit>().state is AuthAuthenticated &&
                          (context.watch<AuthCubit>().state as AuthAuthenticated).isAdmin &&
                          !_ordersWithDistributedShipment.contains(int.tryParse(order.id ?? ''))) ...[
                        const SizedBox(width: 6),
                        _buildCostAdjustmentButton(order),
                      ],
                    ]),
                    GestureDetector(
                      onTap: () => _openOrderDetails(order),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                              order.lines.length > 1
                                  ? '${order.lines.length} أصناف: ${order.lines.map((l) => l.productName).join(' ، ')}'
                                  : (order.productName ?? '—'),
                              style: TextStyle(
                                  color: isDark ? AppTheme.textPrimary : Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          if (order.lines.length > 1) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: order.lines.map((l) {
                                final remaining = l.cartonCount - l.soldCartons;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.productName.isNotEmpty
                                            ? l.productName
                                            : 'صنف',
                                        style: TextStyle(
                                          color: isDark ? AppTheme.textPrimary : Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${l.cartonCount} كرتونة (${l.netWeightPerCarton.toStringAsFixed(0)} كجم) | متبقي: $remaining',
                                        style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black87,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          // === Export Shipment & Customer Tags ===
                          if ((order.exportShipmentNo != null && order.exportShipmentNo!.isNotEmpty) ||
                              (order.customerName != null && order.customerName!.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (order.exportShipmentNo != null && order.exportShipmentNo!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.blue.withAlpha(25) : const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: isDark ? Colors.blue.withAlpha(80) : const Color(0xFF93C5FD)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.local_shipping_outlined, size: 12, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          'شحنة: ${order.exportShipmentNo}',
                                          style: TextStyle(
                                            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order.customerName != null && order.customerName!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.teal.withAlpha(25) : const Color(0xFFF0FDFA),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: isDark ? Colors.teal.withAlpha(80) : const Color(0xFF5EEAD4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person_outline, size: 12, color: isDark ? Colors.teal.shade300 : Colors.teal.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          'عميل: ${order.customerName}',
                                          style: TextStyle(
                                            color: isDark ? Colors.teal.shade300 : Colors.teal.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(children: [
                            Text(
                                '${order.cartonCount} كرتونة ',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                          ]),
                          if (order.soldCartons > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.shopping_cart_outlined,
                                  size: 14, color: AppTheme.success),
                              const SizedBox(width: 4),
                              Text(
                                  'تباع ${order.soldCartons} / ${order.cartonCount} | متبقي ${order.remainingCartons}',
                                  style: const TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo')),
                            ]),
                          ],
                          if (order.createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                                DateFormat('yyyy/MM/dd')
                                    .format(order.createdAt!),
                                style: TextStyle(
                                    color: isDark ? AppTheme.textMuted : Colors.black54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                          ],
                          if (order.notes != null &&
                              order.notes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildNotesSummary(order.notes!),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfButton(PackingOrderModel order) {
    return Tooltip(
      message: 'طباعة إذن التعبئة والتغليف (PDF)',
      child: GestureDetector(
        onTap: () => _printOrderPdf(order),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(40)),
          ),
          child: const Icon(Icons.picture_as_pdf, size: 16, color: AppTheme.primary),
        ),
      ),
    );
  }

  Future<void> _printOrderPdf(PackingOrderModel order) async {
    final warehouseName = order.stationId != null
        ? 'محطة ${order.stationId}'
        : 'محطة التعبئة والتغليف المركزية';
    await PackingOrderPdfService.printOrderVoucher(
      context,
      order: order,
      warehouseName: warehouseName,
    );
  }

  Widget _buildExportButton(PackingOrderModel order) {
    return Tooltip(
      message: 'تصدير تفاصيل أمر التعبئة (Excel)',
      child: GestureDetector(
        onTap: () => _exportExcelSingle(order),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.success.withAlpha(40)),
          ),
          child: const Icon(Icons.table_view, size: 16, color: AppTheme.success),
        ),
      ),
    );
  }

  Widget _buildEditButton(PackingOrderModel order) {
    return Tooltip(
      message: 'تعديل أمر التعبئة',
      child: GestureDetector(
        onTap: () => context.push('/packing/new', extra: order).then((_) {
          if (mounted) _load();
        }),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(40)),
          ),
          child: const Icon(Icons.edit, size: 16, color: AppTheme.primary),
        ),
      ),
    );
  }

  Future<void> _exportExcelSingle(PackingOrderModel order) async {
    try {
      final data = await PackingExcelExporter.prepareOrderData(order);
      if (data == null) return;
      final warehouseName = order.stationId?.toString() ?? 'محطة افتراضية';

      if (mounted) {
        await PackingExcelExporter.export(
          context,
          order: order,
          productSummaries: data.productSummaries,
          rawCostItems: data.costItems,
          calc: data.calcResult,
          warehouseName: warehouseName,
          totalSortingCost: data.totalSortingCost,
          totalRawWeightKg: data.totalRawWeightKg,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ أثناء التصدير: $e')));
      }
    }
  }

  Widget _buildRefreshButton(PackingOrderModel order) {
    return Tooltip(
      message: 'تحديث أسعار البنود والمحاصيل لأمر التعبئة',
      child: GestureDetector(
        onTap: () async {
          try {
            setState(() => _loading = true);
            await _dao.refreshPrices(int.parse(order.id!));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم تحديث السعر بنجاح',
                      style: TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.success,
                ),
              );
              await _load();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('حدث خطأ أثناء تحديث السعر: $e',
                      style: const TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.danger,
                ),
              );
              setState(() => _loading = false);
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.yellow.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.yellow.withAlpha(40)),
          ),
          child: const Icon(Icons.refresh, size: 16, color: Colors.yellow),
        ),
      ),
    );
  }

  Widget _buildViewButton(PackingOrderModel order) {
    return Tooltip(
      message: 'عرض تفاصيل وبيانات أمر التعبئة',
      child: GestureDetector(
        onTap: () => context.push('/packing/view', extra: order).then((_) {
          if (mounted) _load();
        }),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.accent.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent.withAlpha(40)),
          ),
          child: const Icon(Icons.visibility, size: 16, color: AppTheme.accent),
        ),
      ),
    );
  }

  void _openOrderDetails(PackingOrderModel order) {
    showDialog(
      context: context,
      builder: (_) => PackingOrderDetailsDialog(order: order),
    ).then((_) {
      if (mounted) _load();
    });
  }

  Widget _buildVarianceSettlementButton(PackingOrderModel order) {
    final ordId = int.tryParse(order.id ?? '');
    if (ordId == null) return const SizedBox.shrink();

    return Tooltip(
      message: 'تسوية الفروق الفعلية وإعادة احتساب الربحية (Estimated vs. Actual)',
      child: GestureDetector(
        onTap: () {
          PackingCostVarianceSettlementModal.show(
            context,
            packingOrderId: ordId,
            orderNumber: order.orderNumber,
            order: order,
            onSettled: _load,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF06B6D4).withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF06B6D4).withAlpha(60)),
          ),
          child: const Icon(Icons.compare_arrows,
              size: 16, color: Color(0xFF06B6D4)),
        ),
      ),
    );
  }

  Widget _buildCostAdjustmentButton(PackingOrderModel order) {
    return Tooltip(
      message: 'تعديل وتسوية تكاليف أمر التعبئة',
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => PackingOrderCostAdjustmentDialog(
              order: order,
              onUpdated: _load,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(60)),
          ),
          child: const Icon(Icons.price_change_outlined,
              size: 16, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _buildJournalButton(PackingOrderModel order) {
    return Tooltip(
      message: 'عرض القيد المحاسبي لأمر التعبئة',
      child: GestureDetector(
        onTap: () async {
          final journalEntryId = order.journalEntryId;
          final packingOrderId = order.id;
          String searchKey = journalEntryId ?? '';

          if (journalEntryId != null && journalEntryId.isNotEmpty) {
            try {
              final parsedId = int.tryParse(journalEntryId) ?? 0;
              final jeRes = await Supabase.instance.client
                  .from('journal_entries')
                  .select('id')
                  .eq('id', parsedId)
                  .maybeSingle();

              if (jeRes == null && packingOrderId != null) {
                final fallback = await Supabase.instance.client
                    .from('journal_entries')
                    .select('id')
                    .eq('source_type', 'packing_order')
                    .eq('source_id', packingOrderId)
                    .order('id', ascending: false)
                    .maybeSingle();
                if (fallback != null) {
                  searchKey = fallback['id'].toString();
                }
              }
            } catch (_) {}
          }

          if (searchKey.isNotEmpty) {
            if (mounted) {
              JournalEntryNavigationService.openById(
                context,
                journalEntryId: searchKey,
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('لا يوجد قيد محاسبي لهذا الأمر',
                      style: TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.warning,
                ),
              );
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.success.withAlpha(40)),
          ),
          child:
              const Icon(Icons.book_outlined, size: 16, color: AppTheme.success),
        ),
      ),
    );
  }

  Widget _buildFinalApprovalButton(PackingOrderModel order) {
    return Tooltip(
      message: 'إقفال واعتماد أمر التعبئة نهائياً',
      child: GestureDetector(
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Row(
                children: [
                  Icon(Icons.verified, color: AppTheme.success, size: 22),
                  SizedBox(width: 8),
                  Text('إقفال واعتماد أمر التعبئة نهائياً',
                      style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Text(
                'هل أنت متأكد من الإقفال والاعتماد النهائي لأمر التعبئة رقم (${order.orderNumber})؟\n\n'
                '• سيتم اعتماد وتثبيت جميع المراحل والقيود المحاسبية.\n'
                '• لن يمكن تعديل أو زيادة المحاصيل أو مواد التعبئة أو التكاليف بعد هذا الإجراء.\n'
                '• سيصبح أمر التعبئة مكتملاً ومقفلاً بالكامل.',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                  label: const Text('تأكيد الإقفال النهائي',
                      style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('جاري الإقفال والاعتماد النهائي...'), duration: Duration(seconds: 2)));
          String? error = await _dao.confirmFinalStage(int.parse(order.id!));
          if (error != null && (error.contains('not found') || error.contains('PGRST202') || error.contains('Could not find'))) {
            error = await _dao.confirmOrder(int.parse(order.id!));
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          if (error == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم إقفال واعتماد أمر التعبئة بنجاح'),
                backgroundColor: AppTheme.success));
            DataChangeEventBus.instance.notifyStationsChanged();
            DataChangeEventBus.instance.notifyCropPurchasesChanged();
            DataChangeEventBus.instance.notifyItemsChanged();
            DataChangeEventBus.instance.notifySuppliersChanged();
            DataChangeEventBus.instance.notifyJournalEntriesChanged();
            _load();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('خطأ: $error'), backgroundColor: AppTheme.danger));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF059669),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF059669).withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 1),
              )
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, size: 15, color: Colors.white),
              SizedBox(width: 5),
              Text('إقفال نهائي',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
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
      child: Text(_statusLabel(status),
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'Cairo')),
    );
  }

  Widget _buildNotesSummary(String notesStr) {
    try {
      final notes = jsonDecode(notesStr) as Map<String, dynamic>;
      final chips = <Widget>[];

      // if (notes.containsKey('waste_weight_kg')) {
      //   final waste = (notes['waste_weight_kg'] as num?) ?? 0;
      //   if (waste > 0) {
      //     chips.add(_noteChip(
      //         'هالك: ${waste.toStringAsFixed(1)} كجم', AppTheme.warning));
      //   }
      // }

      if (notes.containsKey('grade_a_kg')) {
        final a = (notes['grade_a_kg'] as num?) ?? 0;
        final b = (notes['grade_b_kg'] as num?) ?? 0;
        final c = (notes['grade_c_kg'] as num?) ?? 0;
        if (a > 0 || b > 0 || c > 0) {
          chips.add(_noteChip(
              'A: ${a.toStringAsFixed(1)} | B: ${b.toStringAsFixed(1)} | C: ${c.toStringAsFixed(1)}',
              AppTheme.textSecondary));
        }
      }

      // if (notes.containsKey('materials')) {
      //   final materials = notes['materials'] as List?;
      //   if (materials != null && materials.isNotEmpty) {
      //     chips.add(
      //         _noteChip('مواد تعبئة: ${materials.length}', AppTheme.primary));
      //   }
      // }

      if (notes.containsKey('cost_items')) {
        final costItems = notes['cost_items'] as List?;
        if (costItems != null && costItems.isNotEmpty) {
          chips.add(
              _noteChip('بنود تكلفة: ${costItems.length}', AppTheme.primary));
        }
      }

      if (chips.isEmpty) return const SizedBox.shrink();
      return Wrap(spacing: 6, runSpacing: 4, children: chips);
    } catch (_) {
      return Text(notesStr,
          style: const TextStyle(
              color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'));
    }
  }

  Widget _noteChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontFamily: 'Cairo')),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15), shape: BoxShape.circle),
            child: const Icon(Icons.checklist_outlined,
                size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text('لا توجد أوامر تعبئة',
              style: TextStyle(
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط على "أمر تعبئة جديد" لإنشاء أول أمر',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary.withAlpha(180) : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Future<void> _exportPdfAll() async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد أوامر تعبئة مطابقة للطباعة',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    await PackingOrderPdfService.printOrdersRegister(
      context,
      orders: _filtered,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      filterQuery: _searchCtrl.text.trim(),
    );
  }

  void _openForm(PackingOrderModel? order) {
    context.push('/packing/new', extra: order).then((_) {
      if (mounted) _load();
    });
  }
}
