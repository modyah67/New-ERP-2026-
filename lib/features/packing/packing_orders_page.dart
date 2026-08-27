import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/dao/packing_order_dao.dart';
import 'packing_order_details_dialog.dart';
import 'packing_order_cost_adjustment_dialog.dart';
import '../auth/auth_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/packing_calculation_service.dart';
import 'utils/packing_excel_exporter.dart';

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
        return AppTheme.warning;
      case 'pending':
        return AppTheme.warning;
      case 'in_progress':
        return const Color(0xFF3B82F6);
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
      case 'pending':
        return 'مسودة';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مؤكد';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _allOrders = await _dao.getAll();
      _ordersInShipment.clear();
      _ordersInShipment.addAll(await _dao.getOrdersUsedInShipments());
      _ordersWithSoldSorting.clear();
      _ordersWithSoldSorting.addAll(await _dao.getOrdersWithSoldSorting());
      _ordersWithDistributedShipment.clear();
      _ordersWithDistributedShipment.addAll(await _dao.getOrdersWithDistributedShipments());
    } catch (_) {}
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
        if (!matchOrder && !matchProduct && !matchLot) return false;
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

  String _mapCostCategory(String cat) {
    switch (cat) {
      case 'fruit':
        return 'تكلفة الفاكهة';
      case 'material':
        return 'مواد تعبئة';
      case 'logistics':
        return 'لوجستيك ونقل';
      case 'other':
        return 'أخرى';
      default:
        return cat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.background,
                Color(0xFF0D2137),
                AppTheme.background
              ],
            ),
          ),
          child: Column(children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(null),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('أمر تعبئة جديد',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
            color: const Color(0x3805192D),
            border: Border(
                bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
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
            const Expanded(
              child: Text('أوامر التعبئة',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: const Icon(Icons.refresh_rounded,
                    color: AppTheme.textSecondary, size: 20),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(
              color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'بحث بكود الطلب أو اسم المنتج...',
            hintStyle: TextStyle(
                color: AppTheme.textMuted, fontFamily: 'Cairo', fontSize: 13),
            prefixIcon: const Icon(Icons.search,
                color: AppTheme.textSecondary, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _applyFilters();
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0x2005192D),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppTheme.glassBorder),
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
                onClear: () {
                  setState(() {
                    _dateTo = null;
                    _applyFilters();
                  });
                },
              ),
              // _dateFilterChip(
              //   icon: Icons.refresh,
              //   label: 'اوامر التعبئة التي تحتاج الي تحديث الاسعار',
              //   onTap: () {
              //     setState(() {
              //       _filterNeedsRefresh = !_filterNeedsRefresh;
              //       _applyFilters();
              //     });
              //   },
              //   active: _filterNeedsRefresh,
              //   onClear: () {
              //     setState(() {
              //       _filterNeedsRefresh = false;
              //       _applyFilters();
              //     });
              //   },
              // ),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withAlpha(30)
              : AppTheme.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? AppTheme.primary.withAlpha(60)
                  : AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  color: active ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 11,
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_filtered.isEmpty) return _buildEmptyState();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _filtered.map((o) => _buildOrderCard(o)).toList(),
      ),
    );
  }

  Widget _buildOrderCard(PackingOrderModel order) {
    final statusColor = _statusColor(order.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x3805192D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: order.needsPriceRefresh
                      ? Colors.yellow.withAlpha(200)
                      : AppTheme.glassBorder,
                  width: order.needsPriceRefresh ? 2.0 : 1.0),
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
                        child: Text(order.orderNumber,
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      if (order.status == 'pending' ||
                          order.status == 'draft') ...[
                        _buildConfirmButton(order),
                        const SizedBox(width: 6),
                      ],
                      if (order.status == 'draft' ||
                          order.status == 'pending') ...[
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
                        const SizedBox(width: 6),
                        _buildExportButton(order),
                        const SizedBox(width: 6),
                        _buildViewButton(order),
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
                      // onTap: () => showDialog(
                      //   context: context,
                      //   builder: (_) => PackingOrderDetailsDialog(order: order),
                      // ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                              order.lines.length > 1
                                  ? '${order.lines.length} أصناف: ${order.lines.map((l) => l.productName).join(' ، ')}'
                                  : (order.productName ?? '—'),
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'Cairo'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(children: [
                            Text(
                                '${order.cartonCount} كرتونة ',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    fontFamily: 'Cairo')),
                          ]),
                          if (order.soldCartons > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 14, color: AppTheme.success),
                              const SizedBox(width: 4),
                              Text(
                                  'تباع ${order.soldCartons} / ${order.cartonCount} | متبقي ${order.remainingCartons}',
                                  style: TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo')),
                            ]),
                          ],
                          const SizedBox(height: 4),
                          //Row(children: [
                          //   Text(
                          //       'صافي: ${order.totalNetWeight.toStringAsFixed(1)} كجم',
                          //       style: const TextStyle(
                          //           color: AppTheme.success,
                          //           fontSize: 13,
                          //           fontWeight: FontWeight.w600,
                          //           fontFamily: 'Cairo')),
                          //   const SizedBox(width: 16),
                          //   Text(
                          //       'إجمالي: ${order.totalGrossWeight.toStringAsFixed(1)} كجم',
                          //       style: const TextStyle(
                          //           color: AppTheme.textSecondary,
                          //           fontSize: 13,
                          //           fontFamily: 'Cairo')),
                          // ]),
                          if (order.createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                                DateFormat('yyyy/MM/dd')
                                    .format(order.createdAt!),
                                style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
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

  Widget _buildExportButton(PackingOrderModel order) {
    return GestureDetector(
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
    );
  }

  Widget _buildEditButton(PackingOrderModel order) {
    return GestureDetector(
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
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ أثناء التصدير: $e')));
      }
    }
  }

  Widget _buildRefreshButton(PackingOrderModel order) {
    return GestureDetector(
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
    );
  }

  Widget _buildViewButton(PackingOrderModel order) {
    return GestureDetector(
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
    );
  }

  Widget _buildCostAdjustmentButton(PackingOrderModel order) {
    return GestureDetector(
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
    );
  }

  Widget _buildJournalButton(PackingOrderModel order) {
    return GestureDetector(
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
    );
  }

  Widget _buildConfirmButton(PackingOrderModel order) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('تأكيد أمر التعبئة',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            content: Text(
                'هل أنت متأكد من تأكيد أمر التعبئة ${order.orderNumber}؟\nسيتم خصم المحاصيل ومواد التعبئة من المخزن.',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                child: const Text('تأكيد',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('جاري التأكيد...'), duration: Duration(seconds: 2)));
        final error = await _dao.confirmOrder(int.parse(order.id!));
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        if (error == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تأكيد أمر التعبئة بنجاح'),
              backgroundColor: AppTheme.success));
          DataChangeEventBus.instance.notifyStationsChanged();
          DataChangeEventBus.instance.notifyCropPurchasesChanged();
          DataChangeEventBus.instance.notifyItemsChanged();
          DataChangeEventBus.instance.notifySuppliersChanged();
          _load();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('خطأ: $error'), backgroundColor: AppTheme.danger));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تأكيد',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            SizedBox(width: 6),
            Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton(PackingOrderModel order) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('????? ????? ???????',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            content: Text(
                '?? ??? ????? ?? ??? ????? ??????? ?\n?? ???? ??????? ?? ??? ???????.',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('????',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                child: const Text('???',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('???? ?????...'), duration: Duration(seconds: 2)));
        try {
          await _dao.delete(int.parse(order.id!));
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('?? ??? ??????? ?????'),
              backgroundColor: AppTheme.success));
          _load();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('???: $e'), backgroundColor: AppTheme.danger));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.danger.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.danger.withAlpha(40)),
        ),
        child:
            const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
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
          style: TextStyle(
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

  Widget _buildEmptyState() {
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
          const Text('لا توجد أوامر تعبئة',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط على "أمر تعبئة جديد" لإنشاء أول أمر',
              style: TextStyle(
                  color: AppTheme.textSecondary.withAlpha(180),
                  fontSize: 14,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Future<void> _exportPdfAll() async {
    if (_filtered.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('جاري إنشاء PDF...'), duration: Duration(seconds: 2)));

    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(boldData);
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    final doc = pw.Document();
    final totalPages = (_filtered.length / 50).ceil();
    for (var pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final start = pageIdx * 50;
      final end = (start + 50).clamp(0, _filtered.length);
      final pageOrders = _filtered.sublist(start, end);

      doc.addPage(pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) => [
          if (pageIdx == 0) ...[
            pw.Text('أوامر التعبئة',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 16, color: PdfColors.blueGrey)),
            pw.Text(
                'إجمالي الأوامر: ${_filtered.length} | تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
          ],
          pw.TableHelper.fromTextArray(
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            headerStyle: pw.TextStyle(
                font: boldFont, fontSize: 8, color: PdfColors.white),
            cellStyle:
                pw.TextStyle(font: font, fontSize: 7, color: PdfColors.black),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
            cellHeight: 18,
            headers: [
              '#',
              'رقم الأمر',
              'المحصول',
              'المورد',
              'التاريخ',
              'الحالة',
              'الكراتين',
              'الوزن الصافي',
              'التكلفة الإجمالية'
            ],
            data: [
              for (int i = 0; i < pageOrders.length; i++)
                _pdfRow(start + i + 1, pageOrders[i]),
            ],
          ),
        ],
      ));
    }

    final bytes = await doc.save();
    final dir = await FileHelper.getExportDirectory();
    final filePath =
        '${dir.path}/packing_orders_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(filePath).writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: filePath);
  }

  List<String> _pdfRow(int index, PackingOrderModel o) {
    double packingCost = o.totalPackingCost;
    if (packingCost >= (o.fruitCostAllocated + o.actualMaterialCost) &&
        packingCost > 0) {
      packingCost = packingCost - o.fruitCostAllocated - o.actualMaterialCost;
    }
    final totalCost = o.fruitCostAllocated + packingCost + o.actualMaterialCost;
    return [
      index.toString(),
      o.orderNumber,
      o.productName ?? '—',
      o.supplierName ?? '—',
      o.createdAt != null ? DateFormat('yyyy-MM-dd').format(o.createdAt!) : '—',
      _statusLabel(o.status),
      o.cartonCount.toString(),
      '${o.totalNetWeight.toStringAsFixed(1)} كجم',
      '${totalCost.toStringAsFixed(2)} ${o.displayCurrency}',
    ];
  }

  void _openForm(PackingOrderModel? order) {
    context.push('/packing/new', extra: order).then((_) {
      if (mounted) _load();
    });
  }
}
