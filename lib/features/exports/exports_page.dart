import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/models/export_shipment_model.dart';
import 'export_shipment_cubit.dart';
import 'export_shipment_detail_page.dart';
import 'credit_note_pdf_service.dart';
import 'shipment_invoice_pdf_service.dart';
import '../../data/dao/shipment_cost_breakdown_dao.dart';
import '../../data/models/shipment_cost_breakdown_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'export_shipment_return_page.dart';

class ExportsPage extends StatefulWidget {
  const ExportsPage({super.key});

  @override
  State<ExportsPage> createState() => _ExportsPageState();
}

class _ExportsPageState extends State<ExportsPage> {
  final _searchController = TextEditingController();
  final _shipmentDao = ExportShipmentDao();
  String? _statusFilter;
  bool _showAllIncludingCancelled = false;
  String? _fromDate;
  String? _toDate;
  bool _showFilters = false;
  Map<String, double> _itemTotals = {};
  Set<String> _distributedShipmentIds = {};
  StreamSubscription<void>? _shareholdersSub;

  @override
  void initState() {
    super.initState();
    _shareholdersSub = DataChangeEventBus.instance.shareholdersStream.listen((_) {
      if (mounted) _applyAllFilters();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyAllFilters();
    });
  }

  @override
  void dispose() {
    _shareholdersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  static const _statuses = [
    null, 'draft', 'booked', 'loaded', 'sailed', 'arrived', 'completed', 'returned_from_airport', 'cancelled',
  ];

  String _statusLabel(String? status) {
    switch (status) {
      case null: return 'الكل';
      case 'draft': return 'مسودة';
      case 'booked': return 'محجوزة';
      case 'loaded': return 'محملة';
      case 'sailed': return 'أبحرت';
      case 'arrived': return 'وصلت';
      case 'completed': return 'مكتملة';
      case 'returned_from_airport': return 'عائدة من المطار';
      case 'cancelled': return 'ملغاة';
      default: return status;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'draft': return AppTheme.textSecondary;
      case 'booked': return const Color(0xFF3B82F6);
      case 'loaded': return AppTheme.warning;
      case 'sailed': return const Color(0xFF22D3EE);
      case 'arrived': return const Color(0xFF8B5CF6);
      case 'completed': return AppTheme.success;
      case 'returned_from_airport': return const Color(0xFFEA580C);
      case 'cancelled': return AppTheme.danger;
      default: return AppTheme.primary;
    }
  }

  void _loadItemTotals(List<ExportShipmentModel> shipments) async {
    final ids = shipments.map((s) => s.id).where((id) => id != null).toList();
    if (ids.isEmpty) return;
    final totals = await _shipmentDao.getItemTotals(ids);

    Set<String> distributedIds = {};
    try {
      final intIds = ids.map((id) => int.tryParse(id!)).whereType<int>().toList();
      if (intIds.isNotEmpty) {
        final distRows = await Supabase.instance.client
            .from('shareholder_profit_distributions')
            .select('shipment_id')
            .inFilter('shipment_id', intIds)
            .isFilter('deleted_at', null);
        for (final r in (distRows as List)) {
          final sid = r['shipment_id']?.toString();
          if (sid != null && sid.isNotEmpty) {
            distributedIds.add(sid);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading distributed shipments: $e');
    }

    if (mounted) {
      setState(() {
        if (totals.isNotEmpty) _itemTotals = totals;
        _distributedShipmentIds = distributedIds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFF8FAFC)],
                  ),
          ),
          child: Column(
            children: [
              _buildHeader(isDark),
              _buildSearchBar(isDark),
              if (_showFilters) _buildFilters(isDark),
              Expanded(
                child: BlocConsumer<ExportShipmentCubit, ExportShipmentState>(
                  listener: (context, state) {
                    if (state is ExportShipmentOperationSuccess) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.message), backgroundColor: AppTheme.success, duration: const Duration(seconds: 3)),
                      );
                      _applyAllFilters();
                    } else if (state is ExportShipmentError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.message), backgroundColor: AppTheme.danger, duration: const Duration(seconds: 3)),
                      );
                    }
                    if (state is ExportShipmentListLoaded && state.shipments.isNotEmpty) {
                      _loadItemTotals(state.shipments);
                    }
                  },
                  builder: (context, state) {
                    if (state is ExportShipmentLoading && !(state is ExportShipmentListLoaded)) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                    }
                    if (state is ExportShipmentListLoaded) {
                      if (state.shipments.isEmpty) return _buildEmptyState(isDark);
                      return _buildDataGrid(state.shipments, state.isLoadingMore, isDark);
                    }
                    if (state is ExportShipmentError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                            const SizedBox(height: 12),
                            Text(state.message, style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo')),
                          ],
                        ),
                      );
                    }
                    return _buildEmptyState(isDark);
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(null),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('شحنة جديدة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 20, right: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white.withAlpha(220),
            border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.flight_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('الشحنات التصديرية',
                    style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
              GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(isDark ? 20 : 30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withAlpha(isDark ? 60 : 90)),
                  ),
                  child: const Icon(Icons.filter_list, color: AppTheme.primary, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              _buildIconButton(Icons.refresh_rounded, () {
                _applyAllFilters();
              }, isDark ? AppTheme.textSecondary : const Color(0xFF64748B), isDark),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, Color color, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.transparent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'بحث برقم الشحنة...',
                      hintStyle: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontSize: 13, fontFamily: 'Cairo'),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) {
                      _applyAllFilters();
                    },
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _applyAllFilters();
                    },
                    child: Icon(Icons.clear, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), size: 18),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDateField('من تاريخ', _fromDate, (v) => _fromDate = v, isDark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDateField('إلى تاريخ', _toDate, (v) => _toDate = v, isDark),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _applyAllFilters,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('بحث', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(String label, String? value, Function(String?) onChanged, bool isDark) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          builder: (context, child) => Theme(
            data: isDark
                ? ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary))
                : ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppTheme.primary)),
            child: child!,
          ),
        );
        if (date != null) {
          final formatted = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          onChanged(formatted);
          setState(() {});
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), size: 16),
            const SizedBox(width: 8),
            Text(value ?? label,
                style: TextStyle(
                  color: value != null ? (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)) : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  fontSize: 13,
                  fontWeight: value != null ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'Cairo',
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildDataGrid(List<ExportShipmentModel> shipments, bool isLoadingMore, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth > 850 ? constraints.maxWidth : 850,
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x3805192D) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(10),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                            ),
                            child: Column(
                              children: [
                                _buildTableHeader(isDark),
                                ...shipments.asMap().entries.map((entry) => _buildTableRow(entry.key, entry.value, isDark)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isLoadingMore)
                        const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppTheme.primary)),
                    ],
                  ),
                ),
                if (isLoadingMore && shipments.isEmpty)
                  const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(isDark ? 15 : 20),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('رقم الشحنة', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text('العميل', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('الوجهة', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('اجمالي الفاتورة', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index, ExportShipmentModel shipment, bool isDark) {
    final isLast = index == (context.read<ExportShipmentCubit>().state is ExportShipmentListLoaded
        ? (context.read<ExportShipmentCubit>().state as ExportShipmentListLoaded).shipments.length - 1
        : 0);
    final dateToUse = shipment.shipmentDate ?? shipment.createdAt;
    final dateStr = dateToUse != null
        ? '${dateToUse.year}-${dateToUse.month.toString().padLeft(2, '0')}-${dateToUse.day.toString().padLeft(2, '0')}'
        : '—';
    final textColor = isDark ? AppTheme.textPrimary : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(30) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UIUtils.shipmentNoText(shipment.shipmentNo,
                  style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center),
              if (shipment.status == 'returned_from_airport')
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFEA580C).withAlpha(60)),
                  ),
                  child: const Text('عائدة من المطار', style: TextStyle(fontFamily: 'Cairo', fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                ),
            ],
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text(dateStr,
              style: TextStyle(color: textColor, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(shipment.customerName ?? '—',
              style: TextStyle(color: textColor, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text(shipment.country?.isNotEmpty == true ? shipment.country! : '—',
              style: TextStyle(color: textColor, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(AppUtils.formatNumber(_itemTotals[shipment.id?.toString()] ?? 0),
                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(shipment.currency ?? 'USD',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ],
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!shipment.isConfirmed && shipment.status != 'returned_from_airport' && shipment.status != 'returned') ...[
                _buildRowAction(Icons.check, () => _confirmShipment(shipment), AppTheme.success, tooltip: 'تأكيد الشحنة'),
                const SizedBox(width: 6),
                _buildRowAction(Icons.edit_outlined, () => _openForm(shipment), AppTheme.primary, tooltip: 'تعديل'),
              ] else ...[
                if (!_distributedShipmentIds.contains(shipment.id?.toString() ?? '') && shipment.status != 'returned_from_airport' && shipment.status != 'returned') ...[
                  _buildRowAction(Icons.discount_outlined, () => _editDiscount(shipment), AppTheme.warning, tooltip: 'إضافة خصم'),
                  const SizedBox(width: 6),
                ],
                _buildRowAction(Icons.visibility, () => _viewShipment(shipment), AppTheme.primary, tooltip: 'عرض التفاصيل'),
                const SizedBox(width: 6),
                if (shipment.status != 'returned_from_airport' && shipment.status != 'returned' && shipment.status != 'cancelled') ...[
                  _buildRowAction(Icons.keyboard_return_rounded, () => _openReturnPage(shipment), const Color(0xFFEA580C), tooltip: 'تسجيل رجوع شحنة من المطار'),
                  const SizedBox(width: 6),
                ],
                _buildShipmentJournalDropdown(shipment, isDark),
              ],
            ],
          )),
        ],
      ),
    );
  }

  void _openReturnPage(ExportShipmentModel shipment) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExportShipmentReturnPage(
          shipmentId: shipment.id,
          initialShipment: shipment,
        ),
      ),
    );
    if (result == true) {
      _applyAllFilters();
    }
  }

  Widget _buildStatusChip(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Text(_statusLabel(status),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo'), textAlign: TextAlign.center),
    );
  }

  Widget _buildRowAction(IconData icon, VoidCallback onTap, Color color, {String? tooltip}) {
    final w = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withAlpha(15), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 16),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: w);
    }
    return w;
  }

  Widget _buildShipmentJournalDropdown(ExportShipmentModel shipment, bool isDark) {
    return PopupMenuButton<String>(
      onSelected: (entryNumber) {
        JournalEntryNavigationService.openById(context, journalEntryId: entryNumber);
      },
      offset: const Offset(0, 30),
      constraints: const BoxConstraints(minWidth: 290, maxWidth: 360),
      color: isDark ? AppTheme.surface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _shipmentDao.getJournalEntriesForShipment(shipment.id ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return Text('لا توجد قيود محاسبية',
                    style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontSize: 12, fontFamily: 'Cairo'));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('القيود المحاسبية (${entries.length})',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  ...entries.map((je) {
                    final entryNum = je['entry_number']?.toString() ?? '';
                    final date = je['entry_date']?.toString() ?? '';
                    final debit = (je['total_debit'] as num?)?.toDouble() ?? 0;
                    final cur = je['currency']?.toString() ?? 'EGP';
                    final srcType = je['source_type']?.toString() ?? '';
                    final cat = je['category']?.toString() ?? '';
                    final isReturn = je['is_return_entry'] == true ||
                        srcType == 'export_return' ||
                        srcType == 'export_shipment_return' ||
                        cat == 'return';

                    String typeLabel;
                    IconData iconData;
                    Color iconColor;

                    if (isReturn) {
                      typeLabel = 'قيد إلغاء / مرتجع الشحنة';
                      iconData = Icons.assignment_return_outlined;
                      iconColor = const Color(0xFFEA580C);
                    } else {
                      switch (srcType) {
                        case 'export_shipment':
                          typeLabel = 'قيد البيع';
                          iconData = Icons.receipt_long_outlined;
                          iconColor = AppTheme.cyan;
                          break;
                        case 'export_discount':
                          typeLabel = 'قيد الخصم';
                          iconData = Icons.discount_outlined;
                          iconColor = AppTheme.warning;
                          break;
                        case 'customer_treasury_deposit':
                        case 'bank_deposit':
                        case 'customer_bank_deposit':
                        case 'export_payment':
                          typeLabel = 'قيد السداد';
                          iconData = Icons.payment_outlined;
                          iconColor = AppTheme.success;
                          break;
                        case 'customer_treasury_withdrawal':
                          typeLabel = 'قيـد اسـترداد السـداد';
                          iconData = Icons.replay_outlined;
                          iconColor = AppTheme.danger;
                          break;
                        case 'packing_order':
                          typeLabel = 'قيد أمر التعبئة';
                          iconData = Icons.inventory_2_outlined;
                          iconColor = AppTheme.primary;
                          break;
                        case 'packing_debit_note':
                          typeLabel = 'خصم مورد تعبئة';
                          iconData = Icons.money_off_outlined;
                          iconColor = AppTheme.warning;
                          break;
                        case 'shipment_cost_accrual':
                          typeLabel = 'استحقاق تكلفة شحنة';
                          iconData = Icons.pending_actions_outlined;
                          iconColor = const Color(0xFF8B5CF6);
                          break;
                        case 'shipment_cost_paid':
                          typeLabel = 'سداد تكلفة شحنة';
                          iconData = Icons.paid_outlined;
                          iconColor = AppTheme.success;
                          break;
                        default:
                          typeLabel = je['category_label']?.toString() ?? srcType;
                          iconData = Icons.article_outlined;
                          iconColor = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
                      }
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        JournalEntryNavigationService.openById(context, journalEntryId: entryNum);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isReturn ? const Color(0xFFEA580C).withAlpha(15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(30) : const Color(0xFFE2E8F0))),
                        ),
                        child: Row(children: [
                          Icon(iconData, size: 14, color: iconColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('قيد #$entryNum — $typeLabel',
                                          style: TextStyle(
                                            color: isReturn ? const Color(0xFFEA580C) : (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          )),
                                    ),
                                    if (isReturn)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEA580C).withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('مرتجع', style: TextStyle(color: Color(0xFFEA580C), fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('$date — ${debit.toStringAsFixed(2)} $cur',
                                    style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF64748B), fontSize: 10, fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, size: 12, color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                        ]),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.receipt_long, color: AppTheme.accent, size: 16),
      ),
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
              color: isDark ? AppTheme.primary.withAlpha(15) : AppTheme.primary.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flight_outlined, size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text('لا توجد شحنات',
              style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط على "شحنة جديدة" لإنشاء أول شحنة',
              style: TextStyle(color: isDark ? AppTheme.textSecondary.withAlpha(180) : const Color(0xFF64748B), fontSize: 14, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _confirmShipment(ExportShipmentModel shipment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: isDark ? AppTheme.surface : Colors.white,
          title: Text('تأكيد الشحنة', style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: Text('هل أنت متأكد من تأكيد الشحنة رقم ${shipment.shipmentNo}؟ لن يمكنك تعديل تفاصيلها بعد التأكيد وسيتم ترحيل قيودها المالية.',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<ExportShipmentCubit>().confirmShipment(shipment);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _editDiscount(ExportShipmentModel shipment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sid = shipment.id?.toString() ?? '';
    if (_distributedShipmentIds.contains(sid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل الخصم'), backgroundColor: AppTheme.danger),
      );
      return;
    }
    final amountController = TextEditingController(text: shipment.discountAmount.toString());
    final reasonController = TextEditingController(text: shipment.discountReason ?? '');
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: isDark ? AppTheme.surface : Colors.white,
          title: Text('تعديل الخصم', style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'مبلغ الخصم',
                  labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo'),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                Navigator.pop(ctx);
                context.read<ExportShipmentCubit>().updateDiscount(shipment.id, amount, reasonController.text);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('حفظ', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _printInvoice(ExportShipmentModel shipment) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء الفاتورة...'), backgroundColor: AppTheme.primary, duration: Duration(seconds: 2)),
    );
    try {
      final breakdownDao = ShipmentCostBreakdownDao();
      final itemsDao = ExportShipmentItemDao();
      
      final results = await Future.wait([
        breakdownDao.getForShipment(shipment.id.toString()),
        itemsDao.getByShipmentId(int.parse(shipment.id!)),
      ]);
      
      if (!mounted) return;
      
      await ShipmentInvoicePdfService.savePdf(
        context: context,
        shipment: shipment,
        breakdown: results[0] as List<ShipmentCostBreakdownModel>,
        itemsData: results[1] as List<Map<String, dynamic>>,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _printCreditNote(ExportShipmentModel shipment) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء الإشعار...'), backgroundColor: AppTheme.primary, duration: Duration(seconds: 2)),
    );
    try {
      await CreditNotePdfService.savePdf(
        context: context,
        shipment: shipment,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _viewShipment(ExportShipmentModel shipment) async {
    final result = await context.push<bool>('/exports/edit', extra: {'shipment': shipment, 'isReadOnly': true});
    if (result == true && mounted) {
      _applyAllFilters();
    }
  }

  void _openForm(ExportShipmentModel? shipment) async {
    if (shipment != null) {
      final result = await context.push<bool>('/exports/edit', extra: {'shipment': shipment, 'isReadOnly': false});
      if (result == true && mounted) {
        _applyAllFilters();
      }
    } else {
      final result = await context.push<bool>('/exports/new', extra: {'isReadOnly': false});
      if (result == true && mounted) {
        _applyAllFilters();
      }
    }
  }

  void _openDetail(ExportShipmentModel shipment) {
    context.read<ExportShipmentCubit>().loadDetail(shipment.id!);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<ExportShipmentCubit>(),
        child: const ExportShipmentDetailPage(),
      ),
    ).then((_) {
      _applyAllFilters();
    });
  }

  void _applyAllFilters() {
    context.read<ExportShipmentCubit>().load(
          search:
              _searchController.text.isNotEmpty ? _searchController.text : null,
          status: _statusFilter,
          fromDate: _fromDate,
          toDate: _toDate,
          excludeStatus:
              _statusFilter == null && !_showAllIncludingCancelled ? 'cancelled' : null,
        );
  }

  void _exportExcel() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف Excel...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      final dao = ExportShipmentDao();
      final itemDao = ExportShipmentItemDao();
      final allShipments = await dao.getAll(
        searchQuery:
            _searchController.text.isNotEmpty ? _searchController.text : null,
        status: _statusFilter,
        fromDate: _fromDate,
        toDate: _toDate,
        excludeStatus:
            _statusFilter == null && !_showAllIncludingCancelled ? 'cancelled' : null,
        limit: 10000,
      );
      if (allShipments.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد شحنات للتصدير'),
              backgroundColor: AppTheme.warning),
        );
        return;
      }

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['الشحنات التصديرية'];

      const headerBg = '#FF1A237E';
      const headerFg = '#FFFFFFFF';
      const totalBg = '#FF263238';
      const totalFg = '#FFFFFFFF';

      final headers = [
        'التاريخ',
        'رقم الشحنة',
        'العميل',
        'كود العميل',
        'الوجهة',
        'رقم الحاوية',
        'البوليصة',
        'المحصول',
        'الكراتين',
        'الوزن الصافي',
        'الوزن الصافي/كرتونة',
        'السعر/كرتونة',
        'الاجمالي',
      ];

      for (var c = 0; c < headers.length; c++) {
        final cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString(headerBg),
          fontColorHex: ExcelColor.fromHexString(headerFg),
          fontSize: 11,
        );
      }

      var r = 1;

      for (final shipment in allShipments) {
        final items = await itemDao.getByShipmentId(shipment.id);
        final dateToUse = shipment.shipmentDate ?? shipment.createdAt;
        final dateStr = dateToUse != null
            ? '${dateToUse.year}-${dateToUse.month.toString().padLeft(2, '0')}-${dateToUse.day.toString().padLeft(2, '0')}'
            : '';
        final blOrAwb = shipment.transportMode == 'air'
            ? (shipment.dataLoggerNo ?? '')
            : (shipment.blNumber ?? '');

        if (items.isEmpty) {
          _setExcelRow(sheet, r, [
            dateStr,
            shipment.shipmentNo,
            shipment.customerName ?? '',
            shipment.customerCode ?? '',
            shipment.country ?? '',
            shipment.containerNo ?? '',
            blOrAwb,
            '',
            '',
            '',
            '',
            '',
            '',
          ]);
          r++;
          continue;
        }

        for (final item in items) {
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final netWt = (item['net_weight'] as num?)?.toDouble() ?? 0;
          final pricePerCtn =
              (item['export_price_per_carton'] as num?)?.toDouble() ?? 0;
          final amount = (item['amount'] as num?)?.toDouble() ?? 0;
          final productName = item['product_name']?.toString() ?? '';
          final netPerCtn = qty > 0 ? (netWt / qty) : 0.0;

          _setExcelRow(sheet, r, [
            dateStr,
            shipment.shipmentNo,
            shipment.customerName ?? '',
            shipment.customerCode ?? '',
            shipment.country ?? '',
            shipment.containerNo ?? '',
            blOrAwb,
            productName,
            qty.toStringAsFixed(0),
            netWt.toStringAsFixed(2),
            netPerCtn.toStringAsFixed(2),
            '${pricePerCtn.toStringAsFixed(2)} ${shipment.currency ?? ''}',
            '${amount.toStringAsFixed(2)} ${shipment.currency ?? ''}',
          ]);
          r++;
        }
      }

      for (var c = 0; c < headers.length; c++) {
        sheet.setColumnWidth(c, 18);
      }
      sheet.setColumnWidth(1, 14);
      sheet.setColumnWidth(7, 25);

      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل إنشاء الملف');
      final dir = await FileHelper.getExportDirectory();
      final file = File(
          '${dir.path}/export_shipments_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم التصدير: ${file.path}'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _setExcelRow(Sheet sheet, int row, List<String> values) {
    for (var c = 0; c < values.length; c++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = TextCellValue(values[c]);
      cell.cellStyle = CellStyle(fontSize: 10);
    }
  }

  void _exportPdfAll() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('جاري إنشاء ملف PDF...'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2)),
    );
    try {
      final dao = ExportShipmentDao();
      final allShipments = await dao.getAll(
        searchQuery:
            _searchController.text.isNotEmpty ? _searchController.text : null,
        status: _statusFilter,
        fromDate: _fromDate,
        toDate: _toDate,
        excludeStatus:
            _statusFilter == null && !_showAllIncludingCancelled ? 'cancelled' : null,
        limit: 10000,
      );
      if (allShipments.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد شحنات للتصدير'),
              backgroundColor: AppTheme.warning),
        );
        return;
      }
      // Use the detail page's PDF for each shipment
      for (final s in allShipments) {
        _openDetail(s);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

}
