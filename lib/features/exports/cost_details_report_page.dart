import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:collection/collection.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../core/theme.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/cost_report_dao.dart';
import '../../data/models/cost_center.dart';
import 'cost_center_details_pdf_service.dart';
import 'widgets/season_rollover_dialog.dart';
import '../../ui/widgets/enhanced_summary_bar.dart';
import '../../data/dao/packing_order_dao.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CostDetailsReportPage extends StatefulWidget {
  final String? category;
  final String? categoryLabel;
  final int? shipmentId;
  final String? itemName;
  final String? majorCategory;
  final String? costCenter;
  final String? costCenterLabel;

  const CostDetailsReportPage({
    super.key,
    this.category,
    this.categoryLabel,
    this.shipmentId,
    this.itemName,
    this.majorCategory,
    this.costCenter,
    this.costCenterLabel,
  });

  @override
  State<CostDetailsReportPage> createState() => _CostDetailsReportPageState();
}

enum CostDetailsPartition {
  active,      // العمليات الجارية (الموسم الحالي)
  historical,  // السجل التاريخي المقفل
  all,         // كافة الفترات
}

class _CostDetailsReportPageState extends State<CostDetailsReportPage> {
  final _dao = CostReportDao();
  bool _loading = true;
  bool _exportLoading = false;
  List<Map<String, dynamic>> _rows = [];
  List<CostCenter> _activeCostCenters = [];
  List<CostCenter> _allCostCenters = [];
  String? _category;
  String? _selectedCostCenter;

  // ── Partition Filter (Active vs Historical Closed) ──
  CostDetailsPartition _selectedPartition = CostDetailsPartition.active;

  // ── Multi-Currency Filter ──
  String? _selectedCurrency; // null = All Currencies
  Set<String> _availableCurrencies = {};

  // ── Grouped View Toggle ──
  bool _isGroupedView = true;

  // ── Pagination State ──
  int _currentPage = 1;
  int _rowsPerPage = 25;

  // ── Cost Settlement & Variance Comparison State ──
  bool _settlementMode = false;
  bool get _isBranchVarianceView => widget.majorCategory != null || _settlementMode;
  final TextEditingController _overallActualCtrl = TextEditingController();
  final Map<dynamic, TextEditingController> _itemActualCtrls = {};
  final Map<dynamic, TextEditingController> _itemNotesCtrls = {};
  final Set<dynamic> _modifiedItemKeys = {};
  bool _isSavingSettlement = false;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  final List<StreamSubscription> _subscriptions = [];

  String _catLabel(String cat) {
    switch (cat) {
      case 'engineer_expenses':
      case 'ENGINEER_EXPENSES':
      case 'مصاريف المهندسين':
        return 'مصاريف المهندسين';
      case 'freight':
      case 'shipping_company':
      case 'shipping':
        return 'تكلفة شركات الشحن';
      case 'clearance':
      case 'clearing_agent':
      case 'clearing':
        return 'تكلفة المخلصين';
      case 'crop':
      case 'fruit':
      case 'manual_crop':
        return 'تكلفة المحاصيل';
      case 'packing_material':
        return 'مواد التعبئة';
      case 'packing':
      case 'PACKAGING':
      case 'manual_packing':
        return 'تعبئة وتغليف';
      case 'waste':
      case 'waste_cost':
      case 'crop_waste':
      case 'material_waste':
      case 'packing_waste':
      case 'packing_material_waste':
      case 'packing_crop_waste':
      case 'تكلفة الهالك':
        return 'تكلفة الهالك';
      case 'sorting':
      case 'sorting_sale':
      case 'تكلفة الفرز':
        return 'مبيعات وتكلفة الفرز';
      case 'إيرادات المبيعات':
      case 'مبيعات التصدير':
      case 'export_sales':
      case 'sales':
        return 'إيرادات المبيعات';
      case '34114 - لوجستيك ونقل':
      case 'لوجستيك ونقل':
      case 'logistics':
      case 'TRANSPORT':
        return 'لوجستيك ونقل';
      case '31331 - مصاريف إدارية وعمومية':
      case 'admin':
      case 'ADMIN':
        return 'مصاريف إدارية وعمومية';
      case 'export_cost':
        return 'تكاليف تصدير';
      case 'LABOR':
        return 'عمالة';
      case 'DIESEL':
        return 'ديزل';
      case 'AGRICULTURE':
        return 'أجرة زراعية';
      case 'COOLING':
        return 'تبريد';
      case 'LABELS':
        return 'ليبل';
      case 'STICKERS':
        return 'استيكر';
      case 'OTHER':
      case 'other':
      case 'مصاريف تشغيلية أخرى':
        return 'مصاريف تشغيلية أخرى';
      default:
        return cat;
    }
  }

  /// Resolves an expressive, informative description for the movement in the "البيان" column.
  String _resolveMovementTitle(Map<String, dynamic> r) {
    final rawItem = (r['item_name']?.toString() ?? '').trim();
    final desc = (r['description']?.toString() ?? '').trim();
    final notes = (r['notes']?.toString() ?? '').trim();
    final cat = (r['category']?.toString() ?? '').trim();
    final sType = r['source_type']?.toString() ?? '';
    final sId = r['source_id']?.toString() ?? '';

    // Handle season rollover and period 1 to 2 rollovers with precision
    final isIntraRollover = RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId);
    final isRollover = sType == 'season_rollover' ||
        r['is_rollover'] == true ||
        sId.startsWith('rollover_');
    if (isRollover || isIntraRollover) {
      if (isIntraRollover ||
          rawItem.contains('الفترة الأولى') ||
          notes.contains('الفترة الأولى') ||
          cat.contains('الفترة الأولى')) {
        return 'رصيد مرحل من الفترة الأولى';
      }
      return 'رصيد مرحل من موسم سابق';
    }

    final lowerItem = rawItem.toLowerCase();
    final isGenericSlug = lowerItem == 'other' ||
        lowerItem == 'logistics' ||
        lowerItem == 'transport' ||
        lowerItem == 'crop' ||
        lowerItem == 'fruit' ||
        lowerItem == 'material' ||
        lowerItem == 'packing_material' ||
        lowerItem == 'packing';

    if (rawItem.isNotEmpty && !isGenericSlug) {
      return rawItem;
    }

    if (desc.isNotEmpty && !desc.toLowerCase().startsWith('other')) {
      return desc;
    }

    if (notes.isNotEmpty && !notes.startsWith('{') && !notes.startsWith('null')) {
      return notes;
    }

    if (cat.isNotEmpty && cat.toLowerCase() != 'other' && cat.toLowerCase() != 'logistics') {
      return _catLabel(cat);
    }

    if (rawItem.isNotEmpty) {
      return _catLabel(rawItem);
    }

    if (sType == 'export_shipment' || sType == 'export_sale' || r['is_export_sale'] == true) {
      if (rawItem.isNotEmpty && !isGenericSlug) return rawItem;
      return 'مبيعات تصدير';
    }
    if (sType == 'purchase' || r['is_purchase'] == true) return 'مشتريات مواد تعبئة';
    if (sType == 'packing_material' || r['is_packing_material'] == true) return rawItem.isNotEmpty ? rawItem : 'استهلاك مادة تعبئة';
    if (sType == 'packing_material_waste' || sType == 'packing_crop_waste' || sType == 'packing_waste' || r['is_packing_waste'] == true) return rawItem.isNotEmpty ? rawItem : 'تكلفة الهالك';
    if (sType == 'lot_receipt' || r['is_lot_receipt'] == true) return 'استلام محصول خام';
    if (sType == 'lot_return' || r['is_lot_return'] == true) return 'مرتجع محصول خام';
    if (sType == 'sorting_sale' || r['is_sorting_sale'] == true) return 'مبيعات فرزة';
    if (r['is_opening_balance'] == true) return 'رصيد أول المدة';
    if (r['is_packing_order_cost_item'] == true) return 'تسوية مصروف أمر تعبئة';

    return 'حركة مركز تكلفة';
  }

  Color _resolveCustomerSupplierColor(Map<String, dynamic> r, bool isDark) {
    if (r['is_opening_balance'] == true || r['source_type'] == 'opening_balance') {
      return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }
    if (r['is_sorting_sale'] == true) {
      return const Color(0xFF10B981);
    }
    if (r['is_export_sale'] == true) {
      return const Color(0xFF0284C7);
    }
    return isDark ? Colors.white : const Color(0xFF0F172A);
  }

  Color _resolveAmountColor(Map<String, dynamic> r) {
    final amt = r['amount'] as num?;
    if (amt != null && amt < 0) return const Color(0xFFEF4444);
    if (r['is_sorting_sale'] == true || r['is_export_sale'] == true) return const Color(0xFF10B981);
    if (r['is_rollover'] == true) return const Color(0xFFF59E0B);
    return AppTheme.primary;
  }

  String _resolveCustomerSupplier(Map<String, dynamic> r) {
    final cust = (r['customer_name']?.toString() ?? '').trim();
    final supp = (r['supplier_name']?.toString() ?? '').trim();
    final sType = r['source_type']?.toString() ?? '';
    final sId = r['source_id']?.toString() ?? '';
    final rawItem = (r['item_name']?.toString() ?? '').trim();
    final notes = (r['notes']?.toString() ?? '').trim();

    final isIntraRollover = RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId);
    final isRollover = sType == 'season_rollover' ||
        r['is_rollover'] == true ||
        sId.startsWith('rollover_');

    if (isRollover || isIntraRollover) {
      if (isIntraRollover ||
          rawItem.contains('الفترة الأولى') ||
          notes.contains('الفترة الأولى') ||
          supp.contains('الفترة الأولى')) {
        return 'رصيد مرحل من الفترة الأولى';
      }
      if (supp.isNotEmpty && supp != 'null') return supp;
      return 'رصيد افتتاحي للموسم الجديد';
    }

    if (cust.isNotEmpty && cust != 'null') return cust;
    if (supp.isNotEmpty && supp != 'null') return supp;
    if (r['is_packing_material'] == true) return 'محطة التعبئة والتجهيز';
    if (r['is_packing_operational'] == true || r['is_packing_order_cost_item'] == true) {
      return 'مصاريف تشغيل داخلية';
    }
    return '-';
  }

  String _resolveFullExportDescription(Map<String, dynamic> r, {bool isEnglish = false}) {
    final title = _resolveMovementTitle(r);
    final invoiceRef = (r['invoice_ref']?.toString() ?? '').trim();
    final settlementNotes = (r['settlement_notes']?.toString() ?? '').trim();
    final costStatus = (r['cost_status']?.toString() ?? '').toLowerCase().trim();
    final isSettled = costStatus == 'actual' || costStatus == 'settled' || r['is_settled'] == 1 || r['is_settled'] == true;

    String res = isEnglish ? _translateItemName(title, true) : title;
    if (invoiceRef.isNotEmpty && invoiceRef != 'null') {
      res += isEnglish ? ' (Ref #$invoiceRef)' : ' (مستند #$invoiceRef)';
    }
    if (isSettled) {
      res += isEnglish ? ' [Settled]' : ' [تسوية فعلية]';
    }
    if (settlementNotes.isNotEmpty && settlementNotes != 'null') {
      res += ' - $settlementNotes';
    }
    return res;
  }

  Widget _buildDescriptionCell(Map<String, dynamic> r, bool isDark) {
    final title = _resolveMovementTitle(r);
    final notes = (r['notes']?.toString() ?? '').trim();
    final settlementNotes = (r['settlement_notes']?.toString() ?? '').trim();
    final invoiceRef = (r['invoice_ref']?.toString() ?? '').trim();
    final costStatus = (r['cost_status']?.toString() ?? '').toLowerCase().trim();
    final isPackingCostItem = r['is_packing_order_cost_item'] == true;
    final isSettled = costStatus == 'actual' || costStatus == 'settled' || r['is_settled'] == 1 || r['is_settled'] == true;
    final isPending = costStatus == 'expected' || costStatus == 'estimated' || costStatus == 'pending';

    final List<Widget> metaWidgets = [];

    // 1. Settlement Status Badge
    if (isPackingCostItem || isSettled || isPending) {
      if (isSettled) {
        metaWidgets.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF10B981)),
              SizedBox(width: 3),
              Text(
                'تسوية فعلية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ));
      } else if (isPending) {
        metaWidgets.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pending_actions_rounded, size: 10, color: Color(0xFFF59E0B)),
              SizedBox(width: 3),
              Text(
                'تكلفة تقديرية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ));
      }
    }

    // 2. Invoice / Document Reference Tag
    if (invoiceRef.isNotEmpty && invoiceRef != 'null') {
      metaWidgets.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_rounded, size: 10, color: Color(0xFF0284C7)),
            const SizedBox(width: 3),
            Text(
              'مستند #$invoiceRef',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0284C7),
              ),
            ),
          ],
        ),
      ));
    }

    // 3. Notes or Settlement Notes
    String? extraNote;
    if (settlementNotes.isNotEmpty && settlementNotes != 'null') {
      extraNote = settlementNotes;
    } else if (notes.isNotEmpty && !notes.startsWith('{') && !notes.startsWith('null') && notes != title) {
      extraNote = notes;
    }

    if (extraNote != null && extraNote.isNotEmpty) {
      metaWidgets.add(
        Tooltip(
          message: extraNote,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              extraNote,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (metaWidgets.isNotEmpty) ...[
          const SizedBox(height: 3),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: metaWidgets,
          ),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _selectedCostCenter = widget.costCenter;
    _load();

    _subscriptions.add(DataChangeEventBus.instance.costCentersStream.listen((_) {
      if (mounted) _load();
    }));
    _subscriptions.add(DataChangeEventBus.instance.cropPurchasesStream.listen((_) {
      if (mounted) _load();
    }));
    _subscriptions.add(DataChangeEventBus.instance.purchasesStream.listen((_) {
      if (mounted) _load();
    }));
    _subscriptions.add(DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      if (mounted) _load();
    }));
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _searchCtrl.dispose();
    _overallActualCtrl.dispose();
    for (final c in _itemActualCtrls.values) {
      c.dispose();
    }
    for (final c in _itemNotesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _getMajorCategory(Map<String, dynamic> row) {
    final name = (row['item_name'] as String? ?? '').trim();
    final cat = (row['category'] as String? ?? '').trim();
    final code = (row['account_code'] ?? row['code'] ?? row['category_code'] ?? '').toString().trim();
    final accName = (row['account_name'] ?? '').toString().trim();

    return CostReportDao.resolveExpenseBranchName(
      category: cat,
      itemName: name,
      accountCode: code.isNotEmpty ? code : null,
      accountName: accName.isNotEmpty ? accName : null,
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _fromCtrl.text.isNotEmpty ? _fromCtrl.text : null;
      final to = _toCtrl.text.isNotEmpty ? _toCtrl.text : null;

      final results = await Future.wait([
        _dao.getActiveCostCenters(),
        _dao.getAllCostCenters(),
      ]);
      final activeCenters = results[0];
      final allCenters = results[1];

      final costCenterLabelToPass = _selectedCostCenter != null
          ? (_selectedCostCenter == widget.costCenter ? widget.costCenterLabel : null) ??
              CostCenterHelper.fromId(_selectedCostCenter, allCenters).nameAr
          : widget.costCenterLabel;

      final data = await _dao.getDetails(
        category: _category,
        shipmentId: widget.shipmentId,
        itemName: widget.itemName,
        fromDate: from,
        toDate: to,
        costCenter: _selectedCostCenter,
        costCenterLabel: costCenterLabelToPass,
        activeCenters: activeCenters,
        allCenters: allCenters,
      );

      if (mounted) {
        // Extract available currencies from data
        final currencies = <String>{};
        for (final r in data) {
          final c = r['currency']?.toString().toUpperCase();
          if (c != null && c.isNotEmpty) currencies.add(c);
        }
        // Ensure EGP is always available
        currencies.add('EGP');

        setState(() {
          if (widget.majorCategory != null) {
            final target = widget.majorCategory!;
            final targetCode = CostReportDao.branchToCategoryCode(target);
            _rows = data.where((r) {
              final cat = _getMajorCategory(r);
              if (cat == target) return true;
              final catCode = CostReportDao.branchToCategoryCode(cat);
              if (targetCode.isNotEmpty && catCode.isNotEmpty && targetCode == catCode) {
                return true;
              }
              final rCode = (r['account_code'] ?? r['code'] ?? r['category_code'] ?? '').toString();
              if (targetCode.isNotEmpty && rCode.isNotEmpty && targetCode == rCode) {
                return true;
              }
              if ((target.contains('مهندس') || target.contains('31251')) &&
                  (cat.contains('مهندس') || cat.contains('31251'))) {
                return true;
              }
              return false;
            }).toList();
          } else {
            _rows = data;
          }
          _activeCostCenters = activeCenters;
          _allCostCenters = allCenters;
          _availableCurrencies = currencies;

          // If the selected/current cost center is closed, default to historical partition ONLY if user is still on the initial active view
          final pool = allCenters.isNotEmpty ? allCenters : activeCenters;
          final current = _selectedCostCenter != null
              ? CostCenterHelper.fromId(_selectedCostCenter, pool)
              : (widget.costCenter != null ? CostCenterHelper.fromId(widget.costCenter, pool) : null);
          if (current != null && current.isClosed && _selectedPartition == CostDetailsPartition.active) {
            _selectedPartition = CostDetailsPartition.historical;
          }

          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPartitionChanged(CostDetailsPartition newPartition) {
    if (_selectedPartition == newPartition) return;
    setState(() {
      _selectedPartition = newPartition;
      _currentPage = 1;
    });
  }

  bool _isRolloverRow(Map<String, dynamic> r) {
    final sType = r['source_type']?.toString() ?? '';
    final sId = r['source_id']?.toString() ?? '';
    final itemName = r['item_name']?.toString() ?? '';
    final notes = r['notes']?.toString() ?? '';
    final cat = r['category']?.toString() ?? '';
    return sType == 'season_rollover' ||
        r['is_rollover'] == true ||
        sId.startsWith('rollover_') ||
        itemName.contains('رصيد مرحل') ||
        itemName.contains('رصيد افتتاحي مرحل') ||
        cat.contains('رصيد مرحل') ||
        cat.contains('رصيد افتتاحي منقول') ||
        notes.contains('ترحيل محاسبي');
  }

  bool _isRowClosed(Map<String, dynamic> r) {
    final ccId = (r['cost_center_id']?.toString() ?? '').trim();
    final ccName = (r['cost_center_name']?.toString() ?? '').trim();
    final sId = (r['source_id']?.toString() ?? '').trim();

    // 1. Match against cost centers
    final matchingCenter = _allCostCenters.firstWhereOrNull((c) =>
        (ccId.isNotEmpty &&
            (c.id == ccId ||
             c.code == ccId ||
             (c.dbId != null && c.dbId.toString() == ccId))) ||
        (ccId.isEmpty && (c.nameAr == ccName || c.nameEn == ccName)));

    // 2. If the center itself is permanently closed or closed (e.g. 2026-2027),
    // ALL rows belonging to this card belong strictly to historical!
    if (matchingCenter != null && (matchingCenter.isClosed || matchingCenter.isPermanentlyClosed)) {
      return true;
    }

    // 3. Explicit closed tags
    if (r['is_closed'] == true ||
        r['is_closed'] == 1 ||
        r['is_closed'] == 'true' ||
        r['season_status'] == 'closed' ||
        r['season_status'] == 'permanently_closed') {
      return true;
    }

    // 4. Intra-card lifecycle: If the cost center is currently in Period 2 (closureCount >= 1 or seasonNumber >= 2):
    // Find the latest intra-card rollover transaction that transitioned Period 1 into Period 2 (e.g. rollover_2_to_2)
    if (matchingCenter != null && (matchingCenter.closureCount >= 1 || matchingCenter.seasonNumber >= 2)) {
      final intraRollover = _rows.firstWhereOrNull((row) {
        final rowCc = (row['cost_center_id']?.toString() ?? '').trim();
        final rowSid = (row['source_id']?.toString() ?? '').trim();
        final matchesCc = rowCc.isEmpty || rowCc == ccId || rowCc == matchingCenter.id || rowCc == matchingCenter.code;
        return matchesCc &&
            row['source_type'] == 'season_rollover' &&
            RegExp(r'^rollover_(\d+)_to_\1').hasMatch(rowSid);
      });

      if (intraRollover != null) {
        final intraSid = (intraRollover['source_id']?.toString() ?? '').trim();
        // The intra-card rollover transaction itself IS the active opening baseline of Period 2!
        if (sId == intraSid) {
          return false;
        }

        // Any transaction created or dated strictly before the intra-card rollover belongs to closed Period 1!
        final rolloverTimeStr = intraRollover['created_at']?.toString() ??
            intraRollover['date']?.toString() ??
            intraRollover['shipment_date']?.toString();
        final rTimeStr = r['created_at']?.toString() ??
            r['date']?.toString() ??
            r['shipment_date']?.toString();

        if (rolloverTimeStr != null && rTimeStr != null) {
          final rolloverTime = DateTime.tryParse(rolloverTimeStr);
          final rTime = DateTime.tryParse(rTimeStr);
          if (rolloverTime != null && rTime != null) {
            if (rTime.isBefore(rolloverTime)) {
              return true; // Historical Period 1!
            }
            return false; // Active Period 2!
          }
        }

        // If timestamps are identical or unavailable, any prior inter-season rollovers (e.g. rollover_1_to_2)
        // are superseded by the intra-season rollover and belong to Period 1 (historical).
        if (_isRolloverRow(r) && !RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId)) {
          return true; // Superseded by intra-rollover -> Historical Period 1!
        }
      }
    }

    // 5. Active opening baseline: Initial rollover into an active period
    if (_isRolloverRow(r)) {
      return false;
    }

    return false;
  }

  List<Map<String, dynamic>> get _costCenterScopedRows {
    var rows = _rows;

    // ── Multi-Currency Filter ──
    if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
      final targetCur = _selectedCurrency!.toUpperCase();
      rows = rows.where((r) {
        final cur = (r['currency']?.toString() ?? 'EGP').toUpperCase();
        return cur == targetCur;
      }).toList();
    }

    // ── Strict Cost Center Scoping ──
    if (_selectedCostCenter != null &&
        _selectedCostCenter!.isNotEmpty &&
        _selectedCostCenter != 'all') {
      final pool = _allCostCenters.isNotEmpty ? _allCostCenters : _activeCostCenters;
      final target = CostCenterHelper.fromId(_selectedCostCenter, pool);
      final normTarget = CostCenterHelper.normalizeArabic(target.nameAr);
      final targetId = target.id;
      final targetCode = target.code;
      final targetProdId = target.productId?.toString();
      final targetDbId = target.dbId?.toString();
      final normLabel = widget.costCenterLabel != null
          ? CostCenterHelper.normalizeArabic(widget.costCenterLabel!)
          : '';

      final targetCanonCrop = CostCenter.canonicalCropName(target.nameAr);
      final targetCropSlug = target.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);
      final targetSeason = target.season ?? CostReportDao.extractSeason(targetCode) ?? CostReportDao.extractSeason(target.nameAr);

      rows = rows.where((r) {
        final id = r['cost_center_id']?.toString();
        final name = CostCenterHelper.normalizeArabic(r['cost_center_name']?.toString() ?? '');
        final targetProd = CostCenterHelper.normalizeArabic(r['target_product_name']?.toString() ?? '');
        final prodId = r['product_id']?.toString();

        // STRICT YEAR/SEASON & CLOSED CENTER ISOLATION:
        // Completely exclude transactions that specify a different agricultural year/season or belong to closed centers
        final rowCenter = id != null ? CostCenterHelper.fromId(id, pool) : null;
        if (rowCenter != null) {
          final rowCenterSeason = rowCenter.season ?? CostReportDao.extractSeason(rowCenter.code) ?? CostReportDao.extractSeason(rowCenter.nameAr);
          if (targetSeason != null && targetSeason.isNotEmpty && rowCenterSeason != null && rowCenterSeason.isNotEmpty && rowCenterSeason != targetSeason) {
            return false;
          }
          if (target.isActive && !target.isClosed && (rowCenter.isClosed || rowCenter.isPermanentlyClosed)) {
            final sId = r['source_id']?.toString() ?? '';
            final isRolloverIntoTarget = sId.contains('_to_${target.dbId}') ||
                sId.contains('_to_${target.code}') ||
                sId.contains('_to_${target.id}');
            if (!isRolloverIntoTarget) {
              return false;
            }
          }
        }

        if (targetSeason != null && targetSeason.isNotEmpty) {
          final rowSeason = CostReportDao.extractSeason(id) ??
              CostReportDao.extractSeason(r['cost_center_name']?.toString()) ??
              CostReportDao.extractSeason(r['season']?.toString()) ??
              CostReportDao.extractSeason(r['item_name']?.toString());
          if (rowSeason != null && rowSeason.isNotEmpty && rowSeason != targetSeason) {
            return false;
          }
        }

        final matchesTarget = (id != null &&
                (id == targetId ||
                    id == _selectedCostCenter ||
                    (targetCode != null && id == targetCode) ||
                    (targetDbId != null && id == targetDbId))) ||
            (targetProdId != null && (id == targetProdId || prodId == targetProdId)) ||
            (name == normTarget || targetProd == normTarget) ||
            (normLabel.isNotEmpty && (name == normLabel || targetProd == normLabel));

        if (matchesTarget) {
          return true;
        }

        if (r['is_equal_distribution'] == true) {
          final List<dynamic> prods = r['order_products'] as List<dynamic>? ?? [];
          return prods.any((p) {
            final np = CostCenterHelper.normalizeArabic(p.toString());
            return np == normTarget ||
                np.contains(normTarget) ||
                normTarget.contains(np) ||
                (targetCropSlug != 'CROP' && CostCenterHelper.resolveCropSlug(p.toString()) == targetCropSlug);
          });
        }

        return false;
      }).toList();
    }

    // ── Deduplication & Negative Remainder Guard ──
    // 1. If variety-level season_rollover rows exist for a cost center,
    //    exclude any generic cc_ob_ row to prevent double-counting.
    final centersWithVarietyRollovers = <String>{};
    for (final r in rows) {
      final sType = r['source_type']?.toString() ?? '';
      final sId = r['source_id']?.toString() ?? '';
      final ccId = r['cost_center_id']?.toString() ?? '';
      if (sType == 'season_rollover' && !sId.endsWith('_remainder') && !RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId)) {
        centersWithVarietyRollovers.add(ccId);
      }
    }

    rows = rows.where((r) {
      final sType = r['source_type']?.toString() ?? '';
      final sId = r['source_id']?.toString() ?? '';
      final ccId = r['cost_center_id']?.toString() ?? '';
      final item = r['item_name']?.toString() ?? '';
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;

      // Filter out non-positive remainder artifacts
      if (sType == 'season_rollover' && (sId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
        return false;
      }

      // Filter out generic cc_ob_ fallback when variety-level rollovers exist
      if (sId.startsWith('cc_ob_') && centersWithVarietyRollovers.contains(ccId)) {
        return false;
      }

      return true;
    }).toList();

    return rows;
  }

  List<Map<String, dynamic>> get _filteredRows {
    var rows = _costCenterScopedRows;

    // ── Partition Filter (Active Operations vs Historical Closed Periods) ──
    if (_selectedPartition == CostDetailsPartition.active) {
      rows = rows.where((r) => !_isRowClosed(r)).toList();
    } else if (_selectedPartition == CostDetailsPartition.historical) {
      rows = rows.where((r) => _isRowClosed(r)).toList();
    }

    if (_searchQuery.isEmpty) return rows;
    final q = _searchQuery.toLowerCase();
    return rows.where((r) {
      final item = (r['item_name']?.toString() ?? '').toLowerCase();
      final title = _resolveMovementTitle(r).toLowerCase();
      final desc = (r['description']?.toString() ?? '').toLowerCase();
      final notes = (r['notes']?.toString() ?? '').toLowerCase();
      final ship = (r['shipment_no']?.toString() ?? '').toLowerCase();
      final cust = (r['customer_name']?.toString() ?? '').toLowerCase();
      final supp = (r['supplier_name']?.toString() ?? '').toLowerCase();
      final inv = (r['invoice_ref']?.toString() ?? '').toLowerCase();
      final cc = (r['cost_center_name']?.toString() ?? '').toLowerCase();
      final cat = (r['category']?.toString() ?? '').toLowerCase();
      final isOpening = r['is_opening_balance'] == true ||
          r['source_type'] == 'opening_balance';
      final matchOpening = isOpening &&
          ('رصيد أول المدة رصيد سابق افتتاح مخزون مبدئي').contains(q);
      final isExportReturn = r['is_export_return'] == true ||
          r['source_type'] == 'export_return_waste' ||
          r['source_type'] == 'export_return_expense';
      final matchExportReturn = isExportReturn &&
          ('مرتجع مطار رجوع شحنة تصدير هالك تالف').contains(q);
      return item.contains(q) ||
          title.contains(q) ||
          desc.contains(q) ||
          notes.contains(q) ||
          ship.contains(q) ||
          cust.contains(q) ||
          supp.contains(q) ||
          inv.contains(q) ||
          cc.contains(q) ||
          cat.contains(q) ||
          matchOpening ||
          matchExportReturn;
    }).toList();
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
    final pool = _allCostCenters.isNotEmpty ? _allCostCenters : _activeCostCenters;
    final costCenterName = _selectedCostCenter != null
        ? CostCenterHelper.fromId(_selectedCostCenter, pool).nameAr
        : widget.costCenterLabel;

    final title = widget.majorCategory != null
        ? (costCenterName != null
            ? '${widget.majorCategory!} - $costCenterName'
            : widget.majorCategory!)
        : costCenterName != null
            ? 'تفاصيل تكاليف - $costCenterName'
            : widget.shipmentId != null
                ? (_rows.isNotEmpty
                    ? (_rows.first['shipment_no']?.toString() ??
                        'الشحنة #${widget.shipmentId}')
                    : 'الشحنة #${widget.shipmentId}')
                : widget.itemName != null
                    ? widget.itemName!
                    : widget.categoryLabel != null
                        ? widget.categoryLabel!
                        : _category != null
                            ? _catLabel(_category!)
                            : 'تفاصيل التكاليف';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        body: Container(
          decoration: isDark ? AppTheme.backgroundGradient : null,
          color: isDark ? null : const Color(0xFFF8FAFC),
          child: Column(
            children: [
              _buildHeader(title),
              _buildPartitionSelector(),
              _buildBranchVarianceSummaryHeader(isDark),
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.primary))
                    : (_isGroupedView ? _buildGroupedView() : _buildTable()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextEditingController _getItemActualCtrl(dynamic key, Map<String, dynamic> r) {
    if (!_itemActualCtrls.containsKey(key)) {
      final act = (r['actual_amount'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ??
          (r['expected_amount'] as num?)?.toDouble() ?? 0.0;
      _itemActualCtrls[key] = TextEditingController(
        text: act > 0 ? act.toStringAsFixed(2) : '',
      );
    }
    return _itemActualCtrls[key]!;
  }

  TextEditingController _getItemNotesCtrl(dynamic key, Map<String, dynamic> r) {
    if (!_itemNotesCtrls.containsKey(key)) {
      final n = (r['settlement_notes'] ?? r['notes'] ?? r['invoice_ref'] ?? '').toString();
      _itemNotesCtrls[key] = TextEditingController(
        text: (n != 'null' && !n.startsWith('{')) ? n : '',
      );
    }
    return _itemNotesCtrls[key]!;
  }

  void _distributeOverallActual({required bool proportional}) {
    final rawText = _overallActualCtrl.text.replaceAll(',', '').trim();
    final overall = double.tryParse(rawText);
    if (overall == null || overall <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ إجمالي صالح للتوزيع', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final targetRows = _filteredRows;
    if (targetRows.isEmpty) return;

    final double totalEstimated = targetRows.fold<double>(0.0, (sum, r) {
      final est = (r['expected_amount'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ?? 0.0;
      return sum + est;
    });

    setState(() {
      for (int i = 0; i < targetRows.length; i++) {
        final r = targetRows[i];
        final key = r['cost_item_id'] ?? r['id'] ?? r['packing_order_id'] ?? i;
        final est = (r['expected_amount'] as num?)?.toDouble() ??
            (r['amount'] as num?)?.toDouble() ?? 0.0;

        double distributed;
        if (proportional) {
          distributed = totalEstimated > 0 ? (est / totalEstimated) * overall : (overall / targetRows.length);
        } else {
          distributed = overall / targetRows.length;
        }

        _getItemActualCtrl(key, r).text = distributed.toStringAsFixed(2);
        _modifiedItemKeys.add(key);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          proportional
              ? 'تم توزيع EGP ${overall.toStringAsFixed(2)} تناسبياً حسب التقديري على ${targetRows.length} بند بنجاح'
              : 'تم توزيع EGP ${overall.toStringAsFixed(2)} بالتساوي على ${targetRows.length} بند بنجاح',
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  void _resetToEstimated() {
    setState(() {
      final targetRows = _filteredRows;
      for (int i = 0; i < targetRows.length; i++) {
        final r = targetRows[i];
        final key = r['cost_item_id'] ?? r['id'] ?? r['packing_order_id'] ?? i;
        final est = (r['expected_amount'] as num?)?.toDouble() ??
            (r['amount'] as num?)?.toDouble() ?? 0.0;
        _getItemActualCtrl(key, r).text = est > 0 ? est.toStringAsFixed(2) : '';
        _modifiedItemKeys.add(key);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تمت استعادة القيم التقديرية الأصلية لجميع البنود', textDirection: TextDirection.rtl),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _saveSettlements() async {
    final displayRows = _filteredRows;
    final List<Map<String, dynamic>> itemsToSettle = [];

    for (int i = 0; i < displayRows.length; i++) {
      final r = displayRows[i];
      final key = r['cost_item_id'] ?? r['id'] ?? r['packing_order_id'] ?? i;
      if (_modifiedItemKeys.contains(key) || _itemActualCtrls.containsKey(key)) {
        final ctrl = _itemActualCtrls[key];
        final actAmt = double.tryParse(ctrl?.text.replaceAll(',', '').trim() ?? '');
        if (actAmt != null) {
          final notesCtrl = _itemNotesCtrls[key];
          final notes = notesCtrl?.text.trim() ?? '';
          itemsToSettle.add({
            ...r,
            'resolved_actual': actAmt,
            'resolved_notes': notes,
          });
        }
      }
    }

    if (itemsToSettle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم تعديل أي قيم فعلية لحفظها أو تسويتها.', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final double sumEst = itemsToSettle.fold(0.0, (s, i) => s + ((i['expected_amount'] as num?)?.toDouble() ?? (i['amount'] as num?)?.toDouble() ?? 0.0));
        final double sumAct = itemsToSettle.fold(0.0, (s, i) => s + (i['resolved_actual'] as double));
        final double sumVar = sumAct - sumEst;
        final fNumber = NumberFormat('#,##0.00');

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified_outlined, color: AppTheme.primary),
              SizedBox(width: 8),
              Text('تأكيد اعتماد تسوية التكاليف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('هل أنت متأكد من ترحيل وتسوية ${itemsToSettle.length} بند تكلفة؟', style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildConfirmRow('إجمالي التقديري:', 'EGP ${fNumber.format(sumEst)}'),
                    const SizedBox(height: 6),
                    _buildConfirmRow('إجمالي الفعلي الجديد:', 'EGP ${fNumber.format(sumAct)}', bold: true),
                    const Divider(height: 16),
                    _buildConfirmRow(
                      'صافي الفارق (الانحراف):',
                      '${sumVar >= 0 ? '+' : ''}EGP ${fNumber.format(sumVar)}',
                      color: sumVar > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'سيتم تحديث سجلات التكلفة في قاعدة البيانات وتوليد قيود تسوية الفروق تلقائياً.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('اعتماد وتسوية الآن', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isSavingSettlement = true);

    try {
      final poDao = PackingOrderDao();
      final Map<int, List<Map<String, dynamic>>> packingOrderSettlements = {};
      final List<Map<String, dynamic>> directCostItems = [];

      for (final item in itemsToSettle) {
        final poId = (item['packing_order_id'] as num?)?.toInt();
        final costItemId = (item['cost_item_id'] ?? item['id'] as num?)?.toInt();
        final actualVal = item['resolved_actual'] as double;
        final notesVal = item['resolved_notes'] as String;

        if (poId != null && costItemId != null) {
          packingOrderSettlements.putIfAbsent(poId, () => []).add({
            'cost_item_id': costItemId,
            'actual_amount': actualVal,
            'notes': notesVal,
            'invoice_ref': item['invoice_ref'],
          });
        } else if (costItemId != null) {
          directCostItems.add({
            'id': costItemId,
            'actual_amount': actualVal,
            'notes': notesVal,
          });
        }
      }

      int successCount = 0;

      for (final entry in packingOrderSettlements.entries) {
        final pId = entry.key;
        final settlements = entry.value;
        try {
          await poDao.settleCostVariancesBatch(
            packingOrderId: pId,
            settlements: settlements,
            generalNotes: 'تسوية فروق التكاليف للفرع: ${widget.majorCategory ?? ""}',
          );
          successCount += settlements.length;
        } catch (poErr) {
          debugPrint('Error settling packing order #$pId: $poErr');
          for (final s in settlements) {
            try {
              await Supabase.instance.client.from('packing_order_cost_items').update({
                'actual_amount': s['actual_amount'],
                'cost_status': 'actual',
                'settlement_notes': s['notes'],
                'reconciled_at': DateTime.now().toIso8601String(),
              }).eq('id', s['cost_item_id']);
              successCount++;
            } catch (_) {}
          }
        }
      }

      for (final d in directCostItems) {
        try {
          await Supabase.instance.client.from('packing_order_cost_items').update({
            'actual_amount': d['actual_amount'],
            'cost_status': 'actual',
            'settlement_notes': d['notes'],
            'reconciled_at': DateTime.now().toIso8601String(),
          }).eq('id', d['id']);
          successCount++;
        } catch (_) {}
      }

      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();

      _modifiedItemKeys.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد وتسوية $successCount بند تكلفة بنجاح وتحديث القيود المحاسبية!', textDirection: TextDirection.rtl),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }

      await _load();
    } catch (e, st) {
      debugPrint('❌ Error in _saveSettlements: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ التسوية: $e', textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingSettlement = false);
      }
    }
  }

  Widget _buildBranchVarianceSummaryHeader(bool isDark) {
    if (!_isBranchVarianceView || _rows.isEmpty) return const SizedBox.shrink();

    final displayRows = _filteredRows;
    double totalEst = 0.0;
    double totalAct = 0.0;
    int pendingCount = 0;

    for (int i = 0; i < displayRows.length; i++) {
      final r = displayRows[i];
      final key = r['cost_item_id'] ?? r['id'] ?? r['packing_order_id'] ?? i;
      final e = (r['expected_amount'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ?? 0.0;
      final ctrl = _itemActualCtrls[key];
      double a;
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        a = double.tryParse(ctrl.text.replaceAll(',', '').trim()) ?? e;
      } else {
        a = (r['actual_amount'] as num?)?.toDouble() ??
            (r['amount'] as num?)?.toDouble() ?? e;
      }
      final status = r['cost_status']?.toString();
      totalAct += a;
      totalEst += e;
      if (status != 'settled' && status != 'actual' && !_modifiedItemKeys.contains(key)) {
        pendingCount++;
      }
    }

    final varAmt = totalAct - totalEst;
    final varPct = totalEst > 0 ? (varAmt / totalEst) * 100 : 0.0;
    final isOverrun = totalAct > totalEst && totalEst > 0;
    final isSaving = totalAct < totalEst && totalEst > 0;

    final varianceColor = isOverrun
        ? const Color(0xFFEF4444)
        : (isSaving ? const Color(0xFF10B981) : const Color(0xFF3B82F6));

    final fNumber = NumberFormat('#,##0.00');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.85) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. KPI Row ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.compare_arrows_rounded, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'مقارنة وتسوية التكاليف: ${widget.majorCategory ?? widget.categoryLabel ?? "تفاصيل الفرع"}',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pendingCount > 0 ? 'قيد التسوية ($pendingCount معلق)' : 'مسوى بالكامل',
                            style: TextStyle(
                              color: pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          'المقدر: EGP ${fNumber.format(totalEst)}',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            fontSize: 11.5,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        Text(
                          'الفعلي: EGP ${fNumber.format(totalAct)}',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'الانحراف: ${varAmt >= 0 ? '+' : ''}${fNumber.format(varAmt)}',
                              style: TextStyle(
                                color: varianceColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${varPct >= 0 ? '+' : ''}${varPct.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                color: varianceColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── 2. Top Header Auto-Distribution & Settlement Bar ──
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Overall Amount Input & Distribution buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    height: 38,
                    child: TextFormField(
                      controller: _overallActualCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      enabled: _selectedPartition != CostDetailsPartition.historical,
                      readOnly: _selectedPartition == CostDetailsPartition.historical,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        hintText: 'إجمالي المبلغ الفعلي',
                        hintStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        ),
                        prefixText: 'EGP ',
                        prefixStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'توزيع المبلغ الإجمالي تناسبياً حسب التكلفة التقديرية لكل بند',
                    child: OutlinedButton.icon(
                      onPressed: _selectedPartition == CostDetailsPartition.historical
                          ? null
                          : () => _distributeOverallActual(proportional: true),
                      icon: const Icon(Icons.pie_chart_outline, size: 15),
                      label: const Text('توزيع تناسبي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        side: const BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'توزيع المبلغ الإجمالي بالتساوي على جميع بنود الفرع',
                    child: OutlinedButton.icon(
                      onPressed: _selectedPartition == CostDetailsPartition.historical
                          ? null
                          : () => _distributeOverallActual(proportional: false),
                      icon: const Icon(Icons.splitscreen_rounded, size: 15),
                      label: const Text('توزيع بالتساوي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFF94A3B8)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'استعادة القيم التقديرية الأصلية للبنود',
                    child: IconButton(
                      onPressed: _selectedPartition == CostDetailsPartition.historical
                          ? null
                          : _resetToEstimated,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      tooltip: 'استعادة التقديري',
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              // Execute Settlement Action Button
              ElevatedButton.icon(
                onPressed: (_isSavingSettlement || _selectedPartition == CostDetailsPartition.historical)
                    ? null
                    : _saveSettlements,
                icon: _isSavingSettlement
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.verified_rounded, size: 16),
                label: Text(
                  _modifiedItemKeys.isNotEmpty
                      ? 'اعتماد وحفظ التسوية (${_modifiedItemKeys.length})'
                      : 'اعتماد وحفظ التسوية',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _translateItemName(String item, bool isEnglish) {
    if (!isEnglish) return item;
    final lower = item.toLowerCase();

    // Fruits
    if (lower.contains('مانجا') || lower.contains('مانجو')) return 'Mango';
    if (lower.contains('فراولة')) return 'Strawberry';
    if (lower.contains('برتقال')) return 'Orange';
    if (lower.contains('عنب فليم')) return 'Flame Grapes';
    if (lower.contains('عنب ايرلي') ||
        lower.contains('عنب أيرلي') ||
        lower.contains('عنب ءايرلي') ||
        lower.contains('عنب إيرلي')) {
      return 'Early Sweet Grapes';
    }
    if (lower.contains('عنب')) return 'Grapes';
    if (lower.contains('رمان')) return 'Pomegranate';
    if (lower.contains('ليمون')) return 'Lemon';
    if (lower.contains('يوسفي') || lower.contains('مندرين')) return 'Mandarin';
    if (lower.contains('تفاح')) return 'Apple';
    if (lower.contains('موز')) return 'Banana';
    if (lower.contains('بطيخ')) return 'Watermelon';
    if (lower.contains('شمام') || lower.contains('كنتالوب')) {
      return 'Cantaloupe / Melon';
    }
    if (lower.contains('خوخ')) return 'Peach';
    if (lower.contains('مشمش')) return 'Apricot';
    if (lower.contains('برقوق')) return 'Plum';
    if (lower.contains('جوافة')) return 'Guava';
    if (lower.contains('بلح') || lower.contains('تمر')) return 'Dates';
    if (lower.contains('تين')) return 'Fig';
    if (lower.contains('كمثرى') || lower.contains('اجاص')) return 'Pear';
    if (lower.contains('كيوي')) return 'Kiwi';

    // Materials & Costs
    if (lower.contains('تعبئة') || lower.contains('تغليف')) {
      return 'Packing & Packaging';
    }
    if (lower.contains('كراتين') || lower.contains('كرتون')) return 'Cartons';
    if (lower.contains('بلاستيك') || lower.contains('أكياس')) {
      return 'Plastic / Bags';
    }
    if (lower.contains('شحن')) return 'Shipping';
    if (lower.contains('تخليص')) return 'Clearance';
    if (lower.contains('نولون') || lower.contains('نقل')) {
      return 'Transport / Freight';
    }
    if (lower.contains('عمالة') ||
        lower.contains('عامل') ||
        lower.contains('يومية')) {
      return 'Labor';
    }
    if (lower.contains('مصاريف') || lower.contains('إدارية')) {
      return 'Administrative Expenses';
    }
    if (lower.contains('ورق')) return 'Paper';
    if (lower.contains('خشب') ||
        lower.contains('بالتة') ||
        lower.contains('بالتات')) {
      return 'Pallets';
    }

    return item;
  }

  Future<void> _exportToExcel(bool isEnglish) async {
    final exportRows = _filteredRows;
    if (exportRows.isEmpty) return;
    setState(() => _exportLoading = true);
    try {
      var excel = Excel.createExcel();
      var sheet = excel[isEnglish ? 'Cost Details' : 'تفاصيل التكاليف'];
      excel.setDefaultSheet(sheet.sheetName);

      sheet.appendRow(isEnglish
          ? [
              TextCellValue('Date'),
              TextCellValue('Shipment No'),
              TextCellValue('Customer / Supplier'),
              TextCellValue('Cost Center'),
              TextCellValue('Item'),
              TextCellValue('Quantity'),
              TextCellValue('Unit Price'),
              TextCellValue('Exchange Rate'),
              TextCellValue('Total in Currency'),
              TextCellValue('Total (EGP)'),
            ]
          : [
              TextCellValue('التاريخ'),
              TextCellValue('رقم الشحنة'),
              TextCellValue('العميل / المورد'),
              TextCellValue('مركز التكلفة'),
              TextCellValue('البيان'),
              TextCellValue('الكمية'),
              TextCellValue('سعر الوحدة'),
              TextCellValue('سعر الصرف'),
              TextCellValue('الإجمالي بالعملة'),
              TextCellValue('الإجمالي بالمصري'),
            ]);

      double totalQty = 0;
      double totalAmount = 0;

      for (final r in exportRows) {
        final date = r['shipment_date']?.toString() ?? '';
        final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
        final rawQty = double.tryParse(r['quantity']?.toString() ?? '0') ?? 0.0;
        final rawUnitPrice = double.tryParse(r['unit_price']?.toString() ?? '0') ?? 0.0;
        final amount = double.tryParse(r['amount']?.toString() ?? '0') ?? 0.0;
        final exchangeRate =
            double.tryParse(r['exchange_rate']?.toString() ?? '1') ?? 1.0;
        final totalInCurrency = double.tryParse(
                r['total_in_currency']?.toString() ?? amount.toString()) ??
            amount;
        final currency = _getCurrencyName(r['currency']?.toString());

        double qty = rawQty;
        double unitPriceForeign = rawUnitPrice;
        if (unitPriceForeign <= 0 && qty.abs() > 0 && totalInCurrency != 0) {
          unitPriceForeign = (totalInCurrency / qty).abs();
        } else if (qty == 0 && unitPriceForeign > 0 && totalInCurrency != 0) {
          qty = totalInCurrency / unitPriceForeign;
        } else if (qty == 0 && unitPriceForeign <= 0 && totalInCurrency != 0) {
          qty = totalInCurrency < 0 ? -1.0 : 1.0;
          unitPriceForeign = totalInCurrency.abs();
        }

        final ccId = r['cost_center_id']?.toString();
        final ccNameFromRow = r['cost_center_name']?.toString();
        final cc = ccId != null
            ? CostCenterHelper.fromId(ccId, _activeCostCenters)
            : CostCenterHelper.resolve(r, _activeCostCenters);
        final ccName = isEnglish
            ? (r['cost_center_name_en']?.toString() ?? cc.nameEn)
            : (ccNameFromRow != null &&
                    ccNameFromRow.isNotEmpty &&
                    ccNameFromRow != CostCenterHelper.generalAdmin.nameAr
                ? ccNameFromRow
                : cc.nameAr);

        totalQty += qty;
        totalAmount += amount;

        sheet.appendRow([
          TextCellValue(dateStr),
          TextCellValue('\u200E${r['shipment_no']?.toString() ?? ''}'),
          TextCellValue(_resolveCustomerSupplier(r)),
          TextCellValue(ccName),
          TextCellValue(
              _resolveFullExportDescription(r, isEnglish: isEnglish)),
          DoubleCellValue(qty),
          TextCellValue(
              '$currency ${unitPriceForeign.toStringAsFixed(2)}'),
          DoubleCellValue(exchangeRate),
          TextCellValue('$currency ${totalInCurrency.toStringAsFixed(2)}'),
          DoubleCellValue(amount),
        ]);
      }

      // Append Totals Row
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(isEnglish ? 'Total' : 'الإجمالي'),
        DoubleCellValue(totalQty),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(totalAmount),
      ]);

      final dir = await FileHelper.getExportDirectory();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = '${dir.path}/Cost_Details_$now.xlsx';
      final bytes = excel.save();
      if (bytes != null) {
        final file = File(path);
        await file.writeAsBytes(bytes);
        OpenFilex.open(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ في التصدير: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _printReport() async {
    final printRows = _filteredRows;
    if (printRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد بيانات للطباعة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final costCenterName = _selectedCostCenter != null
        ? CostCenterHelper.fromId(_selectedCostCenter, _activeCostCenters).nameAr
        : widget.costCenterLabel;

    final shipmentNo = printRows.isNotEmpty
        ? (printRows.first['shipment_no']?.toString() ?? '')
        : '';

    await CostCenterDetailsPdfService.generateAndPrint(
      context: context,
      rows: printRows,
      activeCostCenters: _activeCostCenters,
      costCenterName: costCenterName,
      selectedCurrency: _selectedCurrency,
      fromDate: _fromCtrl.text.isNotEmpty ? _fromCtrl.text : null,
      toDate: _toCtrl.text.isNotEmpty ? _toCtrl.text : null,
      shipmentNo: shipmentNo,
      categoryLabel: widget.categoryLabel ?? widget.majorCategory,
    );
  }

  CostCenter? get _currentCostCenter {
    final pool = _allCostCenters.isNotEmpty ? _allCostCenters : _activeCostCenters;
    if (_selectedCostCenter != null) {
      return CostCenterHelper.fromId(_selectedCostCenter, pool);
    } else if (widget.costCenter != null) {
      return CostCenterHelper.fromId(widget.costCenter, pool);
    }
    return null;
  }

  void _openSeasonRolloverDialog() {
    final center = _currentCostCenter;
    if (center != null && center.isPermanentlyClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'مركز التكلفة (${center.nameAr}) مقفل نهائياً للسنة الزراعية. تم استنفاد الموسمين المسموح بهما.',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (center != null && center.isClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'مركز التكلفة (${center.nameAr}) مقفل بالفعل لهذا الموسم ولا يمكن ترحيله مرة أخرى.',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    double netTotal = 0.0;
    double openingTotal = 0.0;
    double operationalTotal = 0.0;

    for (final r in _costCenterScopedRows) {
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final srcId = r['source_id']?.toString() ?? '';
      final srcType = r['source_type']?.toString() ?? '';
      final item = (r['item_name']?.toString() ?? '').trim();

      // Skip non-positive remainder rows
      if (srcType == 'season_rollover' && (srcId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
        continue;
      }

      final isRedundant = r['is_redundant_rollover'] == true;
      final isRollover = _isRolloverRow(r);
      final isOpening = r['is_opening_balance'] == true || r['source_type'] == 'opening_balance' || isRollover;

      if (isRedundant || isOpening) {
        openingTotal += amt;
      } else {
        operationalTotal += amt;
      }
    }

    if (openingTotal == 0.0 && center != null && center.openingBalance > 0) {
      openingTotal = center.openingBalance;
    }

    // Authentic balance calculation:
    // Stage 1 (P1 -> P2): carries forward Period 1 total
    // Stage 2 (Final Closure): carries forward complete closing ledger balance (opening + all operations)
    if (center != null && center.isFinalSeason) {
      netTotal = openingTotal + operationalTotal;
    } else {
      netTotal = openingTotal > 0 ? (openingTotal + operationalTotal) : (center?.currentBalance ?? operationalTotal);
    }

    if (netTotal == 0.0 && (center?.currentBalance ?? 0.0) > 0) {
      netTotal = center!.currentBalance;
    }

    SeasonRolloverDialog.show(
      context,
      costCenter: center,
      activeCostCenters: _activeCostCenters,
      currentNetBalance: netTotal,
      transactionCount: _filteredRows.length,
      onRolloverCompleted: () {
        _load();
      },
    );
  }

  Widget _buildHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCenter = _currentCostCenter;
    final isCenterClosed = currentCenter?.isClosed ?? false;

    final backBtn = Tooltip(
      message: 'العودة إلى تقارير التكاليف',
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF061B3A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  size: 16),
              const SizedBox(width: 4),
              Text('رجوع',
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
      ),
    );

    final titleText = Text(title,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo'));

    final headerActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _isBranchVarianceView
              ? 'إلغاء وضع تسوية التكاليف'
              : 'تفعيل وضع مقارنة وتسوية التكاليف (التقديري vs الفعلي)',
          child: GestureDetector(
            onTap: () => setState(() => _settlementMode = !_settlementMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _isBranchVarianceView
                    ? AppTheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                    : (isDark ? const Color(0xFF061B3A) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isBranchVarianceView
                      ? AppTheme.primary
                      : (isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.balance_rounded,
                    color: _isBranchVarianceView
                        ? AppTheme.primary
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isBranchVarianceView ? 'تسوية التكاليف مفعلة' : 'وضع التسوية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isBranchVarianceView
                          ? AppTheme.primary
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<bool>(
          tooltip: 'تصدير كملف Excel',
          onSelected: (isEnglish) {
            if (!_exportLoading) _exportToExcel(isEnglish);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: false,
              child: Text('تصدير بالعربية',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
            const PopupMenuItem(
              value: true,
              child: Text('Export in English',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF061B3A) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.3 : 0.4)),
            ),
            child: _exportLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF10B981)))
                : const Icon(Icons.table_chart_outlined,
                    color: Color(0xFF10B981), size: 18),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'طباعة / PDF',
          child: GestureDetector(
            onTap: _printReport,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF061B3A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
              ),
              child: Icon(Icons.print_outlined,
                  color: isDark ? Colors.white : const Color(0xFF0F172A), size: 18),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: (currentCenter?.isPermanentlyClosed ?? false)
              ? 'السنة الزراعية مقفلة نهائياً — تم استنفاد الموسمين'
              : isCenterClosed
                  ? 'هذا الموسم مقفل بالفعل ولا يمكن ترحيله مرة أخرى'
                  : 'إقفال وترحيل الموسم الزراعي',
          child: isCenterClosed
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: (currentCenter?.isPermanentlyClosed ?? false)
                        ? Colors.redAccent.withValues(alpha: 0.12)
                        : isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (currentCenter?.isPermanentlyClosed ?? false)
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : isDark
                              ? Colors.white24
                              : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        color: (currentCenter?.isPermanentlyClosed ?? false)
                            ? Colors.redAccent
                            : isDark
                                ? Colors.white38
                                : const Color(0xFF64748B),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (currentCenter?.isPermanentlyClosed ?? false)
                            ? 'السنة مقفلة نهائياً'
                            : 'موسم مقفل',
                        style: TextStyle(
                          color: (currentCenter?.isPermanentlyClosed ?? false)
                              ? Colors.redAccent
                              : isDark
                                  ? Colors.white38
                                  : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                )
              : InkWell(
                  onTap: _openSeasonRolloverDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD97706), Color(0xFFB45309)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD97706).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.published_with_changes_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'إقفال وترحيل الموسم',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.sizeOf(context).width;
        final isMobile = constraints.maxWidth < 950 || screenW < 950;
        final topPad = MediaQuery.of(context).padding.top + (isMobile ? 54.0 : 12.0);
        return Container(
          padding: EdgeInsets.only(
            top: topPad,
            bottom: 12,
            left: isMobile ? 12 : 20,
            right: isMobile ? 12 : 20,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF061B3A) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Column(
            children: [
              if (isMobile) ...[
                Row(
                  children: [
                    backBtn,
                    const SizedBox(width: 10),
                    Expanded(child: titleText),
                  ],
                ),
                if (_rows.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: headerActions,
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    backBtn,
                    const SizedBox(width: 12),
                    Expanded(child: titleText),
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: headerActions,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Filters Row: Date From, Date To, Cost Center, Currency, Toggle, Clear
              Builder(
                builder: (context) {
                  final isNarrow = MediaQuery.sizeOf(context).width < 700;
                  if (isNarrow) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildDateField('من تاريخ', _fromCtrl)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildDateField('إلى تاريخ', _toCtrl)),
                            const SizedBox(width: 8),
                            _buildClearBtn(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildCostCenterSelector(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildCurrencyFilter()),
                            const SizedBox(width: 8),
                            _buildViewToggle(),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 2, child: _buildDateField('من تاريخ', _fromCtrl)),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: _buildDateField('إلى تاريخ', _toCtrl)),
                      const SizedBox(width: 10),
                      Expanded(flex: 3, child: _buildCostCenterSelector()),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: _buildCurrencyFilter()),
                      const SizedBox(width: 10),
                      _buildViewToggle(),
                      const SizedBox(width: 10),
                      _buildClearBtn(),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),

              // Search Bar
              _buildSearchBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClearBtn() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'إعادة تعيين الفلاتر',
      child: GestureDetector(
        onTap: () {
          _fromCtrl.clear();
          _toCtrl.clear();
          _searchCtrl.clear();
          setState(() {
            _selectedCostCenter = null;
            _selectedCurrency = null;
            _selectedPartition = CostDetailsPartition.active;
            _searchQuery = '';
          });
          _load();
        },
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Center(
            child: Icon(Icons.clear_all_rounded,
                color: isDark ? Colors.white70 : const Color(0xFF475569), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencies = _availableCurrencies.toList()..sort((a, b) {
      if (a == 'EGP') return -1;
      if (b == 'EGP') return 1;
      return a.compareTo(b);
    });

    final currencyLabels = {
      'EGP': 'جنيه مصري (EGP)',
      'USD': 'دولار (USD)',
      'EUR': 'يورو (EUR)',
      'GBP': 'إسترليني (GBP)',
    };

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _selectedCurrency != null
            ? (isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFFFEF3C7))
            : (isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedCurrency != null
              ? const Color(0xFFF59E0B)
              : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedCurrency,
          dropdownColor: isDark ? const Color(0xFF0F2238) : Colors.white,
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFF59E0B), size: 20),
          hint: Row(
            children: [
              const Icon(Icons.currency_exchange, size: 15, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'العملة: الكل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.all_inclusive, size: 14, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('كل العملات',
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ],
              ),
            ),
            ...currencies.map((cur) {
              final label = currencyLabels[cur] ?? cur;
              return DropdownMenuItem<String?>(
                value: cur,
                child: Row(
                  children: [
                    Text(
                      cur == 'EGP' ? 'ج.م' : cur == 'USD' ? '\$' : cur == 'EUR' ? '€' : cur == 'GBP' ? '£' : cur,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cur == 'EGP'
                            ? const Color(0xFF10B981)
                            : cur == 'USD'
                                ? const Color(0xFF3B82F6)
                                : cur == 'EUR'
                                    ? const Color(0xFF8B5CF6)
                                    : const Color(0xFFF59E0B),
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12,
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
            setState(() => _selectedCurrency = val);
          },
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: _isGroupedView ? 'عرض مسطح' : 'عرض مجمّع حسب الصنف',
      child: GestureDetector(
        onTap: () => setState(() => _isGroupedView = !_isGroupedView),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _isGroupedView
                ? AppTheme.primary.withValues(alpha: isDark ? 0.15 : 0.1)
                : (isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isGroupedView ? AppTheme.primary : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Center(
            child: Icon(
              _isGroupedView ? Icons.view_agenda_rounded : Icons.table_rows_rounded,
              color: _isGroupedView ? AppTheme.primary : (isDark ? Colors.white70 : const Color(0xFF475569)),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCostCenterSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final seenIds = <String>{};
    final uniqueList = <CostCenter>[];

    final centersToDisplay = _allCostCenters.isNotEmpty ? _allCostCenters : _activeCostCenters;
    for (final cc in centersToDisplay) {
      final code = (cc.code ?? cc.id).trim();
      // Strictly exclude Level 3 (3 digits) and Level 4 (4 digits)
      if (code.length == 3 || code.length == 4) continue;
      if (seenIds.add(cc.id)) {
        uniqueList.add(cc);
      }
    }

    if (seenIds.add(CostCenterHelper.sharedProducts.id)) {
      uniqueList.add(CostCenterHelper.sharedProducts);
    }


    if (_selectedCostCenter != null && !seenIds.contains(_selectedCostCenter)) {
      final resolved =
          CostCenterHelper.fromId(_selectedCostCenter, centersToDisplay);
      uniqueList.add(
        CostCenter(
          id: _selectedCostCenter!,
          nameAr: widget.costCenterLabel ??
              (resolved.id != CostCenterHelper.generalAdmin.id
                  ? resolved.nameAr
                  : _selectedCostCenter!),
          nameEn: resolved.nameEn,
          type: resolved.type,
          color: resolved.color,
          icon: resolved.icon,
          code: _selectedCostCenter,
          seasonStatus: resolved.seasonStatus,
          status: resolved.status,
          isActive: resolved.isActive,
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _selectedCostCenter != null
            ? AppTheme.primary.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedCostCenter != null
              ? AppTheme.primary
              : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedCostCenter,
          dropdownColor: isDark ? const Color(0xFF0F2238) : Colors.white,
          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary, size: 20),
          hint: Row(
            children: [
              const Icon(Icons.hub_outlined, size: 15, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مركز التكلفة: الكل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.all_inclusive, size: 14, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text('جميع مراكز التكلفة',
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ],
              ),
            ),
            ...uniqueList.map((cc) {
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
                    Icon(cc.icon, size: 14, color: cc.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cc.nameAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    if (cc.isClosed) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock_rounded, size: 12, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    ],
                  ],
                ),
              );
            }),
          ],
          onChanged: (val) {
            setState(() {
              _selectedCostCenter = val;
              if (val != null) {
                final target = CostCenterHelper.fromId(val, uniqueList);
                if (target.isClosed) {
                  _selectedPartition = CostDetailsPartition.historical;
                } else {
                  _selectedPartition = CostDetailsPartition.active;
                }
              }
            });
            _load();
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() {
          _searchQuery = v.trim();
          _currentPage = 1;
        }),
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 12,
          fontFamily: 'Cairo',
        ),
        decoration: InputDecoration(
          hintText: 'بحث برقم الشحنة، العميل، البيان، أو مركز التكلفة...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
          prefixIcon: const Icon(Icons.search, color: AppTheme.primary, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() {
                      _searchQuery = '';
                      _currentPage = 1;
                    });
                  },
                  child: Icon(Icons.clear, color: isDark ? Colors.white54 : const Color(0xFF64748B), size: 16),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildDateField(String label, TextEditingController ctrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _pickDate(ctrl),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardBg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppTheme.primary, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ctrl.text.isEmpty ? label : ctrl.text,
                style: TextStyle(
                  color: ctrl.text.isEmpty
                      ? (isDark ? Colors.white54 : const Color(0xFF64748B))
                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostCenterBadge(Map<String, dynamic> r) {
    final ccId = r['cost_center_id']?.toString();
    final ccName = r['cost_center_name']?.toString();

    // Resolve CostCenter entity with full active centers awareness
    final CostCenter cc;
    if (ccId != null && ccId.isNotEmpty) {
      cc = CostCenterHelper.fromId(ccId, _activeCostCenters);
    } else if (ccName != null &&
        ccName.isNotEmpty &&
        ccName != CostCenterHelper.generalAdmin.nameAr) {
      cc = CostCenterHelper.fromId(ccName, _activeCostCenters);
    } else {
      cc = CostCenterHelper.resolve(r, _activeCostCenters);
    }

    final displayName = (ccName != null &&
            ccName.isNotEmpty &&
            ccName != CostCenterHelper.generalAdmin.nameAr)
        ? ccName
        : cc.nameAr;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cc.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cc.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cc.icon, size: 12, color: cc.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cc.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentBadge(Map<String, dynamic> r) {
    final shipmentNo = r['shipment_no']?.toString() ?? '';
    final isExportSale = r['is_export_sale'] == true ||
        r['source_type'] == 'export_shipment' ||
        r['source_type'] == 'export_sale';
    if (isExportSale) {
      final poNum = r['packing_order_number']?.toString();
      final hasPo = poNum != null && poNum.isNotEmpty && poNum != 'null';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flight_takeoff_rounded, size: 13, color: Color(0xFF0284C7)),
            const SizedBox(width: 4),
            Text(
              shipmentNo.isNotEmpty ? '\u202A$shipmentNo\u202C' : 'شحنة تصدير',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0284C7),
              ),
            ),
            if (hasPo) ...[
              const SizedBox(width: 4),
              Text(
                '| أمر #$poNum',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  color: Color(0xFF0284C7),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final isExportReturn = r['is_export_return'] == true ||
        r['source_type'] == 'export_return_waste' ||
        r['source_type'] == 'export_return_expense' ||
        shipmentNo.startsWith('EXR-') ||
        shipmentNo.contains('مرتجع من المطار');
    if (isExportReturn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF97316).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flight_land_rounded, size: 13, color: Color(0xFFF97316)),
            const SizedBox(width: 4),
            Text(
              shipmentNo.isNotEmpty ? '\u202A$shipmentNo\u202C' : 'مرتجع مطار',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF97316),
              ),
            ),
          ],
        ),
      );
    }

    final isRollover = r['is_rollover'] == true ||
        r['source_type'] == 'season_rollover' ||
        shipmentNo == 'رصيد مرحل';
    if (isRollover) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 13, color: Color(0xFFF59E0B)),
            SizedBox(width: 4),
            Text(
              'رصيد مرحل',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      );
    }

    final isOpening = r['is_opening_balance'] == true ||
        r['source_type'] == 'opening_balance' ||
        shipmentNo == 'رصيد أول المدة' ||
        shipmentNo == 'رصيد سابق';
    if (isOpening) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 13, color: Color(0xFFF59E0B)),
            SizedBox(width: 4),
            Text(
              'رصيد أول المدة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      );
    }

    final isReturn = r['is_lot_return'] == true ||
        r['source_type'] == 'lot_return' ||
        r['source_type'] == 'crop_return' ||
        shipmentNo == 'مرتجع شراء محصول' ||
        ((r['amount'] as num?)?.toDouble() ?? 0) < 0;
    if (isReturn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_return_rounded, size: 13, color: Color(0xFFEF4444)),
            SizedBox(width: 4),
            Text(
              'مرتجع شراء محصول',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      );
    }

    final isLotReceipt = r['is_lot_receipt'] == true ||
        r['source_type'] == 'lot_receipt' ||
        shipmentNo == 'استلام لوط';
    if (isLotReceipt) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF3B82F6)),
            SizedBox(width: 4),
            Text(
              'استلام لوط',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      );
    }

    final isPurchase = r['is_purchase'] == true ||
        r['source_type'] == 'purchase' ||
        r['source_type'] == 'crop_purchase' ||
        shipmentNo == 'فاتورة مشتريات';
    if (isPurchase) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 13, color: Color(0xFF8B5CF6)),
            SizedBox(width: 4),
            Text(
              'فاتورة مشتريات',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ],
        ),
      );
    }

    final isSortingSale = r['is_sorting_sale'] == true ||
        r['source_type'] == 'sorting_sale' ||
        shipmentNo == 'بيع فرز';
    if (isSortingSale) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale_rounded, size: 13, color: Color(0xFF10B981)),
            SizedBox(width: 4),
            Text(
              'بيع فرز',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10B981),
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      shipmentNo.isNotEmpty ? '\u202A$shipmentNo\u202C' : '',
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.primary,
      ),
    );
  }

  Widget _buildPartitionSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoped = _costCenterScopedRows;
    final activeCount = scoped.where((r) => !_isRowClosed(r)).length;
    final historicalCount = scoped.where((r) => _isRowClosed(r)).length;
    final totalCount = scoped.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF04152D) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF0EA5E9).withValues(alpha: 0.25)
              : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPartitionTab(
              title: 'العمليات الجارية',
              count: activeCount,
              icon: Icons.play_circle_fill_rounded,
              isSelected: _selectedPartition == CostDetailsPartition.active,
              activeColor: const Color(0xFF10B981),
              onTap: () => _onPartitionChanged(CostDetailsPartition.active),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildPartitionTab(
              title: 'السجل التاريخي المقفل',
              count: historicalCount,
              icon: Icons.lock_rounded,
              isSelected: _selectedPartition == CostDetailsPartition.historical,
              activeColor: const Color(0xFFF59E0B),
              onTap: () => _onPartitionChanged(CostDetailsPartition.historical),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildPartitionTab(
              title: 'كافة الفترات',
              count: totalCount,
              icon: Icons.all_inclusive_rounded,
              isSelected: _selectedPartition == CostDetailsPartition.all,
              activeColor: const Color(0xFF38BDF8),
              onTap: () => _onPartitionChanged(CostDetailsPartition.all),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartitionTab({
    required String title,
    required int count,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: isDark ? 0.18 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? activeColor : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: isDark ? 0.3 : 0.2)
                    : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? activeColor : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoricalLockBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.65) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Color(0xFFF59E0B),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'سجل تاريخي مقفل ومؤرشف (للقراءة فقط)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '• القيود محمية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'تم إقفال هذا المركز/الموسم وترحيل أرصدته للفترة اللاحقة. السجلات محمية بالكامل للقراءة والتحليل المالي ولا تقبل الإضافة أو التعديل أو الحذف.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF78350F),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoped = _costCenterScopedRows;
    final activeCount = scoped.where((r) => !_isRowClosed(r)).length;
    final historicalCount = scoped.where((r) => _isRowClosed(r)).length;

    if (_selectedPartition == CostDetailsPartition.active && historicalCount > 0) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF071C35) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_rounded, color: Color(0xFFF59E0B), size: 48),
              const SizedBox(height: 12),
              Text(
                'لا توجد عمليات جارية في الفترة الحالية',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'توجد $historicalCount معاملات مسجلة في السجل التاريخي المقفل لهذا المركز',
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _onPartitionChanged(CostDetailsPartition.historical),
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: const Text('عرض السجل التاريخي المقفل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedPartition == CostDetailsPartition.historical && activeCount > 0) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF071C35) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_toggle_off_rounded, color: Color(0xFF10B981), size: 48),
              const SizedBox(height: 12),
              Text(
                'لا توجد فترات تاريخية مقفلة',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'الموسم الحالي نشط ويحتوي على $activeCount معاملة جارية',
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _onPartitionChanged(CostDetailsPartition.active),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 16),
                label: const Text('عرض العمليات الجارية'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: isDark ? Colors.white38 : const Color(0xFF94A3B8), size: 48),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? 'لا توجد نتائج مطابقة للبحث'
                : 'لا توجد معاملات',
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A), fontFamily: 'Cairo', fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedView() {
    final displayRows = _filteredRows;
    if (displayRows.isEmpty) return _buildEmptyState();

    // ── PERIOD-ISOLATED GROUPING ──────────────────────────────────────────────
    // KEY = "$ccId||$item"
    // This prevents Period 1 and Period 2 transactions for the same crop from
    // merging into the same variety card, even when item_name is identical.
    final LinkedHashMap<String, List<Map<String, dynamic>>> groups = LinkedHashMap();
    final Map<String, String> keyToDisplay = {}; // composite key -> display item_name
    final Map<String, String> keyToCcId = {};    // composite key -> cost_center_id
    final Map<String, String> keyToCcName = {};  // composite key -> cost_center_name

    for (final r in displayRows) {
      final item = (r['item_name']?.toString() ?? '').trim();
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final srcId = r['source_id']?.toString() ?? '';
      final srcType = r['source_type']?.toString() ?? '';

      // Defensive guard: skip non-positive remainder rollovers
      if (srcType == 'season_rollover' && (srcId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
        continue;
      }

      final ccId = (r['cost_center_id']?.toString() ?? '').trim();
      final ccName = (r['cost_center_name']?.toString() ?? '').trim();

      String displayKey = item;
      if (displayKey.isEmpty) {
        displayKey = _resolveMovementTitle(r);
      } else if (displayKey.toLowerCase() == 'other' || displayKey.toLowerCase() == 'logistics') {
        displayKey = _catLabel(displayKey);
      }

      // Composite key: period-qualified item key for strict isolation
      final compositeKey = ccId.isNotEmpty ? '$ccId||$displayKey' : displayKey;

      groups.putIfAbsent(compositeKey, () => []).add(r);
      keyToDisplay.putIfAbsent(compositeKey, () => displayKey);
      keyToCcId.putIfAbsent(compositeKey, () => ccId);
      keyToCcName.putIfAbsent(compositeKey, () => ccName);
    }

    final isHistoricalPartition = _selectedPartition == CostDetailsPartition.historical;
    final allRowsClosed = displayRows.every(_isRowClosed);

    return Column(
      children: [
        if (isHistoricalPartition || allRowsClosed) _buildHistoricalLockBanner(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final entry = groups.entries.elementAt(index);
              final compositeKey = entry.key;
              final displayName = keyToDisplay[compositeKey] ?? entry.key;
              final ccId = keyToCcId[compositeKey] ?? '';
              final ccName = keyToCcName[compositeKey] ?? '';
              return _buildVarietySection(
                displayName,
                entry.value,
                defaultExpanded: groups.length <= 6,
                costCenterId: ccId,
                costCenterName: ccName,
              );
            },
          ),
        ),
        _buildSummaryBar(displayRows),
      ],
    );
  }

  /// Builds an accordion card for one (cost-center, item_name) group.
  /// [costCenterId] and [costCenterName] come from the composite key so that
  /// Period 1 and Period 2 cards remain strictly segregated even for the same crop.
  Widget _buildVarietySection(
    String varietyName,
    List<Map<String, dynamic>> rows, {
    bool defaultExpanded = true,
    String costCenterId = '',
    String costCenterName = '',
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lowerName = varietyName.toLowerCase();
    final isRolloverSection = lowerName.contains('مرحل') ||
        lowerName.contains('افتتاحي') ||
        lowerName.contains('rollover') ||
        rows.any((r) =>
            _isRolloverRow(r) ||
            r['is_opening_balance'] == true ||
            r['source_type'] == 'season_rollover');

    final groupEgpTotal = rows.fold<double>(0.0, (s, r) {
      return s + ((r['amount'] as num?)?.toDouble() ?? 0.0);
    });
    final groupQty = rows.fold<double>(
        0, (s, r) => s + ((r['quantity'] as num?)?.toDouble() ?? 0));

    // Determine currencies in this group
    final groupCurrencies = <String, double>{};
    for (final r in rows) {
      final c = (r['currency']?.toString() ?? 'EGP').toUpperCase();
      final val = (r['total_in_currency'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ??
          0.0;
      groupCurrencies[c] = (groupCurrencies[c] ?? 0.0) + val;
    }

    // Pick a thematic icon based on variety / category
    IconData sectionIcon = Icons.eco_rounded;
    Color iconColor = const Color(0xFF10B981);
    if (isRolloverSection) {
      sectionIcon = Icons.published_with_changes_rounded;
      iconColor = const Color(0xFFF59E0B);
    } else if (lowerName.contains('فرز')) {
      sectionIcon = Icons.point_of_sale_rounded;
      iconColor = const Color(0xFFF59E0B);
    } else if (lowerName.contains('شحن') || lowerName.contains('نولون')) {
      sectionIcon = Icons.local_shipping_rounded;
      iconColor = const Color(0xFF3B82F6);
    } else if (lowerName.contains('تخليص')) {
      sectionIcon = Icons.assignment_turned_in_rounded;
      iconColor = const Color(0xFF8B5CF6);
    } else if (lowerName.contains('كرتون') || lowerName.contains('تعبئة') || lowerName.contains('ورق')) {
      sectionIcon = Icons.inventory_2_rounded;
      iconColor = const Color(0xFFEC4899);
    }

    final isSectionClosed = rows.isNotEmpty && rows.every(_isRowClosed);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSectionClosed
            ? (isDark ? const Color(0xFF071C35) : const Color(0xFFFEF3C7).withValues(alpha: 0.35))
            : (isDark ? const Color(0xFF072548) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSectionClosed
              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
              : (isDark ? const Color(0xFF0EA5E9).withValues(alpha: 0.2) : const Color(0xFFCBD5E1)),
          width: isSectionClosed ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: defaultExpanded,
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            iconColor: AppTheme.primary,
            collapsedIconColor: isDark ? Colors.white60 : const Color(0xFF64748B),
            title: LayoutBuilder(
              builder: (context, tileConstraints) {
                final screenW = MediaQuery.sizeOf(context).width;
                final isCompactTile = (tileConstraints.maxWidth.isFinite && tileConstraints.maxWidth < 650) || screenW < 750;

                final metaWrap = Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${rows.length} معاملات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                    if (groupQty > 0)
                      Text(
                        'الكمية: ${_fmtNum(groupQty)}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                        ),
                      ),
                  ],
                );

                if (isCompactTile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isSectionClosed
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                  : iconColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: isSectionClosed
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                                    : iconColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Icon(
                              isSectionClosed ? Icons.lock_rounded : sectionIcon,
                              size: 15,
                              color: isSectionClosed ? const Color(0xFFF59E0B) : iconColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  varietyName,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (costCenterName.isNotEmpty)
                                  Text(
                                    costCenterName,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 9.5,
                                      color: isDark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF64748B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isRolloverSection ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: (isRolloverSection ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.4)),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'EGP ${_fmt(groupEgpTotal)}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isRolloverSection ? const Color(0xFFF59E0B) : (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      metaWrap,
                    ],
                  );
                }

                return Row(
                  children: [
                    // Variety icon badge
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isSectionClosed
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                            : iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSectionClosed
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                              : iconColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        isSectionClosed ? Icons.lock_rounded : sectionIcon,
                        size: 18,
                        color: isSectionClosed ? const Color(0xFFF59E0B) : iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Variety name & meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  varietyName,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // ── Period badge ──
                              Builder(builder: (_) {
                                final periodMatch = RegExp(r'-P(\d+)$').firstMatch(costCenterId);
                                if (periodMatch == null) return const SizedBox.shrink();
                                final periodNum = periodMatch.group(1);
                                return Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.18 : 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.55)),
                                    ),
                                    child: Text(
                                      'الفترة $periodNum',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              // ── Lock Badge ──
                              if (isSectionClosed)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_rounded, size: 10, color: Color(0xFFF59E0B)),
                                        SizedBox(width: 3),
                                        Text(
                                          'مقفل',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (costCenterName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: Text(
                                costCenterName,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.5,
                                  color: isDark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 1),
                          metaWrap,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sub-totals
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isRolloverSection ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: (isRolloverSection ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'EGP ${_fmt(groupEgpTotal)}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isRolloverSection ? const Color(0xFFF59E0B) : (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                            ),
                          ),
                        ),
                        if (groupCurrencies.length > 1 || (groupCurrencies.isNotEmpty && !groupCurrencies.containsKey('EGP'))) ...[
                          const SizedBox(height: 2),
                          ...groupCurrencies.entries.where((e) => e.key != 'EGP' && e.value != 0).map((e) {
                            return Text(
                              '${e.key} ${_fmt(e.value)}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9.5,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
            children: [
              if (isSectionClosed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.08) : const Color(0xFFFEF3C7),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Text(
                        'بيانات تاريخية مقفلة — هذه السجلات محمية بالكامل للقراءة والتحليل المالي ولا تقبل التعديل أو الحذف',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildDataTable(rows),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayRows = _filteredRows;
    if (displayRows.isEmpty) return _buildEmptyState();

    final isHistoricalPartition = _selectedPartition == CostDetailsPartition.historical;
    final allRowsClosed = displayRows.every(_isRowClosed);

    final totalRows = displayRows.length;
    final totalPages = (totalRows / _rowsPerPage).ceil().clamp(1, 999999);
    if (_currentPage > totalPages) _currentPage = totalPages;
    final startIndex = (_currentPage - 1) * _rowsPerPage;
    final endIndex = math.min(startIndex + _rowsPerPage, totalRows);
    final paginatedRows = displayRows.sublist(startIndex, endIndex);

    return Column(
      children: [
        if (isHistoricalPartition || allRowsClosed) _buildHistoricalLockBanner(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF072548) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF0EA5E9).withValues(alpha: 0.3)
                      : const Color(0xFFCBD5E1)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildDataTable(paginatedRows),
                ),
              ),
            ),
          ),
        ),
        _buildPaginationBar(totalRows, totalPages, startIndex, endIndex),
        _buildSummaryBar(displayRows),
      ],
    );
  }

  Widget _buildPaginationBar(int totalRows, int totalPages, int startIndex, int endIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF0EA5E9).withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
        ),
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عرض ${startIndex + 1} - $endIndex من $totalRows',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                    _buildRowsPerPageSelector(isDark),
                  ],
                ),
                const SizedBox(height: 6),
                _buildPageControls(totalPages, isDark),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.format_list_numbered_rtl, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'عرض من ${startIndex + 1} إلى $endIndex من إجمالي $totalRows حركة',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildRowsPerPageSelector(isDark),
                    const SizedBox(width: 16),
                    _buildPageControls(totalPages, isDark),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildRowsPerPageSelector(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'لكل صفحة:',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Cairo',
            color: isDark ? Colors.white60 : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPage,
              isDense: true,
              dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              items: const [15, 25, 50, 100].map((count) {
                return DropdownMenuItem<int>(
                  value: count,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null && val != _rowsPerPage) {
                  setState(() {
                    _rowsPerPage = val;
                    _currentPage = 1;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageControls(int totalPages, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.first_page, size: 20),
          tooltip: 'الصفحة الأولى',
          onPressed: _currentPage > 1
              ? () => setState(() => _currentPage = 1)
              : null,
          color: isDark ? Colors.white70 : const Color(0xFF475569),
          disabledColor: isDark ? Colors.white24 : Colors.black26,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 22),
          tooltip: 'الصفحة السابقة',
          onPressed: _currentPage > 1
              ? () => setState(() => _currentPage--)
              : null,
          color: isDark ? Colors.white70 : const Color(0xFF475569),
          disabledColor: isDark ? Colors.white24 : Colors.black26,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            '$_currentPage / $totalPages',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 22),
          tooltip: 'الصفحة التالية',
          onPressed: _currentPage < totalPages
              ? () => setState(() => _currentPage++)
              : null,
          color: isDark ? Colors.white70 : const Color(0xFF475569),
          disabledColor: isDark ? Colors.white24 : Colors.black26,
        ),
        IconButton(
          icon: const Icon(Icons.last_page, size: 20),
          tooltip: 'الصفحة الأخيرة',
          onPressed: _currentPage < totalPages
              ? () => setState(() => _currentPage = totalPages)
              : null,
          color: isDark ? Colors.white70 : const Color(0xFF475569),
          disabledColor: isDark ? Colors.white24 : Colors.black26,
        ),
      ],
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DataTable(
      headingRowColor: WidgetStatePropertyAll(
        isDark
            ? const Color(0xFF0EA5E9).withValues(alpha: 0.1)
            : const Color(0xFFF1F5F9),
      ),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.06 : 0.04);
        }
        return Colors.transparent;
      }),
      columnSpacing: 26,
      dataRowMinHeight: 46,
      dataRowMaxHeight: 64,
      columns: [
        DataColumn(
            label: Text('التاريخ',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
        DataColumn(
            label: Text(_isBranchVarianceView ? 'رقم الشحنة / الأمر' : 'رقم الشحنة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
        DataColumn(
            label: Text('العميل / المورد',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
        const DataColumn(
            label: Text('مركز التكلفة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary))),
        DataColumn(
            label: Text('البيان',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
        if (_isBranchVarianceView) ...[
          DataColumn(
              label: Text('التكلفة التقديرية',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          const DataColumn(
              label: Text('القيمة الفعلية',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
              numeric: true),
          DataColumn(
              label: Text('الفارق (%)',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          DataColumn(
              label: Text('ملاحظات / مستند',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A)))),
          DataColumn(
              label: Text('الحالة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A)))),
        ] else ...[
          DataColumn(
              label: Text('الكمية',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          DataColumn(
              label: Text('سعر الوحدة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          DataColumn(
              label: Text('سعر الصرف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          DataColumn(
              label: Text('الإجمالي بالعملة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
          DataColumn(
              label: Text('الإجمالي بالمصري',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A))),
              numeric: true),
        ],
      ],
      rows: rows.map((r) {
        final date = r['shipment_date']?.toString() ?? '';
        final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
        final rawQty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        final rawUnitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
        final totalInCurrency =
            (r['total_in_currency'] as num?)?.toDouble() ??
                (r['amount'] as num?)?.toDouble() ??
                0.0;
        
        double qty = rawQty;
        double unitPriceForeign = rawUnitPrice;
        if (unitPriceForeign <= 0 && qty.abs() > 0 && totalInCurrency != 0) {
          unitPriceForeign = (totalInCurrency / qty).abs();
        } else if (qty == 0 && unitPriceForeign > 0 && totalInCurrency != 0) {
          qty = totalInCurrency / unitPriceForeign;
        } else if (qty == 0 && unitPriceForeign <= 0 && totalInCurrency != 0) {
          qty = totalInCurrency < 0 ? -1.0 : 1.0;
          unitPriceForeign = totalInCurrency.abs();
        }

        final currCode = r['currency']?.toString();
        final currName = _getCurrencyName(currCode);

        // Branch Variance & Settlement Calculations
        final key = r['cost_item_id'] ?? r['id'] ?? r['packing_order_id'] ?? rows.indexOf(r);
        final estAmt = (r['expected_amount'] as num?)?.toDouble() ??
            (r['amount'] as num?)?.toDouble() ?? 0.0;
        final actualCtrl = _getItemActualCtrl(key, r);
        final notesCtrl = _getItemNotesCtrl(key, r);

        final actVal = double.tryParse(actualCtrl.text.replaceAll(',', '').trim()) ??
            (r['actual_amount'] as num?)?.toDouble() ??
            estAmt;
        final varianceAmt = actVal - estAmt;
        final variancePct = estAmt > 0 ? (varianceAmt / estAmt) * 100 : 0.0;
        final isSaving = varianceAmt < 0;
        final isOverrun = varianceAmt > 0;
        final varianceColor = isOverrun
            ? const Color(0xFFEF4444)
            : (isSaving ? const Color(0xFF10B981) : (isDark ? Colors.white60 : const Color(0xFF64748B)));

        final status = r['cost_status']?.toString();
        final isSettled = status == 'actual' || status == 'settled';
        final isModified = _modifiedItemKeys.contains(key);

        final isClosedRow = _selectedPartition == CostDetailsPartition.historical ||
            _isRowClosed(r);

        return DataRow(cells: [
          DataCell(Text(dateStr,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.white : const Color(0xFF334155)))),
          DataCell(_buildShipmentBadge(r)),
          DataCell(Text(_resolveCustomerSupplier(r),
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: (r['is_opening_balance'] == true ||
                          r['source_type'] == 'opening_balance' ||
                          r['is_sorting_sale'] == true ||
                          r['is_export_sale'] == true)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _resolveCustomerSupplierColor(r, isDark)))),
          DataCell(_buildCostCenterBadge(r)),
          DataCell(_buildDescriptionCell(r, isDark)),
          if (_isBranchVarianceView) ...[
            // 1. Estimated Cost
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'EGP ${NumberFormat('#,##0.00').format(estAmt)}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            // 2. Actual Value (Interactive TextFormField)
            DataCell(
              SizedBox(
                width: 130,
                height: 38,
                child: TextFormField(
                  controller: actualCtrl,
                  enabled: !isClosedRow,
                  readOnly: isClosedRow,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isClosedRow
                        ? (isDark ? Colors.white70 : const Color(0xFF475569))
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  ),
                  textAlign: TextAlign.end,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    prefixText: 'EGP ',
                    prefixStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: isClosedRow
                        ? (isDark ? const Color(0xFF0B192C) : const Color(0xFFF1F5F9))
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isModified
                            ? AppTheme.primary
                            : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _modifiedItemKeys.add(key);
                    });
                  },
                ),
              ),
            ),
            // 3. Variance & Percentage
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${varianceAmt >= 0 ? '+' : ''}${NumberFormat('#,##0.00').format(varianceAmt)}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: varianceColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: varianceColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${variancePct >= 0 ? '+' : ''}${variancePct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: varianceColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 4. Notes / Details / Invoice Ref (Interactive TextFormField)
            DataCell(
              SizedBox(
                width: 170,
                height: 38,
                child: TextFormField(
                  controller: notesCtrl,
                  enabled: !isClosedRow,
                  readOnly: isClosedRow,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    color: isClosedRow
                        ? (isDark ? Colors.white60 : const Color(0xFF64748B))
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    hintText: isClosedRow ? 'مقفل محاسبياً' : 'ملاحظات / مستند...',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: isClosedRow
                        ? (isDark ? const Color(0xFF0B192C) : const Color(0xFFF1F5F9))
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _modifiedItemKeys.add(key);
                    });
                  },
                ),
              ),
            ),
            // 5. Status Badge
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isModified
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                      : (isSettled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isModified
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                        : (isSettled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  isModified
                      ? 'معدل (بانتظار الحفظ)'
                      : (isSettled ? 'مسوى فعلياً' : 'قيد التسوية'),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isModified
                        ? const Color(0xFF3B82F6)
                        : (isSettled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                  ),
                ),
              ),
            ),
          ] else ...[
            DataCell(Text(_fmtNum(qty),
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
            DataCell(Text(
                '$currName ${_fmtNum(unitPriceForeign)}',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
            DataCell(Text(
                _fmtNum(r['exchange_rate'] ?? 1.0),
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white : const Color(0xFF0F172A)))),
            DataCell(Text(
                '$currName ${_fmtNum(totalInCurrency)}',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: (r['is_sorting_sale'] == true || r['is_export_sale'] == true || totalInCurrency < 0)
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: totalInCurrency < 0
                        ? const Color(0xFFEF4444)
                        : ((r['is_sorting_sale'] == true || r['is_export_sale'] == true)
                            ? const Color(0xFF10B981)
                            : (isDark ? Colors.white : const Color(0xFF0F172A)))))),
            DataCell(Text(_fmtNum(r['amount']),
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _resolveAmountColor(r)))),
          ],
        ]);
      }).toList(),
    );
  }

  Widget _buildSummaryBar(List<Map<String, dynamic>> displayRows) {
    double baselineOpeningBalance = 0.0;
    double operationalExpenses = 0.0;
    double redundantRolloverTotal = 0.0;

    for (final r in displayRows) {
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final srcId = r['source_id']?.toString() ?? '';
      final srcType = r['source_type']?.toString() ?? '';
      final item = (r['item_name']?.toString() ?? '').trim();

      // Defensive guard: skip non-positive remainder rollovers
      if (srcType == 'season_rollover' && (srcId.endsWith('_remainder') || item.contains('رصيد عام غير مخصص')) && amt <= 0) {
        continue;
      }

      final isRedundant = r['is_redundant_rollover'] == true;
      final isRollover = r['is_rollover'] == true ||
          r['source_type'] == 'season_rollover' ||
          r['transaction_type'] == 'carried_forward';
      final isOpening = r['is_opening_balance'] == true ||
          r['source_type'] == 'opening_balance' ||
          isRollover;

      if (isRedundant) {
        redundantRolloverTotal += amt;
      } else if (isOpening) {
        baselineOpeningBalance += amt;
      } else {
        operationalExpenses += amt;
      }
    }

    final netTotalCost = operationalExpenses;
    double displayOpening = redundantRolloverTotal > 0 ? redundantRolloverTotal : baselineOpeningBalance;
    if (displayOpening == 0.0 && _selectedPartition != CostDetailsPartition.historical) {
      final curCenter = _currentCostCenter;
      if (curCenter != null && curCenter.openingBalance > 0 && displayRows.any((r) => !_isRowClosed(r))) {
        displayOpening = curCenter.openingBalance;
      }
    }
    final totalLedgerBalance = displayOpening + operationalExpenses;

    // Count distinct (cost_center_id, item_name) pairs
    final distinctVarieties = displayRows
        .map((r) {
          final item = (r['item_name']?.toString() ?? '').trim();
          final ccId = (r['cost_center_id']?.toString() ?? '').trim();
          return ccId.isNotEmpty ? '$ccId||$item' : item;
        })
        .where((s) => s.isNotEmpty)
        .toSet()
        .length;

    // Currency totals breakdown (excluding redundant rollovers)
    final Map<String, double> currencyTotals = {};
    for (final r in displayRows) {
      if (r['is_redundant_rollover'] == true) continue;
      final cur = (r['currency']?.toString() ?? 'EGP').toUpperCase();
      final tot = (r['total_in_currency'] as num?)?.toDouble() ??
          (r['amount'] as num?)?.toDouble() ??
          0.0;
      currencyTotals[cur] = (currencyTotals[cur] ?? 0.0) + tot;
    }

    // Build companion foreign currency chips
    final List<Widget> foreignChips = [];
    currencyTotals.forEach((cur, amt) {
      if (cur != 'EGP' && amt != 0) {
        foreignChips.add(
          ForeignCurrencyChip(
            currency: cur,
            amount: amt,
          ),
        );
      }
    });

    final cards = <SummaryCardData>[
      // 1. Transactions Count
      SummaryCardData(
        id: 'transactions_count',
        title: 'المعاملات',
        customFormattedValue: '${displayRows.length}',
        icon: Icons.receipt_long_rounded,
        cardType: SummaryCardType.neutral,
        tooltip: 'إجمالي عدد الحركات والقيود المسجلة تحت هذا الصنف أو مركز التكلفة.',
      ),

      // 2. Distinct Varieties
      if (distinctVarieties > 1)
        SummaryCardData(
          id: 'varieties_count',
          title: 'الأصناف',
          customFormattedValue: '$distinctVarieties',
          icon: Icons.category_rounded,
          cardType: SummaryCardType.info,
          tooltip: 'عدد أصناف الفاكهة المختلفة المدرجة ضمن التكاليف المعروضة.',
        ),

      // 3. Opening Baseline / Rollover Balance
      if (displayOpening != 0.0)
        SummaryCardData(
          id: 'opening_balance',
          title: redundantRolloverTotal > 0 ? 'رصيد مرحل من الفترة الأولى' : 'رصيد مرحل / أساس',
          value: displayOpening,
          currency: 'EGP',
          icon: Icons.history_edu_rounded,
          cardType: SummaryCardType.warning,
          tooltip: redundantRolloverTotal > 0
              ? 'صافي رصيد التكاليف المنقول والمعتمد من الفترة الأولى داخل نفس الكارت.'
              : 'رصيد التكاليف المنقول من المواسم السابقة أو الرصيد الافتتاحي المعتمد لمركز التكلفة.',
        ),

      // 4. Net Operational Movements
      if (operationalExpenses != 0.0 && displayOpening != 0.0)
        SummaryCardData(
          id: 'operational_movements',
          title: 'صافي الحركات',
          value: operationalExpenses,
          currency: 'EGP',
          icon: Icons.swap_horiz_rounded,
          cardType: SummaryCardType.info,
          tooltip: 'مجموع قيود وحركات التشغيل المباشرة للموسم الحالي (المحاصيل + مواد التعبئة + الهالك - المردودات والفرز).',
        ),

      // 5. Foreign Currency totals if selected or available
      if (_selectedCurrency != null && _selectedCurrency != 'EGP')
        SummaryCardData(
          id: 'selected_foreign_currency',
          title: 'إجمالي بالـ$_selectedCurrency',
          value: currencyTotals[_selectedCurrency!.toUpperCase()] ?? 0.0,
          currency: _selectedCurrency == 'USD'
              ? '\$'
              : _selectedCurrency == 'EUR'
                  ? '€'
                  : _selectedCurrency == 'GBP'
                      ? '£'
                      : _selectedCurrency!,
          icon: Icons.monetization_on_rounded,
          cardType: SummaryCardType.currency,
          tooltip: 'إجمالي التكاليف المسجلة بعملة $_selectedCurrency حسب حركات أمر التعبئة والشحنة.',
        )
      else if (foreignChips.isNotEmpty)
        SummaryCardData(
          id: 'foreign_currencies',
          title: 'العملات الأجنبية',
          customFormattedValue: '',
          icon: Icons.payments_rounded,
          cardType: SummaryCardType.currency,
          companionWidgets: foreignChips,
          tooltip: 'إجمالي الحركات المسجلة بالعملات الأجنبية (مثل الدولار واليورو).',
        ),

      // 6. Net Operating Expenses (The Primary Card)
      SummaryCardData(
        id: 'net_operating_expenses',
        title: _selectedCurrency != null && _selectedCurrency != 'EGP'
            ? 'المعادل بالمصري'
            : 'صافي مصاريف التشغيل',
        value: netTotalCost,
        currency: 'EGP',
        icon: Icons.account_balance_wallet_rounded,
        cardType: SummaryCardType.auto,
        isPrimary: true,
        subtitle: displayOpening != 0.0 ? '(الدفتري: EGP ${_fmt(totalLedgerBalance)})' : null,
        tooltip: 'صافي مصاريف التشغيل المباشرة للموسم الحالي = التكاليف التشغيلية الفعلية للصنف.\n'
            'الإجمالي الدفتري = صافي مصاريف التشغيل + الرصيد المرحل / الأساس.',
      ),
    ];

    return EnhancedSummaryBar(
      storageKey: 'cost_details_report',
      cards: cards,
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return n.toStringAsFixed(2);
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  String _getCurrencyName(String? code) {
    if (code == null) return 'EGP';
    switch (code.toUpperCase()) {
      case 'USD':
        return 'USD';
      case 'EUR':
        return 'EURO';
      case 'GBP':
        return 'GBP';
      case 'EGP':
        return 'EGP';
      default:
        return code;
    }
  }
}
