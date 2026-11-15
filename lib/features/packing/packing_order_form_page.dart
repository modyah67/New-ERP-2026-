import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:excel/excel.dart' hide Border;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/packing_order_sorting_dao.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/services/packing_cost_allocation_engine.dart';
import '../../data/services/packing_calculation_service.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/packing_order_line_model.dart';
import '../../data/models/packing_order_sorting_model.dart';
import '../../data/models/lot_model.dart';
import 'utils/packing_excel_exporter.dart';
import '../../data/models/station_model.dart';
import '../../data/models/station_product_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/station_product_batch.dart';
import '../../data/models/transport_batch_model.dart';
import '../../core/data_change_event_bus.dart';
import 'packing_order_pdf_service.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../data/models/cost_center.dart';
import '../../data/models/packing_cost_variance_model.dart';
import '../../data/services/packing_cost_variance_service.dart';
import '../../data/services/cost_category_service.dart';
import 'widgets/cost_item_category_dropdown.dart';
import '../../data/models/account_model.dart';
import '../../data/dao/account_dao.dart';
import '../accounts/widgets/account_journal_entries_dialog.dart';
import '../station_suppliers/supplier_cost_settlement_view.dart';
import '../../core/router.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/services/custody_service.dart';

class _LotEntry {
  String? lineId;
  StationProductBatch? batch;
  LotReceiptModel? lot;
  String? fallbackProductName;
  bool hasSorting = false;
  bool usePartialCrop = false;
  bool initialHasSorting = false;
  bool initialUsePartialCrop = false;
  double overrideCostPerKg = 0;
  double overrideCostPerCarton = 0;
  final partialWeightCtrl = TextEditingController();
  final sortedWeightCtrl = TextEditingController();
  final cartonCountCtrl = TextEditingController();
  final netWeightPerCartonCtrl = TextEditingController();
  final grossWeightPerCartonCtrl = TextEditingController();
  final wastePercentCtrl = TextEditingController();

  bool get isCartonMode => lot?.purchaseMode == 'carton';

  int get totalCartonsFromLot => lot?.cartonCount ?? 0;

  int get sortingCartons => isCartonMode
      ? ((double.tryParse(sortedWeightCtrl.text) ?? 0).round())
      : 0;
  int get retailCartons => isCartonMode
      ? ((double.tryParse(partialWeightCtrl.text) ?? 0).round())
      : 0;

  int get netCartonCount {
    if (!isCartonMode) return 0;
    final base = usePartialCrop && retailCartons > 0
        ? retailCartons
        : totalCartonsFromLot;
    return (base - sortingCartons).clamp(0, base);
  }

  void updateCartonCountFromDeductions() {
    if (isCartonMode) {
      final net = netCartonCount;
      if (cartonCountCtrl.text != net.toString()) {
        cartonCountCtrl.text = net.toString();
      }
    }
  }

  double get wastePercent =>
      double.tryParse(wastePercentCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
  set wastePercent(double val) {
    if (val > 0) {
      final formatted = val % 1 == 0 ? val.toInt().toString() : val.toString();
      if (wastePercentCtrl.text != formatted) {
        wastePercentCtrl.text = formatted;
      }
    } else {
      if (wastePercentCtrl.text.isNotEmpty) {
        wastePercentCtrl.clear();
      }
    }
  }

  double get grossWeight => batch?.remainingQuantity ?? lot?.grossWeightKg ?? 0;
  double get _partialWeight => double.tryParse(partialWeightCtrl.text) ?? 0;
  double get effectiveWeight {
    if (isCartonMode) {
      return usePartialCrop
          ? (retailCartons > 0 ? retailCartons.toDouble() : 0.0)
          : totalCartonsFromLot.toDouble();
    }
    return usePartialCrop
        ? (_partialWeight > 0 ? _partialWeight : 0.0)
        : grossWeight;
  }

  double get wasteWeight =>
      wastePercent > 0 ? effectiveWeight * (wastePercent / 100.0) : 0.0;

  bool get hasWaste => wasteCost > 0;
  double get netWeight => effectiveWeight;
  double get sortedWeight => isCartonMode
      ? sortingCartons.toDouble()
      : (hasSorting ? (double.tryParse(sortedWeightCtrl.text) ?? 0) : 0.0);

  int get cartonCount => int.tryParse(cartonCountCtrl.text) ?? 0;
  double get netWeightPerCartonValue =>
      double.tryParse(netWeightPerCartonCtrl.text) ?? 0;
  double get grossWeightPerCartonValue =>
      double.tryParse(grossWeightPerCartonCtrl.text) ?? 0;

  double? _exactNetWeightPerCarton;

  /// القيمة الدقيقة لوزن الكرتونة الصافي المستخدمة في الحسابات الداخلية
  double get exactCartonNetWeight {
    if (isCartonMode) return netWeightPerCartonValue;
    if (_exactNetWeightPerCarton != null && _exactNetWeightPerCarton! > 0) {
      return _exactNetWeightPerCarton!;
    }
    if (cartonCount > 0 && availableWeight > 0) {
      return availableWeight / cartonCount;
    }
    return netWeightPerCartonValue;
  }

  double get rawCartonWeight => cartonCount * exactCartonNetWeight;

  double get totalNetWeight => cartonCount * exactCartonNetWeight;
  double get totalGrossWeight => cartonCount * grossWeightPerCartonValue;

  double get originalCurrencyTotalCost {
    final rate = lot?.exchangeRate ?? 1.0;
    if (rate > 0) {
      return totalPurchaseCost / rate;
    }
    return totalPurchaseCost;
  }

  double get _costPerCarton {
    if (isCartonMode) {
      final rate = lot?.exchangeRate ?? 1.0;
      if (overrideCostPerCarton > 0) return overrideCostPerCarton * rate;
      if (batch != null && batch!.unitCost > 0) {
        return batch!.unitCost * rate;
      }
      final lotPrice = lot?.pricePerCarton;
      if (lotPrice != null && lotPrice > 0) return lotPrice * rate;
      return productCostPerKg * exactCartonNetWeight;
    }
    return 0;
  }

  double get costPerUnit => isCartonMode ? _costPerCarton : productCostPerKg;
  double get productCostPerKg {
    final rate = lot?.exchangeRate ?? 1.0;
    if (overrideCostPerKg > 0) return overrideCostPerKg * rate;
    if (batch != null && batch!.unitCost > 0) return batch!.unitCost * rate;
    return (lot?.productCostPerKg ?? 0) * rate;
  }

  double get totalPurchaseCost {
    if (isCartonMode) return effectiveWeight * _costPerCarton;
    return productCostPerKg * effectiveWeight;
  }

  double get wasteCost => totalPurchaseCost * (wastePercent / 100.0);
  double get sortingCost =>
      isCartonMode ? sortedWeight * _costPerCarton : sortedWeight * productCostPerKg;
  double get totalCostAfterAdjustments => totalPurchaseCost - sortingCost;
  double get availableWeight {
    if (isCartonMode) return netWeight;
    return (netWeight - wasteWeight - sortedWeight).clamp(0.0, double.infinity);
  }

  double get adjustedCostPerKg => availableWeight > 0
      ? totalCostAfterAdjustments / availableWeight
      : productCostPerKg;
  double get fruitCost => adjustedCostPerKg * availableWeight;

  bool get isValid =>
      lot != null && cartonCount > 0 && exactCartonNetWeight > 0;
  bool get isCartonWeightMismatch {
    if (lot == null || cartonCount == 0 || exactCartonNetWeight == 0) {
      return false;
    }
    if (isCartonMode) {
      return (cartonCount + sortingCartons) > effectiveWeight + 0.01;
    }
    final totalAllocated =
        totalNetWeight + (hasSorting ? sortedWeight : 0.0) + wasteWeight;
    return (totalAllocated - effectiveWeight).abs() > 0.01;
  }

  void autoCalculateNetWeightPerCarton() {
    if (isCartonMode) return;
    final count = cartonCount;
    if (count <= 0) {
      _exactNetWeightPerCarton = null;
      return;
    }
    final avail = availableWeight;
    if (avail <= 0) {
      _exactNetWeightPerCarton = null;
      return;
    }

    final calculated = avail / count;
    _exactNetWeightPerCarton = calculated;

    String formatted;
    if (calculated == calculated.roundToDouble()) {
      formatted = calculated.toInt().toString();
    } else {
      final fixed3 = double.parse(calculated.toStringAsFixed(3));
      if ((fixed3 * count - avail).abs() < 0.001) {
        formatted = calculated.toStringAsFixed(3);
      } else {
        formatted = calculated.toStringAsFixed(2);
      }
      if (formatted.contains('.')) {
        formatted = formatted.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }
    }
    if (netWeightPerCartonCtrl.text != formatted) {
      netWeightPerCartonCtrl.text = formatted;
    }
  }

  void dispose() {
    partialWeightCtrl.dispose();
    sortedWeightCtrl.dispose();
    cartonCountCtrl.dispose();
    netWeightPerCartonCtrl.dispose();
    grossWeightPerCartonCtrl.dispose();
    wastePercentCtrl.dispose();
  }
}

class PackingOrderFormPage extends StatefulWidget {
  final PackingOrderModel? existingOrder;
  final bool viewOnly;
  const PackingOrderFormPage(
      {super.key, this.existingOrder, this.viewOnly = false});

  @override
  State<PackingOrderFormPage> createState() => _PackingOrderFormPageState();
}

class _PackingOrderFormPageState extends State<PackingOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _dao = PackingOrderDao();
  final _packingOrderDao = PackingOrderDao();
  final _lotDao = LotDao();
  final _stationDao = StationDao();
  final _stationProductDao = StationProductDao();
  final _sortingDao = PackingOrderSortingDao();
  final _rawMaterialDao = RawMaterialDao();

  List<StationModel> _stations = [];
  List<LotReceiptModel> _allLots = [];
  List<LotReceiptModel> _filteredLots = [];
  List<SupplierModel> _suppliers = [];
  List<TransportSupplierModel> _transportSuppliers = [];
  List<StationProductBatch> _availableBatches = [];
  Map<int, double> _batchBaseRemaining = {};
  Map<String, double> _lotRemainingQuantities = {};
  List<Map<String, dynamic>> _costCategories = [];
  List<CostCenter> _costCenters = [];
  List<Map<String, dynamic>> _expenseAccounts = [];

  int? _selectedStationId;
  Set<int> _selectedStationIds = {};
  bool _isAllStations = false;
  String _stationSearchQuery = '';

  int _getStationKey(StationModel s) {
    return int.tryParse(s.id ?? '') ?? s.id.hashCode.abs();
  }

  String _getStationName(dynamic stId) {
    if (stId == null) return '';
    final match = _stations.where((s) => s.id == stId.toString() || _getStationKey(s) == stId).firstOrNull;
    return match?.name ?? 'مخزن #$stId';
  }

  Future<void> _onWarehouseScopeChanged() async {
    _filterLotsFromCache();
    if (mounted) setState(() {});
    await Future.wait([
      _loadMaterialProducts(_selectedStationId),
      _fetchLotRemainingQuantities(_selectedStationId),
    ]);
    if (mounted) setState(() {});
  }

  bool _loading = true;
  bool _saving = false;
  PackingCostVarianceReport? _varianceReport;
  bool _loadingVariance = false;

  final Map<int, TextEditingController> _adminActualControllers = {};
  final Set<int> _adminSettlingIds = {};
  final Set<int> _adminForceEditingIds = {};

  TextEditingController _getAdminActualController(int costId, double defaultEst) {
    if (!_adminActualControllers.containsKey(costId)) {
      _adminActualControllers[costId] = TextEditingController(
        text: defaultEst > 0 ? defaultEst.toStringAsFixed(2) : '',
      );
    }
    return _adminActualControllers[costId]!;
  }

  Future<void> _loadVarianceReport([PackingOrderModel? targetOrder, List<PackingOrderLineModel>? customLines]) async {
    final ord = targetOrder ?? _currentOrder ?? widget.existingOrder;
    if (ord == null) return;
    if (mounted) setState(() => _loadingVariance = true);
    try {
      final rep = await PackingCostVarianceService.generateReport(
        ord,
        lines: customLines ?? (ord.lines.isNotEmpty ? ord.lines : null),
      );
      if (mounted) setState(() => _varianceReport = rep);
    } catch (e) {
      debugPrint('Error loading packing cost variance: $e');
    } finally {
      if (mounted) setState(() => _loadingVariance = false);
    }
  }

  /// التنقل (Navigator.push) إلى شاشة تفاصيل وتسوية الحساب المحاسبي المحدد
  Future<void> _navigateToAccountSettlement({
    String accountCode = '31331',
    PackingCostItemComparison? item,
  }) async {
    try {
      // 1. استعلام الحساب المحاسبي المحدد (افتراضياً 31331 للمصاريف الإدارية والعمومية)
      AccountModel? targetAccount = await AccountDao().getByCode(accountCode);
      if (targetAccount == null) {
        final all = await AccountDao().getAll();
        targetAccount = all.firstWhere(
          (a) => a.code == accountCode || a.name.contains('مصاريف إدارية') || a.name.contains('اداري'),
          orElse: () => AccountModel(
            id: '31331',
            code: accountCode,
            name: 'مصاريف إدارية وعمومية',
            type: 'Expense',
            
            isActive: true,
          ),
        );
      }

      if (!mounted) return;

      // 2. الانتقال (Navigator.push) إلى شاشة تفاصيل وتسوية الحساب مع فتح تبويب التسوية وتصفية الحساب
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.black54,
            body: AccountJournalEntriesDialog(
              account: targetAccount!,
              allBranchAccounts: [targetAccount],
              isBranch: false,
              initialTabIndex: 1, // فتح تبويب تسوية التكاليف مباشرة
              initialSearchQuery: _currentOrder?.orderNumber ?? widget.existingOrder?.orderNumber ?? '',
            ),
          ),
        ),
      );

      // 3. فور العودة من شاشة التسوية، إعادة تحميل تقرير الانحراف وعكس الأثر الفعلي المعتمد
      if (mounted) {
        await _loadVarianceReport();
      }
    } catch (e) {
      debugPrint('Error navigating to account settlement: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الانتقال لشاشة تسوية الحساب: $e', textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  /// التنقل إلى شاشة تسوية مستحقات المورد (مورد محطة أو مورد تخصيمات)
  Future<void> _navigateToSupplierSettlement({
    required String supplierType, // 'station' or 'deduction'
    PackingCostItemComparison? item,
  }) async {
    try {
      final suppId = item?.sourceId;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final isStation = supplierType == 'station';
            final title = isStation
                ? 'تسوية مستحقات موردين المحطات'
                : 'تسوية مستحقات موردين التخصيمات';
            return Scaffold(
              backgroundColor: isDark ? const Color(0xFF07213D) : const Color(0xFFF8FAFC),
              appBar: AppBar(
                title: Text(title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                centerTitle: true,
                elevation: 1,
              ),
              body: SupplierCostSettlementView(
                supplierType: supplierType,
                preselectedSupplierId: suppId,
              ),
            );
          },
        ),
      );
      if (mounted) {
        await _loadVarianceReport();
      }
    } catch (e) {
      debugPrint('Error navigating to supplier settlement: $e');
      if (mounted) {
        context.push(supplierType == 'station' ? RoutePaths.stationSuppliers : RoutePaths.deductionsSuppliers);
      }
    }
  }

  Future<void> _settleCostItemRow(
    PackingCostItemComparison item,
    int? costId,
  ) async {
    final ordId = int.tryParse(_currentOrder?.id ?? widget.existingOrder?.id ?? '');
    if (ordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد معرّف أمر التعبئة', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final ctrl = _getAdminActualController(costId ?? item.name.hashCode, item.estimatedCost);
    final textVal = ctrl.text.trim();
    final enteredActual = double.tryParse(textVal);

    if (enteredActual == null || enteredActual < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال قيمة صحيحة للتكلفة الفعلية', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final diff = enteredActual - item.estimatedCost;

    final name = item.name;
    final category = item.category;
    final suppName = item.supplierName;

    final bool isAdmin = category == 'admin' || name == 'مصاريف إدارية' || name.contains('إدار') || name.contains('ادار');
    final bool isStation = category == 'station' || name.contains('محطة') || (suppName != null && suppName.contains('محطة'));
    final bool isDeduction = category == 'deduction' || name.contains('تخصيم') || (suppName != null && suppName.contains('تخصيم'));
    final bool isTransport = category == 'logistics' || category == 'transport' || name.contains('نقل') || name.contains('شحن');
    final bool isEngineer = category == 'engineer' || category == 'engineer_expenses' || name.contains('مهندس') || (suppName != null && suppName.contains('مهندس'));

    String title = 'تأكيد تسوية التكلفة الفعلية';
    IconData icon = Icons.check_circle_outline;
    Color color = AppTheme.primary;

    if (isStation) {
      title = 'تأكيد تسوية مورد المحطة';
      icon = Icons.domain_verification_outlined;
      color = const Color(0xFF0D9488);
    } else if (isDeduction) {
      title = 'تأكيد تسوية مورد التخصيمات';
      icon = Icons.fact_check_outlined;
      color = const Color(0xFF6366F1);
    } else if (isAdmin) {
      title = 'تأكيد تسوية المصاريف الإدارية';
      icon = Icons.admin_panel_settings_outlined;
      color = const Color(0xFF8B5CF6);
    } else if (isTransport) {
      title = 'تأكيد تسوية مصاريف النقل';
      icon = Icons.local_shipping_outlined;
      color = const Color(0xFF2563EB);
    } else if (isEngineer) {
      title = 'تأكيد تسوية مصاريف المهندسين';
      icon = Icons.engineering_outlined;
      color = const Color(0xFFF59E0B);
    }

    // Confirm settlement dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF07213D) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'البند: ${item.name}${suppName != null && suppName.isNotEmpty && suppName != item.name ? " ($suppName)" : ""}',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (!isTransport) ...[
                Text(
                  'التكلفة التقديرية: ${item.estimatedCost.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
              ] else ...[
                const Text(
                  'التكلفة التقديرية: — (فعلي فقط)',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
              Text(
                'التكلفة الفعلية المدخلة: ${enteredActual.toStringAsFixed(2)} ج.م',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              if (!isTransport)
                Text(
                  'فرق التكلفة: ${diff > 0 ? "+" : ""}${diff.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: diff > 0 ? const Color(0xFFF97316) : (diff < 0 ? AppTheme.accent : AppTheme.textSecondary),
                  ),
                ),
              if (isEngineer) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B).withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          diff > 0
                              ? 'سيتم خصم الفارق (${diff.toStringAsFixed(2)} ج.م) إضافياً من عهدة المهندس.'
                              : (diff < 0
                                  ? 'سيتم رد الوفر (${diff.abs().toStringAsFixed(2)} ج.م) إلى رصيد عهدة المهندس.'
                                  : 'التكلفة الفعلية مطابقة للتقديرية تماماً دون تعديل على رصيد العهدة.'),
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'سيتم ترحيل قيد التسوية المحاسبي وتحديث تكلفة كرتونة التعبئة وربحية الشحنات المرتبطة تلقائياً.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('تأكيد التسوية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final trackingId = costId ?? item.name.hashCode;
    setState(() {
      _adminSettlingIds.add(trackingId);
    });

    try {
      int? effectiveCostId = (costId != null && costId != item.name.hashCode) ? costId : item.costItemId;
      if (effectiveCostId == null) {
        final found = await Supabase.instance.client
            .from('packing_order_cost_items')
            .select('id')
            .eq('packing_order_id', ordId)
            .ilike('name', '%${item.name}%')
            .limit(1)
            .maybeSingle();
        if (found != null && found['id'] != null) {
          effectiveCostId = found['id'] as int;
        } else {
          int? custId;
          if (isEngineer) {
            try {
              final defaultEmpTreasury = await Supabase.instance.client
                  .from('treasuries')
                  .select('id')
                  .inFilter('type', ['employee', 'custody'])
                  .limit(1)
                  .maybeSingle();
              if (defaultEmpTreasury != null) {
                custId = (defaultEmpTreasury['id'] as num?)?.toInt();
              }
            } catch (_) {}
          }

          final insRes = await Supabase.instance.client.from('packing_order_cost_items').insert({
            'packing_order_id': ordId,
            'name': item.name,
            'category': isStation ? 'station' : (isDeduction ? 'deduction' : (isTransport ? 'logistics' : (isAdmin ? 'admin' : (isEngineer ? 'engineer_expenses' : item.category)))),
            'base_amount': isTransport ? 0.0 : item.estimatedCost,
            'original_amount': isTransport ? 0.0 : item.estimatedCost,
            'expected_amount': isTransport ? 0.0 : item.estimatedCost,
            'cost_status': 'expected',
            'allocation_method': 'BY_NET_WEIGHT',
            if (isEngineer && custId != null) 'custody_id': custId,
            if (isEngineer) 'engineer_name': item.supplierName ?? item.name,
            'currency_snapshot': {
              'supplier_name': item.supplierName ?? item.name,
              'supplier_type': isStation ? 'station' : (isDeduction ? 'deduction' : (isTransport ? 'transport' : (isAdmin ? 'admin' : (isEngineer ? 'engineer' : 'general')))),
              if (isEngineer && custId != null) 'custody_id': custId,
              if (isEngineer) 'engineer_name': item.supplierName ?? item.name,
              'notes': 'بند تكلفة تسوية',
            },
          }).select('id').single();
          effectiveCostId = insRes['id'] as int;
        }
      }

      final shipNo = _exportShipmentNoCtrl.text.trim().isNotEmpty
          ? _exportShipmentNoCtrl.text.trim()
          : (_currentOrder?.exportShipmentNo?.trim() ?? widget.existingOrder?.exportShipmentNo?.trim() ?? '');
      final defaultInvRef = shipNo.isNotEmpty ? shipNo : 'تسوية تكلفة فعلية ($name)';

      final res = await _dao.settleCostVariancesBatch(
        packingOrderId: ordId,
        settlements: [
          {
            'cost_item_id': effectiveCostId,
            'actual_amount': enteredActual,
            'invoice_ref': defaultInvRef,
            'notes': 'تسوية من جدول مقارنة التكاليف التفصيلي${shipNo.isNotEmpty ? ' - شحنة $shipNo' : ''}',
          }
        ],
      );

      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'فشلت عملية التسوية');
      }

      _adminForceEditingIds.remove(trackingId);
      _adminForceEditingIds.remove(effectiveCostId);
      if (costId != null) _adminForceEditingIds.remove(costId);
      if (item.costItemId != null) _adminForceEditingIds.remove(item.costItemId);
      _adminForceEditingIds.remove(item.name.hashCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت تسوية ${item.name} وتحديث تكلفة الكرتونة وربحية الشحنة بنجاح ✓',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.success,
          ),
        );

        final reloadedOrder = await _dao.getById(ordId);
        if (reloadedOrder != null && mounted) {
          setState(() {
            _currentOrder = reloadedOrder;
          });
        }
        await _loadVarianceReport(reloadedOrder);
      }
    } catch (e) {
      debugPrint('Error settling cost item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تسوية التكلفة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _adminSettlingIds.remove(trackingId);
        });
      }
    }
  }

  // Alias for backward compatibility if any callers remain
  Future<void> _settleAdminExpensesRow(PackingCostItemComparison item, int? costId) =>
      _settleCostItemRow(item, costId);


  List<StationProductModel> _warehouseProducts = [];
  List<StationProductModel> _materialProducts = [];

  double _getRemainingMaterialQty(StationProductModel p,
      {String? excludeProductCode}) {
    double used = 0;
    for (final item in _materialItems) {
      if (item['product_code'] == p.productCode &&
          item['product_code'] != excludeProductCode) {
        used += (item['used_qty'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return p.quantity - used;
  }

  /// Returns the base available quantity of a batch before any consumption in the current order form.
  double _getBatchBaseAvailable(StationProductBatch batch) {
    final bId = batch.id;
    if (bId == null) return batch.remainingQuantity;
    return _batchBaseRemaining[bId] ?? batch.remainingQuantity;
  }

  /// Returns the remaining available quantity of a batch for a specific [_LotEntry].
  /// Takes into account quantities consumed in other entries of the current order.
  double _getBatchRemainingForEntry(StationProductBatch batch, _LotEntry forEntry) {
    final bId = batch.id;
    if (bId == null) return 0.0;
    final baseAvail = _getBatchBaseAvailable(batch);
    double consumedElsewhere = 0.0;
    for (final e in _lotEntries) {
      if (!identical(e, forEntry) && e.batch?.id == bId) {
        consumedElsewhere += e.effectiveWeight;
      }
    }
    final rem = baseAvail - consumedElsewhere;
    return rem > 0.0 ? rem : 0.0;
  }

  /// Returns total remaining quantity of a batch across all entries in the current order form.
  double _getBatchTotalRemaining(StationProductBatch batch) {
    final bId = batch.id;
    if (bId == null) return 0.0;
    final baseAvail = _getBatchBaseAvailable(batch);
    double totalConsumed = 0.0;
    for (final e in _lotEntries) {
      if (e.batch?.id == bId) {
        totalConsumed += e.effectiveWeight;
      }
    }
    final rem = baseAvail - totalConsumed;
    return rem > 0.0 ? rem : 0.0;
  }

  List<Map<String, dynamic>> _treasuries = [];
  final Map<String, Map<String, dynamic>> _custodyBalancesMap = {};
  List<Map<String, dynamic>> _bankAccounts = [];
  final List<Map<String, dynamic>> _materialItems = [];
  final List<Map<String, dynamic>> _costItems = [];
  bool _isConfirmingCosts = false;
  final List<_LotEntry> _lotEntries = [_LotEntry()];
  final _materialWastePercentCtrl = TextEditingController();
  final _exportShipmentNoCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  List<Map<String, dynamic>> _recentExportShipments = [];
  List<String> _knownCustomerNames = [];

  double _settledMaterialWasteCost = 0.0;
  List<Map<String, dynamic>> _wasteSettlements = [];
  bool _loadingWasteSettlements = false;
  double _returnPackagingWasteCost = 0.0;
  int _returnDamagedCartons = 0;
  List<Map<String, dynamic>> _returnWasteDetails = [];
  bool _isWasteSettled = false;

  bool get isWasteSettled {
    if (_isWasteSettled) return true;
    if (_wasteSettlements.isNotEmpty) return true;
    if (_settledMaterialWasteCost > 0.001) return true;
    final totalWaste = _isRollingWasteMode ? _cumulativePendingWastePool : _currentOrderCalculatedWaste;
    if (totalWaste > 0.001 && _unsettledMaterialWasteCost <= 0.001) {
      return true;
    }
    return false;
  }

  // ─── Seasonal opening cumulative waste balance (رصيد الهالك التراكمي للموسم) ───
  /// Season start month (1 = January → calendar-year season).
  /// Change to e.g. 7 for a July→June agricultural season.
  static const int _kWasteSeasonStartMonth = 1;
  bool _loadingSeasonalWaste = false;
  bool _seasonalWasteLoaded = false;
  double _seasonalOpeningWasteBalance = 0.0;
  double _seasonalReturnWasteTotal = 0.0;
  double _seasonalSettledByOthers = 0.0;
  int _seasonalDamagedCartons = 0;
  int _seasonalReturnsCount = 0;
  DateTime? _seasonStart;
  DateTime? _seasonEnd;

  PackingOrderModel? _currentOrder;
  bool _stageLoading = false;
  StreamSubscription<void>? _suppliersSub;
  StreamSubscription<void>? _transportSuppliersSub;
  StreamSubscription<void>? _packingOrdersSub;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.existingOrder;
    // Load the season-level cumulative waste balance immediately so it is
    // visible before the accountant enters any waste percentage.
    _loadSeasonalWasteBalance();
    _loadData();

    _suppliersSub = DataChangeEventBus.instance.suppliersStream.listen((_) {
      if (mounted && _orderId != null) {
        _refreshCurrentOrder();
      }
    });
    _transportSuppliersSub = DataChangeEventBus.instance.transportSuppliersStream.listen((_) {
      if (mounted && _orderId != null) {
        _refreshCurrentOrder();
      }
    });
    _packingOrdersSub = DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      if (mounted && _orderId != null) {
        _refreshCurrentOrder();
      }
    });
  }

  bool get _isEditing => _currentOrder != null || widget.existingOrder != null;
  bool get _isViewOnly => widget.viewOnly;
  int? get _orderId {
    final ordId = _currentOrder?.id ?? widget.existingOrder?.id;
    return ordId != null ? int.tryParse(ordId) : null;
  }

  // Granular stage statuses:
  bool get _isCropsConfirmed =>
      _currentOrder?.isCropsConfirmed ?? (widget.existingOrder?.isCropsConfirmed ?? false);
  bool get _isPackagingConfirmed =>
      _currentOrder?.isPackagingConfirmed ?? (widget.existingOrder?.isPackagingConfirmed ?? false);
  bool get _isCostsConfirmed =>
      _currentOrder?.isCostsConfirmed ?? (widget.existingOrder?.isCostsConfirmed ?? false);
  bool get _isFinalApproved =>
      _currentOrder?.isFinalApproved ?? (widget.existingOrder?.isFinalApproved ?? false);

  bool get _isOrderFinalized =>
      _isViewOnly ||
      _isFinalApproved ||
      _currentOrder?.status == 'completed' ||
      _currentOrder?.status == 'final_approved' ||
      widget.existingOrder?.status == 'completed' ||
      widget.existingOrder?.status == 'final_approved';

  bool get _isCropsLocked => _isCropsConfirmed || _isOrderFinalized;
  /// Allows continuous adding, editing and viewing of packaging materials until the order is finalized/completed.
  bool get _isPackagingLocked => _isOrderFinalized;
  /// Allows continuous adding and editing of cost items as long as the order is not finalized/completed.
  bool get _isCostsLocked => _isOrderFinalized;
  bool get _isEntireOrderLocked => _isOrderFinalized;

  bool get _isConfirmed =>
      _isFinalApproved ||
      ((_currentOrder?.journalEntryId ?? widget.existingOrder?.journalEntryId) != null);
  bool get _stockFieldsLocked => _isCropsConfirmed || _isOrderFinalized;

  /// True if the packing order itself has been posted or finalized
  /// (stage confirmed, completed, journal entries generated, etc.)
  bool get isOrderPosted {
    if (_isFinalApproved || _isOrderFinalized) return true;
    final ord = _currentOrder ?? widget.existingOrder;
    if (ord == null) return false;
    final status = ord.status.toLowerCase();
    if (status == 'completed' ||
        status == 'final_approved' ||
        status == 'confirmed' ||
        status == 'posted') {
      return true;
    }
    // Check if any stage or main journal entry exists
    final je = ord.journalEntryId;
    if (je != null && je.isNotEmpty && je != '0') return true;
    final pkgJe = ord.packagingJournalEntryId;
    if (pkgJe != null && pkgJe.isNotEmpty && pkgJe != '0') return true;
    final costsJe = ord.costsJournalEntryId;
    if (costsJe != null && costsJe.isNotEmpty && costsJe != '0') return true;
    final cropsJe = ord.cropsJournalEntryId;
    if (cropsJe != null && cropsJe.isNotEmpty && cropsJe != '0') return true;

    // Check confirmed stages
    if (ord.isPackagingConfirmed || ord.isCostsConfirmed || ord.isFinalApproved) {
      return true;
    }
    if (_isPackagingConfirmed || _isCostsConfirmed || _isConfirmed) {
      return true;
    }
    return false;
  }

  /// Shorthand aliases to support the compound rule `isSettled || isPosted`
  bool get isPosted => isOrderPosted;
  bool get isSettled => isWasteSettled;
  bool get isSettledOrPosted => isSettled || isPosted;

  String _formatStageDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshCurrentOrder() async {
    final id = _orderId;
    if (id == null) return;
    try {
      final updated = await _dao.getById(id);
      final freshCostItems = await _dao.getCostItemsRaw(id);
      if (updated != null && mounted) {
        setState(() {
          _currentOrder = updated;
          if (freshCostItems.isNotEmpty) {
            _costItems.clear();
            final Map<String, Map<String, dynamic>> dedupMap = {};
            for (final item in freshCostItems) {
              final amt = (item['total_egp'] ?? item['total'] ?? item['base_amount'] ?? 0) as num;
              if (amt <= 0) continue; // Skip zero-amount / deleted ghost rows
              if (item['item_uuid'] == null || item['item_uuid'].toString().trim().isEmpty) {
                final rawId = (item['id'] as num?)?.toInt();
                item['item_uuid'] = (rawId != null && rawId > 0) ? 'item_$rawId' : const Uuid().v4();
              }
              final rawId = (item['id'] as num?)?.toInt();
              final sig = (rawId != null && rawId > 0 && rawId < 1000000000)
                  ? 'id_$rawId'
                  : 'uuid_${item['item_uuid']}';
              if (!dedupMap.containsKey(sig)) {
                dedupMap[sig] = item;
              } else {
                final existing = dedupMap[sig]!;
                final itemSettled = (item['cost_status'] == 'actual' && item['actual_amount'] != null) ||
                    item['variance_journal_entry_id'] != null;
                final existingSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
                    existing['variance_journal_entry_id'] != null;
                if (itemSettled && !existingSettled) {
                  if ((item['notes'] == null || item['notes'].toString().isEmpty) &&
                      existing['notes'] != null && existing['notes'].toString().isNotEmpty) {
                    item['notes'] = existing['notes'];
                  }
                  if ((item['supplier_id'] == null || item['supplier_id'].toString().isEmpty) &&
                      existing['supplier_id'] != null && existing['supplier_id'].toString().isNotEmpty) {
                    item['supplier_id'] = existing['supplier_id'];
                  }
                  if ((item['supplier_name'] == null || item['supplier_name'].toString().isEmpty) &&
                      existing['supplier_name'] != null && existing['supplier_name'].toString().isNotEmpty) {
                    item['supplier_name'] = existing['supplier_name'];
                  }
                  dedupMap[sig] = item;
                } else {
                  if ((existing['notes'] == null || existing['notes'].toString().isEmpty) &&
                      item['notes'] != null && item['notes'].toString().isNotEmpty) {
                    existing['notes'] = item['notes'];
                  }
                  if ((existing['supplier_id'] == null || existing['supplier_id'].toString().isEmpty) &&
                      item['supplier_id'] != null && item['supplier_id'].toString().isNotEmpty) {
                    existing['supplier_id'] = item['supplier_id'];
                  }
                  if ((existing['supplier_name'] == null || existing['supplier_name'].toString().isEmpty) &&
                      item['supplier_name'] != null && item['supplier_name'].toString().isNotEmpty) {
                    existing['supplier_name'] = item['supplier_name'];
                  }
                }
              }
            }
            _costItems.addAll(dedupMap.values);
          }
          if (updated.notes != null && updated.notes!.isNotEmpty) {
            try {
              final notes = jsonDecode(updated.notes!) as Map<String, dynamic>;
              final mats = (notes['materials'] ?? notes['material_items']) as List?;
              if (mats != null) {
                _materialItems.clear();
                for (final m in mats) {
                  final map = Map<String, dynamic>.from(m as Map);
                  map['total'] = ((map['used_qty'] ?? 0) as num).toDouble() *
                      ((map['unit_cost'] ?? 0) as num).toDouble();
                  _materialItems.add(map);
                }
              }
            } catch (_) {}
          }
        });
        await _loadVarianceReport(updated, updated.lines.isNotEmpty ? updated.lines : null);
        await _loadWasteSettlements();
        try {
          final freshTransport = await TransportSupplierDao().getAll();
          final freshSuppliers = await SupplierDao().getAll(limit: 2000);
          if (mounted) {
            setState(() {
              _transportSuppliers = freshTransport;
              _suppliers = freshSuppliers;
            });
          }
        } catch (e) {
          debugPrint('⚠️ Error reloading suppliers in _refreshCurrentOrder: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error refreshing order: $e');
    }
  }

  Future<void> _loadWasteSettlements() async {
    final id = _orderId;
    if (id == null) {
      if (mounted) {
        setState(() {
          _settledMaterialWasteCost = 0.0;
          _wasteSettlements = [];
          _returnPackagingWasteCost = 0.0;
          _returnDamagedCartons = 0;
          _returnWasteDetails = [];
          _isWasteSettled = false;
        });
      }
      return;
    }
    try {
      _loadingWasteSettlements = true;
      final res = await _dao.getPackingWasteSettlements(id);
      if (mounted) {
        setState(() {
          _returnPackagingWasteCost = (res['return_packaging_waste_cost'] as num?)?.toDouble() ?? 0.0;
          _returnDamagedCartons = (res['return_damaged_cartons'] as num?)?.toInt() ?? 0;
          final rawDetails = res['return_details'] as List?;
          if (rawDetails != null) {
            _returnWasteDetails = rawDetails.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else {
            _returnWasteDetails = [];
          }

          _settledMaterialWasteCost = (res['settled_waste_cost'] as num?)?.toDouble() ?? 0.0;
          final rawList = res['settlements'] as List?;
          if (rawList != null) {
            _wasteSettlements = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else {
            _wasteSettlements = [];
          }
          final status = res['status'] as String?;
          _isWasteSettled = _wasteSettlements.isNotEmpty ||
              _settledMaterialWasteCost > 0.001 ||
              status == 'fully_settled';
          _loadingWasteSettlements = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error loading waste settlements: $e');
      if (mounted) {
        setState(() {
          _loadingWasteSettlements = false;
        });
      }
    }
    // Keep the seasonal opening balance in sync after any settlement change
    await _loadSeasonalWasteBalance();
  }

  /// Season range containing [ref], based on [_kWasteSeasonStartMonth].
  ({DateTime start, DateTime end}) _seasonRangeFor(DateTime ref) {
    final startYear = ref.month >= _kWasteSeasonStartMonth ? ref.year : ref.year - 1;
    final start = DateTime(startYear, _kWasteSeasonStartMonth, 1);
    final end = DateTime(startYear + 1, _kWasteSeasonStartMonth, 1).subtract(const Duration(days: 1));
    return (start: start, end: end);
  }

  String get _seasonLabel {
    final s = _seasonStart, e = _seasonEnd;
    if (s == null || e == null) return '';
    return s.year == e.year ? 'موسم ${s.year}' : 'موسم ${s.year}-${e.year}';
  }

  Future<void> _loadSeasonalWasteBalance() async {
    if (_loadingSeasonalWaste) return;
    final ord = _currentOrder ?? widget.existingOrder;
    final range = _seasonRangeFor(ord?.createdAt ?? DateTime.now());
    _loadingSeasonalWaste = true;
    if (mounted) setState(() {});
    try {
      final res = await _dao.getSeasonalPackingWasteBalance(
        seasonStart: range.start,
        seasonEnd: range.end,
        currentPackingOrderId: _orderId,
      );
      if (!mounted) return;
      setState(() {
        _seasonStart = range.start;
        _seasonEnd = range.end;
        if (res['success'] == true) {
          _seasonalOpeningWasteBalance = (res['opening_balance'] as num?)?.toDouble() ?? 0.0;
          _seasonalReturnWasteTotal = (res['season_return_waste'] as num?)?.toDouble() ?? 0.0;
          _seasonalSettledByOthers = (res['settled_by_other_orders'] as num?)?.toDouble() ?? 0.0;
          _seasonalDamagedCartons = (res['season_damaged_cartons'] as num?)?.toInt() ?? 0;
          _seasonalReturnsCount = (res['season_returns_count'] as num?)?.toInt() ?? 0;
          _seasonalWasteLoaded = true;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error loading seasonal waste balance: $e');
    } finally {
      _loadingSeasonalWaste = false;
      if (mounted) setState(() {});
    }
  }

  String _detectSupplierTypeForCategory(int? catId, {String? categoryName}) {
    if (catId != null) {
      final matched = _costCategories.firstWhere(
        (c) => c['id'] == catId,
        orElse: () => {},
      );
      if (matched.isNotEmpty) {
        return CostCategoryService.resolveCategorySupplierType(matched);
      }
    }
    return CostCategoryService.resolveCategorySupplierType({
      'name': categoryName ?? '',
    });
  }

  /// Resolves the updated category id and default item name when switching the active supplier type tab.
  ({int? categoryId, String? updatedName}) _resolveCategorySelectionForType({
    required String targetType,
    required int? currentCategoryId,
    required String currentName,
    required Map<int, String> allCategories,
  }) {
    final filtered = CostCategoryService.filterCategoriesBySupplierType(
      _costCategories,
      supplierType: targetType,
    );
    final nextCategoryId =
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
      currentCategoryId: currentCategoryId,
      filteredCategories: filtered,
      supplierType: targetType,
    );
    String? nextName;
    if (CostCategoryService.isAutoGeneratedItemName(
        currentName, allCategories.values)) {
      if (targetType == 'admin') {
        nextName = filtered[nextCategoryId] ?? 'مصاريف إدارية';
      } else if (targetType == 'transport') {
        nextName = 'مصاريف نقل';
      } else if (targetType == 'engineer') {
        nextName = 'مصاريف مهندسين وإشراف';
      } else if (nextCategoryId != null) {
        nextName = filtered[nextCategoryId] ?? '';
      } else if (currentName.trim().isNotEmpty) {
        nextName = '';
      }
    }
    return (categoryId: nextCategoryId, updatedName: nextName);
  }


  Future<void> _loadData() async {
    try {
      List<StationModel> stations = [];
      List<LotReceiptModel> lots = [];
      List<SupplierModel> suppliers = [];
      List<Map<String, dynamic>> costCategories = [];
      List<Map<String, dynamic>> treasuries = [];
      List<Map<String, dynamic>> bankAccounts = [];

      try {
        stations = await _stationDao.getAll();
      } catch (e) {
        debugPrint('Error fetching stations: $e');
      }

      try {
        lots = await _lotDao.getAll();
      } catch (e) {
        debugPrint('Error fetching lots: $e');
      }

      try {
        suppliers = await SupplierDao().getAll(limit: 2000);
      } catch (e) {
        debugPrint('Error fetching suppliers: $e');
      }

      List<TransportSupplierModel> transportSuppliers = [];
      try {
        transportSuppliers = await TransportSupplierDao().getAll();
      } catch (e) {
        debugPrint('Error fetching transport suppliers: $e');
      }

      try {
        final catRes = await CostCategoryService().listCategories();
        if (catRes.isNotEmpty) {
          costCategories = catRes;
        } else {
          final raw = await Supabase.instance.client
              .from('cost_report_categories')
              .select('*')
              .order('name');
          if (raw is List) {
            costCategories = raw.map((e) => Map<String, dynamic>.from(e)).toList();
            await CostCategoryService().enrichSupplierType(costCategories);
          }
        }
      } catch (e) {
        debugPrint('Error fetching categories: $e');
      }

      try {
        final trRes = await Supabase.instance.client
            .from('treasuries')
            .select('id, name, type, employee_id, account_id, is_active, treasury_balances(id, balance, currency, account_id)')
            .order('name');
        if (trRes is List) {
          treasuries = List<Map<String, dynamic>>.from(trRes);
        }
      } catch (e) {
        // Fallback if type/employee_id/account_id not in select
        try {
          final trRes = await Supabase.instance.client
              .from('treasuries')
              .select('id, name, treasury_balances(id, balance, currency, account_id)')
              .order('name');
          if (trRes is List) {
            treasuries = List<Map<String, dynamic>>.from(trRes);
          }
        } catch (e2) {
          debugPrint('Error fetching treasuries fallback: $e2');
        }
        debugPrint('Error fetching treasuries: $e');
      }

      // Pre-calculate live EGP balance and populate _custodyBalancesMap for each treasury
      for (final t in treasuries) {
        final balances = t['treasury_balances'];
        double egpBal = 0.0;
        if (balances is List && balances.isNotEmpty) {
          final match = balances.firstWhere(
            (b) => (b['currency']?.toString() ?? '').toUpperCase() == 'EGP',
            orElse: () => null,
          );
          if (match != null) {
            egpBal = (match['balance'] as num?)?.toDouble() ?? 0.0;
          } else {
            egpBal = (balances.first['balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
        t['live_balance'] = egpBal;
        final tIdStr = t['id']?.toString() ?? '';
        if (tIdStr.isNotEmpty) {
          _custodyBalancesMap[tIdStr] = {
            'custody_id': t['id'],
            'custody_name': t['name'] ?? '',
            'balance': egpBal,
            'operational_balance': egpBal,
            'account_id': t['account_id'],
            'currency': 'EGP',
          };
        }
      }

      try {
        final bankRes = await Supabase.instance.client
            .from('bank_accounts')
            .select('id, name, currency, balance')
            .order('name');
        if (bankRes is List) {
          bankAccounts = List<Map<String, dynamic>>.from(bankRes);
        }
      } catch (e) {
        debugPrint('Error fetching banks: $e');
      }

      List<CostCenter> costCenters = [];
      try {
        final ccRes = await Supabase.instance.client
            .from('cost_centers')
            .select()
            .eq('is_active', true)
            .order('season_number', ascending: false);
        costCenters = (ccRes as List).map((e) => CostCenter.fromMap(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        debugPrint('Error fetching cost centers: $e');
      }

      List<Map<String, dynamic>> recentShipments = [];
      List<String> customerNames = [];
      try {
        final shipRes = await Supabase.instance.client
            .from('export_shipments')
            .select('id, shipment_no, customer_name')
            .order('created_at', ascending: false)
            .limit(100);
        recentShipments = List<Map<String, dynamic>>.from(shipRes as List);
        final cSet = <String>{};
        for (final s in recentShipments) {
          final c = (s['customer_name'] as String?)?.trim();
          if (c != null && c.isNotEmpty) cSet.add(c);
        }
        customerNames = cSet.toList()..sort();
      } catch (e) {
        debugPrint('Error fetching export shipments in packing order: $e');
      }

      List<Map<String, dynamic>> expenseAccounts = [];
      try {
        final accRes = await Supabase.instance.client
            .from('accounts')
            .select('id, account_code, name, account_name, account_type, is_leaf, level')
            .or('account_type.eq.expense,account_code.like.3%')
            .filter('deleted_at', 'is', null)
            .order('account_code');
        if (accRes is List) {
          expenseAccounts = accRes.where((a) {
            final code = a['account_code']?.toString().trim() ?? '';
            final isLeaf = a['is_leaf'] == true;
            final level = (a['level'] as num?)?.toInt() ?? 0;
            final isLevel5 = level >= 5 || code.length >= 5 || isLeaf;
            final isExpense = (a['account_type']?.toString().toLowerCase() == 'expense') || code.startsWith('3');
            return isLevel5 && isExpense;
          }).map((a) {
            final m = Map<String, dynamic>.from(a as Map);
            final code = m['account_code']?.toString().trim() ?? '';
            final standardName = AccountModel.getStandardArabicName(code);
            final name = standardName ?? m['account_name']?.toString() ?? m['name']?.toString() ?? code;
            m['display_label'] = '$code - $name';
            m['resolved_name'] = name;
            return m;
          }).toList();
        }
      } catch (e) {
        debugPrint('Error fetching expense accounts in _loadData: $e');
      }

      if (expenseAccounts.isEmpty) {
        expenseAccounts = [
          {'id': 5151, 'account_code': '31251', 'resolved_name': 'مصاريف مهندسين', 'display_label': '31251 - مصاريف مهندسين'},
          {'id': 5152, 'account_code': '31121', 'resolved_name': 'مصروفات سفر وبدلات انتقال', 'display_label': '31121 - مصروفات سفر وبدلات انتقال'},
          {'id': 5153, 'account_code': '31123', 'resolved_name': 'مصروفات انتقالات ومأموريات', 'display_label': '31123 - مصروفات انتقالات ومأموريات'},
          {'id': 5154, 'account_code': '31221', 'resolved_name': 'مصروفات تشغيل ومأموريات مواقع', 'display_label': '31221 - مصروفات تشغيل ومأموريات مواقع'},
          {'id': 5155, 'account_code': '31311', 'resolved_name': 'مصروفات إعاشة وخدمات مواقع', 'display_label': '31311 - مصروفات إعاشة وخدمات مواقع'},
          {'id': 5156, 'account_code': '31318', 'resolved_name': 'مصروفات صيانة عامة وطارئة', 'display_label': '31318 - مصروفات صيانة عامة وطارئة'},
          {'id': 5157, 'account_code': '31331', 'resolved_name': 'مصروفات إدارية وعمومية', 'display_label': '31331 - مصروفات إدارية وعمومية'},
        ];
      }

      if (mounted) {
        setState(() {
          _stations = stations;
          _allLots = lots;
          _suppliers = suppliers;
          _transportSuppliers = transportSuppliers;
          _costCategories = costCategories;
          _treasuries = treasuries;
          _bankAccounts = bankAccounts;
          _costCenters = costCenters;
          _recentExportShipments = recentShipments;
          _knownCustomerNames = customerNames;
          _expenseAccounts = expenseAccounts;
          _loading = false;
        });

        if (_isEditing) {
          PackingOrderModel orderToPrefill = widget.existingOrder!;
          final oId = int.tryParse(widget.existingOrder!.id ?? '');
          if (oId != null) {
            try {
              final fresh = await _dao.getById(oId);
              if (fresh != null) {
                orderToPrefill = fresh;
              }
            } catch (e) {
              debugPrint('⚠️ Error fetching fresh order in _loadData: $e');
            }
          }
          _currentOrder = orderToPrefill;
          await _prefillFromOrder(orderToPrefill);
        } else {
          if (_stations.isNotEmpty && _selectedStationIds.isEmpty) {
            final firstKey = _getStationKey(_stations.first);
            _selectedStationIds.add(firstKey);
            _selectedStationId = firstKey;
            _isAllStations = false;
          }
          await _onWarehouseScopeChanged();
        }
      }
    } catch (e) {
      debugPrint('Error in _loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _prefillFromOrder(PackingOrderModel order) async {
    _currentOrder = order;
    _selectedStationId = int.tryParse(order.stationId ?? '');
    if (order.notes != null) {
      try {
        final n = jsonDecode(order.notes!);
        if (n is Map) {
          if (n.containsKey('all_stations')) {
            _isAllStations = n['all_stations'] == true;
          }
          if (n['selected_station_ids'] is List) {
            _selectedStationIds = (n['selected_station_ids'] as List)
                .map((e) => (e as num).toInt())
                .toSet();
          }
        }
      } catch (_) {}
    }
    if (_selectedStationIds.isEmpty && _selectedStationId != null && !_isAllStations) {
      _selectedStationIds.add(_selectedStationId!);
    }
    if (_selectedStationIds.isEmpty && _stations.isNotEmpty) {
      final firstKey = _getStationKey(_stations.first);
      _selectedStationIds.add(firstKey);
      _selectedStationId ??= firstKey;
    }
    _exportShipmentNoCtrl.text = order.exportShipmentNo ?? '';
    _customerNameCtrl.text = order.customerName ?? '';

    if (_selectedStationId != null) {
      await _filterLots(_selectedStationId!, keepLotId: order.lotId);
      final products =
          await _stationProductDao.getByStation(_selectedStationId!);
      if (mounted) {
        setState(() => _warehouseProducts = products);
      }
      await _loadMaterialProducts(_selectedStationId!);
    }

    final orderId = int.tryParse(order.id ?? '');
    List<PackingOrderLineModel> existingLines = [];
    if (orderId != null) {
      existingLines = await _dao.getLines(orderId);
    }

    final keepBatchIds = existingLines
        .where((l) => l.batchId != null)
        .map((l) => l.batchId!)
        .toSet();

    if (_selectedStationId != null) {
      await _fetchLotRemainingQuantities(
        _selectedStationId!,
        keepBatchIds: keepBatchIds,
      );
    }

    for (final e in _lotEntries) {
      e.dispose();
    }
    _lotEntries.clear();

    if (existingLines.isNotEmpty) {
      for (final line in existingLines) {
        final entry = _LotEntry();
        entry.lineId = line.id;
        entry.fallbackProductName = line.productName;
        final lotIdStr = line.sourceLotId;
        if (lotIdStr != null) {
          final lot =
              _allLots.where((l) => l.id.toString() == lotIdStr).firstOrNull;
          if (lot != null) {
            entry.lot = lot;
          } else {
            final lotId = int.tryParse(lotIdStr);
            if (lotId != null) {
              final lotRes = await Supabase.instance.client
                  .from('lot_receipts')
                  .select()
                  .eq('id', lotId)
                  .maybeSingle();
              if (lotRes != null) {
                entry.lot = LotReceiptModel.fromMap(lotRes);
              }
            }
          }
        }

        entry.usePartialCrop = line.quantity > 0;
        entry.partialWeightCtrl.text =
            line.quantity > 0 ? line.quantity.toString() : '';

        // Inject stored cost data as fallback (preserves costs after confirm when batch is consumed)
        final effectiveW =
            line.quantity > 0 ? line.quantity : line.totalNetWeight;
        if (line.rawMaterialCost > 0 && effectiveW > 0) {
          final rate = entry.lot?.exchangeRate ?? 1.0;
          entry.overrideCostPerKg = (line.rawMaterialCost / effectiveW) / rate;
          entry.overrideCostPerCarton =
              (line.rawMaterialCost / effectiveW) / rate;
        }

        if (line.batchId != null) {
          entry.batch = _availableBatches
              .where((b) => b.id.toString() == line.batchId)
              .firstOrNull;
        }
        entry.cartonCountCtrl.text = line.cartonCount.toString();
        entry.netWeightPerCartonCtrl.text = line.netWeightPerCarton.toString();
        entry._exactNetWeightPerCarton = line.netWeightPerCarton;
        entry.grossWeightPerCartonCtrl.text =
            line.grossWeightPerCarton.toString();
        if (line.sortedWeightKg > 0) {
          entry.hasSorting = true;
          entry.initialHasSorting = true;
          entry.sortedWeightCtrl.text = line.sortedWeightKg.toString();
        }
        _lotEntries.add(entry);
      }
    } else {
      final entry = _LotEntry();
      final lot = _allLots.where((l) => l.id == order.lotId).firstOrNull;
      if (lot != null) {
        entry.lot = lot;
      }
      if (order.notes != null) {
        try {
          final notesMap = jsonDecode(order.notes!);
          final fruitAlloc = notesMap['fruit_allocation'];
          String? stationBatchId;
          if (fruitAlloc is Map) {
            stationBatchId = fruitAlloc['batch_id']?.toString();
          } else if (fruitAlloc is List && fruitAlloc.isNotEmpty) {
            stationBatchId = fruitAlloc.first['batch_id']?.toString();
          }
          if (stationBatchId != null) {
            entry.batch = _availableBatches
                .where((b) => b.id.toString() == stationBatchId)
                .firstOrNull;
          }
        } catch (_) {}
      }
      entry.cartonCountCtrl.text = order.cartonCount.toString();
      entry.netWeightPerCartonCtrl.text = order.netWeightPerCarton.toString();
      entry._exactNetWeightPerCarton = order.netWeightPerCarton;
      if (order.grossWeightPerCarton > 0) {
        entry.grossWeightPerCartonCtrl.text =
            order.grossWeightPerCarton.toString();
      }

      Map<String, dynamic> notes = {};
      if (order.notes != null && order.notes!.isNotEmpty) {
        try {
          notes = jsonDecode(order.notes!) as Map<String, dynamic>;
        } catch (_) {}
      }

      entry.usePartialCrop = true;
      if (notes.containsKey('partial_weight_kg')) {
        entry.partialWeightCtrl.text =
            (notes['partial_weight_kg'] as num?)?.toString() ?? '';
      }
      if (notes.containsKey('sorted_weight_kg')) {
        entry.hasSorting = true;
        entry.initialHasSorting = true;
        entry.sortedWeightCtrl.text =
            (notes['sorted_weight_kg'] as num?)?.toString() ?? '';
      }

      final baseFruit = order.fruitCostBase > 0 ? order.fruitCostBase : order.fruitCostAllocated;
      if (baseFruit > 0) {
        final rate = entry.lot?.exchangeRate ?? 1.0;
        final effW = entry.effectiveWeight > 0 ? entry.effectiveWeight : (order.cartonCount * order.netWeightPerCarton).toDouble();
        if (effW > 0) {
          entry.overrideCostPerKg = (baseFruit / effW) / rate;
          entry.overrideCostPerCarton = (baseFruit / effW) / rate;
        }
      }

      _lotEntries.add(entry);
    }

    Map<String, dynamic> notes = {};
    if (order.notes != null && order.notes!.isNotEmpty) {
      try {
        notes = jsonDecode(order.notes!) as Map<String, dynamic>;
      } catch (_) {}
    }

    final wasteData = notes['waste_data'];
    final fruitAlloc = notes['fruit_allocation'];

    for (int i = 0; i < _lotEntries.length; i++) {
      if (wasteData is List && wasteData.length > i) {
        _lotEntries[i].wastePercent =
            (wasteData[i]['waste_percent'] as num?)?.toDouble() ?? 0.0;
      } else if (wasteData is Map && i == 0) {
        _lotEntries[i].wastePercent =
            (wasteData['waste_percent'] as num?)?.toDouble() ?? 0.0;
      } else if (fruitAlloc is List && fruitAlloc.length > i) {
        _lotEntries[i].wastePercent =
            (fruitAlloc[i]['waste_percent'] as num?)?.toDouble() ?? 0.0;
      } else if (fruitAlloc is Map && i == 0) {
        _lotEntries[i].wastePercent =
            (fruitAlloc['waste_percent'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final mats = (notes['materials'] ?? notes['material_items']) as List?;
    if (mats != null) {
      _materialItems.clear();
      for (final m in mats) {
        final map = Map<String, dynamic>.from(m as Map);
        map['total'] = ((map['used_qty'] ?? 0) as num).toDouble() *
            ((map['unit_cost'] ?? 0) as num).toDouble();
        _materialItems.add(map);
      }
    }

    List<Map<String, dynamic>> dbCostItems = [];
    if (orderId != null) {
      dbCostItems = await _dao.getCostItemsRaw(orderId);
    }

    _costItems.clear();

    final Map<String, Map<String, dynamic>> canonicalCostMap = {};
    void addCostItemIfUnique(Map<String, dynamic> c) {
      if (c['item_uuid'] == null || c['item_uuid'].toString().trim().isEmpty) {
        final rawId = (c['id'] as num?)?.toInt();
        c['item_uuid'] = (rawId != null && rawId > 0) ? 'item_$rawId' : const Uuid().v4();
      }
      final rawId = (c['id'] as num?)?.toInt();
      final sig = (rawId != null && rawId > 0 && rawId < 1000000000)
          ? 'id_$rawId'
          : 'uuid_${c['item_uuid']}';
      if (!canonicalCostMap.containsKey(sig)) {
        canonicalCostMap[sig] = c;
      } else {
        final existing = canonicalCostMap[sig]!;
        final incomingSettled = (c['cost_status'] == 'actual' && c['actual_amount'] != null) ||
            c['variance_journal_entry_id'] != null;
        final existingSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
            existing['variance_journal_entry_id'] != null;
        if (incomingSettled && !existingSettled) {
          if ((c['notes'] == null || c['notes'].toString().isEmpty) &&
              existing['notes'] != null && existing['notes'].toString().isNotEmpty) {
            c['notes'] = existing['notes'];
          }
          if ((c['supplier_id'] == null || c['supplier_id'].toString().isEmpty) &&
              existing['supplier_id'] != null && existing['supplier_id'].toString().isNotEmpty) {
            c['supplier_id'] = existing['supplier_id'];
          }
          if ((c['supplier_name'] == null || c['supplier_name'].toString().isEmpty) &&
              existing['supplier_name'] != null && existing['supplier_name'].toString().isNotEmpty) {
            c['supplier_name'] = existing['supplier_name'];
          }
          canonicalCostMap[sig] = c;
        } else {
          if ((existing['notes'] == null || existing['notes'].toString().isEmpty) &&
              c['notes'] != null && c['notes'].toString().isNotEmpty) {
            existing['notes'] = c['notes'];
          }
          if ((existing['supplier_id'] == null || existing['supplier_id'].toString().isEmpty) &&
              c['supplier_id'] != null && c['supplier_id'].toString().isNotEmpty) {
            existing['supplier_id'] = c['supplier_id'];
          }
          if ((existing['supplier_name'] == null || existing['supplier_name'].toString().isEmpty) &&
              c['supplier_name'] != null && c['supplier_name'].toString().isNotEmpty) {
            existing['supplier_name'] = c['supplier_name'];
          }
        }
      }
    }

    if (dbCostItems.isNotEmpty) {
      for (final c in dbCostItems) {
        final amt = (c['total_egp'] ?? c['total'] ?? c['base_amount'] ?? 0) as num;
        if (amt <= 0) continue;
        addCostItemIfUnique(c);
      }
    } else if (notes.containsKey('cost_items')) {
      final items = notes['cost_items'] as List?;
      if (items != null) {
        for (final c in items) {
          final map = Map<String, dynamic>.from(c as Map);
          final amt = (map['total_egp'] ?? map['total'] ?? map['base_amount'] ?? 0) as num;
          if (amt <= 0) continue;
          addCostItemIfUnique(map);
        }
      }
    }
    _costItems.addAll(canonicalCostMap.values);
    int? resolvedEngCatId;
    for (final cat in _costCategories) {
      final cName = (cat['name'] as String? ?? '').toLowerCase();
      final cSuppType = (cat['supplier_type'] as String? ?? '').toLowerCase();
      if (cName.contains('مهندس') || cName.contains('مهندسين') || cSuppType == 'engineer') {
        resolvedEngCatId = cat['id'] as int?;
        break;
      }
    }

    for (final c in _costItems) {
      final rCatId = c['report_category_id'];
      final isEng = c['category'] == 'engineer_expenses' || c['supplier_type'] == 'engineer';
      if (isEng) {
        c['report_category_id'] = (resolvedEngCatId != null && resolvedEngCatId != 19)
            ? resolvedEngCatId
            : (rCatId != 19 ? rCatId : null);
      } else if (rCatId == 31251 || (rCatId is num && rCatId > 100)) {
        c['report_category_id'] = null;
      }
    }

    if (notes.containsKey('material_waste_percent')) {
      _materialWastePercentCtrl.text =
          (notes['material_waste_percent'] as num?)?.toString() ?? '';
    }

    setState(() {});
    _loadVarianceReport(order, existingLines);
    await _loadWasteSettlements();
  }

  Future<void> _filterLots(int? stationId, {String? keepLotId}) async {
    try {
      final lots = await _lotDao.getAll();
      if (mounted) _allLots = lots;
    } catch (_) {}
    final stationStrs = _selectedStationIds.map((id) => id.toString()).toSet();
    _filteredLots = _allLots
        .where((l) =>
            (_isAllStations ||
                stationStrs.contains(l.stationId) ||
                (stationId != null && l.stationId == stationId.toString()) ||
                (_selectedStationId != null && l.stationId == _selectedStationId.toString())) &&
            (l.status == 'received' ||
                l.status == 'sorting' ||
                l.id == keepLotId))
        .toList();
  }

  void _filterLotsFromCache([int? stationId]) {
    final stationStrs = _selectedStationIds.map((id) => id.toString()).toSet();
    _filteredLots = _allLots
        .where((l) =>
            (_isAllStations ||
                stationStrs.contains(l.stationId) ||
                (stationId != null && l.stationId == stationId.toString()) ||
                (_selectedStationId != null && l.stationId == _selectedStationId.toString())) &&
            (l.status == 'received' || l.status == 'sorting'))
        .toList();
  }

  Future<void> _fetchLotRemainingQuantities(int? stationId,
      {String? keepBatchId, Set<String>? keepBatchIds}) async {
    try {
      var bQuery = Supabase.instance.client
          .from('station_product_batches')
          .select();

      if (!_isAllStations && _selectedStationIds.isNotEmpty) {
        bQuery = bQuery.inFilter('station_id', _selectedStationIds.toList());
      } else if (!_isAllStations && stationId != null) {
        bQuery = bQuery.eq('station_id', stationId);
      } else if (!_isAllStations && _selectedStationId != null) {
        bQuery = bQuery.eq('station_id', _selectedStationId!);
      }

      final batchesData = await bQuery.order('created_at', ascending: true);

      final parsedBatches =
          batchesData.map(StationProductBatch.fromMap).toList();

      final Set<String> cropNames =
          _allLots.map((l) => l.productName ?? '').toSet();
      final Set<String> cropLotNumbers =
          _allLots.map((l) => l.lotNumber ?? '').toSet();

      final cropBatches = parsedBatches.where((b) {
        return cropNames.contains(b.productName) &&
            cropLotNumbers.contains(b.productCode);
      }).toList();

      // Deduct quantities consumed across other active/saved packing orders (status in draft, pending)
      final currentOrderId = _orderId ??
          (widget.existingOrder != null
              ? int.tryParse(widget.existingOrder!.id ?? '')
              : null);
      final Map<int, double> consumedByOtherOrders = {};

      try {
        var activeOrdersQuery = Supabase.instance.client
            .from('packing_orders')
            .select('id, notes')
            .inFilter('status', ['pending', 'draft']);

        if (!_isAllStations && _selectedStationIds.isNotEmpty) {
          activeOrdersQuery = activeOrdersQuery.inFilter('station_id', _selectedStationIds.toList());
        } else if (!_isAllStations && stationId != null) {
          activeOrdersQuery = activeOrdersQuery.eq('station_id', stationId);
        } else if (!_isAllStations && _selectedStationId != null) {
          activeOrdersQuery = activeOrdersQuery.eq('station_id', _selectedStationId!);
        }

        if (currentOrderId != null) {
          activeOrdersQuery = activeOrdersQuery.neq('id', currentOrderId);
        }

        final activeOrders = await activeOrdersQuery;
        final activeOrderIds = <int>[];
        final orderNotesMap = <int, dynamic>{};

        for (final o in (activeOrders as List)) {
          final oId = (o['id'] as num?)?.toInt();
          if (oId != null) {
            activeOrderIds.add(oId);
            orderNotesMap[oId] = o['notes'];
          }
        }

        final Set<int> ordersHandledViaLines = {};
        if (activeOrderIds.isNotEmpty) {
          final linesData = await Supabase.instance.client
              .from('packing_order_lines')
              .select('packing_order_id, batch_id, quantity')
              .inFilter('packing_order_id', activeOrderIds);

          for (final l in (linesData as List)) {
            final pOrderId = (l['packing_order_id'] as num?)?.toInt();
            final bId = int.tryParse(l['batch_id']?.toString() ?? '');
            final q = (l['quantity'] as num?)?.toDouble() ?? 0.0;
            if (bId != null && q > 0) {
              consumedByOtherOrders[bId] =
                  (consumedByOtherOrders[bId] ?? 0.0) + q;
              if (pOrderId != null) ordersHandledViaLines.add(pOrderId);
            }
          }
        }

        for (final oId in activeOrderIds) {
          if (ordersHandledViaLines.contains(oId)) continue;
          final notesRaw = orderNotesMap[oId];
          if (notesRaw == null) continue;
          try {
            final n = notesRaw is Map ? notesRaw : jsonDecode(notesRaw.toString());
            final fa = n['fruit_allocation'];
            if (fa is List) {
              for (final alloc in fa) {
                if (alloc is Map) {
                  final bId = (alloc['batch_id'] as num?)?.toInt() ??
                      int.tryParse(alloc['batch_id']?.toString() ?? '');
                  final q = (alloc['quantity'] as num?)?.toDouble() ?? 0.0;
                  if (bId != null && q > 0) {
                    consumedByOtherOrders[bId] =
                        (consumedByOtherOrders[bId] ?? 0.0) + q;
                  }
                }
              }
            } else if (fa is Map) {
              final bId = (fa['batch_id'] as num?)?.toInt() ??
                  int.tryParse(fa['batch_id']?.toString() ?? '');
              final q = (fa['quantity'] as num?)?.toDouble() ?? 0.0;
              if (bId != null && q > 0) {
                consumedByOtherOrders[bId] =
                    (consumedByOtherOrders[bId] ?? 0.0) + q;
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching batch usage from active packing orders: $e');
      }

      final Map<int, double> newBatchBaseRemaining = {};
      for (final b in parsedBatches) {
        if (b.id != null) {
          final consumed = consumedByOtherOrders[b.id!] ?? 0.0;
          final rem = (b.remainingQuantity - consumed).clamp(0.0, double.infinity);
          newBatchBaseRemaining[b.id!] = rem;
        }
      }

      final Map<String, double> remQtys = {};
      final Map<String, double> origQtys = {};
      for (final b in cropBatches) {
        final code = b.productCode;
        if (code.isNotEmpty) {
          final effectiveRem = newBatchBaseRemaining[b.id] ?? b.remainingQuantity;
          remQtys[code] = (remQtys[code] ?? 0.0) + effectiveRem;
          origQtys[code] = (origQtys[code] ?? 0.0) + b.quantity;
        }
      }

      final newRemQuantities = <String, double>{};
      final newOrigQuantities = <String, double>{};
      for (final lot in _allLots) {
        if (lot.lotNumber != null && remQtys.containsKey(lot.lotNumber)) {
          newRemQuantities[lot.id!] = remQtys[lot.lotNumber]!;
          newOrigQuantities[lot.id!] = origQtys[lot.lotNumber]!;
        }
      }

      final keepIds = <String>{};
      if (keepBatchId != null) keepIds.add(keepBatchId);
      if (keepBatchIds != null) keepIds.addAll(keepBatchIds);

      if (widget.existingOrder?.notes != null) {
        try {
          final notesMap = jsonDecode(widget.existingOrder!.notes!);
          final fruitAlloc = notesMap['fruit_allocation'];
          if (fruitAlloc is Map && fruitAlloc['batch_id'] != null) {
            keepIds.add(fruitAlloc['batch_id'].toString());
          } else if (fruitAlloc is List) {
            for (final alloc in fruitAlloc) {
              if (alloc is Map && alloc['batch_id'] != null) {
                keepIds.add(alloc['batch_id'].toString());
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _batchBaseRemaining = newBatchBaseRemaining;
          _availableBatches = cropBatches
              .where((b) =>
                  (newBatchBaseRemaining[b.id] ?? b.remainingQuantity) > 0 ||
                  keepIds.contains(b.id.toString()))
              .toList();
          _lotRemainingQuantities = newRemQuantities;
        });
      }
    } catch (e) {
      debugPrint('Error fetching remaining quantities: $e');
    }
  }

  Future<void> _loadMaterialProducts([int? stationId]) async {
    try {
      List<RawMaterialModel> rawMats = [];
      try {
        rawMats = await _rawMaterialDao.getAll();
      } catch (e) {
        debugPrint('Error fetching raw materials: $e');
      }

      var matQuery = Supabase.instance.client
          .from('station_product_batches')
          .select(
              'id, station_id, product_code, product_name, remaining_quantity, quantity, source_type')
          .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual']);

      if (!_isAllStations && _selectedStationIds.isNotEmpty) {
        matQuery = matQuery.inFilter('station_id', _selectedStationIds.toList());
      } else if (!_isAllStations && stationId != null) {
        matQuery = matQuery.eq('station_id', stationId);
      } else if (!_isAllStations && _selectedStationId != null) {
        matQuery = matQuery.eq('station_id', _selectedStationId!);
      }

      final batchData = await matQuery;

      final batches = (batchData is List)
          ? List<Map<String, dynamic>>.from(batchData)
          : [];

      final batchQtyByCode = <String, double>{};
      final batchNameByCode = <String, String>{};
      for (final b in batches) {
        final code = b['product_code']?.toString() ?? '';
        final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        if (code.isNotEmpty && rem > 0) {
          batchQtyByCode[code] = (batchQtyByCode[code] ?? 0.0) + rem;
          if (b['product_name'] != null) {
            batchNameByCode[code] = b['product_name'].toString();
          }
        }
      }

      final List<StationProductModel> materialList = [];
      final seenCodes = <String>{};

      for (final rm in rawMats) {
        final code = rm.code;
        seenCodes.add(code);
        final stationQty = batchQtyByCode[code] ?? 0.0;
        materialList.add(StationProductModel(
          stationId: stationId ?? _selectedStationId ?? 0,
          productName: rm.name,
          productCode: code,
          quantity: stationQty,
          unit: rm.unit == 'kg' ? 'piece' : rm.unit,
          itemType: 'material',
          rawMaterialId: rm.id,
        ));
      }

      for (final entry in batchQtyByCode.entries) {
        if (!seenCodes.contains(entry.key)) {
          final name =
              batchNameByCode[entry.key] ?? 'مادة تعبئة ${entry.key}';
          materialList.add(StationProductModel(
            stationId: stationId ?? _selectedStationId ?? 0,
            productName: name.replaceAll(' (مادة تعبئة)', ''),
            productCode: entry.key,
            quantity: entry.value,
            unit: 'piece',
            itemType: 'material',
          ));
        }
      }

      if (mounted) {
        setState(() {
          _materialProducts = materialList;
        });
      }
    } catch (e) {
      debugPrint('Error in _loadMaterialProducts: $e');
    }
  }

  double get _packingCostPerCarton => _calcResult.finalCost.costPerCarton;

  List<PackingLineInput> get _linesInput => _lotEntries
      .map((e) => PackingLineInput(
            productName: e.lot?.productName ?? '',
            cartonCount: e.cartonCount,
            netWeightPerCarton: e.exactCartonNetWeight,
            grossWeightPerCarton: e.grossWeightPerCartonValue > 0
                ? e.grossWeightPerCartonValue
                : e.exactCartonNetWeight,
            effectiveWeight: e.effectiveWeight,
            sortedWeight: e.sortedWeight,
            productCostPerKg: e.costPerUnit,
            wasteWeight: e.wasteWeight,
            totalPurchaseCost: e.totalPurchaseCost,
            precomputedWasteCost: e.wasteCost,
            precomputedSortingCost: e.sortingCost,
          ))
      .toList();

  PackingCalcResult get _calcResult => PackingCalculationService.calculateAll(
        lines: _linesInput,
        materialItems: _materialItems,
        costItems: _costItems,
        materialWastePercent: _materialWastePercent,
        settledMaterialWasteCost: _settledMaterialWasteCost,
        overrideWasteCost: null,
      );

  double get _totalFruitCost => _calcResult.finalCost.fruitCost;
  double get _totalMaterialCost => _calcResult.materials.materialCost;
  double get _actualPackagingMaterialCost {
    // 1. Direct aggregate of all materialItems currently in memory
    if (_materialItems.isNotEmpty) {
      double itemsTotal = 0.0;
      for (final m in _materialItems) {
        final qty = ((m['used_qty'] ?? 0) as num).toDouble();
        final cost = ((m['unit_cost'] ?? 0) as num).toDouble();
        final computed = qty * cost;
        if (computed > 0) {
          itemsTotal += computed;
        } else {
          itemsTotal += ((m['total'] ?? 0) as num).toDouble();
        }
      }
      if (itemsTotal > 0) return itemsTotal;
    }
    final calcCost = _calcResult.materials.materialCost;
    if (calcCost > 0) return calcCost;
    final ord = _currentOrder ?? widget.existingOrder;
    if (ord != null) {
      if (ord.actualMaterialCost > 0) return ord.actualMaterialCost;
      if (ord.materialCostBase > 0) return ord.materialCostBase;
    }
    return 0.0;
  }

  // ─── Cumulative / Rolling Waste Settlement ─────────────────────────────────
  /// Opening cumulative unsettled waste before this order settles anything.
  /// Priority: season-level balance (loaded on init) → this order's return waste → notes snapshot.
  double get _cumulativePendingWastePool {
    if (_seasonalWasteLoaded && _seasonalOpeningWasteBalance > 0.001) {
      return _seasonalOpeningWasteBalance;
    }
    if (_returnPackagingWasteCost > 0) return _returnPackagingWasteCost;
    final ord = _currentOrder ?? widget.existingOrder;
    if (ord?.notes != null) {
      try {
        final parsed = ord!.notes is Map ? ord.notes as Map : jsonDecode(ord.notes.toString()) as Map;
        final pool = (parsed['waste_settlement_summary']?['cumulative_waste_pool'] as num?)?.toDouble();
        if (pool != null && pool > 0) return pool;
      } catch (_) {}
    }
    return 0.0;
  }

  bool get _isRollingWasteMode => _cumulativePendingWastePool > 0.001;

  double get _currentOrderCalculatedWaste {
    final pct = _materialWastePercent;
    final baseCost = _actualPackagingMaterialCost;
    if (pct > 0 && baseCost > 0) {
      return (baseCost * pct / 100.0);
    }
    final calcWaste = _calcResult.materials.wasteCost;
    if (calcWaste > 0) return calcWaste;
    return 0.0;
  }

  /// Total waste value: in rolling mode, represents the cumulative pending pool (e.g. 1000 EGP)
  double get _totalMaterialWasteCost {
    if (_isRollingWasteMode) {
      return _cumulativePendingWastePool;
    }
    return _currentOrderCalculatedWaste;
  }

  /// Current settled amount: in rolling mode, reflects current order waste (e.g. 400 EGP)
  /// or actual recorded settlements if higher
  double get _rollingSettledWasteAmount {
    if (_isRollingWasteMode) {
      final totalSettled = math.max(_settledMaterialWasteCost, _currentOrderCalculatedWaste);
      return totalSettled.clamp(0.0, _cumulativePendingWastePool);
    }
    return _settledMaterialWasteCost;
  }

  double get _settledMaterialWasteCostValue => _settledMaterialWasteCost;

  /// Remaining unsettled balance: Cumulative Unsettled Waste - Current Settled Amount
  /// (e.g., 1000 - 400 = 600 EGP)
  double get _unsettledMaterialWasteCost {
    if (_isRollingWasteMode) {
      return (_cumulativePendingWastePool - _rollingSettledWasteAmount).clamp(0.0, double.infinity);
    }
    return (_currentOrderCalculatedWaste - _settledMaterialWasteCost).clamp(0.0, double.infinity);
  }

  /// Current order's packaging cost includes its own waste (e.g., materials + 400 EGP)
  double get _packagingCostAfterWaste =>
      _actualPackagingMaterialCost + _currentOrderCalculatedWaste;

  String get _wasteSettlementStatusLabel {
    if (isPosted) return 'تم الترحيل (مسوى)';
    if (isWasteSettled) return 'هالك مسوى';
    if (_isRollingWasteMode) {
      if (_unsettledMaterialWasteCost <= 0.001) return 'هالك مسوى';
      if (_rollingSettledWasteAmount > 0.001) return 'تسوية دوارة جزئية';
      return 'رصيد تراكمي غير مسوّى';
    }
    if (_totalMaterialWasteCost <= 0.001) return 'لا يوجد هالك';
    if (_settledMaterialWasteCost <= 0.001) return 'هالك غير مسوّى';
    if (_unsettledMaterialWasteCost <= 0.001) return 'هالك مسوى';
    return 'تسوية جزئية';
  }

  Color get _wasteSettlementStatusColor {
    if (isPosted || isWasteSettled) return AppTheme.success;
    if (_isRollingWasteMode) {
      if (_unsettledMaterialWasteCost <= 0.001) return AppTheme.success;
      if (_rollingSettledWasteAmount > 0.001) return const Color(0xFF0284C7);
      return const Color(0xFFF59E0B);
    }
    if (_totalMaterialWasteCost <= 0.001) return AppTheme.textMuted;
    if (_settledMaterialWasteCost <= 0.001) return AppTheme.warning;
    if (_unsettledMaterialWasteCost <= 0.001) return AppTheme.success;
    return const Color(0xFF0284C7);
  }

  double get _totalCostItems => _calcResult.costItems.totalCostItems;
  int get _totalCartons => _calcResult.weights.totalCartons;
  double get _totalNetWeight => _calcResult.weights.totalNetWeight;
  double get _totalEffectiveWeight =>
      _lotEntries.fold<double>(0.0, (s, e) => s + e.effectiveWeight);
  double get _totalSortingCost => _calcResult.weights.totalSortingCost;
  double get _totalWasteCost =>
      _lotEntries.fold<double>(0, (s, e) => s + e.wasteCost);
  double get _totalAdjustedCost => _calcResult.finalCost.fruitCost;
  double get _materialWastePercent =>
      double.tryParse(_materialWastePercentCtrl.text) ?? 0;

  String _fmt(double v) => PackingCalculationService.fmtMoney(v);
  String _fmtMoney(double v) => PackingCalculationService.fmtMoney(v);
  String _fmtWeight(double v) => PackingCalculationService.fmtWeight(v);
  String _fmtPercent(double v) => PackingCalculationService.fmtPercent(v);

  @override
  void dispose() {
    _suppliersSub?.cancel();
    _transportSuppliersSub?.cancel();
    _packingOrdersSub?.cancel();
    _materialWastePercentCtrl.dispose();
    _exportShipmentNoCtrl.dispose();
    _customerNameCtrl.dispose();
    for (final c in _adminActualControllers.values) {
      c.dispose();
    }
    for (final e in _lotEntries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Container(
          decoration: isDark ? AppTheme.backgroundGradient : null,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : SingleChildScrollView(
                  padding:
                      EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildHeader(isDark),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildWarehouseFilterSection(isDark),
                              const SizedBox(height: 16),
                              if (_isEditing || _orderId != null) ...[
                                _buildWorkflowStageStepper(isDark),
                                const SizedBox(height: 16),
                              ],
                              _buildCard(
                                  'بيانات الشحنة التصديرية والعميل المرتبط (اختياري)',
                                  _buildShipmentReferenceSection(isDark)),
                              const SizedBox(height: 16),
                              if (_isAllStations || _selectedStationIds.isNotEmpty || _selectedStationId != null) ...[
                                ..._buildLotEntries(),
                                const SizedBox(height: 16),
                                _buildCard(
                                    'مواد التعبئة والتغليف (تكلفة فعلية)',
                                    _buildMaterialsSection()),
                                const SizedBox(height: 16),
                                _buildCard('نسبة وفقد مواد التعبئة الفعلية',
                                    _buildMaterialWasteSection()),
                                const SizedBox(height: 16),
                                _buildPackagingStageActionBar(isDark),
                                const SizedBox(height: 16),
                                _buildCard(
                                    'بنود التكلفة الإضافية (نقل فعلي / محطات وتخصيمات)',
                                    _buildCostItemsSection()),
                                const SizedBox(height: 16),
                                _buildCostsStageActionBar(isDark),
                                const SizedBox(height: 16),
                                _buildCard('ملخص تكاليف التشغيلة وأمر التعبئة',
                                    _buildSummarySection()),
                                if (widget.existingOrder != null) ...[
                                  const SizedBox(height: 16),
                                  _buildCard(
                                      'مقارنة التكلفة التقديرية والفعلية (Estimated vs. Actual Variance)',
                                      _buildCostVarianceSection()),
                                ],
                                const SizedBox(height: 16),
                                _buildActionButtons(),
                              ],
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final status = _currentOrder?.status ?? widget.existingOrder?.status ?? 'pending';
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'crops_confirmed':
        statusColor = const Color(0xFF38BDF8);
        statusLabel = 'تم تأكيد المحاصيل (مرحلة 1)';
        break;
      case 'packaging_confirmed':
        statusColor = const Color(0xFFA855F7);
        statusLabel = 'تم صرف مواد التعبئة (مرحلة 2)';
        break;
      case 'costs_confirmed':
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'تم إثبات التكاليف (مرحلة 3)';
        break;
      case 'final_approved':
      case 'completed':
        statusColor = AppTheme.success;
        statusLabel = 'معتمد نهائياً ومغلق';
        break;
      case 'cancelled':
        statusColor = AppTheme.danger;
        statusLabel = 'ملغي';
        break;
      case 'draft':
      case 'pending':
      default:
        statusColor = AppTheme.warning;
        statusLabel = 'مسودة قابلة للتعديل';
        break;
    }

    final hasAnyJournalEntry =
        (_currentOrder?.journalEntryId ?? widget.existingOrder?.journalEntryId) != null ||
            _currentOrder?.cropsJournalEntryId != null ||
            _currentOrder?.packagingJournalEntryId != null ||
            _currentOrder?.costsJournalEntryId != null;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 12,
              left: 8,
              right: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(
                bottom: BorderSide(
                    color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_forward, color: isDark ? Colors.white : Colors.black),
                    onPressed: () => context.pop(),
                  ),
                  if (_isEditing) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withAlpha(50)),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                        _isViewOnly
                            ? 'تفاصيل أمر تعبئة'
                            : (_isEditing
                                ? 'تعديل أمر تعبئة'
                                : 'أمر تعبئة جديد'),
                        style: TextStyle(
                            color: isDark ? AppTheme.textPrimary : Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  if (_isEditing && hasAnyJournalEntry)
                    _buildHeaderViewEntryButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderViewEntryButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton.icon(
        onPressed: () async {
          final journalEntryId = _currentOrder?.journalEntryId ??
              widget.existingOrder?.journalEntryId ??
              _currentOrder?.costsJournalEntryId ??
              _currentOrder?.packagingJournalEntryId ??
              _currentOrder?.cropsJournalEntryId;
          final packingOrderId = _currentOrder?.id ?? widget.existingOrder?.id;
          final orderNumber = _currentOrder?.orderNumber ?? widget.existingOrder?.orderNumber ?? '';
          debugPrint('═══════════════════════════════════════════');
          debugPrint('PackingOrder: عرض القيد المحاسبي');
          debugPrint('  PackingOrder ID = $packingOrderId');
          debugPrint('  PackingOrder Number = $orderNumber');
          debugPrint('  Stored JournalEntry ID = $journalEntryId');
          debugPrint('═══════════════════════════════════════════');

          if (journalEntryId == null || journalEntryId.isEmpty) {
            debugPrint('  ❌ No journal_entry_id stored');
            debugPrint('═══════════════════════════════════════════');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يوجد قيد محاسبي مرتبط بأمر التعبئة'),
                  backgroundColor: AppTheme.warning));
            }
            return;
          }

          String searchKey = journalEntryId;
          try {
            final parsedId = int.tryParse(journalEntryId) ?? 0;
            final jeRes = await Supabase.instance.client
                .from('journal_entries')
                .select('id, entry_number')
                .eq('id', parsedId)
                .maybeSingle();
            if (jeRes == null && packingOrderId != null) {
              debugPrint(
                  '  ⚠️ JE #$journalEntryId not found, searching by source_id=$packingOrderId');
              final fallback = await Supabase.instance.client
                  .from('journal_entries')
                  .select('id, entry_number')
                  .eq('source_type', 'packing_order')
                  .eq('source_id', packingOrderId)
                  .order('id', ascending: false)
                  .maybeSingle();
              if (fallback != null) {
                searchKey = fallback['id'].toString();
                debugPrint(
                    '  ✅ Found JE by source_id: id=${fallback['id']}, entry_number=${fallback['entry_number']}');
              } else {
                debugPrint(
                    '  ❌ No JE found by source_id=$packingOrderId either');
              }
            } else if (jeRes != null) {
              debugPrint(
                  '  ✅ JE #$journalEntryId exists: entry_number=${jeRes['entry_number']}');
            }
          } catch (e) {
            debugPrint('  ⚠️ JE lookup error: $e');
          }

          debugPrint('  Search Key Used = "$searchKey"');
          debugPrint('═══════════════════════════════════════════');

          if (mounted) {
            JournalEntryNavigationService.openById(context,
                journalEntryId: searchKey);
          }
        },
        icon: const Icon(Icons.receipt_long, size: 18, color: Colors.white),
        label: const Text('عرض القيد المحاسبي',
            style: TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.info,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildHeaderDeleteButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton.icon(
        onPressed: _saving ? null : () => _deleteDraftOrder(),
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
        label: const Text('حذف',
            style: TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.danger,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _deleteDraftOrder() async {
    if (widget.existingOrder?.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text('هل أنت متأكد من حذف المسودة؟',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Text(
              'سيتم حذف المسودة نهائياً ولن يمكنك التراجع عن هذا الإجراء.',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'))),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('حذف',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _dao.delete(int.parse(widget.existingOrder!.id!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حذف المسودة بنجاح'),
          backgroundColor: AppTheme.success));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  String get _computedHeaderProductName {
    final distinct = _lotEntries
        .map((e) =>
            e.lot?.productName ??
            e.batch?.productName ??
            e.fallbackProductName ??
            '')
        .where((name) => name.trim().isNotEmpty)
        .toSet()
        .toList();
    if (distinct.length > 1) return distinct.join(' + ');
    if (distinct.isNotEmpty) return distinct.first;
    return _lotEntries.isNotEmpty ? (_lotEntries.first.lot?.productName ?? '') : 'محصول';
  }

  Future<void> _syncSortingsToDb(int orderId) async {
    final sortingModels = <PackingOrderSortingModel>[];
    final headerProd = _computedHeaderProductName;
    final expShipment = _exportShipmentNoCtrl.text.trim();
    final custName = _customerNameCtrl.text.trim();

    for (final entry in _lotEntries) {
      if (entry.hasSorting && entry.sortedWeight > 0) {
        final pName = entry.lot?.productName ??
            entry.batch?.productName ??
            entry.fallbackProductName ??
            headerProd;
        final lNum = entry.lot?.lotNumber;
        final unitCost = entry.isCartonMode ? entry.costPerUnit : entry.productCostPerKg;
        final totalCost = entry.sortingCost;

        sortingModels.add(PackingOrderSortingModel(
          packingOrderId: orderId,
          productName: pName,
          lotNumber: lNum,
          weightKg: entry.sortedWeight,
          remainingWeightKg: entry.sortedWeight,
          costPerKg: unitCost,
          totalCost: totalCost,
          status: 'pending',
          stationId: _selectedStationId,
          exportShipmentNo: expShipment.isNotEmpty ? expShipment : null,
          customerName: custName.isNotEmpty ? custName : null,
        ));
      }
    }

    await _sortingDao.syncSortingsForPackingOrder(
      packingOrderId: orderId,
      items: sortingModels,
    );
    DataChangeEventBus.instance.notifySortingChanged();
  }

  Future<bool> _syncFormStateToDb() async {
    final ordId = _orderId;
    if (ordId == null) return false;
    final ord = _currentOrder ?? widget.existingOrder;
    if (ord == null) return false;

    try {
      final calc = _calcResult;
      Map<String, dynamic> notes = {};
      if (ord.notes != null && ord.notes!.isNotEmpty) {
        try {
          notes = jsonDecode(ord.notes!) as Map<String, dynamic>;
        } catch (_) {}
      }

      final wastePct = double.tryParse(_materialWastePercentCtrl.text) ?? _materialWastePercent;
      notes['materials'] = _materialItems;
      notes['material_items'] = _materialItems;
      notes['material_waste_percent'] = wastePct;
      notes['waste_percentage'] = wastePct;
      final Map<String, Map<String, dynamic>> dedupedCostMap = {};
      int? resolvedEngCatId;
      for (final cat in _costCategories) {
        final cName = (cat['name'] as String? ?? '').toLowerCase();
        final cSuppType = (cat['supplier_type'] as String? ?? '').toLowerCase();
        if (cName.contains('مهندس') || cName.contains('مهندسين') || cSuppType == 'engineer') {
          resolvedEngCatId = cat['id'] as int?;
          break;
        }
      }

      for (final c in _costItems) {
        final amt = (c['total_egp'] ?? c['total'] ?? c['base_amount'] ?? 0) as num;
        if (amt <= 0) continue; // Skip zero-amount or ghost cost items!
        final rCatId = c['report_category_id'];
        final isEng = c['category'] == 'engineer_expenses' || c['supplier_type'] == 'engineer';
        if (isEng) {
          c['report_category_id'] = (resolvedEngCatId != null && resolvedEngCatId != 19)
              ? resolvedEngCatId
              : (rCatId != 19 ? rCatId : null);
        } else if (rCatId == 31251 || (rCatId is num && rCatId > 100)) {
          c['report_category_id'] = null;
        }
        if (c['item_uuid'] == null || c['item_uuid'].toString().trim().isEmpty) {
          final rawId = (c['id'] as num?)?.toInt();
          c['item_uuid'] = (rawId != null && rawId > 0) ? 'item_$rawId' : const Uuid().v4();
        }
        final rawId = (c['id'] as num?)?.toInt();
        final sig = (rawId != null && rawId > 0 && rawId < 1000000000)
            ? 'id_$rawId'
            : 'uuid_${c['item_uuid']}';
        if (!dedupedCostMap.containsKey(sig)) {
          dedupedCostMap[sig] = c;
        } else {
          final existing = dedupedCostMap[sig]!;
          final incomingSettled = (c['cost_status'] == 'actual' && c['actual_amount'] != null) ||
              c['variance_journal_entry_id'] != null;
          final existingSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
              existing['variance_journal_entry_id'] != null;
          if (incomingSettled && !existingSettled) {
            if ((c['notes'] == null || c['notes'].toString().isEmpty) &&
                existing['notes'] != null && existing['notes'].toString().isNotEmpty) {
              c['notes'] = existing['notes'];
            }
            if ((c['supplier_id'] == null || c['supplier_id'].toString().isEmpty) &&
                existing['supplier_id'] != null && existing['supplier_id'].toString().isNotEmpty) {
              c['supplier_id'] = existing['supplier_id'];
            }
            if ((c['supplier_name'] == null || c['supplier_name'].toString().isEmpty) &&
                existing['supplier_name'] != null && existing['supplier_name'].toString().isNotEmpty) {
              c['supplier_name'] = existing['supplier_name'];
            }
            dedupedCostMap[sig] = c;
          } else {
            if ((existing['notes'] == null || existing['notes'].toString().isEmpty) &&
                c['notes'] != null && c['notes'].toString().isNotEmpty) {
              existing['notes'] = c['notes'];
            }
            if ((existing['supplier_id'] == null || existing['supplier_id'].toString().isEmpty) &&
                c['supplier_id'] != null && c['supplier_id'].toString().isNotEmpty) {
              existing['supplier_id'] = c['supplier_id'];
            }
            if ((existing['supplier_name'] == null || existing['supplier_name'].toString().isEmpty) &&
                c['supplier_name'] != null && c['supplier_name'].toString().isNotEmpty) {
              existing['supplier_name'] = c['supplier_name'];
            }
          }
        }
      }
      _costItems.clear();
      _costItems.addAll(dedupedCostMap.values);
      notes['cost_items'] = _costItems;
      if (_isRollingWasteMode || _returnPackagingWasteCost > 0) {
        notes['waste_settlement_summary'] = {
          'cumulative_waste_pool': _cumulativePendingWastePool,
          'current_order_waste': _currentOrderCalculatedWaste,
          'settled_amount': _rollingSettledWasteAmount,
          'remaining_unsettled': _unsettledMaterialWasteCost,
          'status': _wasteSettlementStatusLabel,
        };
      }

      // Sync fruit allocations, waste data, and sorting data into notes
      final fruitAllocations = <Map<String, dynamic>>[];
      for (final entry in _lotEntries) {
        if (entry.batch != null) {
          fruitAllocations.add({
            'batch_id': entry.batch!.id,
            'quantity': entry.effectiveWeight,
            'product_name': entry.batch!.productName,
            'product_code': entry.batch!.productCode,
          });
        }
        if (entry.usePartialCrop) {
          notes['use_partial_crop'] = true;
          notes['partial_weight_kg'] =
              entry.partialWeightCtrl.text.isNotEmpty
                  ? double.tryParse(entry.partialWeightCtrl.text) ?? 0
                  : 0;
        }
      }
      if (fruitAllocations.isNotEmpty) {
        notes['fruit_allocation'] = fruitAllocations.length == 1
            ? fruitAllocations.first
            : fruitAllocations;
      }

      notes['total_raw_weight_kg'] = _lotEntries.fold(0.0, (sum, e) {
        if (e.isCartonMode) {
          return sum + e.effectiveWeight * e.exactCartonNetWeight;
        } else {
          return sum + e.effectiveWeight;
        }
      });

      final wasteData = <Map<String, dynamic>>[];
      final sortingData = <Map<String, dynamic>>[];
      for (int i = 0; i < _lotEntries.length; i++) {
        final entry = _lotEntries[i];
        if (entry.wasteCost > 0) {
          final wWeight = entry.wasteWeight > 0
              ? entry.wasteWeight
              : (entry.wastePercent > 0 ? entry.effectiveWeight * (entry.wastePercent / 100.0) : 0.0);
          final wUnitPrice = wWeight > 0 ? (entry.wasteCost / wWeight) : entry.costPerUnit;
          wasteData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'waste_percent': entry.wastePercent,
            'waste_weight_kg': wWeight,
            'waste_cost': entry.wasteCost,
            'quantity': wWeight,
            'unit_price': wUnitPrice,
          });
        }
        if (entry.hasSorting && entry.sortedWeight > 0) {
          final sWeight = entry.sortedWeight;
          final sUnitPrice = sWeight > 0 ? (entry.sortingCost / sWeight) : entry.costPerUnit;
          sortingData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'sorted_weight_kg': sWeight,
            'sorting_cost': entry.sortingCost,
            'quantity': sWeight,
            'unit_price': sUnitPrice,
          });
        }
      }
      if (wasteData.isNotEmpty) {
        notes['waste_data'] = wasteData.length == 1 ? wasteData.first : wasteData;
        notes['waste_weight_kg'] = wasteData.fold<double>(
            0, (s, w) => s + (w['waste_weight_kg'] as num).toDouble());
        notes['waste_cost'] = wasteData.fold<double>(
            0, (s, w) => s + (w['waste_cost'] as num).toDouble());
      } else {
        notes.remove('waste_data');
        notes.remove('waste_weight_kg');
        notes.remove('waste_cost');
      }
      if (sortingData.isNotEmpty) {
        notes['sorting_data'] = sortingData.length == 1 ? sortingData.first : sortingData;
        notes['sorted_weight_kg'] = sortingData.fold<double>(
            0, (s, w) => s + (w['sorted_weight_kg'] as num).toDouble());
        notes['sorting_cost'] = sortingData.fold<double>(
            0, (s, w) => s + (w['sorting_cost'] as num).toDouble());
      } else {
        notes.remove('sorting_data');
        notes.remove('sorted_weight_kg');
        notes.remove('sorting_cost');
      }

      if (_lotEntries.isNotEmpty) {
        notes['product_cost_per_kg'] = _lotEntries.first.productCostPerKg;
      }

      final safeStatus = ord.isCostsConfirmed
          ? 'costs_confirmed'
          : (ord.isPackagingConfirmed
              ? 'packaging_confirmed'
              : (ord.isCropsConfirmed ? 'crops_confirmed' : ord.status));

      final lines = <PackingOrderLineModel>[];
      final headerProd = _computedHeaderProductName;
      for (int i = 0; i < _lotEntries.length; i++) {
        final entry = _lotEntries[i];
        final calcLine =
            i < calc.packingLines.length ? calc.packingLines[i] : null;
        final fTypeId = int.tryParse(entry.lot?.fruitTypeId ?? '') ??
            entry.batch?.fruitTypeId;
        final prodName = entry.lot?.productName ??
            entry.batch?.productName ??
            entry.fallbackProductName ??
            headerProd;

        lines.add(PackingOrderLineModel(
          id: entry.lineId,
          packingOrderId: ordId,
          fruitTypeId: fTypeId,
          productName: prodName,
          grade: 'A',
          sourceLotId: entry.lot?.id,
          batchId: entry.batch?.id.toString(),
          quantity: entry.effectiveWeight,
          cartonCount: entry.cartonCount,
          netWeightPerCarton: entry.exactCartonNetWeight,
          grossWeightPerCarton: entry.grossWeightPerCartonValue > 0
              ? entry.grossWeightPerCartonValue
              : entry.exactCartonNetWeight,
          totalNetWeight: calcLine?.totalNetWeight ?? entry.totalNetWeight,
          totalGrossWeight:
              calcLine?.totalGrossWeight ?? entry.totalGrossWeight,
          unitCost: entry.costPerUnit / (entry.lot?.exchangeRate ?? 1.0),
          rawMaterialCost: calcLine?.rawMaterialCost ?? entry.totalPurchaseCost,
          wasteWeightKg: entry.wasteWeight > 0
              ? entry.wasteWeight
              : (entry.wastePercent > 0 ? entry.effectiveWeight * (entry.wastePercent / 100.0) : 0.0),
          wasteCost: entry.wasteCost,
          sortedWeightKg: entry.hasSorting ? entry.sortedWeight : 0,
          sortingCost: calcLine?.sortingCost ?? entry.sortingCost,
          specificPackagingCost: calcLine?.specificPackagingCost ?? 0,
          allocatedSharedPackaging: calcLine?.allocatedSharedPackaging ?? 0,
          allocatedCostItems: calcLine?.allocatedCostItems ?? 0,
          finalCost: calcLine?.finalCost ?? 0,
          finalUnitCost: calcLine?.finalUnitCost ?? 0,
        ));
      }

      await _dao.update(
        ordId,
        ord.copyWith(
          status: safeStatus,
          notes: jsonEncode(notes),
          actualMaterialCost: calc.materials.totalMaterialsWithWaste,
          estimatedMaterialCost: calc.materials.materialCost,
          materialCostBase: calc.materials.materialCost,
          otherCostBase: calc.costItems.totalCostItems,
          fruitCostAllocated: calc.finalCost.fruitCost,
          fruitCostBase: calc.finalCost.totalRawCost,
          exportShipmentNo: _exportShipmentNoCtrl.text.trim().isNotEmpty ? _exportShipmentNoCtrl.text.trim() : ord.exportShipmentNo,
          customerName: _customerNameCtrl.text.trim().isNotEmpty ? _customerNameCtrl.text.trim() : ord.customerName,
          lines: lines.isNotEmpty ? lines : ord.lines,
        ),
      );
      await _refreshCurrentOrder();
      return true;
    } catch (e) {
      debugPrint('Error syncing form state to DB: $e');
      return false;
    }
  }

  Future<void> _confirmCropsStage() async {
    final id = _orderId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب حفظ أمر التعبئة كمسودة أولاً'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    // 1. التحقق من تفعيل خيار الفرز ووجود كميات مخصصة للفرز في تفاصيل المحصول
    for (int i = 0; i < _lotEntries.length; i++) {
      final entry = _lotEntries[i];
      if (entry.hasSorting) {
        if (entry.sortedWeight <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('الرجاء إدخال كمية صحيحة للفرز في البند #${i + 1} أو إلغاء تفعيل الفرز'),
              backgroundColor: AppTheme.warning,
            ),
          );
          return;
        }
        if (entry.sortedWeight > entry.effectiveWeight) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('كمية الفرز في البند #${i + 1} (${entry.sortedWeight.toStringAsFixed(1)}) أكبر من الوزن المتاح (${entry.effectiveWeight.toStringAsFixed(1)})'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
        if ((entry.sortedWeight + entry.wasteWeight) > entry.effectiveWeight) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('مجموع الفرز والهالك في البند #${i + 1} يتجاوز الوزن الإجمالي للمحصول'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text(
              _isCropsConfirmed
                  ? 'تحديث وصرف المحاصيل (المرحلة 1)'
                  : 'تأكيد وصرف المحاصيل (المرحلة 1)',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم تنفيذ العمليات التالية:\n'
                '• حفظ وتحديث بيانات المحاصيل والأوزان والفرز في أمر التعبئة.\n'
                '• إدراج/تحديث سجلات الفرز لتظهر فوراً في شاشة الفرز بحالة "قيد الانتظار".\n'
                '• خصم الكميات المستخدمة (${_totalEffectiveWeight.toStringAsFixed(1)} كجم) من أرصدة المحاصيل بالمخزن.\n'
                '• توليد/تحديث القيد المحاسبي لصرف الفاكهة والفرز (12413 و 12414 / 12412).\n'
                '• يظل بإمكانك التعديل والإضافة طالما لم يتم الإقفال النهائي من كرت الأمر بالخارج.',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontFamily: 'Cairo',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'هل أنت متأكد من الاستمرار؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              child: Text(_isCropsConfirmed ? 'تحديث وصرف' : 'تأكيد وصرف',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _stageLoading = true;
      _isConfirmingCosts = true;
    });
    try {
      // 1. Sync form state (allocations, notes, lines) to DB
      await _syncFormStateToDb();

      // 2. Sync sortings linked to this packing order
      await _syncSortingsToDb(id);

      // 3. Confirm crops stage in Supabase (stock deduction & accounting journal entry)
      final error = await _dao.confirmCropsStage(id);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد وصرف المحاصيل وتحديث سجلات الفرز بنجاح (المرحلة 1 مكتملة)'),
            backgroundColor: AppTheme.success,
          ),
        );
        DataChangeEventBus.instance.notifySortingChanged();
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        DataChangeEventBus.instance.notifyJournalEntriesChanged();
        DataChangeEventBus.instance.notifyPackingOrdersChanged();
        await _refreshCurrentOrder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تأكيد المحاصيل: $error'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _stageLoading = false);
    }
  }

  Future<void> _confirmPackagingStage() async {
    final id = _orderId;
    if (id == null) return;
    if (!_isCropsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إتمام المرحلة 1 (المحاصيل) أولاً'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text(
              _currentOrder?.packagingJournalEntryId != null
                  ? 'تحديث وصرف مواد التعبئة (المرحلة 2)'
                  : 'تأكيد وصرف مواد التعبئة (المرحلة 2)',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم تنفيذ العمليات التالية:\n'
                '• حفظ خامات ومواد التعبئة الحالية (${_materialItems.length} مواد) ونسبة الفقد الفعلية.\n'
                '• خصم مواد التعبئة المستخدمة وفاقد الهالك من المخزن.\n'
                '• توليد/تحديث قيد صرف مواد التعبئة (12413 / 12411).\n'
                '• يظل بإمكانك التعديل أو إضافة مواد جديدة طالما لم يتم الإقفال النهائي من كرت الأمر.',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontFamily: 'Cairo',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'هل أنت متأكد من الاستمرار؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA855F7)),
              child: Text(
                  _currentOrder?.packagingJournalEntryId != null
                      ? 'تحديث وصرف'
                      : 'تأكيد وصرف',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _stageLoading = true;
      _isConfirmingCosts = true;
    });
    try {
      await _syncFormStateToDb();
      final error = await _dao.confirmPackagingStage(id);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد وصرف مواد التعبئة بنجاح (المرحلة 2 مكتملة)'),
            backgroundColor: AppTheme.success,
          ),
        );
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        await _refreshCurrentOrder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تأكيد مواد التعبئة: $error'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _stageLoading = false);
    }
  }

Future<void> _confirmCostsStage() async {
    final id = _orderId;
    if (id == null) return;
    if (_isConfirmingCosts || _stageLoading) return;
    if (!_isPackagingConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إتمام المرحلة 2 (مواد التعبئة) أولاً'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text(
              _currentOrder?.costsJournalEntryId != null
                  ? 'تحديث وترحيل التكاليف (المرحلة 3)'
                  : 'تأكيد وترحيل التكاليف (المرحلة 3)',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم تنفيذ العمليات التالية:\n'
                '• حفظ بنود التكاليف الحالية (${_costItems.length} بنود).\n'
                '• ترحيل القيود المحاسبية للتكاليف والمصاريف الإضافية.\n'
                '• إثبات مستحقات الموردين وتحديث كشوف حساباتهم.\n'
                '• يظل بإمكانك التعديل أو إضافة بنود تكلفة أخرى طالما لم يتم الإقفال النهائي.',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontFamily: 'Cairo',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'هل أنت متأكد من الاستمرار؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
              child: Text(
                  _currentOrder?.costsJournalEntryId != null
                      ? 'تحديث وترحيل'
                      : 'تأكيد وترحيل',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _stageLoading = true;
      _isConfirmingCosts = true;
    });
    try {
      await _syncFormStateToDb();
      final error = await _dao.confirmCostsStage(id);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد وترحيل التكاليف بنجاح (المرحلة 3 مكتملة)'),
            backgroundColor: AppTheme.success,
          ),
        );
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        await _refreshCurrentOrder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تأكيد التكاليف: $error'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _stageLoading = false;
          _isConfirmingCosts = false;
        });
      }
    }
  }

  Future<void> _confirmFinalStage() async {
    final id = _orderId;
    if (id == null) return;
    if (!_isCostsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إتمام المرحلة 3 (التكاليف) أولاً'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text('الاعتماد النهائي لأمر التعبئة (المرحلة 4)',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم اعتماد أمر التعبئة بشكل نهائي وإغلاقه بالكامل.\n'
                'لن يمكن إجراء أي تعديلات إضافية على هذا الأمر.',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontFamily: 'Cairo',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'هل تريد تأكيد الاعتماد النهائي والإغلاق؟',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              child: const Text('اعتماد نهائي وإغلاق',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _stageLoading = true);
    try {
      final error = await _dao.confirmFinalStage(id);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الاعتماد النهائي لأمر التعبئة وإغلاقه بنجاح!'),
            backgroundColor: AppTheme.success,
          ),
        );
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifySuppliersChanged();
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        await _refreshCurrentOrder();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الاعتماد النهائي: $error'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _stageLoading = false);
    }
  }

  Widget _buildWorkflowStageStepper(bool isDark) {
    final currentStage = _currentOrder?.currentStageIndex ?? (widget.existingOrder?.currentStageIndex ?? 0);

    final steps = [
      {
        'index': 1,
        'title': 'المحاصيل والخام',
        'icon': Icons.eco_outlined,
        'isCompleted': _isCropsConfirmed,
        'isActive': !_isCropsConfirmed,
      },
      {
        'index': 2,
        'title': 'مواد التعبئة',
        'icon': Icons.inventory_2_outlined,
        'isCompleted': _isPackagingConfirmed,
        'isActive': _isCropsConfirmed && !_isPackagingConfirmed,
      },
      {
        'index': 3,
        'title': 'التكاليف والمصاريف',
        'icon': Icons.payments_outlined,
        'isCompleted': _isCostsConfirmed,
        'isActive': _isPackagingConfirmed && !_isCostsConfirmed,
      },
      {
        'index': 4,
        'title': 'الاعتماد النهائي',
        'icon': Icons.verified_outlined,
        'isCompleted': _isFinalApproved,
        'isActive': _isCostsConfirmed && !_isFinalApproved,
      },
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
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
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.linear_scale, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'مسار تدفق واعتماد أمر التعبئة (Workflow Pipeline)',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'Cairo',
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isFinalApproved
                      ? AppTheme.success.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isFinalApproved
                      ? 'مكتمل بالكامل'
                      : 'المرحلة $currentStage من 4',
                  style: TextStyle(
                    color: _isFinalApproved ? AppTheme.success : AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                final prevStepIdx = index ~/ 2;
                final prevCompleted = steps[prevStepIdx]['isCompleted'] as bool;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(top: 17),
                    decoration: BoxDecoration(
                      color: prevCompleted
                          ? AppTheme.success
                          : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }
              final stepIdx = index ~/ 2;
              final step = steps[stepIdx];
              final isCompleted = step['isCompleted'] as bool;
              final isActive = step['isActive'] as bool;
              final title = step['title'] as String;
              final icon = step['icon'] as IconData;

              Color circleColor;
              Color iconColor;
              if (isCompleted) {
                circleColor = AppTheme.success;
                iconColor = Colors.white;
              } else if (isActive) {
                circleColor = AppTheme.primary;
                iconColor = Colors.white;
              } else {
                circleColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
                iconColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);
              }

              return SizedBox(
                width: 72,
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive
                              ? (isDark ? Colors.white : AppTheme.primary.withValues(alpha: 0.5))
                              : Colors.transparent,
                          width: isActive ? 2 : 0,
                        ),
                        boxShadow: isActive || isCompleted
                            ? [
                                BoxShadow(
                                  color: (isCompleted ? AppTheme.success : AppTheme.primary)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          isCompleted ? Icons.check : icon,
                          size: 18,
                          color: iconColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
                        color: isCompleted
                            ? AppTheme.success
                            : (isActive
                                ? (isDark ? Colors.white : AppTheme.primary)
                                : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }


  Widget _buildCard(String title, Widget child) {
    final isDark = AppTheme.isDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x8C05192D) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1),
            boxShadow: [
              BoxShadow(
                color: isDark ? AppTheme.primary.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
                blurRadius: 25,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarehouseFilterSection(bool isDark) {
    String scopeLabel;
    IconData scopeIcon;
    Color scopeColor;

    if (_isAllStations) {
      scopeLabel = 'كافة المخازن المتاحة';
      scopeIcon = Icons.warehouse_rounded;
      scopeColor = const Color(0xFF0284C7);
    } else if (_selectedStationIds.length == 1) {
      final singleId = _selectedStationIds.first;
      final stName = _getStationName(singleId);
      scopeLabel = stName.length > 25 ? '${stName.substring(0, 22)}...' : stName;
      scopeIcon = Icons.warehouse_rounded;
      scopeColor = const Color(0xFF059669);
    } else if (_selectedStationIds.isNotEmpty) {
      scopeLabel = '${_selectedStationIds.length} مخازن محددة';
      scopeIcon = Icons.domain_rounded;
      scopeColor = const Color(0xFF8B5CF6);
    } else {
      scopeLabel = 'يرجى اختيار مخزن';
      scopeIcon = Icons.warning_amber_rounded;
      scopeColor = AppTheme.warning;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final screenW = MediaQuery.of(context).size.width;
                final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
                final isNarrow = effectiveW < 750;

                final badge = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scopeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scopeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(scopeIcon, size: 13, color: scopeColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          scopeLabel,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: scopeColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: scopeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.warehouse_rounded, color: scopeColor, size: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تحديد المخازن ونطاق السحب للتشغيلة',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          badge,
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'حدد المخازن المسموح بالسحب منها (المحاصيل ومواد التعبئة)',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scopeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.warehouse_rounded, color: scopeColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تحديد المخازن ونطاق السحب للتشغيلة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'حدد المخازن المسموح بالسحب منها (المحاصيل ومواد التعبئة) — يمكنك اختيار أكثر من مخزن',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    badge,
                  ],
                );
              },
            ),
          ),
          if (_stations.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 38,
                child: TextField(
                  onChanged: (val) => setState(() => _stationSearchQuery = val.trim()),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: 'بحث في المخازن المتاحة (${_stations.length} مخزن)...',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final maxChipWidth = constraints.maxWidth;
                final filtered = _stationSearchQuery.isEmpty
                    ? _stations
                    : _stations.where((s) => s.name.toLowerCase().contains(_stationSearchQuery.toLowerCase())).toList();

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ...filtered.map((st) {
                      final stKey = _getStationKey(st);
                      final isSelected = _selectedStationIds.contains(stKey);

                      return ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxChipWidth),
                        child: FilterChip(
                          avatar: Icon(
                            Icons.store_mall_directory_rounded,
                            size: 16,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppTheme.textSecondary : Colors.black54),
                          ),
                          label: Text(
                            st.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedStationIds.add(stKey);
                                _selectedStationId = stKey;
                                _isAllStations = false;
                              } else {
                                if (_selectedStationIds.length > 1) {
                                  _selectedStationIds.remove(stKey);
                                  _selectedStationId = _selectedStationIds.first;
                                }
                              }
                            });
                            _onWarehouseScopeChanged();
                          },
                          selectedColor: const Color(0xFF059669),
                          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF059669)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseSection() {
    int getStationKey(StationModel s) {
      return int.tryParse(s.id ?? '') ?? s.id.hashCode.abs();
    }

    final validStationIds = _stations.map(getStationKey).toSet();

    final selectedValue = validStationIds.contains(_selectedStationId)
        ? _selectedStationId
        : null;

    final isDark = AppTheme.isDark(context);

    return DropdownButtonFormField<int>(
      value: selectedValue,
      decoration: _inputDecoration('المخزن'),
      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
      style: TextStyle(
          color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold),
      items: _stations.map((s) {
        final stId = getStationKey(s);
        return DropdownMenuItem<int>(
          value: stId,
          child: Text(
            s.name,
            style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
          ),
        );
      }).toList(),
      onChanged: (v) async {
        if (v != null && _selectedStationId != v && _hasAnyLotsSelected()) {
          final confirmed = await _showWarehouseChangeDialog();
          if (!confirmed) return;
          for (final e in _lotEntries) {
            e.dispose();
          }
          _lotEntries
            ..clear()
            ..add(_LotEntry());
          _materialItems.clear();
          _costItems.clear();
        }
        setState(() {
          _selectedStationId = v;
        });
        if (v != null) {
          final matchedStation = _stations.firstWhere(
            (s) => getStationKey(s) == v,
            orElse: () => _stations.first,
          );
          final rawId = int.tryParse(matchedStation.id ?? '') ?? v;
          _filterLotsFromCache(rawId);
          if (mounted) setState(() {});
          final products = await _stationProductDao.getByStation(rawId);
          if (mounted) {
            setState(() => _warehouseProducts = products);
          }
          await Future.wait([
            _loadMaterialProducts(rawId),
            _fetchLotRemainingQuantities(rawId),
          ]);
        }
      },
      validator: (v) => v == null ? 'اختر المخزن' : null,
    );
  }

  Widget _buildShipmentReferenceSection(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        final shipmentField = Autocomplete<String>(
          initialValue: TextEditingValue(text: _exportShipmentNoCtrl.text),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (_recentExportShipments.isEmpty) {
              return const Iterable<String>.empty();
            }
            final q = textEditingValue.text.trim().toLowerCase();
            if (q.isEmpty) {
              return _recentExportShipments
                  .map((s) => s['shipment_no']?.toString() ?? '')
                  .where((s) => s.isNotEmpty)
                  .take(8);
            }
            return _recentExportShipments
                .where((s) {
                  final no = (s['shipment_no']?.toString() ?? '').toLowerCase();
                  final cust = (s['customer_name']?.toString() ?? '').toLowerCase();
                  return no.contains(q) || cust.contains(q);
                })
                .map((s) => s['shipment_no']?.toString() ?? '')
                .where((s) => s.isNotEmpty);
          },
          onSelected: (String selection) {
            _exportShipmentNoCtrl.text = selection;
            final matched = _recentExportShipments.firstWhere(
              (s) => s['shipment_no']?.toString() == selection,
              orElse: () => {},
            );
            if (matched.isNotEmpty &&
                matched['customer_name'] != null &&
                _customerNameCtrl.text.trim().isEmpty) {
              _customerNameCtrl.text = matched['customer_name'].toString();
            }
            setState(() {});
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            if (textEditingController.text != _exportShipmentNoCtrl.text) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (textEditingController.text != _exportShipmentNoCtrl.text) {
                  textEditingController.text = _exportShipmentNoCtrl.text;
                }
              });
            }
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: !_isViewOnly,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              decoration: _inputDecoration(
                'رقم الشحنة التصديرية (Export Shipment No)',
                hint: 'مثال: EXP-2026-001 أو رقم الحاوية/الشحنة',
                suffixIcon: textEditingController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          textEditingController.clear();
                          _exportShipmentNoCtrl.clear();
                          setState(() {});
                        },
                      )
                    : const Icon(Icons.local_shipping_outlined,
                        color: AppTheme.primary, size: 20),
              ),
              onChanged: (val) {
                _exportShipmentNoCtrl.text = val;
              },
            );
          },
        );

        final customerField = Autocomplete<String>(
          initialValue: TextEditingValue(text: _customerNameCtrl.text),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (_knownCustomerNames.isEmpty) {
              return const Iterable<String>.empty();
            }
            final q = textEditingValue.text.trim().toLowerCase();
            if (q.isEmpty) {
              return _knownCustomerNames.take(8);
            }
            return _knownCustomerNames
                .where((c) => c.toLowerCase().contains(q));
          },
          onSelected: (String selection) {
            _customerNameCtrl.text = selection;
            setState(() {});
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            if (textEditingController.text != _customerNameCtrl.text) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (textEditingController.text != _customerNameCtrl.text) {
                  textEditingController.text = _customerNameCtrl.text;
                }
              });
            }
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              enabled: !_isViewOnly,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              decoration: _inputDecoration(
                'اسم العميل / المستورد (Customer Name)',
                hint: 'مثال: اسم المستورد أو الشركة المشترية',
                suffixIcon: textEditingController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          textEditingController.clear();
                          _customerNameCtrl.clear();
                          setState(() {});
                        },
                      )
                    : const Icon(Icons.person_outline,
                        color: Color(0xFF8B5CF6), size: 20),
              ),
              onChanged: (val) {
                _customerNameCtrl.text = val;
              },
            );
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: shipmentField),
                  const SizedBox(width: 16),
                  Expanded(child: customerField),
                ],
              )
            else ...[
              shipmentField,
              const SizedBox(height: 12),
              customerField,
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 15, color: AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تسجيل رقم الشحنة التصديرية أو اسم العميل يساعد في تمييز أمر التعبئة وسرعة اختياره وفلترته عند إنشاء الشحنة التصديرية.',
                    style: TextStyle(
                      color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  bool _hasAnyLotsSelected() => _lotEntries.any((e) => e.lot != null);

  Future<bool> _showWarehouseChangeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
          title: Text('تأكيد تغيير المخزن',
              style: TextStyle(
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold)),
          content: Text('سيتم مسح جميع المحاصيل المحددة. هل أنت متأكد؟',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.textSecondary : Colors.black87)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white),
              child: const Text('تأكيد',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  List<Widget> _buildLotEntries() {
    final isDark = AppTheme.isDark(context);
    final widgets = <Widget>[];
    for (int i = 0; i < _lotEntries.length; i++) {
      widgets.add(_buildLotEntryCard(i));
      widgets.add(const SizedBox(height: 16));
    }
    if (!_isViewOnly && !_stockFieldsLocked) {
      widgets.add(_buildAddLotButton());
      widgets.add(const SizedBox(height: 16));
    }
    widgets.add(_buildCropsStageActionBar(isDark));
    return widgets;
  }

  Widget _buildCropsStageActionBar(bool isDark) {
    final totalUsedWeight =
        _lotEntries.fold<double>(0.0, (s, e) => s + e.effectiveWeight);

    if (_isCropsConfirmed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF0284C7), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المرحلة 1: تم تأكيد وصرف المحاصيل من المخزن',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0369A1),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(_isOrderFinalized ? Icons.lock : Icons.edit_note, size: 12, color: const Color(0xFF0284C7)),
                      const SizedBox(width: 4),
                      Text(
                        _isOrderFinalized ? 'مقفل نهائياً' : 'مؤكد (قابل للتعديل)',
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_currentOrder?.cropsConfirmedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'تاريخ التأكيد والصرف: ${_formatStageDate(_currentOrder?.cropsConfirmedAt)}',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
            if (_currentOrder?.cropsJournalEntryId != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: _currentOrder!.cropsJournalEntryId,
                  );
                },
                icon: const Icon(Icons.receipt_long, size: 16, color: Color(0xFF0284C7)),
                label: Text(
                  'عرض قيد إخراج وصرف الفاكهة (#${_currentOrder!.cropsJournalEntryId})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0284C7)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
            if (!_isOrderFinalized) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _stageLoading ? null : _confirmCropsStage,
                  icon: const Icon(Icons.sync, size: 16, color: Color(0xFF0284C7)),
                  label: const Text(
                    'تحديث وصرف المحاصيل (المرحلة 1)',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_orderId == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.info, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'يجب حفظ أمر التعبئة كمسودة أولاً قبل بدء التأكيد المرحلي للمحاصيل والمواد.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.info),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_outlined, color: AppTheme.success, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المرحلة 1: تأكيد وصرف المحاصيل والخام',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF166534),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'سيتم خصم كميات المحاصيل المستخدمة (${totalUsedWeight.toStringAsFixed(1)} كجم) من المخزن وتوليد قيد إخراج الفاكهة وقفل بيانات المحاصيل.',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black87,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stageLoading ? null : _confirmCropsStage,
              icon: _stageLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text(
                'تأكيد وصرف المحاصيل (المرحلة 1)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLotEntryCard(int index) {
    final entry = _lotEntries[index];
    final title =
        _lotEntries.length > 1 ? 'المحصول #${index + 1}' : 'اختر المحصول';

    return _buildCard(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLotDropdown(index, entry),
          if (entry.lot != null) ...[
            const SizedBox(height: 16),
            _buildEntryWeightSection(entry),
            const SizedBox(height: 16),
            _buildEntryCartonSection(entry),
          ],
          if (_lotEntries.length > 1) ...[
            const SizedBox(height: 12),
            _buildDeleteLotButton(index),
          ],
        ],
      ),
    );
  }

  Widget _buildLotDropdown(int index, _LotEntry entry) {
    final options = <StationProductBatch>[];
    for (final b in _availableBatches) {
      if (b.id == null) continue;
      if (b.id == entry.batch?.id || _getBatchRemainingForEntry(b, entry) > 0.001) {
        options.add(b);
      }
    }
    if (entry.batch != null && !options.any((b) => b.id == entry.batch!.id)) {
      options.add(entry.batch!);
    }
    final seenIds = <int>{};
    final uniqueOptions =
        options.where((b) => b.id != null && seenIds.add(b.id!)).toList();

    final isDark = AppTheme.isDark(context);
    return DropdownButtonFormField<int>(
      initialValue: entry.batch?.id,
      decoration: _inputDecoration('اختر الدفعة'),
      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
      style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
          fontSize: 14),
      isExpanded: true,
      items: uniqueOptions.map((b) {
        final matchedLot = _allLots.firstWhere(
          (l) => l.lotNumber == b.productCode,
          orElse: () => LotReceiptModel(
              lotNumber: b.productCode,
              productName: b.productName,
              receiptDate: DateTime.now(),
              purchaseMode: 'weight'),
        );
        final isCarton = matchedLot.purchaseMode == 'carton';
        final rem = _getBatchRemainingForEntry(b, entry);
        final remainingDisplay = isCarton
            ? rem.toInt().toString()
            : (rem == rem.roundToDouble()
                ? rem.toInt().toString()
                : rem.toStringAsFixed(1));
        final unit = isCarton ? 'كرتونة' : 'كجم';
        final displayPrice = b.unitCost;
        return DropdownMenuItem<int>(
          value: b.id!,
          child: Text(
            '${b.productCode} — ${b.productName}${_getStationName(b.stationId).isNotEmpty ? ' | ' + _getStationName(b.stationId) : ''} (سعر ${displayPrice.toStringAsFixed(2)}) — متاح $remainingDisplay $unit',
            style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: _stockFieldsLocked
          ? null
          : (v) {
              setState(() {
                final batch = v != null
                    ? _availableBatches.where((b) => b.id == v).firstOrNull
                    : null;
                entry.batch = batch;
                entry.lot = batch != null
                    ? _allLots.firstWhere(
                        (l) => l.lotNumber == batch.productCode,
                        orElse: () => LotReceiptModel(
                          lotNumber: batch.productCode,
                          productName: batch.productName,
                          receiptDate: DateTime.now(),
                          purchaseMode: 'weight',
                        ),
                      )
                    : null;

                entry.hasSorting = false;
                entry.usePartialCrop = false;
                entry.partialWeightCtrl.clear();
                entry.sortedWeightCtrl.clear();

                if (entry.lot != null && entry.lot!.purchaseMode == 'carton') {
                  final lot = entry.lot!;
                  entry.cartonCountCtrl.text =
                      lot.cartonCount != null && lot.cartonCount! > 0
                          ? lot.cartonCount.toString()
                          : '';
                  entry.netWeightPerCartonCtrl.text =
                      lot.weightPerCartonKg != null &&
                              lot.weightPerCartonKg! > 0
                          ? lot.weightPerCartonKg.toString()
                          : '';
                  entry.grossWeightPerCartonCtrl.text =
                      lot.grossWeightPerCartonKg != null &&
                              lot.grossWeightPerCartonKg! > 0
                          ? lot.grossWeightPerCartonKg.toString()
                          : '';
                } else {
                  entry.cartonCountCtrl.clear();
                  entry.netWeightPerCartonCtrl.clear();
                  entry.grossWeightPerCartonCtrl.clear();
                }

                if (entry.lot != null && entry.batch != null) {
                  final lot = entry.lot!;
                  final remaining = _getBatchRemainingForEntry(entry.batch!, entry);
                  final isCarton = lot.purchaseMode == 'carton';
                  entry.usePartialCrop = true;
                  if (isCarton) {
                    entry.partialWeightCtrl.text = remaining.toInt().toString();
                  } else {
                    entry.partialWeightCtrl.text =
                        (remaining == remaining.roundToDouble()
                            ? remaining.toInt().toString()
                            : remaining.toStringAsFixed(2));
                  }
                  entry.updateCartonCountFromDeductions();
                  if (!isCarton && entry.cartonCount > 0) {
                    entry.autoCalculateNetWeightPerCarton();
                  }
                }
              });
            },
      validator: (v) => v == null ? 'اختر الدفعة' : null,
    );
  }

  Widget _buildEntryWeightSection(_LotEntry entry) {
    final isDark = AppTheme.isDark(context);
    final lot = entry.lot!;
    final isCarton = entry.isCartonMode;
    final remaining = entry.batch != null
        ? _getBatchRemainingForEntry(entry.batch!, entry)
        : entry.grossWeight;
    final unit = isCarton ? 'كرتونة' : 'كجم';
    final remainingStr = isCarton
        ? remaining.toInt().toString()
        : (remaining == remaining.roundToDouble()
            ? remaining.toInt().toString()
            : remaining.toStringAsFixed(1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                value: true,
                onChanged: null,
                title: Text(
                    isCarton ? 'استخدام جزء من الكراتين' : 'تجزئة المحصول',
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
              ),
            ),
          ],
        ),
        if (entry.batch != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? AppTheme.primary.withValues(alpha: 0.3)
                    : AppTheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _stockFieldsLocked
                      ? 'حالة رصيد الدفعة:'
                      : 'الرصيد المتبقي المتاح للدفعة:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textPrimary : Colors.black87,
                  ),
                ),
                Text(
                  _stockFieldsLocked
                      ? 'تم الصرف بنجاح (المرحلة 1 مؤكدة)'
                      : '$remainingStr $unit',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _stockFieldsLocked
                        ? AppTheme.success
                        : (remaining > 0 ? AppTheme.primary : AppTheme.danger),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (entry.usePartialCrop) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: entry.partialWeightCtrl,
            enabled: !_stockFieldsLocked,
            decoration: _inputDecoration(isCarton
                ? 'عدد الكراتين المستخدمة (كرتونة)'
                : 'الكمية المستخدمة من المحصول (كجم)'),
            keyboardType: isCarton
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
            ],
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 15),
            onChanged: (_) {
              entry.updateCartonCountFromDeductions();
              if (!entry.isCartonMode && entry.cartonCount > 0) {
                entry.autoCalculateNetWeightPerCarton();
              }
              setState(() {});
            },
            validator: (v) {
              if (isCarton) {
                final n = (double.tryParse(v ?? '') ?? 0).round();
                if (n <= 0) return 'يجب أن تكون الكمية أكبر من الصفر';
                if (n > remaining.toInt() && !_stockFieldsLocked)
                  return 'الكمية تتجاوز العدد المتبقي (${remaining.toInt()})';
                return null;
              }
              final n = double.tryParse(v ?? '');
              if (n == null || n <= 0)
                return 'يجب أن تكون الكمية أكبر من الصفر';
              if (n > remaining + 0.001 && !_stockFieldsLocked)
                return 'الكمية تتجاوز الوزن المتبقي ($remainingStr كجم)';
              return null;
            },
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        TextFormField(
          controller: entry.wastePercentCtrl,
          enabled: !_stockFieldsLocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: _inputDecoration('نسبة هالك المحصول (%)').copyWith(
            prefixIcon: const Icon(Icons.percent_rounded, color: AppTheme.warning, size: 18),
            hintText: 'أدخل نسبة الهالك (مثال: 1.5 أو 3 أو 5.25)',
            helperText: entry.wastePercent > 0
                ? 'نسبة الهالك المطبقة: ${entry.wastePercent % 1 == 0 ? entry.wastePercent.toInt() : entry.wastePercent}%'
                : 'اترك الحقل فارغاً أو 0 إذا لم يكن هناك هالك للمحصول',
            helperStyle: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
            ),
            suffixIcon: entry.wastePercent > 0 && !_stockFieldsLocked
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    tooltip: 'إلغاء نسبة الهالك',
                    onPressed: () {
                      setState(() {
                        entry.wastePercent = 0.0;
                        if (!entry.isCartonMode && entry.cartonCount > 0) {
                          entry.autoCalculateNetWeightPerCarton();
                        }
                      });
                    },
                  )
                : null,
          ),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: 14,
          ),
          onChanged: (_) {
            setState(() {
              if (!entry.isCartonMode && entry.cartonCount > 0) {
                entry.autoCalculateNetWeightPerCarton();
              }
            });
          },
        ),
        if (entry.wastePercent > 0) ...[
          const SizedBox(height: 6),
          if (!isCarton) ...[
            _infoRow(
                'وزن الهالك (${entry.wastePercent % 1 == 0 ? entry.wastePercent.toInt() : entry.wastePercent}%)',
                '${entry.wasteWeight.toStringAsFixed(2)} كجم',
                valueColor: AppTheme.warning),
            const SizedBox(height: 4),
          ],
          _infoRow(
              'تكلفة الهالك (${entry.wastePercent % 1 == 0 ? entry.wastePercent.toInt() : entry.wastePercent}%)',
              '${entry.wasteCost.toStringAsFixed(2)} ج.م',
              valueColor: AppTheme.warning),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                value: entry.hasSorting,
                onChanged: _stockFieldsLocked
                    ? null
                    : (v) {
                        setState(() {
                          entry.hasSorting = v ?? false;
                          if (!entry.hasSorting) entry.sortedWeightCtrl.clear();
                          entry.updateCartonCountFromDeductions();
                          if (!entry.isCartonMode && entry.cartonCount > 0) {
                            entry.autoCalculateNetWeightPerCarton();
                          }
                        });
                      },
                title: Text('يوجد فرز',
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
              ),
            ),
          ],
        ),
        if (entry.hasSorting) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: entry.sortedWeightCtrl,
            enabled: !_stockFieldsLocked,
            decoration: _inputDecoration(
                isCarton ? 'كراتين الفرز (كرتونة)' : 'فرز (كجم)'),
            keyboardType: isCarton
                ? TextInputType.number
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: isCarton
                ? [FilteringTextInputFormatter.digitsOnly]
                : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 15),
            onChanged: (_) {
              entry.updateCartonCountFromDeductions();
              if (!entry.isCartonMode && entry.cartonCount > 0) {
                entry.autoCalculateNetWeightPerCarton();
              }
              setState(() {});
            },
            validator: (v) {
              if (!entry.hasSorting) return null;
              if (isCarton) {
                final n = (double.tryParse(v ?? '') ?? 0).round();
                if (n < 0) return 'أدخل عدداً صحيحاً';
                if (n > entry.effectiveWeight.toInt())
                  return 'الفرز يتجاوز العدد المتاح (${entry.effectiveWeight.toInt()})';
                return null;
              }
              final n = double.tryParse(v ?? '');
              if (n == null || n < 0) return 'أدخل وزناً صحيحاً';
              if (n > entry.effectiveWeight)
                return 'الفرز يتجاوز الوزن الفعلي (${entry.effectiveWeight.toStringAsFixed(1)} كجم)';
              if (n + entry.totalNetWeight > entry.effectiveWeight) {
                return 'مجموع الفرز والوزن المعبأ يتجاوز الكمية المتاحة';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          _infoRow(
              'تكلفة الفرز', '${entry.sortingCost.toStringAsFixed(2)} ج.م',
              valueColor: AppTheme.warning),
        ],
      ],
    );
  }

  Widget _buildEntryCartonSection(_LotEntry entry) {
    final isDark = AppTheme.isDark(context);
    final lot = entry.lot;
    final isCartonMode = lot?.purchaseMode == 'carton';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: entry.cartonCountCtrl,
          enabled: !_stockFieldsLocked,
          readOnly: isCartonMode,
          decoration: _inputDecoration(
              isCartonMode ? 'عدد الكراتين الصافي (كرتونة)' : 'عدد الكراتين'),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              color: isCartonMode ? AppTheme.info : (isDark ? Colors.white : Colors.black),
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold),
          onChanged: isCartonMode
              ? null
              : (_) {
                  entry.autoCalculateNetWeightPerCarton();
                  setState(() {});
                },
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n <= 0) return 'أدخل عدداً صحيحاً موجباً';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: entry.netWeightPerCartonCtrl,
          readOnly: true,
          decoration: _inputDecoration(
            'الوزن الصافي للكرتونة (كجم) (محسوب تلقائياً)',
            suffixIcon: Tooltip(
              message: 'يتم احتسابه تلقائياً لمنع التعديل',
              child: Icon(Icons.lock_outline, size: 18, color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
          ],
          style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black87,
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold),
          validator: (v) {
            final n = double.tryParse(v ?? '');
            if (n == null || n <= 0) return 'أدخل وزناً صحيحاً';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: entry.grossWeightPerCartonCtrl,
          readOnly: isCartonMode,
          decoration: _inputDecoration('الوزن الإجمالي للكرتونة (كجم)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
          ],
          style: TextStyle(
              color: isCartonMode ? (isDark ? AppTheme.textSecondary : Colors.black54) : (isDark ? Colors.white : Colors.black),
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 15),
          onChanged: isCartonMode ? null : (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || n <= 0) return 'أدخل وزناً صحيحاً';
            return null;
          },
        ),
        const SizedBox(height: 10),
        if (entry.totalNetWeight > 0)
          _infoRow('إجمالي الوزن الصافي',
              '${entry.totalNetWeight.toStringAsFixed(1)} كجم',
              valueColor: AppTheme.success),
        if (entry.totalGrossWeight > 0 &&
            entry.totalGrossWeight != entry.totalNetWeight)
          _infoRow('الوزن الإجمالي للكراتين',
              '${entry.totalGrossWeight.toStringAsFixed(1)} كجم',
              valueColor: AppTheme.success),
        if (!entry.isCartonMode &&
            entry.cartonCount > 0 &&
            entry.exactCartonNetWeight > 0) ...[
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final totalAllocated = entry.totalNetWeight +
                (entry.hasSorting ? entry.sortedWeight : 0.0) +
                entry.wasteWeight;
            final isBalanced =
                (totalAllocated - entry.effectiveWeight).abs() <= 0.01;
            if (isBalanced) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الأوزان مطابقة تماماً: معبأ (${entry.totalNetWeight.toStringAsFixed(1)}) + فرز (${(entry.hasSorting ? entry.sortedWeight : 0).toStringAsFixed(1)}) + هالك (${entry.wasteWeight.toStringAsFixed(1)}) = ${entry.effectiveWeight.toStringAsFixed(1)} كجم',
                        style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              final diff = entry.effectiveWeight - totalAllocated;
              final diffText = diff > 0
                  ? 'متبقي ${diff.toStringAsFixed(1)} كجم لم يتم توزيعها'
                  : 'زيادة ${(-diff).toStringAsFixed(1)} كجم تتجاوز الكمية المستخدمة';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppTheme.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'المجموع: ${totalAllocated.toStringAsFixed(1)} كجم (معبأ: ${entry.totalNetWeight.toStringAsFixed(1)} + فرز: ${(entry.hasSorting ? entry.sortedWeight : 0).toStringAsFixed(1)} + هالك: ${entry.wasteWeight.toStringAsFixed(1)})',
                            style: const TextStyle(
                                color: AppTheme.warning,
                                fontSize: 12,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 24, top: 4),
                      child: Text(
                        'الوزن المستخدم: ${entry.effectiveWeight.toStringAsFixed(1)} كجم ($diffText)',
                        style: const TextStyle(
                            color: AppTheme.warning,
                            fontSize: 11,
                            fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
              );
            }
          }),
        ],
      ],
    );
  }

  Widget _buildDeleteLotButton(int index) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          final entry = _lotEntries[index];
          setState(() {
            _lotEntries.removeAt(index);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            entry.dispose();
          });
        },
        icon:
            const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
        label: const Text('حذف المحصول',
            style: TextStyle(
                color: AppTheme.danger, fontSize: 13, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildAddLotButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() => _lotEntries.add(_LotEntry()));
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('إضافة محصول آخر',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: const BorderSide(color: AppTheme.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildMaterialsSection() {
    final isDark = AppTheme.isDark(context);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _materialItems) {
      final code = item['product_code']?.toString() ?? (item['product_name'] as String);
      grouped.putIfAbsent(code, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_materialItems.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 20,
                    color: isDark ? AppTheme.textSecondary : Colors.black45),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لم يتم إضافة مواد تعبئة بعد (انقر على الزر أدناه لإضافة كراتين، فواصل، زوايا...)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? AppTheme.textSecondary : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ...grouped.entries.map((group) {
          final items = group.value;
          final groupTotal = items.fold<double>(
              0.0,
              (s, i) =>
                  s +
                  (((i['used_qty'] ?? 0) as num).toDouble() *
                      ((i['unit_cost'] ?? 0) as num).toDouble()));
          final groupQty = items.fold<double>(
              0.0, (s, i) => s + ((i['used_qty'] ?? 0) as num).toDouble());
          final firstItem = items.first;
          final itemCode = firstItem['product_code']?.toString() ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isPackagingConfirmed
                    ? const Color(0xFFA855F7).withValues(alpha: 0.4)
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(firstItem['product_name'] as String,
                          style: TextStyle(
                              color: isDark ? AppTheme.textPrimary : Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ),
                    // Status Badge (مسودة vs فعلي)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: _isPackagingConfirmed
                            ? const Color(0xFFA855F7).withValues(alpha: 0.15)
                            : AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isPackagingConfirmed
                              ? const Color(0xFFA855F7).withValues(alpha: 0.4)
                              : AppTheme.warning.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isPackagingConfirmed
                                ? Icons.check_circle_outline
                                : Icons.edit_note,
                            size: 13,
                            color: _isPackagingConfirmed
                                ? const Color(0xFFA855F7)
                                : AppTheme.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isPackagingConfirmed ? 'فعلي (مرحل)' : 'مسودة (تقديري)',
                            style: TextStyle(
                              color: _isPackagingConfirmed
                                  ? const Color(0xFFA855F7)
                                  : (isDark ? AppTheme.warning : const Color(0xFFB45309)),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text('${groupTotal.toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                            color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(width: 8),
                    if (!_isOrderFinalized)
                      Tooltip(
                        message: _isPackagingConfirmed
                            ? 'تعديل أو زيادة خامات (يتطلب تحديث الصرف)'
                            : 'تعديل مادة التعبئة',
                        child: GestureDetector(
                          onTap: () => _showMaterialForm(
                              editProductCode: firstItem['product_code'] as String),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.edit_outlined,
                                size: 16, color: AppTheme.primary),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    itemCode.isNotEmpty
                        ? 'كود: $itemCode | الإجمالي: ${groupQty.toStringAsFixed(1)} وحدة'
                        : 'الإجمالي: ${groupQty.toStringAsFixed(1)} وحدة',
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 6),
                ...items.asMap().entries.map((entry) {
                  final localIdx = entry.key;
                  final item = entry.value;
                  final globalIdx = _materialItems.indexOf(item);
                  final batchNum = localIdx + 1;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: isDark ? null : Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Builder(builder: (context) {
                          final sName = item['supplier_name']?.toString() ?? '';
                          final invNum = item['invoice_number']?.toString() ?? '';
                          final stName = item['station_name']?.toString() ?? '';
                          var title = 'دفعة $batchNum';
                          if (stName.isNotEmpty) title += ' | $stName';
                          if (sName.isNotEmpty) title += ' ($sName)';
                          if (invNum.isNotEmpty) title += ' (فاتورة $invNum)';
                          return Text(title,
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                  fontSize: 11,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold));
                        }),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(builder: (context) {
                            final used =
                                ((item['used_qty'] ?? 0) as num).toDouble();
                            final unitCost =
                                ((item['unit_cost'] ?? 0) as num).toDouble();
                            final exchangeRate =
                                ((item['exchange_rate'] ?? 1.0) as num)
                                    .toDouble();
                            final currency =
                                item['currency'] as String? ?? 'EGP';

                            final displayEx =
                                exchangeRate == 0.0 ? 1.0 : exchangeRate;
                            final originalCost = unitCost / displayEx;

                            final costText = (displayEx != 1.0)
                                ? '${originalCost.toStringAsFixed(2)} ${currency == 'EGP' ? 'أصلي' : AppUtils.currencySymbol(currency)} (صرف ${displayEx.toStringAsFixed(2)})'
                                : '${unitCost.toStringAsFixed(2)} ج.م';

                            return Text(
                              '${used.toStringAsFixed(1)} × $costText',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textPrimary : Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo'),
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                        ),
                        Text(
                            '${(((item['used_qty'] ?? 0) as num).toDouble() * ((item['unit_cost'] ?? 0) as num).toDouble()).toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                fontSize: 12,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: GestureDetector(
                            onTap: () {
                              if (_isPackagingConfirmed) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم ترحيل مواد التعبئة فعلياً. لتعديل طريقة التوزيع، يرجى إلغاء ترحيل المرحلة أولاً.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                final apply =
                                    (item['apply_to'] as String?) ?? 'all';
                                if (apply == 'all' && _lotEntries.length > 1) {
                                  item['apply_to'] = 'line:0';
                                } else if (apply.startsWith('line:')) {
                                  final idx =
                                      int.tryParse(apply.substring(5)) ?? 0;
                                  if (idx + 1 < _lotEntries.length) {
                                    item['apply_to'] = 'line:${idx + 1}';
                                  } else {
                                    item['apply_to'] = 'all';
                                  }
                                } else {
                                  item['apply_to'] = 'all';
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                () {
                                  final apply =
                                      (item['apply_to'] as String?) ?? 'all';
                                  if (apply.startsWith('line:')) {
                                    final idx =
                                        int.tryParse(apply.substring(5)) ?? 0;
                                    final name = _lotEntries.length > idx
                                        ? (_lotEntries[idx].lot?.productName ??
                                            '#${idx + 1}')
                                        : '#${idx + 1}';
                                    return '→ $name';
                                  }
                                  final method = CostAllocationMethod.fromCode(
                                      item['allocation_method'] as String?);
                                  return 'مشترك • ${method.label}';
                                }(),
                                style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 10,
                                    fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        if (!_isOrderFinalized) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: _isPackagingConfirmed
                                ? 'حذف البند (مرحل فعلياً)'
                                : 'حذف البند',
                            child: GestureDetector(
                              onTap: () async {
                                if (_isPackagingConfirmed) {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('تأكيد حذف مادة مرحلة',
                                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                      content: Text(
                                        'هذه المادة تم تأكيدها وصرفها مخزنياً بالفعل في قيد الصرف (#${_currentOrder?.packagingJournalEntryId ?? ''}).\n\n'
                                        'إذا قمت بحذفها الآن، ستحتاج إلى الضغط على "تحديث وصرف مواد التعبئة" لتسوية المخزن وقيد الصرف، أو إلغاء ترحيل المرحلة أولاً.\n\nهل تريد حذف هذا البند من أمر التعبئة؟',
                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.5),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo')),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                                          child: const Text('نعم، حذف',
                                              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true) return;
                                }
                                setState(() => _materialItems.removeAt(globalIdx));
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.delete_outline,
                                    size: 14, color: AppTheme.danger),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isOrderFinalized ? null : _addMaterialItem,
            icon: Icon(
              _isPackagingConfirmed ? Icons.add_circle_outline : Icons.add,
              size: 20,
              color: _isOrderFinalized ? Colors.grey : AppTheme.primary,
            ),
            label: Text(
              _isPackagingConfirmed
                  ? 'إضافة مادة تعبئة إضافية'
                  : 'إضافة مادة تعبئة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _isOrderFinalized ? Colors.grey : AppTheme.primary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(
                color: _isOrderFinalized ? Colors.grey.withValues(alpha: 0.3) : AppTheme.primary,
                width: 1.5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_isPackagingConfirmed && !_isOrderFinalized) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              'المرحلة 2 مرحلة فعلياً. يمكنك إضافة مواد إضافية أو تعديلها ثم الضغط على "تحديث وصرف مواد التعبئة".',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black54,
                fontSize: 11,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _addMaterialItem() => _showMaterialForm();

  void _showMaterialForm({String? editProductCode}) {
    int? selectedIdx;
    String selectedApplyTo = _lotEntries.length == 1 ? 'line:0' : 'all';
    String selectedMaterialAllocationMethod = 'EQUAL';
    bool showAdvancedMatMethods = false;
    if (editProductCode != null) {
      selectedIdx =
          _materialProducts.indexWhere((p) => p.productCode == editProductCode);
      if (selectedIdx == -1) selectedIdx = null;
      final existingItem = _materialItems.firstWhere(
        (item) => item['product_code'] == editProductCode,
        orElse: () => {},
      );
      if (existingItem.isNotEmpty) {
        selectedApplyTo = (existingItem['apply_to'] as String?) ??
            (_lotEntries.length == 1 ? 'line:0' : 'all');
        selectedMaterialAllocationMethod =
            (existingItem['allocation_method'] as String?) ?? 'EQUAL';
      }
    }

    final requestedQtyCtrl = TextEditingController();
    final _materialSearchCtrl = TextEditingController();
    if (selectedIdx != null) {
      _materialSearchCtrl.text = _materialProducts[selectedIdx]
          .productName
          .replaceAll(' (مادة تعبئة)', '');
    }

    List<Map<String, dynamic>> batches = [];
    List<TextEditingController> batchQtyCtrls = [];
    bool loadingBatches = false;
    int currentFetchId = 0;

    Future<void> fetchBatches(
        int idx, void Function(void Function()) setDialogState) async {
      if (idx < 0 || idx >= _materialProducts.length) return;
      final selectedProduct = _materialProducts[idx];
      final fetchId = ++currentFetchId;

      setDialogState(() {
        loadingBatches = true;
        batches = [];
        batchQtyCtrls = [];
      });

      try {
        var mBatchQuery = Supabase.instance.client
            .from('station_product_batches')
            .select(
                'id, station_id, unit_cost, remaining_quantity, created_at, source_type, supplier_name, exchange_rate, currency, product_code, product_name, purchase_invoices(invoice_number, suppliers(name))')
            .eq('product_code', selectedProduct.productCode)
            .gt('remaining_quantity', 0)
            .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual']);

        if (!_isAllStations && _selectedStationIds.isNotEmpty) {
          mBatchQuery = mBatchQuery.inFilter('station_id', _selectedStationIds.toList());
        } else if (!_isAllStations && _selectedStationId != null) {
          mBatchQuery = mBatchQuery.eq('station_id', _selectedStationId!);
        }

        final data = await mBatchQuery.order('created_at', ascending: true);

        if (fetchId != currentFetchId) return;

        final filteredData = (data as List).where((b) {
          final bCode = b['product_code']?.toString() ?? '';
          final bSrc = b['source_type']?.toString() ?? '';
          if (bSrc == 'lot_receipt' || bSrc == 'crop_purchase') return false;
          return bCode == selectedProduct.productCode;
        }).toList();

        final mappedBatches = filteredData.map((b) {
          final invSupplier = (b['purchase_invoices'] is Map &&
                  b['purchase_invoices']['suppliers'] is Map)
              ? (b['purchase_invoices']['suppliers']['name']?.toString() ?? '')
              : '';
          final rawSupplier = b['supplier_name']?.toString() ?? '';
          final supplierName =
              rawSupplier.isNotEmpty ? rawSupplier : invSupplier;

          return {
            'batch_id': b['id'],
            'station_id': b['station_id'],
            'station_name': _getStationName(b['station_id']),
            'product_code': b['product_code']?.toString() ?? '',
            'product_name': b['product_name']?.toString() ?? '',
            'unit_cost': (b['unit_cost'] as num?)?.toDouble() ?? 0.0,
            'remaining': (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
            'created_at': b['created_at']?.toString() ?? '',
            'source_type': b['source_type']?.toString() ?? '',
            'supplier_name': supplierName,
            'exchange_rate':
                ((b['exchange_rate'] as num?)?.toDouble() ?? 1.0) == 0.0
                    ? 1.0
                    : ((b['exchange_rate'] as num?)?.toDouble() ?? 1.0),
            'currency': b['currency']?.toString() ?? 'EGP',
            'invoice_number': (b['purchase_invoices'] is Map)
                ? (b['purchase_invoices']['invoice_number']?.toString() ?? '')
                : '',
          };
        }).toList();

        for (int i = 0; i < mappedBatches.length; i++) {
          final bId = mappedBatches[i]['batch_id'];
          double claimedQty = 0;
          for (final item in _materialItems) {
            if (editProductCode != null &&
                item['product_code'] == editProductCode) continue;

            if (item['product_code'] == selectedProduct.productCode &&
                (item['batch_id'] == bId ||
                    (item['batch_id'] == null && mappedBatches.length == 1))) {
              claimedQty += ((item['used_qty'] ?? 0) as num).toDouble();
            }
          }
          double currentRemaining =
              ((mappedBatches[i]['remaining'] ?? 0) as num).toDouble();
          mappedBatches[i]['remaining'] = currentRemaining - claimedQty;
        }

        mappedBatches
            .removeWhere((b) => ((b['remaining'] ?? 0) as num).toDouble() <= 0);

        batches = mappedBatches;
        batchQtyCtrls =
            List.generate(batches.length, (_) => TextEditingController());

        if (editProductCode != null) {
          double totalUsed = 0;
          for (int i = 0; i < batches.length; i++) {
            final bId = batches[i]['batch_id'];
            final existingItem = _materialItems
                .where((item) =>
                    item['product_code'] == editProductCode &&
                    (item['batch_id'] == bId ||
                        (item['batch_id'] == null && batches.length == 1)))
                .firstOrNull;
            if (existingItem != null) {
              final used = ((existingItem['used_qty'] ?? 0) as num).toDouble();
              if (used > 0) {
                batchQtyCtrls[i].text = used.toStringAsFixed(1);
                totalUsed += used;
              }
            }
          }
          if (totalUsed > 0) {
            requestedQtyCtrl.text = totalUsed.toStringAsFixed(1);
          }
        }
      } catch (e) {
        debugPrint('Error fetching batches: $e');
        if (fetchId == currentFetchId) {
          batches = [];
          batchQtyCtrls = [];
        }
      }
      if (fetchId == currentFetchId) {
        setDialogState(() => loadingBatches = false);
      }
    }

    if (editProductCode != null && selectedIdx != null) {
      loadingBatches = true;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = AppTheme.isDark(ctx);
          if (editProductCode != null &&
              selectedIdx != null &&
              batches.isEmpty &&
              loadingBatches) {
            fetchBatches(selectedIdx!, setDialogState);
          }

          final totalAllocated = batchQtyCtrls.fold<double>(
              0.0, (s, c) => s + (double.tryParse(c.text) ?? 0));
          final requestedQty = double.tryParse(requestedQtyCtrl.text) ?? 0;
          final hasMismatch =
              requestedQty > 0 && (totalAllocated - requestedQty).abs() > 0.01;
          final hasOverflow = batches.asMap().entries.any((e) {
            final ctrl = batchQtyCtrls[e.key];
            final entered = double.tryParse(ctrl.text) ?? 0;
            return entered >
                ((e.value['remaining'] ?? 0) as num).toDouble() + 0.001;
          });
          final canAdd = selectedIdx != null &&
              totalAllocated > 0 &&
              !hasMismatch &&
              !hasOverflow;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            title: Text(
                editProductCode != null
                    ? 'تعديل مادة التعبئة'
                    : 'إضافة مادة تعبئة',
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (editProductCode != null) ...[
                        _infoRow(
                            'المنتج',
                            _materialProducts[selectedIdx!]
                                .productName
                                .replaceAll(' (مادة تعبئة)', ''),
                            valueColor: isDark ? AppTheme.textPrimary : Colors.black),
                      ] else ...[
                        TypeAheadField<int>(
                          controller: _materialSearchCtrl,
                          autoFlipDirection: true,
                          hideOnEmpty: false,
                          hideOnError: true,
                          suggestionsCallback: (query) {
                            final available = _materialProducts
                                .asMap()
                                .entries
                                .toList();
                            if (query.isEmpty) {
                              return available.map((e) => e.key).toList();
                            }
                            final q = query.toLowerCase().trim();
                            return available
                                .where((e) =>
                                    e.value.productName
                                        .toLowerCase()
                                        .contains(q) ||
                                    e.value.productCode
                                        .toLowerCase()
                                        .contains(q))
                                .map((e) => e.key)
                                .toList();
                          },
                          itemBuilder: (context, idx) {
                            final p = _materialProducts[idx];
                            final rem = _getRemainingMaterialQty(p,
                                excludeProductCode: editProductCode);
                            final cleanName = p.productName
                                .replaceAll(' (مادة تعبئة)', '');
                            return ListTile(
                              dense: true,
                              title: Text(cleanName,
                                  style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'المتوفر: ${rem.toStringAsFixed(1)} | كود: ${p.productCode}',
                                  style: TextStyle(
                                      color: rem > 0
                                          ? (isDark ? AppTheme.textSecondary : Colors.black87)
                                          : AppTheme.danger,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 11)),
                            );
                          },
                          onSelected: (idx) {
                            selectedIdx = idx;
                            batches = [];
                            batchQtyCtrls = [];
                            requestedQtyCtrl.clear();
                            _materialSearchCtrl.text = _materialProducts[idx]
                                .productName
                                .replaceAll(' (مادة تعبئة)', '');
                            if (_selectedStationId != null) {
                              fetchBatches(idx, setDialogState);
                            } else {
                              setDialogState(() {});
                            }
                          },
                          builder: (context, controller, focusNode) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration:
                                  _inputDecoration('بحث بالاسم أو الكود'),
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14),
                            );
                          },
                        ),
                      ],
                      if (selectedIdx != null) ...[
                        const SizedBox(height: 14),
                        _infoRow('الكمية المتوفرة',
                            '${_getRemainingMaterialQty(_materialProducts[selectedIdx!], excludeProductCode: editProductCode).toStringAsFixed(1)} وحدة',
                            valueColor: isDark ? AppTheme.success : const Color(0xFF16A34A)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: requestedQtyCtrl,
                          decoration: _inputDecoration('الكمية المطلوبة'),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*$'))
                          ],
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 15),
                          onChanged: (v) {
                            final qty = double.tryParse(v) ?? 0;
                            if (qty <= 0 || batches.isEmpty) return;
                            double remaining = qty;
                            for (int i = 0; i < batches.length; i++) {
                              if (remaining <= 0) {
                                batchQtyCtrls[i].text = '';
                              } else {
                                final batchRem =
                                    ((batches[i]['remaining'] ?? 0) as num)
                                        .toDouble();
                                final take =
                                    remaining < batchRem ? remaining : batchRem;
                                batchQtyCtrls[i].text =
                                    take > 0 ? take.toStringAsFixed(1) : '';
                              }
                              remaining -=
                                  (double.tryParse(batchQtyCtrls[i].text) ?? 0);
                            }
                            setDialogState(() {});
                          },
                        ),
                        if (loadingBatches)
                          const Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        if (!loadingBatches && batches.isEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.warning.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: AppTheme.warning, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'لا توجد دفعات متاحة لهذه المادة في هذا المخزن',
                                    style: TextStyle(
                                      color: AppTheme.warning,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!loadingBatches && batches.length == 1) ...[
                          const SizedBox(height: 14),
                          Builder(builder: (context) {
                            final b = batches[0];
                            final isOpening = b['source_type'] == 'opening';
                            final sName = b['supplier_name']?.toString() ?? '';
                            final stName = b['station_name']?.toString() ?? '';
                            var title = 'الدفعة الوحيدة';
                            if (stName.isNotEmpty) title += ' | $stName';
                            if (sName.isNotEmpty) title += ' | $sName';
                            if (isOpening) title += ' (رصيد سابق)';
                            final invNum = b['invoice_number']?.toString() ?? '';
                            if (invNum.isNotEmpty) title += ' | فاتورة: $invNum';
                            return _infoRow(title,
                                '${((b['remaining'] ?? 0) as num).toDouble().toStringAsFixed(1)} وحدة',
                                valueColor: AppTheme.info);
                          }),
                          const SizedBox(height: 8),
                          TextField(
                            controller: batchQtyCtrls.isNotEmpty
                                ? batchQtyCtrls[0]
                                : null,
                            decoration: _inputDecoration('الكمية المستخدمة'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*$'))
                            ],
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 15),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ],
                        if (!loadingBatches && batches.length > 1) ...[
                          const SizedBox(height: 14),
                          ...List.generate(batches.length, (i) {
                            final b = batches[i];
                            final bDate = (b['created_at'] as String).length >=
                                    10
                                ? (b['created_at'] as String).substring(0, 10)
                                : '—';
                            final bRem =
                                ((b['remaining'] ?? 0) as num).toDouble();
                            final bCost =
                                ((b['unit_cost'] ?? 0) as num).toDouble();
                            final rawEx =
                                (b['exchange_rate'] as num?)?.toDouble() ?? 1.0;
                            final bExchangeRate = rawEx == 0.0 ? 1.0 : rawEx;
                            final bCostEgp = bCost * bExchangeRate;
                            final bCurrency =
                                b['currency']?.toString() ?? 'EGP';
                            final entered =
                                double.tryParse(batchQtyCtrls[i].text) ?? 0;
                            final overLimit = entered > bRem + 0.001;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: overLimit
                                        ? AppTheme.danger
                                        : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Builder(builder: (context) {
                                          final isOpening =
                                              b['source_type'] == 'opening';
                                          final sName =
                                              b['supplier_name']?.toString() ??
                                                  '';
                                          final stName = b['station_name']?.toString() ?? '';
                                           var title = 'دفعة ${i + 1} — $bDate';
                                          if (sName.isNotEmpty)
                                            if (stName.isNotEmpty) title += ' | $stName';
                                           title += ' | $sName';
                                          if (isOpening)
                                            title += ' (رصيد سابق)';
                                          final invNum =
                                              b['invoice_number']?.toString() ??
                                                  '';
                                          if (invNum.isNotEmpty)
                                            title += ' | فاتورة: $invNum';
                                          return Text(title,
                                              style: TextStyle(
                                                  color: isDark ? AppTheme.textSecondary : Colors.black,
                                                  fontSize: 11,
                                                  fontFamily: 'Cairo',
                                                  fontWeight: FontWeight.bold));
                                        }),
                                      ),
                                      const SizedBox(width: 6),
                                      Builder(builder: (context) {
                                        final costStr = (bCurrency != 'EGP' &&
                                                bExchangeRate != 1.0)
                                            ? '${bCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(bCurrency)}'
                                            : '${bCost.toStringAsFixed(2)} ج.م';
                                        return Text(
                                            'متاح: ${bRem.toStringAsFixed(1)} | $costStr',
                                            style: TextStyle(
                                                color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                fontFamily: 'Cairo'));
                                      }),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: batchQtyCtrls[i],
                                          decoration:
                                              _inputDecoration('الكمية المستخدمة'),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d*$'))
                                          ],
                                          style: TextStyle(
                                              color: overLimit
                                                  ? AppTheme.danger
                                                  : (isDark ? Colors.white : Colors.black),
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                              fontSize: 13),
                                          onChanged: (_) =>
                                              setDialogState(() {}),
                                        ),
                                      ),
                                      if (entered > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                            '${(entered * bCostEgp).toStringAsFixed(2)} ج.م',
                                            textAlign: TextAlign.start,
                                            style: const TextStyle(
                                                color: AppTheme.accent,
                                                fontSize: 11,
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        if (!loadingBatches && batches.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: hasMismatch || hasOverflow
                                  ? AppTheme.danger.withValues(alpha: 0.1)
                                  : AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: hasMismatch || hasOverflow
                                      ? AppTheme.danger
                                      : AppTheme.success
                                          .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                    hasMismatch || hasOverflow
                                        ? Icons.error_outline
                                        : Icons.check_circle_outline,
                                    size: 16,
                                    color: hasMismatch || hasOverflow
                                        ? AppTheme.danger
                                        : AppTheme.success),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    requestedQty > 0
                                        ? 'الإجمالي المسحوب: ${totalAllocated.toStringAsFixed(1)} / ${requestedQty.toStringAsFixed(1)}'
                                        : 'الإجمالي المسحوب: ${totalAllocated.toStringAsFixed(1)} وحدة',
                                    style: TextStyle(
                                        color: hasMismatch || hasOverflow
                                            ? AppTheme.danger
                                            : AppTheme.success,
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (hasMismatch)
                                  const Text('يجب المطابقة',
                                      style: TextStyle(
                                          color: AppTheme.danger,
                                          fontSize: 11,
                                          fontFamily: 'Cairo')),
                                if (hasOverflow && !hasMismatch)
                                  const Text('كمية زايدة',
                                      style: TextStyle(
                                          color: AppTheme.danger,
                                          fontSize: 11,
                                          fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                        ],
                        if (!loadingBatches &&
                            batches.isNotEmpty &&
                            _lotEntries.length > 1) ...[
                          const SizedBox(height: 14),
                          Text('تطبيق على:',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          ...List.generate(_lotEntries.length + 1, (i) {
                            final isShared = i == 0;
                            final entry = isShared ? null : _lotEntries[i - 1];
                            final label = isShared
                                ? 'مشترك على جميع المنتجات'
                                : 'محصول #${i} — ${_lotEntries[i - 1].lot?.productName ?? ''}';
                            final value = isShared ? 'all' : 'line:${i - 1}';
                            final isSelected = selectedApplyTo == value;
                            return GestureDetector(
                              onTap: () =>
                                  setDialogState(() => selectedApplyTo = value),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFE0F2FE))
                                      : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                        : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 18,
                                      color: isSelected
                                          ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                          : (isDark ? AppTheme.textMuted : Colors.black45),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(label,
                                              style: TextStyle(
                                                  color: isDark
                                                      ? (isSelected
                                                          ? AppTheme.textPrimary
                                                          : AppTheme.textSecondary)
                                                      : Colors.black,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  fontFamily: 'Cairo')),
                                          if (!isShared && entry != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'الوزن الصافي: ${entry.totalNetWeight.toStringAsFixed(1)} كجم | الكراتين: ${entry.cartonCount}',
                                              style: TextStyle(
                                                  color: isDark ? AppTheme.textMuted : Colors.black87,
                                                  fontSize: 10,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (!isShared && entry != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.info
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${entry.cartonCount} كرتونة',
                                          style: const TextStyle(
                                              color: AppTheme.info,
                                              fontSize: 10,
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          if (selectedApplyTo == 'all') ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.info.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        isDark ? AppTheme.info.withValues(alpha: 0.3) : const Color(0xFFBAE6FD)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 14, color: isDark ? AppTheme.info : const Color(0xFF0284C7)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'إجمالي الاحتياج: ${_lotEntries.fold(0, (s, e) => s + e.cartonCount)} كرتونة',
                                      style: TextStyle(
                                          color: isDark ? AppTheme.info : const Color(0xFF0284C7),
                                          fontSize: 11,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                        if (selectedApplyTo == 'all') ...[
                          const SizedBox(height: 14),
                          _buildAllocationMethodPicker(
                            selectedCode: selectedMaterialAllocationMethod,
                            showAdvanced: showAdvancedMatMethods,
                            onToggleAdvanced: () => setDialogState(() =>
                                showAdvancedMatMethods =
                                    !showAdvancedMatMethods),
                            onChanged: (code) => setDialogState(
                                () => selectedMaterialAllocationMethod = code),
                            availableMethods: const [
                              CostAllocationMethod.equal
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canAdd
                    ? () {
                        final product = _materialProducts[selectedIdx!];
                        setState(() {
                          if (editProductCode != null) {
                            _materialItems.removeWhere((item) =>
                                item['product_code'] == editProductCode);
                          }

                          for (int i = 0; i < batches.length; i++) {
                            final usedQty =
                                double.tryParse(batchQtyCtrls[i].text) ?? 0;
                            if (usedQty <= 0) continue;

                            final rawEx = (batches[i]['exchange_rate'] as num?)
                                    ?.toDouble() ??
                                1.0;
                            final bExchangeRate = rawEx == 0.0 ? 1.0 : rawEx;
                            final bUnitCost =
                                ((batches[i]['unit_cost'] ?? 0) as num)
                                    .toDouble();
                            final bUnitCostEgp = bUnitCost * bExchangeRate;
                            final bCurrency =
                                (batches[i]['currency'] as String?) ?? 'EGP';
                            int? targetLineIdx;
                            String? targetProdName;
                            String? targetProdId;
                            String? targetCostCenterId;
                            String? targetCostCenterName;
                            String allocMethod = 'MANUAL';

                            if (selectedApplyTo.startsWith('line:')) {
                              final idx = int.tryParse(selectedApplyTo.substring(5));
                              if (idx != null && idx >= 0 && idx < _lotEntries.length) {
                                targetLineIdx = idx;
                                final entry = _lotEntries[idx];
                                targetProdName = entry.lot?.productName ?? '';
                                targetProdId = entry.lot?.fruitTypeId;
                                final cc = CostCenterHelper.resolve({
                                  'item_name': targetProdName,
                                  'target_product_name': targetProdName,
                                  if (targetProdId != null) 'fruit_type_id': targetProdId,
                                }, _costCenters);
                                targetCostCenterId = cc.id;
                                targetCostCenterName = cc.nameAr;
                                allocMethod = 'MANUAL';
                              }
                            } else if (_lotEntries.length == 1) {
                              targetLineIdx = 0;
                              final entry = _lotEntries.first;
                              targetProdName = entry.lot?.productName ?? '';
                              targetProdId = entry.lot?.fruitTypeId;
                              final cc = CostCenterHelper.resolve({
                                'item_name': targetProdName,
                                'target_product_name': targetProdName,
                                if (targetProdId != null) 'fruit_type_id': targetProdId,
                              }, _costCenters);
                              targetCostCenterId = cc.id;
                              targetCostCenterName = cc.nameAr;
                              allocMethod = 'MANUAL';
                            } else {
                              allocMethod = 'EQUAL';
                              targetCostCenterId = 'ALL';
                              targetCostCenterName = 'توزيع بالتساوي على كل المنتجات';
                            }

                            _materialItems.add({
                              'product_name': product.productName,
                              'product_code': product.productCode,
                              'available_qty': product.quantity,
                              'used_qty': usedQty,
                              'unit_cost_foreign': bUnitCost,
                              'total_foreign': usedQty * bUnitCost,
                              'unit_cost': bUnitCostEgp,
                              'total': usedQty * bUnitCostEgp,
                              'batch_id': batches[i]['batch_id'],
                              'station_id': batches[i]['station_id'],
                              'station_name': batches[i]['station_name'],
                              'exchange_rate': bExchangeRate,
                              'currency': bCurrency,
                              'invoice_number': batches[i]['invoice_number'],
                              'supplier_name': batches[i]['supplier_name'],
                              'apply_to': selectedApplyTo,
                              'allocation_method': allocMethod,
                              'target_line_index': targetLineIdx,
                              'target_product_name': targetProdName,
                              'target_product_id': targetProdId,
                              'cost_center_id': targetCostCenterId,
                              'cost_center_name': targetCostCenterName,
                            });
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppTheme.primary.withValues(alpha: 0.3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: Text(editProductCode != null ? 'حفظ التعديلات' : 'إضافة',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMaterialWasteSection() {
    final isDark = AppTheme.isDark(context);
    final isRolling = _isRollingWasteMode;
    final actualMaterialCost = _actualPackagingMaterialCost;
    final currentOrderWaste = _currentOrderCalculatedWaste;
    final cumulativePool = _cumulativePendingWastePool;
    final totalWastePool = isRolling ? cumulativePool : currentOrderWaste;
    final settledAmount = _rollingSettledWasteAmount;
    final remainingUnsettled = _unsettledMaterialWasteCost;
    final totalWithWaste = _packagingCostAfterWaste;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 0. Prominent Return Packaging Waste Banner if recorded
        if (_returnPackagingWasteCost > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.keyboard_return_rounded, color: Color(0xFFEA580C), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'رصيد هالك مواد التعبئة المعلق من رجوع الشحنة: ${_fmtMoney(_returnPackagingWasteCost)} ج.م',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          Text(
                            'عدد الكراتين التالفة: $_returnDamagedCartons كرتونة | نظام التسوية الدوارة التراكمية نشط لتسوية هذا الرصيد',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_returnWasteDetails.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _returnWasteDetails.map((det) {
                      final rNo = det['return_number'] ?? '';
                      final sNo = det['shipment_no'] ?? '';
                      final amt = (det['waste_cost'] as num?)?.toDouble() ?? 0.0;
                      final dmg = det['damaged_cartons'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'مرتجع #$rNo (شحنة $sNo): ${_fmtMoney(amt)} ج.م ($dmg كرتونة)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],

        // 0.5 Seasonal opening cumulative waste balance (visible immediately on open)
        _buildSeasonalOpeningWasteBanner(isDark, currentOrderWaste, remainingUnsettled),

        // 1. Dedicated Global Waste Value Card (Cumulative Rolling Waste Settlement)
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : (isRolling
                      ? [const Color(0xFFFFFBEB), const Color(0xFFF8FAFC)]
                      : [const Color(0xFFF0FDF4), const Color(0xFFF8FAFC)]),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRolling
                  ? (isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : const Color(0xFFF59E0B).withValues(alpha: 0.5))
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
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
                      color: (isRolling ? const Color(0xFFF59E0B) : const Color(0xFF0284C7)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isRolling ? Icons.history_toggle_off_rounded : Icons.analytics_rounded,
                      color: isRolling ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRolling
                              ? 'التسوية التراكمية والدوارة لهالك مواد التعبئة (Rolling Waste Settlement)'
                              : 'إجمالي هالك مواد التعبئة على مستوى أمر التعبئة ككل',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          isRolling
                              ? 'تسوية رصيد الهالك المعلق السابق جزئياً باستخدام هالك أمر التشغيل الحالي'
                              : 'تجميع القيمة المالية للهالك لكافة خامات ومواد التعبئة المنصرفة في هذا الأمر',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: isDark ? AppTheme.textSecondary : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, boxConstraints) {
                  final isWideCards = boxConstraints.maxWidth >= 580;
                  final cards = [
                    _buildGlobalWasteStatCard(
                      title: isRolling ? 'إجمالي الهالك غير المسوّى (سابق)' : 'إجمالي تكلفة مواد التعبئة',
                      subtitle: isRolling ? 'الرصيد التراكمي المعلق للتسوية' : 'كافة الأصناف بدون هالك',
                      value: '${_fmtMoney(totalWastePool)} ج.م',
                      icon: isRolling ? Icons.history_toggle_off_rounded : Icons.inventory_2_outlined,
                      color: isRolling ? const Color(0xFFEA580C) : const Color(0xFF0284C7),
                      isDark: isDark,
                      isBold: isRolling,
                    ),
                    _buildGlobalWasteStatCard(
                      title: isRolling ? 'تم تسويته (هالك هذا الأمر)' : 'نسبة الفقد العامة للأمر',
                      subtitle: isRolling ? 'بنسبة ${_fmtPercent(_materialWastePercent)}% (يضاف لتكلفة الأمر)' : 'تطبق على إجمالي الخامات',
                      value: isRolling ? '${_fmtMoney(currentOrderWaste)} ج.م' : '${_fmtPercent(_materialWastePercent)}%',
                      icon: isRolling ? Icons.task_alt_rounded : Icons.percent_rounded,
                      color: isRolling ? AppTheme.success : const Color(0xFF6366F1),
                      isDark: isDark,
                      isBold: isRolling,
                    ),
                    _buildGlobalWasteStatCard(
                      title: isRolling ? 'المتبقي للتسوية (رصيد معلق)' : 'إجمالي القيمة المالية للهالك',
                      subtitle: isRolling ? 'المعادلة: ${_fmtMoney(totalWastePool)} - ${_fmtMoney(currentOrderWaste)}' : 'التكلفة × النسبة ÷ 100',
                      value: isRolling ? '${_fmtMoney(remainingUnsettled)} ج.م' : '${_fmtMoney(currentOrderWaste)} ج.م',
                      icon: isRolling ? Icons.pending_actions_rounded : Icons.delete_sweep_outlined,
                      color: isRolling ? const Color(0xFF0284C7) : AppTheme.danger,
                      isDark: isDark,
                      isBold: true,
                    ),
                  ];

                  if (isWideCards) {
                    return Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[2]),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 8),
                        cards[1],
                        const SizedBox(height: 8),
                        cards[2],
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRolling
                            ? 'المعادلة التراكمية: رصيد الهالك غير المسوّى (${_fmtMoney(totalWastePool)} ج.م) - تسوية هالك هذا الأمر (${_fmtMoney(currentOrderWaste)} ج.م) = المتبقي للتسوية (${_fmtMoney(remainingUnsettled)} ج.م) | يضاف ${_fmtMoney(currentOrderWaste)} ج.م لتكلفة أمر التعبئة الحالي'
                            : 'المعادلة التجميعية للأمر: ${_fmtMoney(actualMaterialCost)} ج.م (إجمالي خامات التعبئة) × ${_fmtPercent(_materialWastePercent)}% (نسبة الفقد) = ${_fmtMoney(currentOrderWaste)} ج.م (إجمالي قيمة الهالك العام)',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Percentage Input & Dedicated Rolling Waste Settlement Action Card
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 620;

            final percentageInputField = TextFormField(
              controller: _materialWastePercentCtrl,
              enabled: !_isPackagingLocked,
              decoration: _inputDecoration(
                isRolling
                    ? 'نسبة هالك أمر التعبئة الحالي (%)'
                    : 'نسبة الفقد الفعلية الشاملة لأمر التعبئة (%)',
                helperText: isRolling
                    ? 'تطبق على خامات الأمر (${_fmtMoney(actualMaterialCost)} ج.م) لحساب هالك ${_fmtMoney(currentOrderWaste)} ج.م يضاف لتكلفة التشغيلة ويسوي جزءاً من الرصيد التراكمي'
                    : 'تطبق على إجمالي تكلفة كافة مواد التعبئة (${_fmtMoney(actualMaterialCost)} ج.م) لحساب الهالك',
                suffixIcon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: const Center(
                    widthFactor: 1.0,
                    child: Text(
                      '%',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
              ],
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 16,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'أدخل نسبة صحيحة';
                if (n > 100) return 'النسبة لا تتجاوز 100%';
                return null;
              },
            );

            final unsettledWasteCard = Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: (isSettledOrPosted || remainingUnsettled <= 0.001)
                    ? (isDark ? const Color(0xFF0F231D) : const Color(0xFFF0FDF4))
                    : (isDark ? const Color(0xFF2D2012) : const Color(0xFFFFFBEB)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isSettledOrPosted || remainingUnsettled <= 0.001)
                      ? AppTheme.success.withValues(alpha: 0.4)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isSettledOrPosted || remainingUnsettled <= 0.001 ? AppTheme.success : const Color(0xFFF59E0B))
                        .withValues(alpha: isDark ? 0.25 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (isSettledOrPosted || remainingUnsettled <= 0.001 ? AppTheme.success : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          (isSettledOrPosted || remainingUnsettled <= 0.001)
                              ? Icons.check_circle_rounded
                              : Icons.pending_actions_rounded,
                          size: 18,
                          color: (isSettledOrPosted || remainingUnsettled <= 0.001) ? AppTheme.success : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isSettledOrPosted
                              ? 'حالة هالك أمر التعبئة'
                              : (isRolling
                                  ? 'المتبقي للتسوية (من الرصيد التراكمي)'
                                  : 'قيمة الهالك غير المسوّى (المتبقي للتسوية)'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isSettledOrPosted || remainingUnsettled <= 0.001 ? AppTheme.success : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPosted
                              ? 'تم الترحيل (مسوى)'
                              : (isSettled
                                  ? 'هالك مسوى'
                                  : (remainingUnsettled > 0.001
                                      ? 'هالك غير مسوّى'
                                      : (totalWastePool > 0.001 ? 'هالك مسوى' : 'لا يوجد هالك'))),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: (isSettledOrPosted || remainingUnsettled <= 0.001) ? AppTheme.success : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _fmtMoney(isSettledOrPosted ? 0.0 : remainingUnsettled),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: 0.5,
                          color: (isSettledOrPosted || remainingUnsettled <= 0.001)
                              ? AppTheme.success
                              : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: (isSettledOrPosted || remainingUnsettled <= 0.001)
                              ? AppTheme.success
                              : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
                        ),
                      ),
                      if (isPosted) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(تم ترحيل الأمر)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ] else if (isSettled) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(تمت التسوية)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPosted
                        ? 'تم ترحيل أمر التعبئة واحتساب الهالك ضمن تكلفة التشغيل وترحيل القيود المحاسبية بنجاح.'
                        : (isSettled
                            ? 'تم تسجيل تسوية الهالك بنجاح بقيمة ${_fmtMoney(settledAmount > 0.001 ? settledAmount : currentOrderWaste)} ج.م ونقلها إلى حساب وسيط الهالك 9111'
                            : (isRolling
                                ? 'المعادلة: رصيد سابق (${_fmtMoney(totalWastePool)} ج.م) - تسوية حالية (${_fmtMoney(currentOrderWaste)} ج.م) = متبقي (${_fmtMoney(remainingUnsettled)} ج.م) | يضاف ${_fmtMoney(currentOrderWaste)} ج.م لتكلفة أمر التعبئة'
                                : (settledAmount > 0.001
                                    ? 'المعادلة: (${_fmtMoney(actualMaterialCost)} ج.م × ${_fmtPercent(_materialWastePercent)}% = ${_fmtMoney(currentOrderWaste)} ج.م) - مسوّى ${_fmtMoney(settledAmount)} ج.م = ${_fmtMoney(remainingUnsettled)} ج.م'
                                    : 'المعادلة: ${_fmtMoney(actualMaterialCost)} ج.م (تكلفة المواد) × ${_fmtPercent(_materialWastePercent)}% = ${_fmtMoney(currentOrderWaste)} ج.م'))),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: percentageInputField),
                  const SizedBox(width: 14),
                  Expanded(flex: 6, child: unsettledWasteCard),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  percentageInputField,
                  const SizedBox(height: 12),
                  unsettledWasteCard,
                ],
              );
            }
          },
        ),

        const SizedBox(height: 16),

        // 3. Clear Distinction Grid & Comprehensive Breakdown (Exact Distinction for Accountants)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            children: [
              // Row 1: Actual Packaging Cost (Clean distinction: Base without waste)
              _buildWasteMetricTile(
                title: 'تكلفة مواد التعبئة الفعلية المنصرفة (الصافية)',
                value: '${_fmtMoney(actualMaterialCost)} ج.م',
                subtitle: 'مجموع كافة خامات ومواد التعبئة المنصرفة في أمر التشغيل (بدون هالك)',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF0284C7),
              ),
              const Divider(height: 16),
              // Row 2: Waste Percent
              _buildWasteMetricTile(
                title: 'نسبة هالك أمر التعبئة الحالي',
                value: '${_fmtPercent(_materialWastePercent)}%',
                subtitle: 'النسبة المعتمدة لتشغيلة هذا الأمر لحساب الهالك المحمل على الإنتاج',
                icon: Icons.percent,
                color: const Color(0xFF6366F1),
              ),
              const Divider(height: 16),
              // Row 3: Current Order Waste Cost
              _buildWasteMetricTile(
                title: 'هالك أمر التعبئة الحالي (المحمل على التشغيلة)',
                value: '${_fmtMoney(currentOrderWaste)} ج.م',
                subtitle: 'المعادلة: تكلفة المواد (${_fmtMoney(actualMaterialCost)} ج.م) × النسبة (${_fmtPercent(_materialWastePercent)}%) - تضاف لتكلفة الأمر وتخفض الرصيد المعلق',
                icon: Icons.delete_sweep_outlined,
                color: AppTheme.danger,
                bold: true,
              ),
              const Divider(height: 16),
              // Row 4: Cumulative Unsettled Pool
              _buildWasteMetricTile(
                title: isRolling
                    ? 'إجمالي الهالك غير المسوّى (الرصيد التراكمي السابق)'
                    : 'إجمالي قيمة الهالك العام للأمر',
                value: '${_fmtMoney(totalWastePool)} ج.م',
                subtitle: isRolling
                    ? 'الرصيد المعلق السابق المطلوب تسويته (من رجوع الشحنات)'
                    : 'إجمالي الهالك المحسوب للأمر',
                icon: Icons.history_toggle_off_rounded,
                color: const Color(0xFFEA580C),
              ),
              const Divider(height: 16),
              // Row 5: Settled Amount
              _buildWasteMetricTile(
                title: 'المبلغ المسوّى (تم تسويته)',
                value: '${_fmtMoney(settledAmount)} ج.م',
                subtitle: isRolling
                    ? 'يشمل تسوية هالك هذا الأمر (${_fmtMoney(currentOrderWaste)} ج.م) والتسويات السابقة المنقولة لوسيط 9111'
                    : 'إجمالي المبالغ المنقولة من مخزن الإنتاج التام إلى حساب وسيط الهالك (9111)',
                icon: Icons.task_alt,
                color: AppTheme.success,
              ),
              const Divider(height: 16),
              // Row 6: Remaining Unsettled Balance
              _buildWasteMetricTile(
                title: 'المتبقي للتسوية (الرصيد المعلق بعد التشغيلة)',
                value: '${_fmtMoney(remainingUnsettled)} ج.م',
                subtitle: 'المعادلة: الرصيد التراكمي (${_fmtMoney(totalWastePool)}) - المسوّى (${_fmtMoney(settledAmount)}) ج.م',
                icon: Icons.pending_actions,
                color: remainingUnsettled > 0.001 ? const Color(0xFFF59E0B) : AppTheme.success,
                isHighlighted: true,
              ),
              const Divider(height: 16),
              // Row 7: Total Packaging Cost after Waste (Loaded onto order)
              _buildWasteMetricTile(
                title: 'تكلفة مواد التعبئة الإجمالية بعد الهالك (المحملة على أمر التعبئة)',
                value: '${_fmtMoney(totalWithWaste)} ج.م',
                subtitle: 'التكلفة الفعلية للأمر شاملة الهالك (${_fmtMoney(actualMaterialCost)} + ${_fmtMoney(currentOrderWaste)} ج.م) ومحملة على الإنتاج (12413)',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFA855F7),
                bold: true,
              ),
              const Divider(height: 16),
              // Row 8: Settlement Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'حالة التسوية:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _wasteSettlementStatusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _wasteSettlementStatusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _wasteSettlementStatusLabel.contains('كامل')
                              ? Icons.check_circle
                              : (_wasteSettlementStatusLabel.contains('جزئية')
                                  ? Icons.hourglass_top
                                  : Icons.pending_actions),
                          size: 14,
                          color: _wasteSettlementStatusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _wasteSettlementStatusLabel,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: _wasteSettlementStatusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Section 7 Explanatory Note (Banner)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF0284C7).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20, color: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ملاحظة محاسبية ورقابية: تم خصم مواد التعبئة والهالك بالكامل من المخزن (12411) وتحميلها على الإنتاج (12413) فور تأكيد المرحلة 2. تصنيف «هالك غير مسوّى» يعبر عن التتبع والاعتماد الإداري للتسوية فقط، ولا يعني وجود مواد متبقية في المخزن.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    height: 1.45,
                    color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 4. Action Buttons (تسجيل تسوية هالك + عرض قيد صرف مواد التعبئة)
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            // Settle Waste Button (Disabled when isSettled || isPosted)
            ElevatedButton.icon(
              onPressed: (isSettledOrPosted || remainingUnsettled <= 0.001)
                  ? null
                  : _openSettleWasteDialog,
              icon: Icon(
                isSettledOrPosted ? Icons.check_circle : Icons.assignment_turned_in,
                size: 16,
              ),
              label: Text(
                isPosted
                    ? 'تم ترحيل الأمر / تمت التسوية'
                    : (isSettled
                        ? 'تمت تسوية الهالك'
                        : (remainingUnsettled <= 0.001
                            ? 'لا يوجد هالك للتسوية'
                            : 'تسجيل تسوية هالك')),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSettledOrPosted
                    ? (isDark ? const Color(0xFF334155) : const Color(0xFF9CA3AF))
                    : const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                disabledBackgroundColor: isSettledOrPosted
                    ? (isDark ? const Color(0xFF334155) : const Color(0xFF9CA3AF))
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
                disabledForegroundColor: isSettledOrPosted
                    ? Colors.white
                    : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: isSettledOrPosted ? 0 : 2,
              ),
            ),

            // GL View Button for packaging issue entry
            if (_currentOrder?.packagingJournalEntryId != null)
              OutlinedButton.icon(
                onPressed: () {
                  JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: _currentOrder!.packagingJournalEntryId,
                  );
                },
                icon: const Icon(Icons.receipt_long, size: 16, color: Color(0xFFA855F7)),
                label: Text(
                  'عرض قيد صرف مواد التعبئة والهالك (#${_currentOrder!.packagingJournalEntryId})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFFA855F7),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFA855F7)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),

        // 5. Past Settlements Table
        if (_wasteSettlements.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'سجل تسويات الهالك المسجلة:',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _buildWasteSettlementsTable(isDark),
        ],
      ],
    );
  }

  Widget _buildSeasonalOpeningWasteBanner(bool isDark, double currentOrderWaste, double remainingUnsettled) {
    if (_loadingSeasonalWaste) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0284C7).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'جارٍ استرجاع رصيد الهالك التراكمي الافتتاحي للموسم من قاعدة البيانات...',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (!_seasonalWasteLoaded || _seasonalOpeningWasteBalance <= 0.001) {
      return const SizedBox.shrink();
    }

    final openingBal = _seasonalOpeningWasteBalance;
    final seasonTxt = _seasonLabel.isNotEmpty ? _seasonLabel : 'الموسم الحالي';
    final hasCurrentOrderWaste = currentOrderWaste > 0.001;

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_edu_rounded, color: Color(0xFFD97706), size: 22),
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
                            'رصيد الهالك التراكمي الافتتاحي ($seasonTxt)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'معلق للتسوية الدوارة',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'رصيد هالك مواد تعبئة متراكم من شحنات ومرتجعات سابقة بالموسم تم جلبه فورياً لبدء التسوية الدوارة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'تحديث رصيد الموسم',
                color: const Color(0xFFD97706),
                onPressed: _loadSeasonalWasteBalance,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Metric Chips Row
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildSeasonalMetricMini(
                  title: 'إجمالي هالك المرتجعات بالموسم',
                  value: '${_fmtMoney(_seasonalReturnWasteTotal)} ج.م',
                  sub: '$_seasonalDamagedCartons كرتونة (${_seasonalReturnsCount} مرتجع)',
                  color: const Color(0xFFEA580C),
                  isDark: isDark,
                ),
                _buildSeasonalMetricMini(
                  title: 'مسوّى بأوامر أخرى بالموسم',
                  value: '${_fmtMoney(_seasonalSettledByOthers)} ج.م',
                  sub: 'تسويات دفتريّة سابقة',
                  color: AppTheme.success,
                  isDark: isDark,
                ),
                _buildSeasonalMetricMini(
                  title: 'الرصيد الافتتاحي المعلق للتسوية',
                  value: '${_fmtMoney(openingBal)} ج.م',
                  sub: 'رصيد الهالك قبل هذا الأمر',
                  color: const Color(0xFFD97706),
                  isDark: isDark,
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Dynamic calculation preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hasCurrentOrderWaste
                  ? const Color(0xFF0284C7).withValues(alpha: 0.1)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasCurrentOrderWaste
                    ? const Color(0xFF0284C7).withValues(alpha: 0.3)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasCurrentOrderWaste ? Icons.published_with_changes_rounded : Icons.info_outline,
                  size: 16,
                  color: hasCurrentOrderWaste ? const Color(0xFF0284C7) : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasCurrentOrderWaste
                        ? 'تسوية دوارة نشطة: رصيد افتتاحي (${_fmtMoney(openingBal)} ج.م) - هالك هذا الأمر (${_fmtMoney(currentOrderWaste)} ج.م) = المتبقي للتسوية (${_fmtMoney(remainingUnsettled)} ج.م) ويضاف ${_fmtMoney(currentOrderWaste)} ج.م لتكلفة هذا الأمر.'
                        : 'جاهز للتسوية: الرصيد الافتتاحي المعلق (${_fmtMoney(openingBal)} ج.م) يظهر بالكامل في «المتبقي للتسوية»، وسيسوى جزئياً فور إدخال نسبة الهالك لأمر التعبئة الحالي.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasCurrentOrderWaste
                          ? (isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1))
                          : (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E)),
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

  Widget _buildSeasonalMetricMini({
    required String title,
    required String value,
    required String sub,
    required Color color,
    required bool isDark,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.5,
            color: isDark ? AppTheme.textSecondary : Colors.black54,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        Text(
          sub,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 9.5,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildWasteMetricTile({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    bool bold = false,
    bool isHighlighted = false,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: isHighlighted ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: isHighlighted
          ? BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: bold || isHighlighted ? FontWeight.bold : FontWeight.w600,
                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: bold || isHighlighted ? 14 : 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalWasteStatCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.8) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isBold ? 0.45 : 0.25),
          width: isBold ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: isBold ? 16 : 14.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildWasteSettlementsTable(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            ),
            columnSpacing: 20,
            horizontalMargin: 12,
            columns: const [
              DataColumn(label: Text('رقم التسوية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
              DataColumn(label: Text('التاريخ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المبلغ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الملاحظات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
              DataColumn(label: Text('المسجل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
              DataColumn(label: Text('القيد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
            ],
            rows: _wasteSettlements.map((s) {
              final id = s['id']?.toString() ?? '';
              final date = s['settlement_date']?.toString().split('T').first ?? '';
              final amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
              final notes = s['notes']?.toString() ?? '-';
              final user = s['created_by']?.toString() ?? '-';
              final jId = s['journal_entry_id'];

              return DataRow(cells: [
                DataCell(Text('#$id', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                DataCell(Text(date, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11))),
                DataCell(Text('${_fmtMoney(amt)} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.success))),
                DataCell(Text(notes, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11))),
                DataCell(Text(user, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10))),
                DataCell(
                  jId != null
                      ? IconButton(
                          icon: const Icon(Icons.receipt_long, size: 16, color: Color(0xFFA855F7)),
                          tooltip: 'عرض القيد المحاسبي (#$jId)',
                          onPressed: () {
                            JournalEntryNavigationService.openById(context, journalEntryId: (jId as num).toInt());
                          },
                        )
                      : const Text('-', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettleWasteDialog() async {
    final orderId = _orderId;
    if (orderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى حفظ أمر التعبئة أولاً قبل تسجيل التسوية'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    if (isSettled || isPosted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isPosted
              ? 'لا يمكن تسجيل تسوية الهالك: تم ترحيل أمر التعبئة واحتساب الهالك ضمن تكلفة التشغيل وترحيل القيود المحاسبية بالفعل.'
              : 'تمت تسوية هالك مواد التعبئة لهذا الأمر مسبقاً.'),
          backgroundColor: isPosted ? AppTheme.warning : AppTheme.info,
        ),
      );
      return;
    }

    // Always sync current form state (percentage + items) to DB first
    await _syncFormStateToDb();

    final isRolling = _isRollingWasteMode;
    final cumulativePool = _cumulativePendingWastePool;
    final currentOrderWaste = _currentOrderCalculatedWaste;
    final alreadySettled = _settledMaterialWasteCost;
    final actualMaterialCost = _actualPackagingMaterialCost;

    // Remaining pool before this settlement action
    final double maxAvailableToSettle = isRolling
        ? (cumulativePool - alreadySettled).clamp(0.0, double.infinity)
        : (currentOrderWaste - alreadySettled).clamp(0.0, double.infinity);

    if (maxAvailableToSettle <= 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRolling
              ? 'تمت تسوية كامل الرصيد التراكمي لهالك مواد التعبئة بالفعل'
              : 'تمت تسوية كامل هالك مواد التعبئة بالفعل'),
          backgroundColor: AppTheme.info,
        ),
      );
      return;
    }

    // Target settlement amount for this order:
    // In rolling mode: if current order waste hasn't been settled yet, default to current order waste.
    // If already partially settled, default to the remaining part of this order waste (or whatever is left in pool).
    final double defaultAmount = isRolling
        ? (alreadySettled < currentOrderWaste
            ? (currentOrderWaste - alreadySettled).clamp(0.0, maxAvailableToSettle)
            : maxAvailableToSettle)
        : maxAvailableToSettle;

    final initialAmount = defaultAmount > 0.001 ? defaultAmount : maxAvailableToSettle;
    final amountCtrl = TextEditingController(text: initialAmount.toStringAsFixed(2));

    final effectiveWastePercent = (_returnPackagingWasteCost > 0 && actualMaterialCost > 0)
        ? ((_returnPackagingWasteCost / actualMaterialCost) * 100)
        : _materialWastePercent;

    final defaultNote = isRolling
        ? (_returnPackagingWasteCost > 0
            ? 'تسوية هالك مواد تعبئة (أمر #${_currentOrder?.orderNumber ?? orderId}) بقيمة ${_fmtMoney(initialAmount)} ج.م خصماً من رصيد هالك رجوع الشحنة ${_returnWasteDetails.isNotEmpty ? _returnWasteDetails.map((d) => d['shipment_no']).where((s) => s != null && s.isNotEmpty).join(', ') : (_exportShipmentNoCtrl.text.isNotEmpty ? _exportShipmentNoCtrl.text : '')}'
            : 'تسوية هالك مواد تعبئة (أمر #${_currentOrder?.orderNumber ?? orderId}) بقيمة ${_fmtMoney(initialAmount)} ج.م خصماً من الرصيد التراكمي المعلق (${_fmtMoney(cumulativePool)} ج.م)')
        : (_returnPackagingWasteCost > 0
            ? 'تسوية هالك مواد تعبئة من رجوع الشحنة ${_returnWasteDetails.isNotEmpty ? _returnWasteDetails.map((d) => d['shipment_no']).where((s) => s != null && s.isNotEmpty).join(', ') : (_exportShipmentNoCtrl.text.isNotEmpty ? _exportShipmentNoCtrl.text : '')} (مرتجع ${_returnWasteDetails.isNotEmpty ? _returnWasteDetails.map((d) => d['return_number']).where((s) => s != null && s.isNotEmpty).join(', ') : ''})'
            : '');
    final notesCtrl = TextEditingController(text: defaultNote);
    DateTime settlementDate = DateTime.now();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = AppTheme.isDark(context);
            final enteredAmount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
            final remainingAfterEntry = isRolling
                ? (cumulativePool - (alreadySettled + enteredAmount)).clamp(0.0, double.infinity)
                : (currentOrderWaste - (alreadySettled + enteredAmount)).clamp(0.0, double.infinity);

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.assignment_turned_in, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isRolling
                          ? 'تسجيل تسوية هالك مواد التعبئة (تسوية دوارة)'
                          : 'تسجيل تسوية هالك مواد التعبئة',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary card showing Total, Settled, Unsettled
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              if (isRolling) ...[
                                if (_returnPackagingWasteCost > 0) ...[
                                  _infoRow(
                                    'مصدر الهالك المعلق',
                                    'رجوع شحنة من المطار ($_returnDamagedCartons كرتونة)',
                                    valueColor: const Color(0xFFEA580C),
                                    bold: true,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                _infoRow(
                                  'إجمالي الهالك غير المسوّى (الرصيد التراكمي السابق)',
                                  '${_fmtMoney(cumulativePool)} ج.م',
                                  valueColor: const Color(0xFFEA580C),
                                  bold: true,
                                ),
                                const SizedBox(height: 6),
                                _infoRow(
                                  'هالك أمر التعبئة الحالي (${_fmtPercent(_materialWastePercent)}%)',
                                  '${_fmtMoney(currentOrderWaste)} ج.م',
                                  valueColor: const Color(0xFF6366F1),
                                  bold: true,
                                ),
                                const SizedBox(height: 6),
                                _infoRow(
                                  'الهالك المسوّى سابقاً في الدفاتر',
                                  '${_fmtMoney(alreadySettled)} ج.م',
                                  valueColor: AppTheme.success,
                                ),
                                const SizedBox(height: 6),
                                _infoRow(
                                  'المبلغ المستهدف لتسوية هالك هذا الأمر',
                                  '${_fmtMoney(defaultAmount)} ج.م',
                                  valueColor: const Color(0xFF0284C7),
                                  bold: true,
                                ),
                                const SizedBox(height: 6),
                                _infoRow(
                                  'المتبقي للتسوية بعد تنفيذ هذا القيد',
                                  '${_fmtMoney(remainingAfterEntry)} ج.م',
                                  valueColor: const Color(0xFFF59E0B),
                                  bold: true,
                                ),
                              ] else ...[
                                if (_returnPackagingWasteCost > 0) ...[
                                  _infoRow(
                                    'مصدر الهالك',
                                    'رجوع شحنة من المطار ($_returnDamagedCartons كرتونة)',
                                    valueColor: const Color(0xFFEA580C),
                                    bold: true,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                _infoRow('إجمالي تكلفة مواد التعبئة في الأمر', '${_fmtMoney(actualMaterialCost)} ج.م',
                                    valueColor: const Color(0xFF0284C7)),
                                const SizedBox(height: 6),
                                _infoRow('نسبة الفقد العامة لأمر التعبئة', '${_fmtPercent(effectiveWastePercent)}%',
                                    valueColor: const Color(0xFF6366F1)),
                                const SizedBox(height: 6),
                                _infoRow('إجمالي قيمة الهالك على مستوى الأمر', '${_fmtMoney(_totalMaterialWasteCost)} ج.م',
                                    valueColor: AppTheme.danger, bold: true),
                                const SizedBox(height: 6),
                                _infoRow('الهالك المسوّى سابقاً', '${_fmtMoney(alreadySettled)} ج.م',
                                    valueColor: AppTheme.success),
                                const SizedBox(height: 6),
                                _infoRow('الهالك غير المسوّى (المتاح للتسوية)', '${_fmtMoney(maxAvailableToSettle)} ج.م',
                                    valueColor: const Color(0xFFF59E0B), bold: true),
                                const SizedBox(height: 6),
                                _infoRow('المتبقي بعد تنفيذ هذا القيد', '${_fmtMoney(remainingAfterEntry)} ج.م',
                                    valueColor: AppTheme.success, bold: true),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFF0284C7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isRolling
                                      ? 'سيتم توليد قيد مزدوج فوري: مدين حساب وسيط هالك مواد التعبئة (9111) ودائن مخزن إنتاج تام (12413)، مما يسوي جزئياً الرصيد التراكمي ويحمل قيمة هالك هذا الأمر (${_fmtMoney(enteredAmount)} ج.م) على التشغيلة.'
                                      : 'سيتم توليد قيد مزدوج فوري: مدين حساب وسيط هالك مواد التعبئة (9111) ودائن مخزن إنتاج تام (12413).',
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5, color: Color(0xFF0284C7)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Amount input
                        TextFormField(
                          controller: amountCtrl,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: _inputDecoration(
                            'قيمة التسوية (ج.م) *',
                            helperText: isRolling
                                ? 'الحد الأقصى المتاح للتسوية: ${_fmtMoney(maxAvailableToSettle)} ج.م (المقترح لهذا الأمر: ${_fmtMoney(defaultAmount)} ج.م)'
                                : 'الحد الأقصى المتاح للتسوية: ${_fmtMoney(maxAvailableToSettle)} ج.م',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'يرجى إدخال قيمة التسوية';
                            final parsed = double.tryParse(v.trim());
                            if (parsed == null || parsed <= 0) return 'يجب إدخال مبلغ أكبر من صفر';
                            if (parsed > (maxAvailableToSettle + 0.001)) {
                              return 'قيمة التسوية لا يمكن أن تتجاوز ${_fmtMoney(maxAvailableToSettle)} ج.م';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Notes input
                        TextFormField(
                          controller: notesCtrl,
                          maxLines: 2,
                          decoration: _inputDecoration(
                            'ملاحظات التسوية (اختياري)',
                            hint: 'مثال: تسوية تشغيلية لهالك كراتين ومواد تغليف (وسيط 9111)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final amount = double.parse(amountCtrl.text.trim());
                          setDialogState(() => isSubmitting = true);
                          try {
                            final res = await _dao.settlePackingMaterialWaste(
                              packingOrderId: orderId,
                              amount: amount,
                              notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                              settlementDate: settlementDate,
                            );

                            if (res['success'] == true) {
                              final jeNum = res['journal_entry_number'];
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(jeNum != null
                                        ? 'تم تسجيل تسوية الهالك بنجاح بقيمة ${_fmtMoney(amount)} ج.م (قيد #$jeNum - وسيط 9111)'
                                        : 'تم تسجيل تسوية الهالك بنجاح بقيمة ${_fmtMoney(amount)} ج.م (وسيط 9111)'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                              }
                              if (mounted) {
                                setState(() {
                                  _isWasteSettled = true;
                                });
                              }
                              await _loadWasteSettlements();
                              await _refreshCurrentOrder();
                            } else {
                              final err = res['error']?.toString() ?? 'فشل في تسجيل التسوية';
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err), backgroundColor: AppTheme.danger),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isSubmitting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'تسجيل التسوية',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPackagingStageActionBar(bool isDark) {
    if (_isPackagingConfirmed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFA855F7).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFFA855F7), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المرحلة 2: تم تأكيد وصرف مواد التعبئة والتغليف',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF7E22CE),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(_isOrderFinalized ? Icons.lock : Icons.edit_note, size: 12, color: const Color(0xFFA855F7)),
                      const SizedBox(width: 4),
                      Text(
                        _isOrderFinalized ? 'مقفل نهائياً' : 'مؤكد (مفتوح للتعديل)',
                        style: const TextStyle(
                          color: Color(0xFFA855F7),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_currentOrder?.packagingConfirmedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'تاريخ الصرف: ${_formatStageDate(_currentOrder?.packagingConfirmedAt)}',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
            if (_currentOrder?.packagingJournalEntryId != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: _currentOrder!.packagingJournalEntryId,
                  );
                },
                icon: const Icon(Icons.receipt_long, size: 16, color: Color(0xFFA855F7)),
                label: Text(
                  'عرض قيد صرف مواد التعبئة (#${_currentOrder!.packagingJournalEntryId})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA855F7),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFA855F7)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.purple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFA855F7)),
                    const SizedBox(width: 6),
                    Text(
                      'لا توجد مواد تعبئة مستخدمة في هذا الأمر (التكلفة = 0.00 ج.م - لا يتطلب قيد صرف مخزني)',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF6B21A8),
                        fontSize: 11,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isOrderFinalized) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stageLoading ? null : _confirmPackagingStage,
                  icon: _stageLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 18, color: Colors.white),
                  label: Text(
                    _currentOrder?.packagingJournalEntryId != null
                        ? 'تحديث وصرف مواد التعبئة (${_materialItems.length} مواد)'
                        : 'صرف مواد التعبئة وتوليد القيد (${_materialItems.length} مواد)',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA855F7),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

            ],
          ],
        ),
      );
    }

    if (!_isCropsConfirmed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: isDark ? Colors.white38 : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'المرحلة 2 (صرف مواد التعبئة) غير متاحة حالياً: يجب إتمام تأكيد وصرف المحاصيل أولاً.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFAF5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFFA855F7), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المرحلة 2: تأكيد وصرف مواد التعبئة والتغليف',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF7E22CE),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'سيتم خصم كميات خامات التعبئة (${_materialItems.length} مواد) وفاقد المواد من المخزن وترحيل القيد المحاسبي وقفل قسم التعبئة.',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black87,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stageLoading ? null : _confirmPackagingStage,
              icon: _stageLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text(
                'تأكيد وصرف مواد التعبئة (المرحلة 2)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostItemsSection() {
    final isDark = AppTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isCostsConfirmed && !_isOrderFinalized) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, size: 20, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'القسم مفتوح للإضافة والتعديل: يمكنك إضافة أو تعديل بنود التكلفة الإضافية بحرية طالما لم يُقفل الأمر نهائياً، ثم الضغط على زر "تحديث وترحيل التكاليف الإضافية" لإعادة احتساب وتوزيع التكاليف وتحديث القيود تلقائياً.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ..._costItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final itemCurrency = (item['supplier_currency'] as String? ?? 'EGP').toUpperCase();
          final currSymbol = SupplierModel.getCurrencySymbol(itemCurrency);
          final isForeign = itemCurrency != 'EGP' && itemCurrency != 'MULTI';
          final totalEgp =
              ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();
          final totalNative = ((item['total'] ?? totalEgp) as num).toDouble();
          final categoryId = item['report_category_id'] as int?;
          String categoryLabel = '';
          if (categoryId != null) {
            final matched = _costCategories
                .firstWhere((c) => c['id'] == categoryId, orElse: () => {});
            categoryLabel = matched['name'] as String? ?? '';
          }
          if (categoryLabel.isEmpty) {
            categoryLabel = (item['category_name'] as String?) ??
                _costCategoryLabel(item['category'] as String? ?? 'other');
          }

          final pType = item['payment_source_type'] as String?;
          final pId = (item['payment_source_id'] as num?)?.toInt();
          String pText = 'آجل';
          Color pColor = AppTheme.warning;
          if (pType == 'treasury' && pId != null) {
            final t =
                _treasuries.firstWhere((e) => e['id'] == pId, orElse: () => {});
            pText = 'خزينة: ${t['name'] ?? ''}';
            pColor = AppTheme.success;
          } else if (pType == 'bank' && pId != null) {
            final b = _bankAccounts.firstWhere((e) => e['id'] == pId,
                orElse: () => {});
            pText = 'بنك: ${b['account_name'] ?? ''}';
            pColor = const Color(0xFF8B5CF6);
          }

          final itemNameLower = (item['name']?.toString() ?? '').toLowerCase();
          final itemSuppLower = (item['supplier_name']?.toString() ?? '').toLowerCase();
          final isEngineerItem = item['supplier_type'] == 'engineer' ||
              item['category'] == 'engineer_expenses' ||
              itemNameLower.contains('مهندس') ||
              itemSuppLower.contains('مهندس') ||
              item['custody_id'] != null;
          final isEngineerSettled = isEngineerItem ||
              item['is_engineer_cost_settled'] == true ||
              (isEngineerItem && item['cost_status'] == 'actual' && item['actual_amount'] != null);
          final isTransportItem = item['supplier_type'] == 'transport' || item['category'] == 'logistics';
          final isStationOrDeduction = item['supplier_type'] == 'station' ||
              item['supplier_type'] == 'deduction' ||
              item['supplier_type'] == 'deductions' ||
              itemNameLower.contains('محطة') ||
              itemNameLower.contains('تخصيم') ||
              itemSuppLower.contains('محطة') ||
              itemSuppLower.contains('تخصيم');
          final isActualCost = isTransportItem ||
              (isEngineerItem ? isEngineerSettled : (item['cost_status'] == 'actual' && item['actual_amount'] != null));

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(item['name'] as String,
                                style: TextStyle(
                                    color: isDark ? AppTheme.textPrimary : Colors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                          ),
                          if (isEngineerItem) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(80)),
                              ),
                              child: const Text(
                                'مصاريف مهندسين 👷',
                                style: TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (item['supplier_type'] == 'station') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF059669).withAlpha(80)),
                              ),
                              child: const Text(
                                'محطة 🏭',
                                style: TextStyle(
                                  color: Color(0xFF059669),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (item['supplier_type'] == 'deduction') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C3AED).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80)),
                              ),
                              child: const Text(
                                'تخصيمات 📋',
                                style: TextStyle(
                                  color: Color(0xFF7C3AED),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (item['supplier_type'] == 'transport' || item['category'] == 'logistics') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.accent.withAlpha(80)),
                              ),
                              child: const Text(
                                'نقل 🚛',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (item['supplier_type'] == 'admin') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF0284C7).withAlpha(80)),
                              ),
                              child: const Text(
                                'مصاريف إدارية 💼',
                                style: TextStyle(
                                  color: Color(0xFF0284C7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (isEngineerItem) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.success.withAlpha(80)),
                              ),
                              child: const Text(
                                'تكلفة فعلية من العهد ✓',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (isTransportItem || isStationOrDeduction || item['cost_status'] != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActualCost
                                    ? AppTheme.success.withAlpha(25)
                                    : AppTheme.warning.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isActualCost
                                      ? AppTheme.success.withAlpha(80)
                                      : AppTheme.warning.withAlpha(80),
                                ),
                              ),
                              child: Text(
                                isActualCost
                                    ? (isTransportItem ? 'تكلفة نقل فعلية ✓' : 'تكلفة فعلية ✓')
                                    : 'تكلفة تقديرية ⏳',
                                style: TextStyle(
                                  color: isActualCost
                                      ? AppTheme.success
                                      : AppTheme.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: pColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pColor.withAlpha(80)),
                            ),
                            child: Text(
                              pText,
                              style: TextStyle(
                                color: pColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          isEngineerItem
                              ? 'عهدة الموظف/المهندس: ${item['engineer_name'] ?? item['supplier_name'] ?? 'عهدة نقدية'}${item['expense_account_name'] != null ? ' | التوجيه: ${item['expense_account_code'] != null ? "[${item['expense_account_code']}] " : ""}${item['expense_account_name']}' : ''} | مركز التكلفة: CC-ENG-EXP | التوزيع: ${CostAllocationMethod.fromCode(item['allocation_method'] as String?).label}'
                              : ((item['supplier_type'] == 'transport' || item['category'] == 'logistics')
                                  ? 'التوزيع: ${CostAllocationMethod.fromCode(item['allocation_method'] as String?).label} | مقاول النقل: ${item['supplier_name'] ?? ''} | عدد النقلات: ${(() { final trk = ((item['truck_count'] ?? item['quantity'] ?? 0) as num).toDouble(); return trk % 1 == 0 ? trk.toInt().toString() : trk.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''); })()} نقلة | تكلفة النقل: ${totalEgp.toStringAsFixed(2)} ج.م${item['transport_batch_id'] != null ? ' | دفعة: #' + (item['transport_batch_id'] == -1 ? 'افتتاحي' : item['transport_batch_id'].toString()) + (item['transport_batch_cost_per_truck'] != null ? ' (' + NumberFormat('#,##0.00').format(item['transport_batch_cost_per_truck']) + ' ج.م/نقلة)' : '') : ''}'
                                  : (item['supplier_type'] == 'admin')
                                      ? 'مصاريف إدارية — ${NumberFormat('#,##0.##').format(totalEgp)} ج.م'
                                      : 'التصنيف: $categoryLabel | التوزيع: ${CostAllocationMethod.fromCode(item['allocation_method'] as String?).label} | المورد: ${item['supplier_name'] ?? ''} | الكمية: ${((item['quantity'] ?? 0) as num).toDouble().toStringAsFixed(1)} | سعر الوحدة: ${((item['unit_price'] ?? 0) as num).toDouble().toStringAsFixed(2)} $currSymbol'),
                          style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      if (item['notes'] != null && item['notes'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark
                                  ? (item['supplier_type'] == 'admin' ? const Color(0xFF0284C7).withAlpha(120) : AppTheme.glassBorder)
                                  : (item['supplier_type'] == 'admin' ? const Color(0xFFBAE6FD) : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notes_rounded,
                                  size: 14,
                                  color: item['supplier_type'] == 'admin'
                                      ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'البيان: ${item['notes']}',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: item['supplier_type'] == 'admin'
                                        ? (isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1))
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isForeign)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${totalNative.toStringAsFixed(2)} $currSymbol',
                        style: TextStyle(
                            color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo'),
                      ),
                      Text(
                        '${totalEgp.toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo'),
                      ),
                    ],
                  )
                else if (isEngineerItem)
                  Builder(builder: (_) {
                    final actualAmt = (item['actual_amount'] as num?)?.toDouble() ?? totalEgp;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${actualAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        const Text('تكلفة فعلية محملة من العهد ✓',
                            style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ],
                    );
                  })
                else if (isStationOrDeduction && item['cost_status'] != 'actual')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${(item['expected_amount'] != null ? (item['expected_amount'] as num).toDouble() : totalEgp).toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      Text('تقديري',
                          style: TextStyle(
                              color: AppTheme.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ],
                  )
                else if (isStationOrDeduction && item['cost_status'] == 'actual' && item['actual_amount'] != null)
                  Builder(builder: (_) {
                    final actualAmt = (item['actual_amount'] as num).toDouble();
                    final expectedAmt = item['expected_amount'] != null
                        ? (item['expected_amount'] as num).toDouble()
                        : totalEgp;
                    final varianceAmt = actualAmt - expectedAmt;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${actualAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        Text('التقديري: ${expectedAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.textMuted : Colors.black54,
                                fontSize: 10,
                                fontFamily: 'Cairo')),
                        if (varianceAmt.abs() > 0.01)
                          Text(
                            'فرق: ${varianceAmt > 0 ? "+" : ""}${varianceAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                              color: varianceAmt > 0 ? AppTheme.danger : AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                      ],
                    );
                  })
                else if (item['cost_status'] == 'actual' && item['variance_amount'] != null && (item['variance_amount'] as num) != 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${totalEgp.toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      Text(
                        'فرق: ${(item['variance_amount'] as num) > 0 ? "+" : ""}${((item['variance_amount'] as num).toDouble()).toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                          color: (item['variance_amount'] as num) > 0 ? AppTheme.danger : AppTheme.success,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  )
                else
                  Text('${totalEgp.toStringAsFixed(2)} ج.م',
                      style: TextStyle(
                          color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                if (isEngineerItem) ...[
                  IconButton(
                    icon: Icon(
                      isEngineerSettled ? Icons.verified_outlined : Icons.receipt_long,
                      color: isEngineerSettled ? AppTheme.success : const Color(0xFFF59E0B),
                      size: 20,
                    ),
                    tooltip: isEngineerSettled ? 'تعديل تسوية مصاريف المهندس' : 'تسوية مصاريف المهندس الفعلية والعهدة',
                    onPressed: () => _openEngineerCostSettlementDialog(item, i),
                  ),
                ],
                if (!_isCostsLocked) ...[
                  if (!isEngineerItem)
                  IconButton(
                    icon:
                        const Icon(Icons.edit, color: AppTheme.accent, size: 20),
                    onPressed: () => _editCostItem(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete,
                        color: AppTheme.danger, size: 20),
                    onPressed: () async {
                      final itemToRemove = _costItems[i];
                      final txId = (itemToRemove['treasury_transaction_id'] as num?)?.toInt();
                      if (txId != null) {
                        try {
                          await Supabase.instance.client
                              .from('treasury_transactions')
                              .delete()
                              .eq('id', txId)
                              .eq('status', 'draft');
                        } catch (_) {}
                      }
                      setState(() => _costItems.removeAt(i));
                      await _syncFormStateToDb();
                      await _refreshCurrentOrder();
                      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
                      DataChangeEventBus.instance.notifySuppliersChanged();
                    },
                  ),
                ],
              ],
            ),
          );
        }),
        if (!_isCostsLocked) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addCostItem,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('إضافة بند تكلفة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCostsStageActionBar(bool isDark) {
    if (_isCostsConfirmed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFFF59E0B), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المرحلة 3: تم إثبات وترحيل التكاليف الإضافية',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFFB45309),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(_isOrderFinalized ? Icons.lock : Icons.edit_note, size: 12, color: const Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        _isOrderFinalized ? 'مقفل نهائياً' : 'مؤكد (مفتوح للإضافة والتعديل)',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_currentOrder?.costsConfirmedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'تاريخ الترحيل: ${_formatStageDate(_currentOrder?.costsConfirmedAt)}',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
            if (_currentOrder?.costsJournalEntryId != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: _currentOrder!.costsJournalEntryId,
                  );
                },
                icon: const Icon(Icons.receipt_long, size: 16, color: Color(0xFFF59E0B)),
                label: Text(
                  'عرض قيد التكاليف والموردين (#${_currentOrder!.costsJournalEntryId})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.amber.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      'لا توجد بنود تكلفة إضافية في هذا الأمر (التكلفة = 0.00 ج.م - لا يتطلب قيد محاسبي)',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : const Color(0xFFB45309),
                        fontSize: 11,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isOrderFinalized) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stageLoading ? null : _confirmCostsStage,
                  icon: _stageLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, size: 18, color: Colors.white),
                  label: Text(
                    _currentOrder?.costsJournalEntryId != null
                        ? 'تحديث وترحيل التكاليف الإضافية (${_costItems.length} بنود)'
                        : 'ترحيل التكاليف الإضافية وتوليد القيد (${_costItems.length} بنود)',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (!_isPackagingConfirmed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: isDark ? Colors.white38 : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'المرحلة 3 (ترحيل التكاليف) غير متاحة حالياً: يجب إتمام تأكيد وصرف مواد التعبئة أولاً.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? AppTheme.textSecondary : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المرحلة 3: تأكيد وترحيل التكاليف الإضافية',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFFB45309),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'سيتم إثبات مستحقات الموردين وتحديث كشوف حساباتهم وترحيل القيود المحاسبية وقفل قسم التكاليف.',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black87,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_stageLoading || _isConfirmingCosts) ? null : _confirmCostsStage,
              icon: (_stageLoading || _isConfirmingCosts)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text(
                'تأكيد وترحيل التكاليف (المرحلة 3)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _costCategoryLabel(String cat) {
    switch (cat) {
      case 'packing_material':
        return 'مواد تعبئة';
      case 'packing':
        return 'تعبئة وتغليف';
      case 'logistics':
        return 'لوجستيك ونقل';
      case 'admin':
        return 'مصاريف إدارية';
      case 'export_cost':
        return 'تكاليف تصدير';
      case 'fruit':
        return 'تكلفة الفاكهة';
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
      case 'other':
        return 'أخرى';
      default:
        return cat;
    }
  }

  String _costCategoryDbKey(String displayOrKey) {
    final lower = displayOrKey.toLowerCase();
    if (lower.contains('محصول') || lower == 'fruit') return 'fruit';
    if (lower.contains('نقل') ||
        lower.contains('شحن') ||
        lower.contains('لوجستيك') ||
        lower == 'logistics') return 'logistics';
    if (lower.contains('تعبئة') ||
        lower.contains('packing') ||
        lower.contains('material')) return 'material';
    return displayOrKey;
  }

  /// Fetches real-time custody balance details, linking operational cash balance (treasury_balances)
  /// with the General Ledger / Chart of Accounts (accounts & account_ledger_entries).
  Future<Map<String, dynamic>> fetchCustodyBalanceInfo(
    dynamic custodyId, {
    String currency = 'EGP',
  }) async {
    if (custodyId == null) return {};
    final idStr = custodyId.toString();
    try {
      final details = await TreasuryDao().getCustodyBalanceDetails(
        treasuryId: custodyId,
        currency: currency,
      );
      if (details.isNotEmpty) {
        _custodyBalancesMap[idStr] = details;
        final effectiveBal = (details['balance'] as num?)?.toDouble() ?? 0.0;
        final tIdx = _treasuries.indexWhere((t) => t['id']?.toString() == idStr);
        if (tIdx != -1) {
          _treasuries[tIdx]['live_balance'] = effectiveBal;
          if (details['account_id'] != null) {
            _treasuries[tIdx]['account_id'] = details['account_id'];
          }
        }
        return details;
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching custody balance for $custodyId: $e');
    }
    return _custodyBalancesMap[idStr] ?? {
      'custody_id': custodyId,
      'balance': 0.0,
      'operational_balance': 0.0,
      'currency': currency,
    };
  }


  Widget _buildTransportBatchSection({
    required bool isDark,
    required bool isLoadingBatches,
    required List<TransportBatchModel> batches,
    required TransportBatchModel? selectedBatch,
    required ValueChanged<TransportBatchModel?> onBatchChanged,
    required ValueChanged<double> onSelectQuickQty,
  }) {
    if (isLoadingBatches) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
            ),
            SizedBox(width: 10),
            Text(
              'جاري تحميل دفعات استحقاقات النقل للمورد...',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      );
    }

    final availableBatches = batches.where((b) => b.availableTrucks > 0.0001).toList();

    if (availableBatches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: AppTheme.warning.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.warning.withAlpha(80)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.warning, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'لا توجد دفعات استحقاق نقل متاحة برصيد متبقٍ لهذا المورد. يمكنك إدخال عدد النقلات والتكلفة يدوياً أدناه.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.warning,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'دفعات استحقاقات النقل المتاحة للمورد:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${availableBatches.length} دفعة متاحة',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: (selectedBatch != null && availableBatches.any((b) => b.id == selectedBatch.id))
                ? selectedBatch.id
                : null,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            decoration: _inputDecoration('اختر دفعة الاستحقاق للسحب منها *').copyWith(
              prefixIcon: const Icon(Icons.local_shipping_outlined, color: AppTheme.accent, size: 18),
            ),
            selectedItemBuilder: (BuildContext context) {
              return availableBatches.map((b) {
                return Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    b.displayTitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList();
            },
            items: availableBatches.map((b) {
              return DropdownMenuItem<int>(
                value: b.id,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.displayTitle,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (b.displaySubtitle.isNotEmpty)
                      Text(
                        b.displaySubtitle,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                final match = availableBatches.firstWhere((b) => b.id == val, orElse: () => availableBatches.first);
                onBatchChanged(match);
              }
            },
          ),
          if (selectedBatch != null && availableBatches.any((b) => b.id == selectedBatch.id)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14243B) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent.withAlpha(40)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.attach_money, color: AppTheme.accent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'تكلفة النقلة بالدفعة:',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${selectedBatch.formattedCostPerTruck} ج.م/نقلة',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: Color(0xFF00B4D8), size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'النقلات المتاحة في هذه الدفعة:',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${selectedBatch.formattedAvailableTrucks} نقلة (من إجمالي ${selectedBatch.formattedTotalTrucks})',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00B4D8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'سحب كمية سريعة:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final q in [0.5, 1.0, 1.5, 2.0])
                          if (q <= (selectedBatch.availableTrucks + 0.0001))
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ActionChip(
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                label: Text(
                                  '${q % 1 == 0 ? q.toInt() : q} نقلة',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => onSelectQuickQty(q),
                              ),
                            ),
                        if (selectedBatch.availableTrucks > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: ActionChip(
                              backgroundColor: AppTheme.accent.withAlpha(40),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              label: Text(
                                'كامل المتاح (${selectedBatch.formattedAvailableTrucks})',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                ),
                              ),
                              onPressed: () => onSelectQuickQty(selectedBatch.availableTrucks),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Fetch transport entitlement batches for [supplierId] and deduct in-memory
  /// allocations from [_costItems] so available truck balances are 100% up to date.
  Future<List<TransportBatchModel>> _getEffectiveTransportBatches({
    required int supplierId,
    int? excludeItemIndex,
    bool onlyAvailable = true,
    int? includeBatchId,
  }) async {
    final currentOrdId = int.tryParse(_currentOrder?.id ?? widget.existingOrder?.id ?? '');
    final rawBatches = await TransportSupplierDao().getEntitlementBatches(
      supplierId,
      excludePackingOrderId: currentOrdId,
    );

    // Sum allocated trucks per batch from current in-memory _costItems
    final Map<int, double> allocatedByBatch = {};
    double unallocatedAllocatedTrucks = 0.0;

    for (int i = 0; i < _costItems.length; i++) {
      if (excludeItemIndex != null && i == excludeItemIndex) continue;
      final c = _costItems[i];
      final itemSuppId = c['transport_supplier_id']?.toString() ?? c['supplier_id']?.toString();
      if (itemSuppId == supplierId.toString()) {
        final bId = (c['transport_batch_id'] as num?)?.toInt();
        final tCount = (c['truck_count'] as num?)?.toDouble() ??
            (c['quantity'] as num?)?.toDouble() ?? 0.0;
        if (tCount <= 0) continue;

        if (bId != null) {
          allocatedByBatch[bId] = (allocatedByBatch[bId] ?? 0.0) + tCount;
        } else {
          unallocatedAllocatedTrucks += tCount;
        }
      }
    }

    // Now compute effective available & consumed trucks for each batch
    final List<TransportBatchModel> effectiveBatches = [];
    double remainingUnallocated = unallocatedAllocatedTrucks;

    for (final b in rawBatches) {
      double allocated = allocatedByBatch[b.id] ?? 0.0;
      double available = (b.availableTrucks - allocated).clamp(0.0, double.infinity);
      double consumed = b.consumedTrucks + allocated;

      if (remainingUnallocated > 0 && available > 0) {
        final deduct = remainingUnallocated.clamp(0.0, available);
        available = (available - deduct).clamp(0.0, double.infinity);
        consumed += deduct;
        remainingUnallocated -= deduct;
      }

      effectiveBatches.add(b.copyWith(
        availableTrucks: available,
        consumedTrucks: consumed,
      ));
    }

    if (onlyAvailable) {
      return effectiveBatches.where((b) {
        if (includeBatchId != null && b.id == includeBatchId) return true;
        return b.availableTrucks > 0.0001;
      }).toList();
    }

    return effectiveBatches;
  }

  /// Computes remaining truck balance for transport contractor [supplierId],
  /// subtracting any trucks currently allocated in [_costItems].
  double _getRemainingTruckBalance(String? supplierId, {int? excludeItemIndex}) {
    if (supplierId == null || supplierId.isEmpty) return 0.0;
    final transSupplier = _transportSuppliers.firstWhere(
      (s) => s.id.toString() == supplierId,
      orElse: () => const TransportSupplierModel(name: '', createdAt: ''),
    );
    double allocated = 0.0;
    for (int i = 0; i < _costItems.length; i++) {
      if (excludeItemIndex != null && i == excludeItemIndex) continue;
      final c = _costItems[i];
      final itemSuppId = c['transport_supplier_id']?.toString() ?? c['supplier_id']?.toString();
      if (itemSuppId == supplierId) {
        final t = (c['truck_count'] as num?)?.toDouble() ??
            (c['quantity'] as num?)?.toDouble() ?? 0.0;
        allocated += t;
      }
    }
    return transSupplier.truckBalance - allocated;
  }

  void _addCostItem() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final exchangeRateCtrl = TextEditingController(text: '');
    final supplierSearchCtrl = TextEditingController();
    String? selectedSupplierId;
    String? selectedSupplierName;
    int? selectedExpenseAccountId;
    String? selectedExpenseAccountName;
    String? selectedExpenseAccountCode;
    String supplierCurrency = 'EGP';
    bool isMultiCurrencySupplier = false;
    List<String> supplierSupportedCurrencies = [];
    bool isFetchingRate = false;
    bool isLoadingCustodyBal = false;
    Map<String, dynamic>? selectedCustodyInfo;
    String? lastLoadedCustodyId;
    int? selectedCategoryId;

    List<TransportBatchModel> transportBatches = [];
    TransportBatchModel? selectedTransportBatch;
    bool isLoadingBatches = false;
    String? lastLoadedTransportId;

    String paymentSourceType = 'none';
    int? selectedPaymentSourceId;
    String selectedAllocationMethod = 'EQUAL';
    int? selectedTargetLineIndex;
    bool showAdvancedMethods = false;
    final notesCtrl = TextEditingController();
    CustodyExpensePoolSummary? custodyPoolSummary;
    bool isLoadingCustodyPool = false;
    bool isEngineerPercentageMode = false;
    final engineerPercentageCtrl = TextEditingController(text: '100');
    bool hasInitializedCustodyPool = false;
    DateTime? custodyFromDate;
    DateTime? custodyToDate;

    final categories = <int, String>{
      for (final c in _costCategories)
        if (c['id'] != null) c['id'] as int: (c['name'] ?? '').toString(),
    };

    String supplierType = 'station';
    final initialFilteredCategories =
        CostCategoryService.filterCategoriesBySupplierType(
      _costCategories,
      supplierType: supplierType,
    );
    selectedCategoryId =
        CostCategoryService.resolveSelectedCategoryIdForSupplierType(
      currentCategoryId: selectedCategoryId,
      filteredCategories: initialFilteredCategories,
      supplierType: supplierType,
    );
    if (selectedCategoryId != null && initialFilteredCategories.containsKey(selectedCategoryId)) {
      nameCtrl.text = initialFilteredCategories[selectedCategoryId]!;
    }

    final adminCategories = CostCategoryService.filterCategoriesBySupplierType(
      _costCategories,
      supplierType: 'admin',
    );
    if (adminCategories.isEmpty) {
      final defaultAdmin = _costCategories.firstWhere(
        (c) => (c['name']?.toString().contains('إدار') ?? false) ||
               (c['name']?.toString().contains('ادار') ?? false) ||
               c['supplier_type'] == 'admin',
        orElse: () => {},
      );
      if (defaultAdmin.isNotEmpty && defaultAdmin['id'] != null) {
        adminCategories[defaultAdmin['id'] as int] = defaultAdmin['name']?.toString() ?? 'مصاريف إدارية';
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void loadTransportBatches(String? suppId) async {
            if (suppId == null || suppId.isEmpty) return;
            final sId = int.tryParse(suppId);
            if (sId == null) return;
            lastLoadedTransportId = suppId;
            setDialogState(() => isLoadingBatches = true);
            try {
              final batches = await _getEffectiveTransportBatches(
                supplierId: sId,
                onlyAvailable: true,
              );
              if (ctx.mounted) {
                setDialogState(() {
                  transportBatches = batches.where((b) => b.availableTrucks > 0.0001).toList();
                  isLoadingBatches = false;
                  if (transportBatches.isNotEmpty) {
                    if (selectedTransportBatch == null || !transportBatches.any((b) => b.id == selectedTransportBatch!.id)) {
                      selectedTransportBatch = transportBatches.first;
                      if (qtyCtrl.text.trim().isEmpty) {
                        final defaultQty = selectedTransportBatch!.availableTrucks >= 1 ? 1.0 : selectedTransportBatch!.availableTrucks;
                        qtyCtrl.text = defaultQty % 1 == 0 ? defaultQty.toInt().toString() : defaultQty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
                      }
                      final currentQty = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;
                      final autoCost = currentQty * selectedTransportBatch!.costPerTruck;
                      priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                    } else {
                      final match = transportBatches.firstWhere((b) => b.id == selectedTransportBatch!.id);
                      selectedTransportBatch = match;
                    }
                  } else {
                    selectedTransportBatch = null;
                  }
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingBatches = false);
              }
            }
          }



          void loadCustodyDetails(String? cId) async {
            if (cId == null || cId.isEmpty) return;
            lastLoadedCustodyId = cId;
            setDialogState(() => isLoadingCustodyBal = true);
            try {
              final info = await fetchCustodyBalanceInfo(cId, currency: supplierCurrency);
              if (ctx.mounted) {
                setDialogState(() {
                  selectedCustodyInfo = info;
                  isLoadingCustodyBal = false;
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingCustodyBal = false);
              }
            }
          }

          void loadCustodyPoolData({bool forceUpdatePrice = false}) async {
            if (isLoadingCustodyPool) return;
            setDialogState(() => isLoadingCustodyPool = true);
            try {
              final currentOrdId = int.tryParse(_currentOrder?.id ?? widget.existingOrder?.id ?? '');
              final summary = await CustodyService().getCustodyExpensePoolSummary(
                excludePackingOrderId: currentOrdId,
                fromDate: custodyFromDate,
                toDate: custodyToDate,
              );
              if (ctx.mounted) {
                setDialogState(() {
                  custodyPoolSummary = summary;
                  isLoadingCustodyPool = false;
                  if (supplierType == 'engineer') {
                    final curAlloc = _costItems.where((c) {
                      final cat = (c['category']?.toString() ?? '').toLowerCase();
                      final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                      final name = (c['name']?.toString() ?? '').toLowerCase();
                      return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                    }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                    final effRem = (summary.remainingPool - curAlloc).clamp(0.0, double.infinity);
                    if (isEngineerPercentageMode) {
                      final pct = double.tryParse(engineerPercentageCtrl.text) ?? 100.0;
                      final calcAmt = effRem * (pct / 100.0);
                      priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                    } else if (forceUpdatePrice || priceCtrl.text.isEmpty || effRem > 0) {
                      priceCtrl.text = effRem > 0 ? effRem.toStringAsFixed(2) : '';
                    }
                  }
                });
              }
            } catch (_) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingCustodyPool = false);
              }
            }
          }

          final name = nameCtrl.text.trim();
          final isTransport = supplierType == 'transport' ||
              _transportSuppliers.any((ts) => ts.id.toString() == selectedSupplierId);
          final qty =
              double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final price =
              double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final rate = double.tryParse(
                  exchangeRateCtrl.text.trim().replaceAll(',', '.')) ??
              (supplierCurrency == 'EGP' ? 1.0 : 0.0);
          final totalInSupplierCurrency = isTransport ? price : (qty * price);
          final totalEgp = supplierCurrency == 'EGP'
              ? totalInSupplierCurrency
              : (rate > 0
                  ? CurrencyConversionService.instance
                      .toBase(totalInSupplierCurrency, supplierCurrency, rate)
                  : 0.0);

          Future<void> onCurrencyChanged(String newCur) async {
            if (newCur == supplierCurrency) return;
            setDialogState(() {
              supplierCurrency = newCur;
              selectedPaymentSourceId = null;
              if (newCur == 'EGP') {
                exchangeRateCtrl.text = '1.0';
                isFetchingRate = false;
              } else {
                isFetchingRate = true;
              }
            });

            if (newCur != 'EGP') {
              try {
                final r = await CurrencyConversionService.instance.getRate(newCur);
                setDialogState(() {
                  exchangeRateCtrl.text = r > 0 ? r.toStringAsFixed(4) : '';
                  isFetchingRate = false;
                });
              } catch (_) {
                setDialogState(() {
                  exchangeRateCtrl.text = '';
                  isFetchingRate = false;
                });
              }
            }
          }

          Future<void> refreshRate() async {
            if (supplierCurrency == 'EGP') {
              setDialogState(() => exchangeRateCtrl.text = '1.0');
              return;
            }
            setDialogState(() => isFetchingRate = true);
            try {
              CurrencyConversionService.instance.invalidateCache();
              final r = await CurrencyConversionService.instance.getRate(supplierCurrency);
              setDialogState(() {
                exchangeRateCtrl.text = r > 0 ? r.toStringAsFixed(4) : '';
                isFetchingRate = false;
              });
            } catch (_) {
              setDialogState(() => isFetchingRate = false);
            }
          }

          double availableBalance = 0;
          String sourceName = '';

          if (paymentSourceType == 'treasury' &&
              selectedPaymentSourceId != null) {
            final sIdStr = selectedPaymentSourceId.toString();
            final t = _treasuries.firstWhere(
                (e) => e['id']?.toString() == sIdStr,
                orElse: () => {});
            sourceName = t['name'] as String? ?? 'الخزينة المختارة';

            if (selectedCustodyInfo != null && selectedCustodyInfo!['custody_id']?.toString() == sIdStr) {
              availableBalance = (selectedCustodyInfo!['balance'] as num?)?.toDouble() ?? 0.0;
            } else if (_custodyBalancesMap.containsKey(sIdStr) && _custodyBalancesMap[sIdStr]!['balance'] != null) {
              availableBalance = (_custodyBalancesMap[sIdStr]!['balance'] as num).toDouble();
            } else if (t['live_balance'] != null) {
              availableBalance = (t['live_balance'] as num).toDouble();
            } else {
              final balances = t['treasury_balances'];
              if (balances is List) {
                final match = balances
                    .where((b) =>
                        (b['currency']?.toString() ?? 'EGP').toUpperCase() ==
                        supplierCurrency.toUpperCase())
                    .toList();
                if (match.isNotEmpty) {
                  availableBalance = (match.first['balance'] as num).toDouble();
                }
              }
            }
          } else if (paymentSourceType == 'bank' &&
              selectedPaymentSourceId != null) {
            final b = _bankAccounts.firstWhere(
                (e) => e['id']?.toString() == selectedPaymentSourceId.toString(),
                orElse: () => {});
            sourceName = '${b['name'] ?? ''} (${b['bank_name'] ?? ''})';
            availableBalance = (b['balance'] as num?)?.toDouble() ?? 0;
          }

          final isAdmin = supplierType == 'admin';
          final isEngineer = supplierType == 'engineer';

          final isInsufficientBalance = !isEngineer &&
              (paymentSourceType != 'none') &&
              (selectedPaymentSourceId != null) &&
              (totalInSupplierCurrency > availableBalance);
          if (isEngineer && selectedExpenseAccountId == null && _expenseAccounts.isNotEmpty) {
            final defaultEngAcc = _expenseAccounts.firstWhere(
              (a) => a['account_code'] == '31251',
              orElse: () => _expenseAccounts.first,
            );
            selectedExpenseAccountId = (defaultEngAcc['id'] as num?)?.toInt();
            selectedExpenseAccountName = defaultEngAcc['resolved_name']?.toString() ?? 'مصاريف مهندسين';
            selectedExpenseAccountCode = defaultEngAcc['account_code']?.toString() ?? '31251';
          }

          final isBatchQtyValid = !isTransport || selectedTransportBatch == null || (qty > 0 && qty <= (selectedTransportBatch!.availableTrucks + 0.0001));
          final canSubmit = name.isNotEmpty &&
              (isAdmin || isEngineer
                  ? price > 0
                  : (isTransport ? (price > 0 && qty > 0 && isBatchQtyValid) : (qty > 0 && price > 0))) &&
              (isAdmin || isEngineer || selectedSupplierId != null) &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' || isEngineer ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;
          final isDark = AppTheme.isDark(ctx);

          final employeeCustodies = _treasuries.where((t) {
            final type = t['type']?.toString().toLowerCase() ?? '';
            final tName = t['name']?.toString() ?? '';
            return type == 'employee' || tName.contains('عهدة') || tName.contains('مهندس');
          }).toList();
          final effectiveCustodies = employeeCustodies.isNotEmpty ? employeeCustodies : _treasuries;

          if (isEngineer) {
            selectedSupplierName = 'مجمع عهد الموظفين';
            paymentSourceType = 'none';
            selectedPaymentSourceId = null;
          }

          if (isEngineer && selectedSupplierId != null && !isLoadingCustodyBal && lastLoadedCustodyId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCustodyDetails(selectedSupplierId);
            });
          }

          if (isTransport && selectedSupplierId != null && !isLoadingBatches && lastLoadedTransportId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadTransportBatches(selectedSupplierId);
            });
          }

          if (isEngineer && !hasInitializedCustodyPool && !isLoadingCustodyPool) {
            hasInitializedCustodyPool = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCustodyPoolData();
            });
          }

          if (isTransport && selectedSupplierId != null && !isLoadingBatches && lastLoadedTransportId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadTransportBatches(selectedSupplierId);
            });
          }

          final filteredCategories =
              CostCategoryService.filterCategoriesBySupplierType(
            _costCategories,
            supplierType: supplierType,
          );

          void switchStandardSupplierType(String nextType) {
            setDialogState(() {
              supplierType = nextType;
              selectedSupplierId = null;
              selectedSupplierName = null;
              supplierSearchCtrl.clear();
              supplierCurrency = 'EGP';
              exchangeRateCtrl.text = '';
              final resolved = _resolveCategorySelectionForType(
                targetType: nextType,
                currentCategoryId: selectedCategoryId,
                currentName: nameCtrl.text,
                allCategories: categories,
              );
              selectedCategoryId = resolved.categoryId;
              if (resolved.updatedName != null) {
                nameCtrl.text = resolved.updatedName!;
              }
            });
          }

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            title: Text('إضافة بند تكلفة',
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: _inputDecoration('اسم البند'),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              avatar: Icon(Icons.people_outline,
                                  size: 14,
                                  color: supplierType == 'general'
                                      ? (isDark ? Colors.white : AppTheme.primary)
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('عام / خامات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'general',
                              selectedColor: isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFFBAE6FD),
                              onSelected: (val) {
                                if (val) switchStandardSupplierType('general');
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.local_shipping,
                                  size: 14,
                                  color: supplierType == 'transport'
                                      ? (isDark ? Colors.white : AppTheme.accent)
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد نقل 🚛',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'transport',
                              selectedColor: isDark ? AppTheme.accent.withAlpha(80) : const Color(0xFF99F6E4),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'transport';
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    final resolved =
                                        _resolveCategorySelectionForType(
                                      targetType: 'transport',
                                      currentCategoryId: selectedCategoryId,
                                      currentName: nameCtrl.text,
                                      allCategories: categories,
                                    );
                                    selectedCategoryId = resolved.categoryId;
                                    if (resolved.updatedName != null) {
                                      nameCtrl.text = resolved.updatedName!;
                                    }
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.factory_outlined,
                                  size: 14,
                                  color: supplierType == 'station'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد محطة 🏭',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'station',
                              selectedColor: const Color(0xFF059669).withAlpha(120),
                              onSelected: (val) {
                                if (val) switchStandardSupplierType('station');
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.assignment_outlined,
                                  size: 14,
                                  color: supplierType == 'deduction'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد تخصيمات 📋',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'deduction',
                              selectedColor: const Color(0xFF7C3AED).withAlpha(120),
                              onSelected: (val) {
                                if (val) {
                                  switchStandardSupplierType('deduction');
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.business_center_outlined,
                                  size: 14,
                                  color: supplierType == 'admin'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مصاريف إدارية 💼',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'admin',
                              selectedColor: const Color(0xFF0284C7).withAlpha(120),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'admin';
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    qtyCtrl.text = '1';
                                    final resolved =
                                        _resolveCategorySelectionForType(
                                      targetType: 'admin',
                                      currentCategoryId: selectedCategoryId,
                                      currentName: '',
                                      allCategories: categories,
                                    );
                                    selectedCategoryId = resolved.categoryId;
                                    nameCtrl.text = resolved.updatedName ??
                                        'مصاريف إدارية';
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.engineering_outlined,
                                  size: 14,
                                  color: supplierType == 'engineer'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مصاريف مهندسين 👷',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'engineer',
                              selectedColor: const Color(0xFFF59E0B).withAlpha(140),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'engineer';
                                    selectedSupplierId = null;
                                    selectedSupplierName = 'مجمع عهد الموظفين';
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    qtyCtrl.text = '1';
                                    paymentSourceType = 'none';
                                    selectedCategoryId = null;
                                    if (CostCategoryService
                                        .isAutoGeneratedItemName(
                                            nameCtrl.text, categories.values)) {
                                      nameCtrl.text = 'مصاريف مهندسين وإشراف';
                                    }
                                    if (custodyPoolSummary == null) {
                                      loadCustodyPoolData();
                                    } else {
                                      final curAlloc = _costItems.where((c) {
                                        final cat = (c['category']?.toString() ?? '').toLowerCase();
                                        final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                        final name = (c['name']?.toString() ?? '').toLowerCase();
                                        return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                      }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                                      final effRem = math.max(0.0, custodyPoolSummary!.remainingPool - curAlloc);
                                      if (isEngineerPercentageMode) {
                                        final pct = double.tryParse(engineerPercentageCtrl.text) ?? 100.0;
                                        final calcAmt = effRem * (pct / 100.0);
                                        priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                                      } else if (priceCtrl.text.isEmpty && effRem > 0) {
                                        priceCtrl.text = effRem.toStringAsFixed(2);
                                      }
                                    }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      if (isEngineer) ...[
                        const SizedBox(height: 14),
                        // 1. Custody Expense Pool Summary Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF132337) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? const Color(0xFFF59E0B).withAlpha(80) : const Color(0xFFF59E0B).withAlpha(120),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withAlpha(25),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.account_balance_wallet, color: Color(0xFFF59E0B), size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'مجمع مصروفات عهد الموظفين المتاحة للتحميل',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'تكلفة فعلية تم صرفها مسبقاً من العهد (وجبات، عمالة، انتقالات) ويتم تحميلها على التعبئة دون سحب مالي جديد',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isLoadingCustodyPool)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 18, color: Color(0xFFF59E0B)),
                                      tooltip: 'تحديث بيانات مجمع العهد',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => loadCustodyPoolData(),
                                    ),
                                ],
                              ),
                              _buildCustodyDateFilterBar(
                                context: ctx,
                                isDark: isDark,
                                fromDate: custodyFromDate,
                                toDate: custodyToDate,
                                onDatesChanged: (f, t) {
                                  setDialogState(() {
                                    custodyFromDate = f;
                                    custodyToDate = t;
                                  });
                                  loadCustodyPoolData(forceUpdatePrice: true);
                                },
                              ),
                              // Dynamic remaining balance calculation factoring in items already added in current order
                              Builder(
                                builder: (_) {
                                  final currentOrderAllocated = _costItems.where((c) {
                                    final cat = (c['category']?.toString() ?? '').toLowerCase();
                                    final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                    final name = (c['name']?.toString() ?? '').toLowerCase();
                                    return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                  }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                                  final effectiveAllocated = (custodyPoolSummary?.totalAllocated ?? 0.0) + currentOrderAllocated;
                                  final effectiveRemainingPool = (math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - currentOrderAllocated));

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'إجمالي المنصرف من العهد',
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.white70 : Colors.black54),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(custodyPoolSummary?.totalSpent ?? 0)} ج.م',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'المحمل سابقاً',
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.white70 : Colors.black54),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(effectiveAllocated)} ج.م',
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF6366F1),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                    ? const Color(0xFF059669).withAlpha(isDark ? 35 : 20)
                                                    : const Color(0xFFDC2626).withAlpha(isDark ? 35 : 20),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                      ? const Color(0xFF059669).withAlpha(80)
                                                      : const Color(0xFFDC2626).withAlpha(80),
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'المتبقي للتحميل',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFFDC2626),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(effectiveRemainingPool)} ج.م',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFFDC2626),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              if (custodyPoolSummary != null && custodyPoolSummary!.totalSpent > 0) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (custodyPoolSummary!.mealsSpent > 0)
                                      _poolCategoryPill('وجبات: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.mealsSpent)} ج.م', const Color(0xFFEA580C)),
                                    if (custodyPoolSummary!.laborSpent > 0)
                                      _poolCategoryPill('عمالة: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.laborSpent)} ج.م', const Color(0xFF2563EB)),
                                    if (custodyPoolSummary!.transportSpent > 0)
                                      _poolCategoryPill('انتقالات: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.transportSpent)} ج.م', const Color(0xFF059669)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Mode Selector: Cash Amount vs Percentage
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('مبلغ نقدي مباشر (ج.م)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                selected: !isEngineerPercentageMode,
                                selectedColor: const Color(0xFFF59E0B).withAlpha(isDark ? 70 : 160),
                                onSelected: (val) {
                                  if (val) {
                                    setDialogState(() {
                                      isEngineerPercentageMode = false;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('نسبة مئوية (%)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                selected: isEngineerPercentageMode,
                                selectedColor: const Color(0xFFF59E0B).withAlpha(isDark ? 70 : 160),
                                onSelected: (val) {
                                  if (val) {
                                    setDialogState(() {
                                      isEngineerPercentageMode = true;
                                      final pct = double.tryParse(engineerPercentageCtrl.text) ?? 100.0;
                                      final curAlloc = _costItems.where((c) {
                                        final cat = (c['category']?.toString() ?? '').toLowerCase();
                                        final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                        final name = (c['name']?.toString() ?? '').toLowerCase();
                                        return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                      }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                                      final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - curAlloc);
                                      final calcAmt = (poolRem * (pct / 100.0));
                                      priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 3. Inputs
                        if (isEngineerPercentageMode) ...[
                          TextField(
                            controller: engineerPercentageCtrl,
                            decoration: _inputDecoration('النسبة المئوية المراد تحميلها (%) *').copyWith(
                              prefixIcon: const Icon(Icons.percent, color: Color(0xFFF59E0B), size: 18),
                              helperText: 'يتم احتساب النسبة تلقائياً من رصيد المصروفات المتبقي للعهد',
                              helperStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                            ],
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 15,
                            ),
                            onChanged: (val) {
                              final pct = double.tryParse(val) ?? 0.0;
                              final curAlloc = _costItems.where((c) {
                                final cat = (c['category']?.toString() ?? '').toLowerCase();
                                final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                final name = (c['name']?.toString() ?? '').toLowerCase();
                                return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                              }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                              final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - curAlloc);
                              final calcAmt = (poolRem * (pct / 100.0));
                              priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                              setDialogState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [25, 50, 75, 100].map((pct) {
                              final isCurPct = engineerPercentageCtrl.text == pct.toString();
                              return ActionChip(
                                label: Text('$pct%', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                                backgroundColor: isCurPct ? const Color(0xFFF59E0B).withAlpha(120) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                onPressed: () {
                                  setDialogState(() {
                                    engineerPercentageCtrl.text = pct.toString();
                                    final curAlloc = _costItems.where((c) {
                                      final cat = (c['category']?.toString() ?? '').toLowerCase();
                                      final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                      final name = (c['name']?.toString() ?? '').toLowerCase();
                                      return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                    }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                                    final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - curAlloc);
                                    final calcAmt = (poolRem * (pct / 100.0));
                                    priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ] else ...[
                          TextField(
                            controller: priceCtrl,
                            decoration: _inputDecoration('المبلغ المراد تحميله على أمر التعبئة (ج.م) *').copyWith(
                              prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFFF59E0B), size: 18),
                              helperText: 'أدخل المبلغ بالجنيه ليتم خصمه توضيحياً من مجمع العهد',
                              helperStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                              ),
                              suffixIcon: Builder(
                                builder: (_) {
                                  final curAlloc = _costItems.where((c) {
                                    final cat = (c['category']?.toString() ?? '').toLowerCase();
                                    final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                    final name = (c['name']?.toString() ?? '').toLowerCase();
                                    return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                  }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                                  final effRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - curAlloc);
                                  return (custodyPoolSummary != null && effRem > 0)
                                      ? TextButton(
                                          child: const Text('كامل المتبقي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                                          onPressed: () {
                                            setDialogState(() {
                                              priceCtrl.text = effRem.toStringAsFixed(2);
                                            });
                                          },
                                        )
                                      : const SizedBox.shrink();
                                },
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                            ],
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 15,
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ],

                        // 4. Live Calculation & Pool Impact Preview
                        const SizedBox(height: 12),
                        Builder(
                          builder: (_) {
                            final inputVal = double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0.0;
                            final curAlloc = _costItems.where((c) {
                              final cat = (c['category']?.toString() ?? '').toLowerCase();
                              final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                              final name = (c['name']?.toString() ?? '').toLowerCase();
                              return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                            }).fold<double>(0.0, (sum, c) => sum + ((c['total_egp'] ?? c['total'] ?? c['expected_amount'] ?? 0) as num).toDouble());
                            final remPool = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - curAlloc);
                            final remAfter = remPool - inputVal;
                            final isExceeded = remAfter < -0.01;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isExceeded
                                    ? const Color(0xFFDC2626).withAlpha(15)
                                    : const Color(0xFF059669).withAlpha(15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isExceeded ? const Color(0xFFDC2626).withAlpha(80) : const Color(0xFF059669).withAlpha(80),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isExceeded ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                    size: 20,
                                    color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'التكلفة المحملة على أمر التعبئة: ${NumberFormat('#,##0.##').format(inputVal)} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          isExceeded
                                              ? 'تنبيه: المبلغ يتجاوز المتبقي بمقدار ${NumberFormat('#,##0.##').format(-remAfter)} ج.م'
                                              : 'المتبقي في مجمع العهد بعد هذا الأمر: ${NumberFormat('#,##0.##').format(remAfter.clamp(0.0, double.infinity))} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // 5. Statement / Notes for Engineer Expenses
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesCtrl,
                          maxLines: 2,
                          decoration: _inputDecoration('البيان / تفاصيل وملاحظات المصروف').copyWith(
                            prefixIcon: const Icon(Icons.description_outlined, color: Color(0xFFF59E0B), size: 18),
                            hintText: 'مثل: تحميل نسبة من وجبات وانتقالات مهندسي المحطة على هذا الأمر...',
                            helperText: 'بيان المصروف المحمل يظهر في كشف التكاليف التفصيلي لأمر التعبئة',
                            helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                            ),
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 14,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ] else if (isAdmin) ...[
                        if (adminCategories.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          CostItemCategoryDropdown(
                            keyPrefix: 'admin_cost_cat',
                            supplierType: supplierType,
                            filteredCategories: adminCategories,
                            selectedCategoryId:
                                adminCategories.containsKey(selectedCategoryId)
                                    ? selectedCategoryId
                                    : adminCategories.keys.first,
                            decoration: _inputDecoration(
                                    'تصنيف بند المصاريف الإدارية')
                                .copyWith(
                              prefixIcon: const Icon(
                                  Icons.business_center_outlined,
                                  color: Color(0xFF0284C7),
                                  size: 18),
                            ),
                            isDark: isDark,
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  selectedCategoryId = v;
                                  final catName = adminCategories[v] ?? '';
                                  if (catName.isNotEmpty) {
                                    nameCtrl.text = catName;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: priceCtrl,
                          decoration: _inputDecoration('قيمة المصروف *').copyWith(
                            prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF0284C7), size: 18),
                            helperText: 'أدخل قيمة المصروف بالجنيه المصري (مثال: 1500 أو 2500.50)',
                            helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                          ],
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ] else ...[
                        if (supplierType != 'transport') ...[
                          const SizedBox(height: 14),
                          CostItemCategoryDropdown(
                            keyPrefix: 'add_cost_cat',
                            supplierType: supplierType,
                            filteredCategories: filteredCategories,
                            selectedCategoryId: selectedCategoryId,
                            decoration: _inputDecoration('تصنيف البند'),
                            isDark: isDark,
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  final previousCatName =
                                      filteredCategories[selectedCategoryId] ??
                                          categories[selectedCategoryId] ??
                                          '';
                                  selectedCategoryId = v;
                                  final newType =
                                      _detectSupplierTypeForCategory(v);
                                  if (newType != supplierType) {
                                    supplierType = newType;
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text =
                                        (newType == 'transport' ||
                                                newType == 'admin')
                                            ? '1.0'
                                            : '';
                                  }
                                  final catName = filteredCategories[v] ??
                                      categories[v] ??
                                      '';
                                  final currentName = nameCtrl.text.trim();
                                  if (newType == 'admin') {
                                    nameCtrl.text = 'مصاريف إدارية';
                                    qtyCtrl.text = '1';
                                  } else if (currentName == previousCatName ||
                                      CostCategoryService
                                          .isAutoGeneratedItemName(
                                              currentName, categories.values)) {
                                    nameCtrl.text = catName;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      const SizedBox(height: 14),
                      TypeAheadField<String>(
                        key: ValueKey('${supplierType}_$selectedSupplierId'),
                        controller: supplierSearchCtrl,
                        autoFlipDirection: true,
                        hideOnEmpty: false,
                        hideOnError: true,
                        suggestionsCallback: (query) async {
                          final q = query.trim().toLowerCase();
                          if (supplierType == 'transport') {
                            if (q.isEmpty) {
                              return _transportSuppliers
                                  .map((s) => s.id!.toString())
                                  .toList();
                            }
                            return _transportSuppliers
                                .where((s) =>
                                    s.name.toLowerCase().contains(q) ||
                                    s.displayName.toLowerCase().contains(q) ||
                                    s.code.toLowerCase().contains(q) ||
                                    s.phone.toLowerCase().contains(q))
                                .map((s) => s.id!.toString())
                                .toList();
                          } else if (supplierType == 'station') {
                            final stationMatches = _suppliers.where((s) {
                              final isStation = s.supplierType == 'station' ||
                                  s.isStationSupplier ||
                                  (int.tryParse(s.supplierCode) != null &&
                                      int.parse(s.supplierCode) >= 85000 &&
                                      int.parse(s.supplierCode) <= 89999);
                              if (!isStation) return false;
                              if (q.isEmpty) return true;
                              return s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q) ||
                                  s.phone.toLowerCase().contains(q) ||
                                  s.categories.any((c) => c.toLowerCase().contains(q));
                            }).toList();

                            if (q.isNotEmpty && stationMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if ((s.supplierType == 'station' || s.isStationSupplier) &&
                                      !stationMatches.any((m) => m.id == s.id)) {
                                    stationMatches.add(s);
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }
                            return stationMatches.map((s) => s.id!).toList();
                          } else if (supplierType == 'deduction') {
                            final deductionMatches = _suppliers.where((s) {
                              final isDeduction = s.supplierType == 'deduction' ||
                                  s.isDeductionSupplier ||
                                  (int.tryParse(s.supplierCode) != null &&
                                      int.parse(s.supplierCode) >= 40000 &&
                                      int.parse(s.supplierCode) <= 49999);
                              if (!isDeduction) return false;
                              if (q.isEmpty) return true;
                              return s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q) ||
                                  s.phone.toLowerCase().contains(q) ||
                                  s.categories.any((c) => c.toLowerCase().contains(q));
                            }).toList();

                            if (q.isNotEmpty && deductionMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if ((s.supplierType == 'deduction' || s.isDeductionSupplier) &&
                                      !deductionMatches.any((m) => m.id == s.id)) {
                                    deductionMatches.add(s);
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }
                            return deductionMatches.map((s) => s.id!).toList();
                          } else {
                            final inMemoryMatches = _suppliers
                                .where((s) {
                                  final isSpecialized = s.supplierType == 'station' ||
                                      s.supplierType == 'deduction' ||
                                      s.isStationSupplier ||
                                      s.isDeductionSupplier;
                                  if (isSpecialized) return false;
                                  if (q.isEmpty) return true;
                                  return s.name.toLowerCase().contains(q) ||
                                      s.displayName.toLowerCase().contains(q) ||
                                      s.supplierCode.toLowerCase().contains(q) ||
                                      s.phone.toLowerCase().contains(q) ||
                                      s.supplierType.toLowerCase().contains(q) ||
                                      s.supplierTypeLabel.toLowerCase().contains(q);
                                })
                                .toList();

                            if (q.isNotEmpty && inMemoryMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if (!s.isStationSupplier && !s.isDeductionSupplier && s.supplierType != 'station' && s.supplierType != 'deduction') {
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                    if (!inMemoryMatches.any((m) => m.id == s.id)) {
                                      inMemoryMatches.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }

                            return inMemoryMatches.map((s) => s.id!).toList();
                          }
                        },
                        itemBuilder: (context, supplierId) {
                          if (supplierType == 'transport') {
                            final s = _transportSuppliers.firstWhere(
                                (s) => s.id.toString() == supplierId,
                                orElse: () => const TransportSupplierModel(
                                    name: '', createdAt: ''));
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.local_shipping,
                                  color: AppTheme.accent, size: 18),
                              title: Text(s.displayName,
                                  style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 13)),
                              subtitle: s.phone.isNotEmpty
                                  ? Text(s.phone,
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'))
                                  : null,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else if (supplierType == 'station') {
                            final s = _suppliers.firstWhere(
                              (s) => s.id == supplierId,
                              orElse: () => const SupplierModel(
                                supplierCode: '',
                                name: '',
                              ),
                            );
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.factory_rounded,
                                  color: Color(0xFF059669), size: 20),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFF059669).withAlpha(80)),
                                    ),
                                    child: const Text('مورد محطة 🏭',
                                        style: TextStyle(
                                            color: Color(0xFF059669),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                ],
                              ),
                              subtitle: s.categories.isNotEmpty
                                  ? Text(s.categories.join(' • '),
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : (s.phone.isNotEmpty
                                      ? Text(s.phone,
                                          style: TextStyle(
                                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                                              fontSize: 11,
                                              fontFamily: 'Cairo'))
                                      : null),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else if (supplierType == 'deduction') {
                            final s = _suppliers.firstWhere(
                              (s) => s.id == supplierId,
                              orElse: () => const SupplierModel(
                                supplierCode: '',
                                name: '',
                              ),
                            );
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.assignment_rounded,
                                  color: Color(0xFF7C3AED), size: 20),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFF7C3AED).withAlpha(80)),
                                    ),
                                    child: const Text('مورد تخصيمات 📋',
                                        style: TextStyle(
                                            color: Color(0xFF7C3AED),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                ],
                              ),
                              subtitle: s.categories.isNotEmpty
                                  ? Text(s.categories.join(' • '),
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : (s.phone.isNotEmpty
                                      ? Text(s.phone,
                                          style: TextStyle(
                                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                                              fontSize: 11,
                                              fontFamily: 'Cairo'))
                                      : null),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            final isMulti = s.supportsMultiCurrency;
                            final currencyDisplay = isMulti
                                ? 'متعدد (${s.supportedCurrencies.join('/')})'
                                : s.currency;
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: s.isSharedSupplier
                                          ? AppTheme.primary.withAlpha(35)
                                          : AppTheme.accent.withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(s.supplierTypeLabel,
                                        style: TextStyle(
                                            color: s.isSharedSupplier
                                                ? AppTheme.primary
                                                : (isDark ? Colors.white70 : const Color(0xFF1E293B)),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isMulti
                                          ? AppTheme.cyan.withAlpha(30)
                                          : (isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0)),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isMulti
                                            ? AppTheme.cyan.withAlpha(80)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Text(
                                      currencyDisplay,
                                      style: TextStyle(
                                          color: isMulti
                                              ? (isDark ? AppTheme.cyan : const Color(0xFF0369A1))
                                              : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        onSelected: (supplierId) async {
                          if (supplierType == 'transport') {
                            final s = _transportSuppliers.firstWhere(
                                (s) => s.id.toString() == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id?.toString();
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = [];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;

                              selectedTransportBatch = null;
                              lastLoadedTransportId = null;

                              // Auto-fill cost item name if empty or generic
                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty ||
                                  currentName.startsWith('مصاريف نقل') ||
                                  currentName == 'نقل' ||
                                  currentName == 'نقل بضاعة') {
                                nameCtrl.text = s.name.isNotEmpty
                                    ? 'مصاريف نقل - ${s.name}'
                                    : 'نقل بضاعة';
                              }
                            });
                            loadTransportBatches(s.id?.toString());
                          } else if (supplierType == 'station') {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = ['EGP'];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;

                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty) {
                                nameCtrl.text = 'خدمات محطة - ${s.name}';
                              }
                            });
                          } else if (supplierType == 'deduction') {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = ['EGP'];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;

                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty) {
                                nameCtrl.text = 'تخصيمات - ${s.name}';
                              }
                            });
                          } else {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            final isMulti = s.supportsMultiCurrency;
                            final supported = isMulti
                                ? (s.supportedCurrencies.isNotEmpty
                                    ? s.supportedCurrencies
                                    : ['EGP', 'USD', 'EUR'])
                                : [((s.currency.isNotEmpty && s.currency != 'MULTI')
                                    ? s.currency
                                    : 'EGP')];
                            final initialCur = isMulti
                                ? (s.packagingCurrency.isNotEmpty &&
                                        supported.contains(s.packagingCurrency)
                                    ? s.packagingCurrency
                                    : (supported.contains('EGP')
                                        ? 'EGP'
                                        : supported.first))
                                : supported.first;

                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              isMultiCurrencySupplier = isMulti;
                              supplierSupportedCurrencies = supported;
                              supplierCurrency = initialCur;
                              selectedPaymentSourceId = null;
                              if (supplierCurrency == 'EGP') {
                                exchangeRateCtrl.text = '1.0';
                                isFetchingRate = false;
                              } else {
                                isFetchingRate = true;
                              }
                            });

                            if (supplierCurrency != 'EGP') {
                              try {
                                final r = await CurrencyConversionService
                                    .instance
                                    .getRate(supplierCurrency);
                                setDialogState(() {
                                  exchangeRateCtrl.text =
                                      r > 0 ? r.toStringAsFixed(4) : '';
                                  isFetchingRate = false;
                                });
                              } catch (_) {
                                setDialogState(() {
                                  exchangeRateCtrl.text = '';
                                  isFetchingRate = false;
                                });
                              }
                            }
                          }
                        },
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: _inputDecoration(
                                supplierType == 'transport'
                                    ? 'مقاول النقل (إجباري) - بحث بالاسم أو الكود'
                                    : (supplierType == 'station'
                                        ? 'مورد المحطة (إجباري) - بحث بالاسم أو الكود أو الخدمة'
                                        : (supplierType == 'deduction'
                                            ? 'مورد التخصيمات (إجباري) - بحث بالاسم أو الكود أو نوع التخصيم'
                                            : 'المورد (إجباري) - بحث بالاسم أو الكود'))),
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                          );
                        },
                      ),
                      if (selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: supplierType == 'transport'
                              ? Builder(
                                  builder: (ctx) {
                                    final transSupplier = _transportSuppliers.firstWhere(
                                      (s) => s.id.toString() == selectedSupplierId,
                                      orElse: () => const TransportSupplierModel(
                                          name: '', createdAt: ''),
                                    );
                                    final bal = transSupplier.balance;
                                    final isCredit = bal > 0;
                                    final isDebit = bal < 0;
                                    final balColor = isCredit
                                        ? AppTheme.warning
                                        : (isDebit ? AppTheme.accent : AppTheme.success);
                                    final balLabel = isCredit
                                        ? 'مستحق له (دائن)'
                                        : (isDebit ? 'مسدد مقدماً (مدين)' : 'خالص (لا يوجد مديونية)');

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: isDark ? AppTheme.accent.withAlpha(80) : const Color(0xFFCBD5E1)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.local_shipping,
                                                  color: AppTheme.accent, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'مقاول النقل: ${transSupplier.displayName}',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.white : Colors.black,
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedSupplierId = null;
                                                    selectedSupplierName = null;
                                                    supplierSearchCtrl.clear();
                                                    supplierCurrency = 'EGP';
                                                    exchangeRateCtrl.text = '';
                                                  });
                                                },
                                                child: const Icon(Icons.close,
                                                    color: AppTheme.danger, size: 16),
                                              ),
                                            ],
                                          ),
                                          Divider(
                                              color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 14),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.account_balance_wallet_outlined,
                                                      color: AppTheme.textSecondary,
                                                      size: 14),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'الرصيد المالي الحالي:',
                                                    style: TextStyle(
                                                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                      fontWeight: FontWeight.bold,
                                                      fontFamily: 'Cairo',
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: balColor.withAlpha(25),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: balColor.withAlpha(80)),
                                                ),
                                                child: Text(
                                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                                  style: TextStyle(
                                                    color: balColor,
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Builder(
                                            builder: (_) {
                                              final effTruckBalance = _getRemainingTruckBalance(selectedSupplierId);

                                              return Column(
                                                children: [
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.local_shipping_outlined,
                                                              color: Color(0xFF00B4D8),
                                                              size: 14),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            'مخزون النقلات المتاحة:',
                                                            style: TextStyle(
                                                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                              fontWeight: FontWeight.bold,
                                                              fontFamily: 'Cairo',
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: (effTruckBalance > 0
                                                                  ? AppTheme.success
                                                                  : (effTruckBalance < 0
                                                                      ? AppTheme.danger
                                                                      : AppTheme.textSecondary))
                                                              .withAlpha(25),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(
                                                              color: (effTruckBalance > 0
                                                                      ? AppTheme.success
                                                                      : (effTruckBalance < 0
                                                                          ? AppTheme.danger
                                                                          : AppTheme.textSecondary))
                                                                  .withAlpha(80)),
                                                        ),
                                                        child: Text(
                                                          '${effTruckBalance % 1 == 0 ? effTruckBalance.toInt() : effTruckBalance.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                                                          style: TextStyle(
                                                            color: effTruckBalance > 0
                                                                ? AppTheme.success
                                                                : (effTruckBalance < 0
                                                                    ? AppTheme.danger
                                                                    : (isDark ? Colors.white70 : Colors.black87)),
                                                            fontFamily: 'Cairo',
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (effTruckBalance <= 0) ...[
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.warning.withAlpha(20),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(
                                                            color: AppTheme.warning.withAlpha(60)),
                                                      ),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.info_outline,
                                                              color: AppTheme.warning, size: 14),
                                                          SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              'ملاحظة: لا يوجد رصيد نقلات متاح مسبقاً. سيتم تسجيل استهلاك نقلة وتحميلها على أمر التعبئة دون ازدواج مالي.',
                                                              style: TextStyle(
                                                                color: AppTheme.warning,
                                                                fontFamily: 'Cairo',
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                           _buildTransportBatchSection(
                                             isDark: isDark,
                                             isLoadingBatches: isLoadingBatches,
                                             batches: transportBatches,
                                             selectedBatch: selectedTransportBatch,
                                             onBatchChanged: (newB) {
                                               setDialogState(() {
                                                 selectedTransportBatch = newB;
                                                 if (newB != null) {
                                                   final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;
                                                   final autoCost = q * newB.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                             onSelectQuickQty: (q) {
                                               setDialogState(() {
                                                 qtyCtrl.text = q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
                                                 if (selectedTransportBatch != null) {
                                                   final autoCost = q * selectedTransportBatch!.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                           ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : supplierType == 'station'
                                  ? Builder(
                                      builder: (ctx) {
                                        final s = _suppliers.firstWhere(
                                          (sup) => sup.id == selectedSupplierId,
                                          orElse: () => SupplierModel(name: '', supplierCode: ''),
                                        );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF059669).withAlpha(80)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.factory_rounded, color: Color(0xFF059669), size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('مورد المحطة: ${s.displayName}',
                                                        style: TextStyle(
                                                            color: isDark ? Colors.white : Colors.black,
                                                            fontWeight: FontWeight.bold,
                                                            fontFamily: 'Cairo',
                                                            fontSize: 13)),
                                                    if (s.categories.isNotEmpty) ...[
                                                      Builder(
                                                        builder: (_) {
                                                          // Filter to show only the selected category
                                                          final selectedCatName = categories[selectedCategoryId] ?? '';
                                                          final matchingCats = s.categories.where((c) =>
                                                              c.trim().toLowerCase() == selectedCatName.trim().toLowerCase() ||
                                                              c.trim().toLowerCase().contains(selectedCatName.trim().toLowerCase()) ||
                                                              selectedCatName.trim().toLowerCase().contains(c.trim().toLowerCase())
                                                          ).toList();
                                                          final displayCats = matchingCats.isNotEmpty ? matchingCats : s.categories;
                                                          final isFiltered = matchingCats.isNotEmpty && matchingCats.length < s.categories.length;
                                                          return Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      isFiltered
                                                                          ? 'الخدمة المحددة: ${displayCats.join(' • ')}'
                                                                          : 'الخدمات: ${displayCats.join(' • ')}',
                                                                      style: TextStyle(
                                                                        color: isFiltered ? const Color(0xFF059669) : const Color(0xFF059669),
                                                                        fontSize: 11,
                                                                        fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                                                                        fontFamily: 'Cairo',
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (isFiltered)
                                                                    Container(
                                                                      margin: const EdgeInsets.only(right: 4),
                                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0xFF059669).withAlpha(20),
                                                                        borderRadius: BorderRadius.circular(4),
                                                                        border: Border.all(color: const Color(0xFF059669).withAlpha(60)),
                                                                      ),
                                                                      child: Text(
                                                                        '+${s.categories.length - matchingCats.length} أخرى',
                                                                        style: const TextStyle(
                                                                          color: Color(0xFF059669),
                                                                          fontSize: 9,
                                                                          fontWeight: FontWeight.bold,
                                                                          fontFamily: 'Cairo',
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ],
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedSupplierId = null;
                                                    selectedSupplierName = null;
                                                    supplierSearchCtrl.clear();
                                                    supplierCurrency = 'EGP';
                                                    exchangeRateCtrl.text = '';
                                                  });
                                                },
                                                child: const Icon(Icons.close, color: AppTheme.danger, size: 16),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    )
                                  : supplierType == 'deduction'
                                      ? Builder(
                                          builder: (ctx) {
                                            final s = _suppliers.firstWhere(
                                              (sup) => sup.id == selectedSupplierId,
                                              orElse: () => SupplierModel(name: '', supplierCode: ''),
                                            );
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF0F2338) : const Color(0xFFFAF5FF),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.assignment_rounded, color: Color(0xFF7C3AED), size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('مورد التخصيمات: ${s.displayName}',
                                                            style: TextStyle(
                                                                color: isDark ? Colors.white : Colors.black,
                                                                fontWeight: FontWeight.bold,
                                                                fontFamily: 'Cairo',
                                                                fontSize: 13)),
                                                        if (s.categories.isNotEmpty) ...[
                                                          Builder(
                                                            builder: (_) {
                                                              // Filter to show only the selected category
                                                              final selectedCatName = categories[selectedCategoryId] ?? '';
                                                              final matchingCats = s.categories.where((c) =>
                                                                  c.trim().toLowerCase() == selectedCatName.trim().toLowerCase() ||
                                                                  c.trim().toLowerCase().contains(selectedCatName.trim().toLowerCase()) ||
                                                                  selectedCatName.trim().toLowerCase().contains(c.trim().toLowerCase())
                                                              ).toList();
                                                              final displayCats = matchingCats.isNotEmpty ? matchingCats : s.categories;
                                                              final isFiltered = matchingCats.isNotEmpty && matchingCats.length < s.categories.length;
                                                              return Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Row(
                                                                    children: [
                                                                      Expanded(
                                                                        child: Text(
                                                                          isFiltered
                                                                              ? 'البند المحدد: ${displayCats.join(' • ')}'
                                                                              : 'بنود التخصيم: ${displayCats.join(' • ')}',
                                                                          style: TextStyle(
                                                                            color: const Color(0xFF7C3AED),
                                                                            fontSize: 11,
                                                                            fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                                                                            fontFamily: 'Cairo',
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      if (isFiltered)
                                                                        Container(
                                                                          margin: const EdgeInsets.only(right: 4),
                                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                          decoration: BoxDecoration(
                                                                            color: const Color(0xFF7C3AED).withAlpha(20),
                                                                            borderRadius: BorderRadius.circular(4),
                                                                            border: Border.all(color: const Color(0xFF7C3AED).withAlpha(60)),
                                                                          ),
                                                                          child: Text(
                                                                            '+${s.categories.length - matchingCats.length} أخرى',
                                                                            style: const TextStyle(
                                                                              color: Color(0xFF7C3AED),
                                                                              fontSize: 9,
                                                                              fontWeight: FontWeight.bold,
                                                                              fontFamily: 'Cairo',
                                                                            ),
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        selectedSupplierId = null;
                                                        selectedSupplierName = null;
                                                        supplierSearchCtrl.clear();
                                                        supplierCurrency = 'EGP';
                                                        exchangeRateCtrl.text = '';
                                                      });
                                                    },
                                                    child: const Icon(Icons.close, color: AppTheme.danger, size: 16),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        )
                                      : Row(
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: AppTheme.success, size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'تم اختيار: ${_suppliers.firstWhere((s) => s.id == selectedSupplierId, orElse: () => SupplierModel(name: '', supplierCode: '')).displayName}',
                                                style: const TextStyle(
                                                    color: AppTheme.success,
                                                    fontSize: 11,
                                                    fontFamily: 'Cairo'),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                setDialogState(() {
                                                  selectedSupplierId = null;
                                                  selectedSupplierName = null;
                                                  supplierSearchCtrl.clear();
                                                  supplierCurrency = 'EGP';
                                                  isMultiCurrencySupplier = false;
                                                  supplierSupportedCurrencies = [];
                                                  exchangeRateCtrl.text = '';
                                                  isFetchingRate = false;
                                                });
                                              },
                                              child: const Icon(Icons.close,
                                                  color: AppTheme.danger, size: 14),
                                            ),
                                          ],
                                        ),
                        ),
                      if (selectedSupplierId != null && supplierType != 'transport') ...[
                        if (isMultiCurrencySupplier) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: supplierSupportedCurrencies.contains(supplierCurrency)
                                ? supplierCurrency
                                : (supplierSupportedCurrencies.isNotEmpty
                                    ? supplierSupportedCurrencies.first
                                    : 'EGP'),
                            dropdownColor: isDark ? const Color(0xFF0F2338) : Colors.white,
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                            decoration: _inputDecoration('عملة التعامل للبند *')
                                .copyWith(
                              prefixIcon: const Icon(Icons.currency_exchange,
                                  color: AppTheme.primary, size: 18),
                            ),
                            items: supplierSupportedCurrencies.map((cur) {
                              final sym = SupplierModel.getCurrencySymbol(cur);
                              return DropdownMenuItem<String>(
                                value: cur,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(cur,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo')),
                                    const SizedBox(width: 8),
                                    Text('($sym)',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppTheme.textSecondary : Colors.black54,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo')),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (newCur) {
                              if (newCur != null) {
                                onCurrencyChanged(newCur);
                              }
                            },
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isDark ? AppTheme.primary.withAlpha(60) : const Color(0xFF93C5FD)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'مورد متعدد العملات — العملة المختارة: $supplierCurrency (${SupplierModel.getCurrencySymbol(supplierCurrency)})',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                      fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFF93C5FD)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline,
                                    size: 16, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'عملة المورد: $supplierCurrency (${SupplierModel.getCurrencySymbol(supplierCurrency)})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withAlpha(40),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    SupplierModel.getCurrencySymbol(supplierCurrency),
                                    style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (supplierCurrency != 'EGP') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: exchangeRateCtrl,
                            decoration: _inputDecoration(
                                    'سعر الصرف ($supplierCurrency → ج.م) *')
                                .copyWith(
                              prefixIcon: const Icon(Icons.trending_up,
                                  color: AppTheme.accent, size: 18),
                              suffixIcon: isFetchingRate
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.primary),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.sync,
                                          color: AppTheme.primary, size: 18),
                                      tooltip: 'تحديث سعر الصرف الحي',
                                      onPressed: refreshRate,
                                    ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*$'))
                            ],
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 15),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          if (rate > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 6),
                              child: Text(
                                'السعر الفوري: 1 $supplierCurrency = ${rate.toStringAsFixed(4)} ج.م',
                                style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'عدد النقلات المسحوبة من الدفعة (مثال: 0.5، 1، 1.5) *'
                                    : 'الكمية')
                            .copyWith(
                          helperText: isTransport
                              ? (selectedTransportBatch != null
                                  ? 'تكلفة النقلة بالدفعة: ${selectedTransportBatch!.formattedCostPerTruck} ج.م (المتاح: ${selectedTransportBatch!.formattedAvailableTrucks} نقلة)'
                                  : 'تُخصم من مخزون نقلات المورد (يدعم 0.5، 1.5 نقلة)')
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) {
                          if (isTransport && selectedTransportBatch != null) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            if (q > 0) {
                              final autoCost = q * selectedTransportBatch!.costPerTruck;
                              priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                            }
                          }
                          setDialogState(() {});
                        },
                      ),
                      if (isTransport && selectedTransportBatch != null) ...[
                        const SizedBox(height: 6),
                        Builder(
                          builder: (_) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            final isOver = q > (selectedTransportBatch!.availableTrucks + 0.0001);
                            final rem = (selectedTransportBatch!.availableTrucks - q).clamp(0.0, double.infinity);
                            if (isOver) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.danger.withAlpha(80)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'تنبيه: الكمية المطلوبة ($q نقلة) تتجاوز الرصيد المتاح في هذه الدفعة (${selectedTransportBatch!.formattedAvailableTrucks} نقلة)!',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.success.withAlpha(60)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'الحسبة: $q نقلة × ${selectedTransportBatch!.formattedCostPerTruck} ج.م = ${(q * selectedTransportBatch!.costPerTruck).toStringAsFixed(2)} ج.م | المتبقي في الدفعة: ${rem % 1 == 0 ? rem.toInt() : rem.toStringAsFixed(2)} نقلة',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: priceCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'تكلفة البند (إجمالي تكلفة النقل بالجنيه) *'
                                    : 'سعر الوحدة (${SupplierModel.getCurrencySymbol(supplierCurrency)}) *')
                            .copyWith(
                          helperText: isTransport
                              ? 'التكلفة المباشرة المضافة على أمر التعبئة (مستقلة عن عدد النقلات)'
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.success : const Color(0xFF059669)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (isInsufficientBalance) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withAlpha(35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.danger.withAlpha(90)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppTheme.danger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'تنبيه: المبلغ الإجمالي للبند (${totalInSupplierCurrency.toStringAsFixed(2)} $supplierCurrency) أكبر من الرصيد المتوفر في $sourceName (${availableBalance.toStringAsFixed(2)} $supplierCurrency)',
                                  style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo'),
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (selectedSupplierId != null &&
                          supplierCurrency != 'EGP') ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: isDark ? AppTheme.info.withAlpha(60) : const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                'المبلغ بالعملة الأصلية ($supplierCurrency)',
                                '${totalInSupplierCurrency.toStringAsFixed(2)} ${SupplierModel.getCurrencySymbol(supplierCurrency)}',
                                valueColor: AppTheme.info,
                              ),
                              Divider(
                                  color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 12),
                              _infoRow(
                                'المعادل بالجنيه المصري (EGP)',
                                '${totalEgp.toStringAsFixed(2)} ج.م',
                                valueColor: AppTheme.accent,
                              ),
                              if (rate > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'سعر الصرف المطبق:',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    Text(
                                      '1 $supplierCurrency = ${rate.toStringAsFixed(4)} ج.م',
                                      style: const TextStyle(
                                        color: AppTheme.success,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (selectedSupplierId != null &&
                          supplierCurrency == 'EGP' &&
                          (isTransport ? (price > 0) : (qty > 0 && price > 0))) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                isTransport ? 'تكلفة النقل المضافة لأمر التعبئة' : 'إجمالي البند',
                                '${totalEgp.toStringAsFixed(2)} ج.م',
                                valueColor: AppTheme.accent,
                              ),
                              if (isTransport && qty > 0) ...[
                                const SizedBox(height: 4),
                                _infoRow(
                                  'النقلات المستهلكة من الرصيد',
                                  '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                                  valueColor: const Color(0xFF00B4D8),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                    if (!isAdmin && !isEngineer) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: _inputDecoration('البيان / تفاصيل وملاحظات البند').copyWith(
                          prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.primary, size: 18),
                          hintText: 'اكتب بيان أو تفاصيل إضافية للبند المحاسبي (اختياري)...',
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                    const SizedBox(height: 14),
                      _buildAllocationMethodPicker(
                        selectedCode: selectedAllocationMethod,
                        showAdvanced: showAdvancedMethods,
                        onToggleAdvanced: () => setDialogState(
                            () => showAdvancedMethods = !showAdvancedMethods),
                        onChanged: (code) => setDialogState(() {
                          selectedAllocationMethod = code;
                          if (code != 'MANUAL') {
                            selectedTargetLineIndex = null;
                          } else if (selectedTargetLineIndex == null && _lotEntries.isNotEmpty) {
                            selectedTargetLineIndex = 0;
                          }
                        }),
                      ),
                      if (selectedAllocationMethod == 'MANUAL') ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: selectedTargetLineIndex,
                          decoration: _inputDecoration('تحميل على محصول / مركز تكلفة محدد'),
                          dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: [
                            for (int li = 0; li < _lotEntries.length; li++)
                              DropdownMenuItem<int>(
                                value: li,
                                child: Text(
                                  'خط ${_lotEntries[li].lot?.productName ?? 'محصول #${li + 1}'}',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedTargetLineIndex = v),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () {
                        final isAdmin = supplierType == 'admin';
                        final isEngineer = supplierType == 'engineer';
                        final rate = double.tryParse(exchangeRateCtrl.text
                                .trim()
                                .replaceAll(',', '.')) ??
                            (supplierCurrency == 'EGP' ? 1.0 : 0.0);
                        final isTransport = supplierType == 'transport' ||
                            _transportSuppliers.any((ts) => ts.id.toString() == selectedSupplierId);
                        final totalInSupplierCurrency = (isTransport || isAdmin || isEngineer) ? price : (qty * price);
                        final totalInEgp = (isTransport || isAdmin || isEngineer)
                            ? price
                            : (supplierCurrency == 'EGP'
                                ? totalInSupplierCurrency
                                : (rate > 0
                                    ? CurrencyConversionService.instance
                                        .toBase(totalInSupplierCurrency, supplierCurrency, rate)
                                    : 0.0));
                        int? transportCatId;
                        if (isTransport) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('نقل') || cName.contains('لوجستيك') || cName.contains('logistics')) {
                              transportCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        int? adminCatId;
                        if (isAdmin) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('إدار') || cName.contains('ادار') || c['supplier_type'] == 'admin') {
                              adminCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        int? engineerCatId;
                        if (isEngineer) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('مهندس') || cName.contains('مهندسين')) {
                              engineerCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        final effectiveCategoryId = isEngineer
                            ? engineerCatId
                            : (isAdmin
                                ? (adminCatId ?? (selectedCategoryId == 31251 ? null : selectedCategoryId))
                                : (isTransport ? (transportCatId ?? selectedCategoryId) : (selectedCategoryId == 31251 ? null : selectedCategoryId)));
                        final selectedCategoryName = isEngineer
                            ? 'مصاريف مهندسين'
                            : (isAdmin
                                ? 'مصاريف إدارية'
                                : (isTransport
                                    ? 'لوجستيك ونقل'
                                    : (filteredCategories[selectedCategoryId] ??
                                        categories[selectedCategoryId] ??
                                        (supplierType == 'station'
                                            ? 'خدمات محطة'
                                            : (supplierType == 'deduction'
                                                ? 'تخصيمات'
                                                : 'أخرى')))));
                        final isStation = supplierType == 'station' ||
                            _suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'station' || s.isStationSupplier));
                        final isDeduction = supplierType == 'deduction' ||
                            _suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'deduction' || s.isDeductionSupplier));
                        final effectiveSupplierType = isAdmin
                            ? 'admin'
                            : (isEngineer
                                ? 'engineer'
                                : (isTransport
                                    ? 'transport'
                                    : (isStation ? 'station' : (isDeduction ? 'deduction' : 'general'))));
                        final effectiveTruckCount = isTransport
                            ? (qty > 0 ? qty : 0.0)
                            : null;
                        final effectiveTransportSupplierId = isTransport
                            ? int.tryParse(selectedSupplierId ?? '')
                            : null;

                        final targetProduct = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? (_lotEntries[selectedTargetLineIndex!].lot?.productName ??
                               _lotEntries[selectedTargetLineIndex!].batch?.productName)
                            : null;
                        final targetProductId = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? (_lotEntries[selectedTargetLineIndex!].lot?.fruitTypeId ??
                               _lotEntries[selectedTargetLineIndex!].batch?.id?.toString())
                            : null;
                        final targetProductCode = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? _lotEntries[selectedTargetLineIndex!].batch?.productCode
                            : null;

                        final resolvedCc = targetProduct != null
                            ? CostCenterHelper.fromId(targetProduct, _costCenters)
                            : null;
                        final costCenterId = isEngineer
                            ? 'CC-ENG-EXP'
                            : (resolvedCc?.id ?? (targetProduct != null
                                ? 'CC-${targetProductCode ?? targetProduct}'
                                : (isAdmin ? 'CC-ADMIN-EXPENSES' : (selectedAllocationMethod == 'EQUAL' ? 'ALL' : null))));
                        final costCenterName = isEngineer
                            ? 'مصاريف مهندسين وإشراف'
                            : (resolvedCc?.nameAr ?? (targetProduct != null
                                ? '${CostCenter.canonicalCropName(targetProduct)} (موسم 2026-2027)'
                                : (isAdmin ? 'مصاريف إدارية' : (selectedAllocationMethod == 'EQUAL' ? 'توزيع بالتساوي على كل المنتجات' : null))));

                        setState(() {
                          _costItems.add({
                            'item_uuid': const Uuid().v4(),
                            'name': name,
                            'category': isEngineer
                                ? 'engineer_expenses'
                                : (isAdmin
                                    ? 'admin'
                                    : (isTransport
                                        ? 'logistics'
                                        : _costCategoryDbKey(selectedCategoryName))),
                            'category_name': selectedCategoryName,
                            'report_category_id': effectiveCategoryId,
                            'supplier_type': effectiveSupplierType,
                            'supplier_id': isAdmin ? null : selectedSupplierId,
                            'transport_supplier_id': effectiveTransportSupplierId,
                            'truck_count': effectiveTruckCount,
                            'transport_batch_id': isTransport ? selectedTransportBatch?.id : null,
                            'transport_batch_desc': isTransport ? selectedTransportBatch?.description : null,
                            'transport_batch_cost_per_truck': isTransport ? selectedTransportBatch?.costPerTruck : null,
                            'transport_batch_ref': isTransport ? selectedTransportBatch?.referenceId : null,
                            'transport_batch_available': isTransport ? selectedTransportBatch?.availableTrucks : null,
                            'custody_id': null,
                            'engineer_name': isEngineer ? 'مجمع عهد الموظفين' : null,
                            'is_engineer_cost_settled': isEngineer ? true : false,
                            'allocation_type': isEngineer ? (isEngineerPercentageMode ? 'percentage' : 'fixed') : null,
                            'allocation_percentage': isEngineer && isEngineerPercentageMode ? double.tryParse(engineerPercentageCtrl.text) : null,
                            'pool_total_spent': isEngineer ? custodyPoolSummary?.totalSpent : null,
                            'pool_total_allocated': isEngineer ? custodyPoolSummary?.totalAllocated : null,
                            'pool_remaining_pool': isEngineer ? custodyPoolSummary?.remainingPool : null,
                            'expense_account_id': null,
                            'expense_account_name': null,
                            'expense_account_code': null,
                            'supplier_name': isAdmin ? '' : (selectedSupplierName ?? ''),
                            'quantity': (isAdmin || isEngineer) ? 1.0 : qty,
                            'unit_price': (isTransport || isAdmin || isEngineer) ? price : price,
                            'total': (isAdmin || isEngineer) ? price : totalInSupplierCurrency,
                            'total_egp': (isAdmin || isEngineer) ? price : totalInEgp,
                            'exchange_rate': 1.0,
                            'supplier_currency': 'EGP',
                            'ledger_entry_id': null,
                            'payment_source_type': (isEngineer || isAdmin)
                                ? null
                                : (paymentSourceType == 'none' ? null : paymentSourceType),
                            'payment_source_id': (isEngineer || isAdmin)
                                ? null
                                : (paymentSourceType == 'none' ? null : selectedPaymentSourceId),
                            'allocation_method': selectedAllocationMethod,
                            'target_line_index':
                                selectedAllocationMethod == 'MANUAL'
                                    ? selectedTargetLineIndex
                                    : null,
                            'target_product_name': targetProduct,
                            'target_product_id': targetProductId,
                            'cost_center_id': costCenterId,
                            'cost_center_name': costCenterName,
                            'notes': notesCtrl.text.trim(),
                            'cost_status': (effectiveSupplierType == 'station' || effectiveSupplierType == 'deduction' || isAdmin)
                                ? 'expected'
                                : 'actual',
                            'expected_amount': (isAdmin || isEngineer) ? price : totalInEgp,
                            'actual_amount': (effectiveSupplierType == 'station' || effectiveSupplierType == 'deduction' || isAdmin)
                                ? null
                                : (isEngineer ? price : totalInEgp),
                            'variance_amount': 0.0,
                          });
                        });
                        Navigator.pop(ctx);
                        _syncFormStateToDb().then((_) {
                          _loadVarianceReport();
                          DataChangeEventBus.instance.notifyTransportSuppliersChanged();
                          DataChangeEventBus.instance.notifySuppliersChanged();
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppTheme.primary
                      : AppTheme.textSecondary.withAlpha(80),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text('إضافة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editCostItem(int index) {
    final item = _costItems[index];
    final nameCtrl = TextEditingController(text: item['name'] as String);
    final notesCtrl = TextEditingController(text: item['notes'] as String? ?? '');
    final rawQty = item['truck_count'] ?? item['quantity'] ?? 1.0;
    final qtyVal = (rawQty is num)
        ? rawQty.toDouble()
        : (double.tryParse('$rawQty') ?? 1.0);
    final qtyCtrl = TextEditingController(
        text: (qtyVal == qtyVal.roundToDouble())
            ? qtyVal.toInt().toString()
            : qtyVal.toString());

    final rawPrice = item['unit_price'] ?? item['total_egp'] ?? item['total'] ?? 0;
    final priceVal = (rawPrice is num)
        ? rawPrice.toDouble()
        : (double.tryParse('$rawPrice') ?? 0.0);
    final priceCtrl = TextEditingController(
        text: (priceVal == priceVal.roundToDouble())
            ? priceVal.toInt().toString()
            : (priceVal.toString().contains('.')
                ? priceVal.toString().replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
                : priceVal.toString()));

    final rawExchangeRate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    String supplierCurrency = item['supplier_currency'] as String? ?? 'EGP';
    bool isMultiCurrencySupplier = false;
    List<String> supplierSupportedCurrencies = [];
    bool isFetchingRate = false;

    final supplierSearchCtrl =
        TextEditingController(text: item['supplier_name'] as String? ?? '');
    String? selectedSupplierId = item['transport_supplier_id']?.toString() ??
        item['custody_id']?.toString() ??
        item['supplier_id']?.toString();
    String? selectedSupplierName = item['engineer_name'] as String? ?? item['supplier_name'] as String?;
    int? selectedExpenseAccountId = (item['expense_account_id'] as num?)?.toInt();
    String? selectedExpenseAccountName = item['expense_account_name']?.toString();
    String? selectedExpenseAccountCode = item['expense_account_code']?.toString();
    int? selectedCategoryId = item['report_category_id'] as int?;

    final initialBatchId = (item['transport_batch_id'] as num?)?.toInt();
    List<TransportBatchModel> transportBatches = [];
    TransportBatchModel? selectedTransportBatch;
    bool isLoadingBatches = false;
    String? lastLoadedTransportId;

    if ((item['supplier_type'] as String? ?? '') != 'transport' &&
        (item['supplier_type'] as String? ?? '') != 'engineer' &&
        selectedSupplierId != null) {
      final s = _suppliers.where((s) => s.id == selectedSupplierId).firstOrNull;
      if (s != null) {
        isMultiCurrencySupplier = s.supportsMultiCurrency;
        if (isMultiCurrencySupplier) {
          supplierSupportedCurrencies = s.supportedCurrencies.isNotEmpty
              ? s.supportedCurrencies
              : ['EGP', 'USD', 'EUR'];
          if (supplierCurrency == 'MULTI' ||
              !supplierSupportedCurrencies.contains(supplierCurrency)) {
            supplierCurrency = s.primaryCurrency != 'MULTI'
                ? s.primaryCurrency
                : supplierSupportedCurrencies.first;
          }
        } else {
          if (supplierCurrency == 'MULTI') {
            supplierCurrency = s.currency != 'MULTI' ? s.currency : 'EGP';
          }
        }
      }
    }

    final exchangeRateCtrl = TextEditingController(
        text: supplierCurrency == 'EGP'
            ? '1.0'
            : (rawExchangeRate > 0 ? rawExchangeRate.toStringAsFixed(4) : ''));

    String paymentSourceType = 'none'; // Forced to none as requested
    int? selectedPaymentSourceId = (item['payment_source_id'] as num?)?.toInt() ??
        (item['custody_id'] as num?)?.toInt();
    String selectedAllocationMethod =
        (item['allocation_method'] as String?) ?? (_lotEntries.isNotEmpty ? 'MANUAL' : 'EQUAL');
    int? selectedTargetLineIndex = (item['target_line_index'] as num?)?.toInt() ??
        (selectedAllocationMethod == 'MANUAL' && _lotEntries.isNotEmpty ? 0 : null);
    bool showAdvancedMethods =
        CostAllocationMethod.fromCode(selectedAllocationMethod).isAdvanced;
// notesCtrl already declared above

    if (selectedCategoryId == null && item['category'] != null) {
      final catName =
          (item['category_name'] as String?) ?? (item['category'] as String?);
      if (catName != null) {
        final matched = _costCategories.firstWhere(
          (c) => c['name'] == catName,
          orElse: () => {},
        );
        selectedCategoryId = matched['id'] as int?;
      }
    }

    final String rawCat = (item['category'] as String? ?? '').toLowerCase();
    final String rawName = (item['name'] as String? ?? '').toLowerCase();
    final bool isItemEng = item['supplier_type'] == 'engineer' ||
        rawCat == 'engineer' ||
        rawCat == 'engineer_expenses' ||
        rawName.contains('مهندس') ||
        item['custody_id'] != null;

    String supplierType = item['supplier_type'] as String? ??
        (isItemEng
            ? 'engineer'
            : (item['category'] == 'admin' || (item['category_name'] as String? ?? '').contains('إدار') || (item['category_name'] as String? ?? '').contains('ادار') || rawName.contains('إدار') || rawName.contains('ادار')
                ? 'admin'
                : ((item['transport_supplier_id'] != null ||
                  item['category'] == 'logistics' ||
                  (item['category_name'] as String? ?? '').contains('نقل') ||
                  _transportSuppliers.any((ts) => ts.id.toString() == selectedSupplierId))
                    ? 'transport'
                    : (_suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'station' || s.isStationSupplier))
                        ? 'station'
                        : (_suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'deduction' || s.isDeductionSupplier))
                            ? 'deduction'
                            : _detectSupplierTypeForCategory(selectedCategoryId, categoryName: item['category_name'] as String?))))));

    final categories = <int, String>{
      for (final c in _costCategories)
        if (c['id'] != null) c['id'] as int: (c['name'] ?? '').toString(),
    };

    final initialFilteredCategories =
        CostCategoryService.filterCategoriesBySupplierType(
      _costCategories,
      supplierType: supplierType,
    );
    if (selectedCategoryId == null && initialFilteredCategories.isNotEmpty) {
      selectedCategoryId = initialFilteredCategories.keys.first;
    }

    final adminCategories = CostCategoryService.filterCategoriesBySupplierType(
      _costCategories,
      supplierType: 'admin',
    );

    bool isLoadingCustodyBal = false;
    Map<String, dynamic>? selectedCustodyInfo;
    String? lastLoadedCustodyId;
    CustodyExpensePoolSummary? custodyPoolSummary;
    bool isLoadingCustodyPool = false;
    bool isEngineerPercentageMode = item['allocation_type'] == 'percentage';
    final engineerPercentageCtrl = TextEditingController(
      text: item['allocation_percentage'] != null ? item['allocation_percentage'].toString() : '100',
    );
    bool hasInitializedCustodyPool = false;
    DateTime? custodyFromDate;
    DateTime? custodyToDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void loadTransportBatches(String? suppId) async {
            if (suppId == null || suppId.isEmpty) return;
            final sId = int.tryParse(suppId);
            if (sId == null) return;
            lastLoadedTransportId = suppId;
            setDialogState(() => isLoadingBatches = true);
            try {
              final batches = await _getEffectiveTransportBatches(
                supplierId: sId,
                excludeItemIndex: index,
                onlyAvailable: true,
                includeBatchId: initialBatchId,
              );
              if (ctx.mounted) {
                setDialogState(() {
                  transportBatches = batches.where((b) => b.availableTrucks > 0.0001 || (initialBatchId != null && b.id == initialBatchId)).toList();
                  isLoadingBatches = false;
                  if (transportBatches.isNotEmpty) {
                    if (selectedTransportBatch == null) {
                      if (initialBatchId != null) {
                        final match = transportBatches.where((b) => b.id == initialBatchId).firstOrNull;
                        if (match != null) {
                          selectedTransportBatch = match;
                        }
                      }
                      selectedTransportBatch ??= transportBatches.first;
                    } else {
                      final match = transportBatches.where((b) => b.id == selectedTransportBatch!.id).firstOrNull;
                      selectedTransportBatch = match ?? transportBatches.first;
                    }
                  } else {
                    selectedTransportBatch = null;
                  }
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingBatches = false);
              }
            }
          }

          void loadCustodyDetails(String? cId) async {
            if (cId == null || cId.isEmpty) return;
            lastLoadedCustodyId = cId;
            setDialogState(() => isLoadingCustodyBal = true);
            try {
              final info = await fetchCustodyBalanceInfo(cId, currency: supplierCurrency);
              if (ctx.mounted) {
                setDialogState(() {
                  selectedCustodyInfo = info;
                  isLoadingCustodyBal = false;
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingCustodyBal = false);
              }
            }
          }

          void loadCustodyPoolData({bool forceUpdatePrice = false}) async {
            if (isLoadingCustodyPool) return;
            setDialogState(() => isLoadingCustodyPool = true);
            try {
              final currentOrdId = int.tryParse(_currentOrder?.id ?? widget.existingOrder?.id ?? '');
              final summary = await CustodyService().getCustodyExpensePoolSummary(
                excludePackingOrderId: currentOrdId,
                fromDate: custodyFromDate,
                toDate: custodyToDate,
              );
              if (ctx.mounted) {
                setDialogState(() {
                  custodyPoolSummary = summary;
                  isLoadingCustodyPool = false;
                  if (supplierType == 'engineer') {
                    final otherAlloc = _costItems.asMap().entries.where((e) {
                      if (e.key == index) return false;
                      final c = e.value;
                      final cat = (c['category']?.toString() ?? '').toLowerCase();
                      final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                      final name = (c['name']?.toString() ?? '').toLowerCase();
                      return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                    }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                    final effRem = (summary.remainingPool - otherAlloc).clamp(0.0, double.infinity);
                    if (isEngineerPercentageMode) {
                      final pct = double.tryParse(engineerPercentageCtrl.text) ?? 100.0;
                      final calcAmt = effRem * (pct / 100.0);
                      priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                    } else if (forceUpdatePrice || priceCtrl.text.isEmpty || effRem > 0) {
                      priceCtrl.text = effRem > 0 ? effRem.toStringAsFixed(2) : '';
                    }
                  }
                });
              }
            } catch (_) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingCustodyPool = false);
              }
            }
          }

          final name = nameCtrl.text.trim();
          final isTransport = supplierType == 'transport' ||
              _transportSuppliers.any((ts) => ts.id.toString() == selectedSupplierId);
          final qty =
              double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final price =
              double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final rate = double.tryParse(
                  exchangeRateCtrl.text.trim().replaceAll(',', '.')) ??
              (supplierCurrency == 'EGP' ? 1.0 : 0.0);
          final totalInSupplierCurrency = isTransport ? price : (qty * price);
          final totalEgp = supplierCurrency == 'EGP'
              ? totalInSupplierCurrency
              : (rate > 0
                  ? CurrencyConversionService.instance
                      .toBase(totalInSupplierCurrency, supplierCurrency, rate)
                  : 0.0);

          Future<void> onCurrencyChanged(String newCur) async {
            if (newCur == supplierCurrency) return;
            setDialogState(() {
              supplierCurrency = newCur;
              selectedPaymentSourceId = null;
              if (newCur == 'EGP') {
                exchangeRateCtrl.text = '1.0';
                isFetchingRate = false;
              } else {
                isFetchingRate = true;
              }
            });

            if (newCur != 'EGP') {
              try {
                final r = await CurrencyConversionService.instance.getRate(newCur);
                setDialogState(() {
                  exchangeRateCtrl.text = r > 0 ? r.toStringAsFixed(4) : '';
                  isFetchingRate = false;
                });
              } catch (_) {
                setDialogState(() {
                  exchangeRateCtrl.text = '';
                  isFetchingRate = false;
                });
              }
            }
          }

          Future<void> refreshRate() async {
            if (supplierCurrency == 'EGP') {
              setDialogState(() => exchangeRateCtrl.text = '1.0');
              return;
            }
            setDialogState(() => isFetchingRate = true);
            try {
              CurrencyConversionService.instance.invalidateCache();
              final r = await CurrencyConversionService.instance.getRate(supplierCurrency);
              setDialogState(() {
                exchangeRateCtrl.text = r > 0 ? r.toStringAsFixed(4) : '';
                isFetchingRate = false;
              });
            } catch (_) {
              setDialogState(() => isFetchingRate = false);
            }
          }

          double availableBalance = 0;
          String sourceName = '';

          if (paymentSourceType == 'treasury' &&
              selectedPaymentSourceId != null) {
            final sIdStr = selectedPaymentSourceId.toString();
            final t = _treasuries.firstWhere(
                (e) => e['id']?.toString() == sIdStr,
                orElse: () => {});
            sourceName = t['name'] as String? ?? 'الخزينة المختارة';

            if (selectedCustodyInfo != null && selectedCustodyInfo!['custody_id']?.toString() == sIdStr) {
              availableBalance = (selectedCustodyInfo!['balance'] as num?)?.toDouble() ?? 0.0;
            } else if (_custodyBalancesMap.containsKey(sIdStr) && _custodyBalancesMap[sIdStr]!['balance'] != null) {
              availableBalance = (_custodyBalancesMap[sIdStr]!['balance'] as num).toDouble();
            } else if (t['live_balance'] != null) {
              availableBalance = (t['live_balance'] as num).toDouble();
            } else {
              final balances = t['treasury_balances'];
              if (balances is List) {
                final match = balances
                    .where((b) =>
                        (b['currency']?.toString() ?? 'EGP').toUpperCase() ==
                        supplierCurrency.toUpperCase())
                    .toList();
                if (match.isNotEmpty) {
                  availableBalance = (match.first['balance'] as num).toDouble();
                }
              }
            }
          } else if (paymentSourceType == 'bank' &&
              selectedPaymentSourceId != null) {
            final b = _bankAccounts.firstWhere(
                (e) => e['id']?.toString() == selectedPaymentSourceId.toString(),
                orElse: () => {});
            sourceName = '${b['name'] ?? ''} (${b['bank_name'] ?? ''})';
            availableBalance = (b['balance'] as num?)?.toDouble() ?? 0;
          }
          final isAdmin = supplierType == 'admin';
          final isEngineer = supplierType == 'engineer';

          final isInsufficientBalance = !isEngineer &&
              (paymentSourceType != 'none') &&
              (selectedPaymentSourceId != null) &&
              (totalInSupplierCurrency > availableBalance);
          if (isEngineer && selectedExpenseAccountId == null && _expenseAccounts.isNotEmpty) {
            final defaultEngAcc = _expenseAccounts.firstWhere(
              (a) => a['account_code'] == '31251',
              orElse: () => _expenseAccounts.first,
            );
            selectedExpenseAccountId = (defaultEngAcc['id'] as num?)?.toInt();
            selectedExpenseAccountName = defaultEngAcc['resolved_name']?.toString() ?? 'مصاريف مهندسين';
            selectedExpenseAccountCode = defaultEngAcc['account_code']?.toString() ?? '31251';
          }

          final isBatchQtyValid = !isTransport || selectedTransportBatch == null || (qty > 0 && qty <= (selectedTransportBatch!.availableTrucks + 0.0001));
          final canSubmit = name.isNotEmpty &&
              (isAdmin || isEngineer
                  ? price > 0
                  : (isTransport ? (price > 0 && qty > 0 && isBatchQtyValid) : (qty > 0 && price > 0))) &&
              (isAdmin || isEngineer || selectedSupplierId != null) &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' || isEngineer ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;

          final isDark = AppTheme.isDark(ctx);

          final employeeCustodies = _treasuries.where((t) {
            final type = t['type']?.toString().toLowerCase() ?? '';
            final tName = t['name']?.toString() ?? '';
            return type == 'employee' || tName.contains('عهدة') || tName.contains('مهندس');
          }).toList();
          final effectiveCustodies = employeeCustodies.isNotEmpty ? employeeCustodies : _treasuries;

          if (isEngineer) {
            selectedSupplierName = 'مجمع عهد الموظفين';
            paymentSourceType = 'none';
            selectedPaymentSourceId = null;
          }

          if (isEngineer && selectedSupplierId != null && !isLoadingCustodyBal && lastLoadedCustodyId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCustodyDetails(selectedSupplierId);
            });
          }

          if (isTransport && selectedSupplierId != null && !isLoadingBatches && lastLoadedTransportId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadTransportBatches(selectedSupplierId);
            });
          }

          final filteredCategories =
              CostCategoryService.filterCategoriesBySupplierType(
            _costCategories,
            supplierType: supplierType,
          );

          void switchStandardSupplierType(String nextType) {
            setDialogState(() {
              supplierType = nextType;
              selectedSupplierId = null;
              selectedSupplierName = null;
              supplierSearchCtrl.clear();
              supplierCurrency = 'EGP';
              exchangeRateCtrl.text = '';
              final resolved = _resolveCategorySelectionForType(
                targetType: nextType,
                currentCategoryId: selectedCategoryId,
                currentName: nameCtrl.text,
                allCategories: categories,
              );
              selectedCategoryId = resolved.categoryId;
              if (resolved.updatedName != null) {
                nameCtrl.text = resolved.updatedName!;
              }
            });
          }

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            title: Text('تعديل بند التكلفة',
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: _inputDecoration('اسم البند'),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              avatar: Icon(Icons.people_outline,
                                  size: 14,
                                  color: supplierType == 'general'
                                      ? (isDark ? Colors.white : AppTheme.primary)
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('عام / خامات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'general',
                              selectedColor: isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFFBAE6FD),
                              onSelected: (val) {
                                if (val) switchStandardSupplierType('general');
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.local_shipping,
                                  size: 14,
                                  color: supplierType == 'transport'
                                      ? (isDark ? Colors.white : AppTheme.accent)
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد نقل 🚛',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'transport',
                              selectedColor: isDark ? AppTheme.accent.withAlpha(80) : const Color(0xFF99F6E4),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'transport';
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    final resolved =
                                        _resolveCategorySelectionForType(
                                      targetType: 'transport',
                                      currentCategoryId: selectedCategoryId,
                                      currentName: nameCtrl.text,
                                      allCategories: categories,
                                    );
                                    selectedCategoryId = resolved.categoryId;
                                    if (resolved.updatedName != null) {
                                      nameCtrl.text = resolved.updatedName!;
                                    }
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.factory_outlined,
                                  size: 14,
                                  color: supplierType == 'station'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد محطة 🏭',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'station',
                              selectedColor: const Color(0xFF059669).withAlpha(120),
                              onSelected: (val) {
                                if (val) switchStandardSupplierType('station');
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.assignment_outlined,
                                  size: 14,
                                  color: supplierType == 'deduction'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مورد تخصيمات 📋',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'deduction',
                              selectedColor: const Color(0xFF7C3AED).withAlpha(120),
                              onSelected: (val) {
                                if (val) {
                                  switchStandardSupplierType('deduction');
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.business_center_outlined,
                                  size: 14,
                                  color: supplierType == 'admin'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مصاريف إدارية 💼',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'admin',
                              selectedColor: const Color(0xFF0284C7).withAlpha(120),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'admin';
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    qtyCtrl.text = '1';
                                    final resolved =
                                        _resolveCategorySelectionForType(
                                      targetType: 'admin',
                                      currentCategoryId: selectedCategoryId,
                                      currentName: '',
                                      allCategories: categories,
                                    );
                                    selectedCategoryId = resolved.categoryId;
                                    nameCtrl.text = resolved.updatedName ??
                                        'مصاريف إدارية';
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              avatar: Icon(Icons.engineering_outlined,
                                  size: 14,
                                  color: supplierType == 'engineer'
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : Colors.black54)),
                              label: Text('مصاريف مهندسين 👷',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black)),
                              selected: supplierType == 'engineer',
                              selectedColor: const Color(0xFFF59E0B).withAlpha(140),
                              onSelected: (val) {
                                if (val) {
                                  setDialogState(() {
                                    supplierType = 'engineer';
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    selectedCustodyInfo = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text = '1.0';
                                    qtyCtrl.text = '1';
                                    selectedCategoryId = null;
                                    if (effectiveCustodies.isNotEmpty) {
                                      final firstC = effectiveCustodies.first;
                                      selectedSupplierId = firstC['id'].toString();
                                      selectedSupplierName = firstC['name']?.toString() ?? 'عهدة مهندس';
                                      selectedPaymentSourceId = int.tryParse(selectedSupplierId ?? '');
                                      paymentSourceType = 'treasury';
                                    }
                                    if (CostCategoryService
                                        .isAutoGeneratedItemName(
                                            nameCtrl.text, categories.values)) {
                                      nameCtrl.text = 'مصاريف مهندسين وإشراف';
                                    }
                                  });
                                  if (selectedSupplierId != null) {
                                    loadCustodyDetails(selectedSupplierId);
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      if (isEngineer) ...[
                        const SizedBox(height: 14),
                        // 1. Custody Expense Pool Summary Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF132337) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? const Color(0xFFF59E0B).withAlpha(80) : const Color(0xFFF59E0B).withAlpha(120),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withAlpha(25),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.account_balance_wallet, color: Color(0xFFF59E0B), size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'مجمع مصروفات عهد الموظفين المتاحة للتحميل',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'تكلفة فعلية تم صرفها مسبقاً من العهد (وجبات، عمالة، انتقالات) ويتم تحميلها على التعبئة دون سحب مالي جديد',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isLoadingCustodyPool)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 18, color: Color(0xFFF59E0B)),
                                      tooltip: 'تحديث بيانات مجمع العهد',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => loadCustodyPoolData(),
                                    ),
                                ],
                              ),
                              _buildCustodyDateFilterBar(
                                context: ctx,
                                isDark: isDark,
                                fromDate: custodyFromDate,
                                toDate: custodyToDate,
                                onDatesChanged: (f, t) {
                                  setDialogState(() {
                                    custodyFromDate = f;
                                    custodyToDate = t;
                                  });
                                  loadCustodyPoolData(forceUpdatePrice: true);
                                },
                              ),
                              // Dynamic remaining balance calculation factoring in other items in current order
                              Builder(
                                builder: (_) {
                                  final otherAlloc = _costItems.asMap().entries.where((e) {
                                    if (e.key == index) return false;
                                    final c = e.value;
                                    final cat = (c['category']?.toString() ?? '').toLowerCase();
                                    final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                    final name = (c['name']?.toString() ?? '').toLowerCase();
                                    return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                  }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                                  final effectiveAllocated = (custodyPoolSummary?.totalAllocated ?? 0.0) + otherAlloc;
                                  final effectiveRemainingPool = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'إجمالي المنصرف من العهد',
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.white70 : Colors.black54),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(custodyPoolSummary?.totalSpent ?? 0)} ج.م',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.white : Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'المحمل سابقاً',
                                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.white70 : Colors.black54),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(effectiveAllocated)} ج.م',
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF6366F1),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                    ? const Color(0xFF059669).withAlpha(isDark ? 35 : 20)
                                                    : const Color(0xFFDC2626).withAlpha(isDark ? 35 : 20),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                      ? const Color(0xFF059669).withAlpha(80)
                                                      : const Color(0xFFDC2626).withAlpha(80),
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'المتبقي للتحميل',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFFDC2626),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${NumberFormat('#,##0.##').format(effectiveRemainingPool)} ج.م',
                                                    style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: (custodyPoolSummary != null && effectiveRemainingPool > 0)
                                                          ? const Color(0xFF059669)
                                                          : const Color(0xFFDC2626),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              if (custodyPoolSummary != null && custodyPoolSummary!.totalSpent > 0) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (custodyPoolSummary!.mealsSpent > 0)
                                      _poolCategoryPill('وجبات: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.mealsSpent)} ج.م', const Color(0xFFEA580C)),
                                    if (custodyPoolSummary!.laborSpent > 0)
                                      _poolCategoryPill('عمالة: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.laborSpent)} ج.م', const Color(0xFF2563EB)),
                                    if (custodyPoolSummary!.transportSpent > 0)
                                      _poolCategoryPill('انتقالات: ${NumberFormat('#,##0.##').format(custodyPoolSummary!.transportSpent)} ج.م', const Color(0xFF059669)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Mode Selector: Cash Amount vs Percentage
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('مبلغ نقدي مباشر (ج.م)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                selected: !isEngineerPercentageMode,
                                selectedColor: const Color(0xFFF59E0B).withAlpha(isDark ? 70 : 160),
                                onSelected: (val) {
                                  if (val) {
                                    setDialogState(() {
                                      isEngineerPercentageMode = false;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('نسبة مئوية (%)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                selected: isEngineerPercentageMode,
                                selectedColor: const Color(0xFFF59E0B).withAlpha(isDark ? 70 : 160),
                                onSelected: (val) {
                                  if (val) {
                                    setDialogState(() {
                                      isEngineerPercentageMode = true;
                                      final pct = double.tryParse(engineerPercentageCtrl.text) ?? 100.0;
                                      final otherAlloc = _costItems.asMap().entries.where((e) {
                                        if (e.key == index) return false;
                                        final c = e.value;
                                        final cat = (c['category']?.toString() ?? '').toLowerCase();
                                        final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                        final name = (c['name']?.toString() ?? '').toLowerCase();
                                        return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                      }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                                      final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);
                                      final calcAmt = (poolRem * (pct / 100.0));
                                      priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 3. Inputs
                        if (isEngineerPercentageMode) ...[
                          TextField(
                            controller: engineerPercentageCtrl,
                            decoration: _inputDecoration('النسبة المئوية المراد تحميلها (%) *').copyWith(
                              prefixIcon: const Icon(Icons.percent, color: Color(0xFFF59E0B), size: 18),
                              helperText: 'يتم احتساب النسبة تلقائياً من رصيد المصروفات المتبقي للعهد',
                              helperStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                            ],
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 15,
                            ),
                            onChanged: (val) {
                              final pct = double.tryParse(val) ?? 0.0;
                              final otherAlloc = _costItems.asMap().entries.where((e) {
                                if (e.key == index) return false;
                                final c = e.value;
                                final cat = (c['category']?.toString() ?? '').toLowerCase();
                                final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                final name = (c['name']?.toString() ?? '').toLowerCase();
                                return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                              }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                              final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);
                              final calcAmt = (poolRem * (pct / 100.0));
                              priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                              setDialogState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [25, 50, 75, 100].map((pct) {
                              final isCurPct = engineerPercentageCtrl.text == pct.toString();
                              return ActionChip(
                                label: Text('$pct%', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                                backgroundColor: isCurPct ? const Color(0xFFF59E0B).withAlpha(120) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                onPressed: () {
                                  setDialogState(() {
                                    engineerPercentageCtrl.text = pct.toString();
                                    final otherAlloc = _costItems.asMap().entries.where((e) {
                                      if (e.key == index) return false;
                                      final c = e.value;
                                      final cat = (c['category']?.toString() ?? '').toLowerCase();
                                      final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                      final name = (c['name']?.toString() ?? '').toLowerCase();
                                      return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                    }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                                    final poolRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);
                                    final calcAmt = (poolRem * (pct / 100.0));
                                    priceCtrl.text = calcAmt > 0 ? calcAmt.toStringAsFixed(2) : '';
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ] else ...[
                          TextField(
                            controller: priceCtrl,
                            decoration: _inputDecoration('المبلغ المراد تحميله على أمر التعبئة (ج.م) *').copyWith(
                              prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFFF59E0B), size: 18),
                              helperText: 'أدخل المبلغ بالجنيه ليتم خصمه توضيحياً من مجمع العهد',
                              helperStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                              ),
                              suffixIcon: Builder(
                                builder: (_) {
                                  final otherAlloc = _costItems.asMap().entries.where((e) {
                                    if (e.key == index) return false;
                                    final c = e.value;
                                    final cat = (c['category']?.toString() ?? '').toLowerCase();
                                    final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                                    final name = (c['name']?.toString() ?? '').toLowerCase();
                                    return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                                  }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                                  final effRem = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);
                                  return (custodyPoolSummary != null && effRem > 0)
                                      ? TextButton(
                                          child: const Text('كامل المتبقي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                                          onPressed: () {
                                            setDialogState(() {
                                              priceCtrl.text = effRem.toStringAsFixed(2);
                                            });
                                          },
                                        )
                                      : const SizedBox.shrink();
                                },
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                            ],
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 15,
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ],

                        // 4. Live Calculation & Pool Impact Preview
                        const SizedBox(height: 12),
                        Builder(
                          builder: (_) {
                            final inputVal = double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0.0;
                            final otherAlloc = _costItems.asMap().entries.where((e) {
                              if (e.key == index) return false;
                              final c = e.value;
                              final cat = (c['category']?.toString() ?? '').toLowerCase();
                              final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();
                              final name = (c['name']?.toString() ?? '').toLowerCase();
                              return cat == 'engineer_expenses' || cat == 'engineer' || suppType == 'engineer' || name.contains('مهندس');
                            }).fold<double>(0.0, (sum, e) => sum + ((e.value['total_egp'] ?? e.value['total'] ?? e.value['expected_amount'] ?? 0) as num).toDouble());
                            final remPool = math.max(0.0, (custodyPoolSummary?.remainingPool ?? 0.0) - otherAlloc);
                            final remAfter = remPool - inputVal;
                            final isExceeded = remAfter < -0.01;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isExceeded
                                    ? const Color(0xFFDC2626).withAlpha(15)
                                    : const Color(0xFF059669).withAlpha(15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isExceeded ? const Color(0xFFDC2626).withAlpha(80) : const Color(0xFF059669).withAlpha(80),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isExceeded ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                    size: 20,
                                    color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'التكلفة المحملة على أمر التعبئة: ${NumberFormat('#,##0.##').format(inputVal)} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          isExceeded
                                              ? 'تنبيه: المبلغ يتجاوز المتبقي بمقدار ${NumberFormat('#,##0.##').format(-remAfter)} ج.م'
                                              : 'المتبقي في مجمع العهد بعد هذا الأمر: ${NumberFormat('#,##0.##').format(remAfter.clamp(0.0, double.infinity))} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: isExceeded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // 5. Statement / Notes for Engineer Expenses
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesCtrl,
                          maxLines: 2,
                          decoration: _inputDecoration('البيان / تفاصيل وملاحظات المصروف').copyWith(
                            prefixIcon: const Icon(Icons.description_outlined, color: Color(0xFFF59E0B), size: 18),
                            hintText: 'مثل: تحميل نسبة من وجبات وانتقالات مهندسي المحطة على هذا الأمر...',
                            helperText: 'بيان المصروف المحمل يظهر في كشف التكاليف التفصيلي لأمر التعبئة',
                            helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                            ),
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 14,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ] else if (isAdmin) ...[
                        if (adminCategories.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          CostItemCategoryDropdown(
                            keyPrefix: 'admin_cost_cat',
                            supplierType: supplierType,
                            filteredCategories: adminCategories,
                            selectedCategoryId:
                                adminCategories.containsKey(selectedCategoryId)
                                    ? selectedCategoryId
                                    : adminCategories.keys.first,
                            decoration: _inputDecoration(
                                    'تصنيف بند المصاريف الإدارية')
                                .copyWith(
                              prefixIcon: const Icon(
                                  Icons.business_center_outlined,
                                  color: Color(0xFF0284C7),
                                  size: 18),
                            ),
                            isDark: isDark,
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  selectedCategoryId = v;
                                  final catName = adminCategories[v] ?? '';
                                  if (catName.isNotEmpty) {
                                    nameCtrl.text = catName;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: priceCtrl,
                          decoration: _inputDecoration('قيمة المصروف *').copyWith(
                            prefixIcon: const Icon(Icons.payments_outlined, color: Color(0xFF0284C7), size: 18),
                            helperText: 'أدخل قيمة المصروف بالجنيه المصري (مثال: 1500 أو 2500.50)',
                            helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                          ],
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ] else ...[
                        if (supplierType != 'transport') ...[
                          const SizedBox(height: 14),
                          CostItemCategoryDropdown(
                            keyPrefix: 'edit_cost_cat',
                            supplierType: supplierType,
                            filteredCategories: filteredCategories,
                            selectedCategoryId: selectedCategoryId,
                            decoration: _inputDecoration('تصنيف البند'),
                            isDark: isDark,
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
                                  final previousCatName =
                                      filteredCategories[selectedCategoryId] ??
                                          categories[selectedCategoryId] ??
                                          '';
                                  selectedCategoryId = v;
                                  final newType =
                                      _detectSupplierTypeForCategory(v);
                                  if (newType != supplierType) {
                                    supplierType = newType;
                                    selectedSupplierId = null;
                                    selectedSupplierName = null;
                                    supplierSearchCtrl.clear();
                                    supplierCurrency = 'EGP';
                                    exchangeRateCtrl.text =
                                        (newType == 'transport' ||
                                                newType == 'admin')
                                            ? '1.0'
                                            : '';
                                  }
                                  final catName = filteredCategories[v] ??
                                      categories[v] ??
                                      '';
                                  final currentName = nameCtrl.text.trim();
                                  if (newType == 'admin') {
                                    nameCtrl.text = 'مصاريف إدارية';
                                    qtyCtrl.text = '1';
                                  } else if (currentName == previousCatName ||
                                      CostCategoryService
                                          .isAutoGeneratedItemName(
                                              currentName, categories.values)) {
                                    nameCtrl.text = catName;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      const SizedBox(height: 14),
                      TypeAheadField<String>(
                        key: ValueKey('edit_${supplierType}_$selectedSupplierId'),
                        controller: supplierSearchCtrl,
                        autoFlipDirection: true,
                        hideOnEmpty: false,
                        hideOnError: true,
                        suggestionsCallback: (query) async {
                          final q = query.trim().toLowerCase();
                          if (supplierType == 'transport') {
                            if (q.isEmpty) {
                              return _transportSuppliers
                                  .map((s) => s.id!.toString())
                                  .toList();
                            }
                            return _transportSuppliers
                                .where((s) =>
                                    s.name.toLowerCase().contains(q) ||
                                    s.displayName.toLowerCase().contains(q) ||
                                    s.code.toLowerCase().contains(q) ||
                                    s.phone.toLowerCase().contains(q))
                                .map((s) => s.id!.toString())
                                .toList();
                          } else if (supplierType == 'station') {
                            final stationMatches = _suppliers.where((s) {
                              final isStation = s.supplierType == 'station' ||
                                  s.isStationSupplier ||
                                  (int.tryParse(s.supplierCode) != null &&
                                      int.parse(s.supplierCode) >= 85000 &&
                                      int.parse(s.supplierCode) <= 89999);
                              if (!isStation) return false;
                              if (q.isEmpty) return true;
                              return s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q) ||
                                  s.phone.toLowerCase().contains(q) ||
                                  s.categories.any((c) => c.toLowerCase().contains(q));
                            }).toList();

                            if (q.isNotEmpty && stationMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if ((s.supplierType == 'station' || s.isStationSupplier) &&
                                      !stationMatches.any((m) => m.id == s.id)) {
                                    stationMatches.add(s);
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }
                            return stationMatches.map((s) => s.id!).toList();
                          } else if (supplierType == 'deduction') {
                            final deductionMatches = _suppliers.where((s) {
                              final isDeduction = s.supplierType == 'deduction' ||
                                  s.isDeductionSupplier ||
                                  (int.tryParse(s.supplierCode) != null &&
                                      int.parse(s.supplierCode) >= 40000 &&
                                      int.parse(s.supplierCode) <= 49999);
                              if (!isDeduction) return false;
                              if (q.isEmpty) return true;
                              return s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q) ||
                                  s.phone.toLowerCase().contains(q) ||
                                  s.categories.any((c) => c.toLowerCase().contains(q));
                            }).toList();

                            if (q.isNotEmpty && deductionMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if ((s.supplierType == 'deduction' || s.isDeductionSupplier) &&
                                      !deductionMatches.any((m) => m.id == s.id)) {
                                    deductionMatches.add(s);
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }
                            return deductionMatches.map((s) => s.id!).toList();
                          } else {
                            final inMemoryMatches = _suppliers
                                .where((s) {
                                  final isSpecialized = s.supplierType == 'station' ||
                                      s.supplierType == 'deduction' ||
                                      s.isStationSupplier ||
                                      s.isDeductionSupplier;
                                  if (isSpecialized) return false;
                                  if (q.isEmpty) return true;
                                  return s.name.toLowerCase().contains(q) ||
                                      s.displayName.toLowerCase().contains(q) ||
                                      s.supplierCode.toLowerCase().contains(q) ||
                                      s.phone.toLowerCase().contains(q) ||
                                      s.supplierType.toLowerCase().contains(q) ||
                                      s.supplierTypeLabel.toLowerCase().contains(q);
                                })
                                .toList();

                            if (q.isNotEmpty && inMemoryMatches.length < 5) {
                              try {
                                final dbSuppliers = await SupplierDao().search(q, limit: 30);
                                for (final s in dbSuppliers) {
                                  if (!s.isStationSupplier && !s.isDeductionSupplier && s.supplierType != 'station' && s.supplierType != 'deduction') {
                                    if (!_suppliers.any((existing) => existing.id == s.id)) {
                                      _suppliers.add(s);
                                    }
                                    if (!inMemoryMatches.any((m) => m.id == s.id)) {
                                      inMemoryMatches.add(s);
                                    }
                                  }
                                }
                              } catch (_) {}
                            }

                            return inMemoryMatches.map((s) => s.id!).toList();
                          }
                        },
                        itemBuilder: (context, supplierId) {
                          if (supplierType == 'transport') {
                            final s = _transportSuppliers.firstWhere(
                                (s) => s.id.toString() == supplierId,
                                orElse: () => const TransportSupplierModel(
                                    name: '', createdAt: ''));
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.local_shipping,
                                  color: AppTheme.accent, size: 18),
                              title: Text(s.displayName,
                                  style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 13)),
                              subtitle: s.phone.isNotEmpty
                                  ? Text(s.phone,
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'))
                                  : null,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else if (supplierType == 'station') {
                            final s = _suppliers.firstWhere(
                              (s) => s.id == supplierId,
                              orElse: () => const SupplierModel(
                                supplierCode: '',
                                name: '',
                              ),
                            );
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.factory_rounded,
                                  color: Color(0xFF059669), size: 20),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFF059669).withAlpha(80)),
                                    ),
                                    child: const Text('مورد محطة 🏭',
                                        style: TextStyle(
                                            color: Color(0xFF059669),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                ],
                              ),
                              subtitle: s.categories.isNotEmpty
                                  ? Text(s.categories.join(' • '),
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : (s.phone.isNotEmpty
                                      ? Text(s.phone,
                                          style: TextStyle(
                                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                                              fontSize: 11,
                                              fontFamily: 'Cairo'))
                                      : null),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else if (supplierType == 'deduction') {
                            final s = _suppliers.firstWhere(
                              (s) => s.id == supplierId,
                              orElse: () => const SupplierModel(
                                supplierCode: '',
                                name: '',
                              ),
                            );
                            final bal = s.balance;
                            final isCredit = bal > 0;
                            final isDebit = bal < 0;
                            final balColor = isCredit
                                ? AppTheme.warning
                                : (isDebit ? AppTheme.accent : AppTheme.success);
                            final balLabel = isCredit
                                ? 'له'
                                : (isDebit ? 'عليه' : 'خالص');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.assignment_rounded,
                                  color: Color(0xFF7C3AED), size: 20),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFF7C3AED).withAlpha(80)),
                                    ),
                                    child: const Text('مورد تخصيمات 📋',
                                        style: TextStyle(
                                            color: Color(0xFF7C3AED),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                ],
                              ),
                              subtitle: s.categories.isNotEmpty
                                  ? Text(s.categories.join(' • '),
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black54,
                                          fontSize: 11,
                                          fontFamily: 'Cairo'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)
                                  : (s.phone.isNotEmpty
                                      ? Text(s.phone,
                                          style: TextStyle(
                                              color: isDark ? AppTheme.textSecondary : Colors.black54,
                                              fontSize: 11,
                                              fontFamily: 'Cairo'))
                                      : null),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: balColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: balColor.withAlpha(80)),
                                ),
                                child: Text(
                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                  style: TextStyle(
                                    color: balColor,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            final isMulti = s.supportsMultiCurrency;
                            final currencyDisplay = isMulti
                                ? 'متعدد (${s.supportedCurrencies.join('/')})'
                                : s.currency;
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s.displayName,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: s.isSharedSupplier
                                          ? AppTheme.primary.withAlpha(35)
                                          : AppTheme.accent.withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(s.supplierTypeLabel,
                                        style: TextStyle(
                                            color: s.isSharedSupplier
                                                ? AppTheme.primary
                                                : (isDark ? Colors.white70 : const Color(0xFF1E293B)),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                            fontFamily: 'Cairo')),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isMulti
                                          ? AppTheme.cyan.withAlpha(30)
                                          : (isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0)),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isMulti
                                            ? AppTheme.cyan.withAlpha(80)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Text(
                                      currencyDisplay,
                                      style: TextStyle(
                                          color: isMulti
                                              ? (isDark ? AppTheme.cyan : const Color(0xFF0369A1))
                                              : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        onSelected: (supplierId) async {
                          if (supplierType == 'transport') {
                            final s = _transportSuppliers.firstWhere(
                                (s) => s.id.toString() == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id?.toString();
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = [];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;
                              selectedTransportBatch = null;
                              lastLoadedTransportId = null;

                              // Auto-fill cost item name if empty or generic
                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty ||
                                  currentName.startsWith('مصاريف نقل') ||
                                  currentName == 'نقل' ||
                                  currentName == 'نقل بضاعة') {
                                nameCtrl.text = s.name.isNotEmpty
                                    ? 'مصاريف نقل - '
                                    : 'نقل بضاعة';
                              }
                            });
                            loadTransportBatches(s.id?.toString());
                          } else if (supplierType == 'station') {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = ['EGP'];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;

                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty) {
                                nameCtrl.text = 'خدمات محطة - ${s.name}';
                              }
                            });
                          } else if (supplierType == 'deduction') {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              supplierCurrency = 'EGP';
                              isMultiCurrencySupplier = false;
                              supplierSupportedCurrencies = ['EGP'];
                              exchangeRateCtrl.text = '1.0';
                              isFetchingRate = false;
                              selectedPaymentSourceId = null;

                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty) {
                                nameCtrl.text = 'تخصيمات - ${s.name}';
                              }
                            });
                          } else {
                            final s = _suppliers
                                .firstWhere((s) => s.id == supplierId);
                            final isMulti = s.supportsMultiCurrency;
                            final supported = isMulti
                                ? (s.supportedCurrencies.isNotEmpty
                                    ? s.supportedCurrencies
                                    : ['EGP', 'USD', 'EUR'])
                                : [((s.currency.isNotEmpty && s.currency != 'MULTI')
                                    ? s.currency
                                    : 'EGP')];
                            final initialCur = isMulti
                                ? (s.packagingCurrency.isNotEmpty &&
                                        supported.contains(s.packagingCurrency)
                                    ? s.packagingCurrency
                                    : (supported.contains('EGP')
                                        ? 'EGP'
                                        : supported.first))
                                : supported.first;

                            setDialogState(() {
                              selectedSupplierId = s.id;
                              selectedSupplierName = s.name;
                              supplierSearchCtrl.text = s.displayName;
                              isMultiCurrencySupplier = isMulti;
                              supplierSupportedCurrencies = supported;
                              supplierCurrency = initialCur;
                              selectedPaymentSourceId = null;
                              if (supplierCurrency == 'EGP') {
                                exchangeRateCtrl.text = '1.0';
                                isFetchingRate = false;
                              } else {
                                isFetchingRate = true;
                              }
                            });

                            if (supplierCurrency != 'EGP') {
                              try {
                                final r = await CurrencyConversionService
                                    .instance
                                    .getRate(supplierCurrency);
                                setDialogState(() {
                                  exchangeRateCtrl.text =
                                      r > 0 ? r.toStringAsFixed(4) : '';
                                  isFetchingRate = false;
                                });
                              } catch (_) {
                                setDialogState(() {
                                  exchangeRateCtrl.text = '';
                                  isFetchingRate = false;
                                });
                              }
                            }
                          }
                        },
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: _inputDecoration(
                                supplierType == 'transport'
                                    ? 'مقاول النقل (إجباري) - بحث بالاسم أو الكود'
                                    : (supplierType == 'station'
                                        ? 'مورد المحطة (إجباري) - بحث بالاسم أو الكود أو الخدمة'
                                        : (supplierType == 'deduction'
                                            ? 'مورد التخصيمات (إجباري) - بحث بالاسم أو الكود أو نوع التخصيم'
                                            : 'المورد (إجباري) - بحث بالاسم أو الكود'))),
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                          );
                        },
                      ),
                      if (selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: supplierType == 'transport'
                              ? Builder(
                                  builder: (ctx) {
                                    final transSupplier = _transportSuppliers.firstWhere(
                                      (s) => s.id.toString() == selectedSupplierId,
                                      orElse: () => const TransportSupplierModel(
                                          name: '', createdAt: ''),
                                    );
                                    final bal = transSupplier.balance;
                                    final isCredit = bal > 0;
                                    final isDebit = bal < 0;
                                    final balColor = isCredit
                                        ? AppTheme.warning
                                        : (isDebit ? AppTheme.accent : AppTheme.success);
                                    final balLabel = isCredit
                                        ? 'مستحق له (دائن)'
                                        : (isDebit ? 'مسدد مقدماً (مدين)' : 'خالص (لا يوجد مديونية)');

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: isDark ? AppTheme.accent.withAlpha(80) : const Color(0xFFCBD5E1)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.local_shipping,
                                                  color: AppTheme.accent, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'مقاول النقل: ${transSupplier.displayName}',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.white : Colors.black,
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedSupplierId = null;
                                                    selectedSupplierName = null;
                                                    supplierSearchCtrl.clear();
                                                    supplierCurrency = 'EGP';
                                                    exchangeRateCtrl.text = '';
                                                  });
                                                },
                                                child: const Icon(Icons.close,
                                                    color: AppTheme.danger, size: 16),
                                              ),
                                            ],
                                          ),
                                          Divider(
                                              color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 14),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.account_balance_wallet_outlined,
                                                      color: AppTheme.textSecondary,
                                                      size: 14),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'الرصيد المالي الحالي:',
                                                    style: TextStyle(
                                                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                      fontWeight: FontWeight.bold,
                                                      fontFamily: 'Cairo',
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: balColor.withAlpha(25),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: balColor.withAlpha(80)),
                                                ),
                                                child: Text(
                                                  '${NumberFormat('#,##0.00').format(bal.abs())} ج.م ($balLabel)',
                                                  style: TextStyle(
                                                    color: balColor,
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Builder(
                                            builder: (_) {
                                              final effTruckBalance = _getRemainingTruckBalance(selectedSupplierId, excludeItemIndex: index);

                                              return Column(
                                                children: [
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.local_shipping_outlined,
                                                              color: Color(0xFF00B4D8),
                                                              size: 14),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            'مخزون النقلات المتاحة:',
                                                            style: TextStyle(
                                                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                              fontWeight: FontWeight.bold,
                                                              fontFamily: 'Cairo',
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: (effTruckBalance > 0
                                                                  ? AppTheme.success
                                                                  : (effTruckBalance < 0
                                                                      ? AppTheme.danger
                                                                      : AppTheme.textSecondary))
                                                              .withAlpha(25),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(
                                                              color: (effTruckBalance > 0
                                                                      ? AppTheme.success
                                                                      : (effTruckBalance < 0
                                                                          ? AppTheme.danger
                                                                          : AppTheme.textSecondary))
                                                                  .withAlpha(80)),
                                                        ),
                                                        child: Text(
                                                          '${effTruckBalance % 1 == 0 ? effTruckBalance.toInt() : effTruckBalance.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                                                          style: TextStyle(
                                                            color: effTruckBalance > 0
                                                                ? AppTheme.success
                                                                : (effTruckBalance < 0
                                                                    ? AppTheme.danger
                                                                    : (isDark ? Colors.white70 : Colors.black87)),
                                                            fontFamily: 'Cairo',
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (effTruckBalance <= 0) ...[
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.warning.withAlpha(20),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(
                                                            color: AppTheme.warning.withAlpha(60)),
                                                      ),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.info_outline,
                                                              color: AppTheme.warning, size: 14),
                                                          SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              'ملاحظة: لا يوجد رصيد نقلات متاح مسبقاً. سيتم تسجيل استهلاك نقلة وتحميلها على أمر التعبئة دون ازدواج مالي.',
                                                              style: TextStyle(
                                                                color: AppTheme.warning,
                                                                fontFamily: 'Cairo',
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                           _buildTransportBatchSection(
                                             isDark: isDark,
                                             isLoadingBatches: isLoadingBatches,
                                             batches: transportBatches,
                                             selectedBatch: selectedTransportBatch,
                                             onBatchChanged: (newB) {
                                               setDialogState(() {
                                                 selectedTransportBatch = newB;
                                                 if (newB != null) {
                                                   final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;
                                                   final autoCost = q * newB.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                             onSelectQuickQty: (q) {
                                               setDialogState(() {
                                                 qtyCtrl.text = q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
                                                 if (selectedTransportBatch != null) {
                                                   final autoCost = q * selectedTransportBatch!.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                           ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : supplierType == 'station'
                                  ? Builder(
                                      builder: (ctx) {
                                        final s = _suppliers.firstWhere(
                                          (sup) => sup.id == selectedSupplierId,
                                          orElse: () => SupplierModel(name: '', supplierCode: ''),
                                        );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF059669).withAlpha(80)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.factory_rounded, color: Color(0xFF059669), size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('مورد المحطة: ${s.displayName}',
                                                        style: TextStyle(
                                                            color: isDark ? Colors.white : Colors.black,
                                                            fontWeight: FontWeight.bold,
                                                            fontFamily: 'Cairo',
                                                            fontSize: 13)),
                                                    if (s.categories.isNotEmpty) ...[
                                                      Builder(
                                                        builder: (_) {
                                                          final selectedCatName = categories[selectedCategoryId] ?? '';
                                                          final matchingCats = s.categories.where((c) =>
                                                              c.trim().toLowerCase() == selectedCatName.trim().toLowerCase() ||
                                                              c.trim().toLowerCase().contains(selectedCatName.trim().toLowerCase()) ||
                                                              selectedCatName.trim().toLowerCase().contains(c.trim().toLowerCase())
                                                          ).toList();
                                                          final displayCats = matchingCats.isNotEmpty ? matchingCats : s.categories;
                                                          final isFiltered = matchingCats.isNotEmpty && matchingCats.length < s.categories.length;
                                                          return Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  isFiltered
                                                                      ? 'الخدمة المحددة: ${displayCats.join(' • ')}'
                                                                      : 'الخدمات: ${displayCats.join(' • ')}',
                                                                  style: TextStyle(
                                                                    color: const Color(0xFF059669),
                                                                    fontSize: 11,
                                                                    fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                                                                    fontFamily: 'Cairo',
                                                                  ),
                                                                ),
                                                              ),
                                                              if (isFiltered)
                                                                Container(
                                                                  margin: const EdgeInsets.only(right: 4),
                                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                  decoration: BoxDecoration(
                                                                    color: const Color(0xFF059669).withAlpha(20),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                    border: Border.all(color: const Color(0xFF059669).withAlpha(60)),
                                                                  ),
                                                                  child: Text(
                                                                    '+${s.categories.length - matchingCats.length} أخرى',
                                                                    style: const TextStyle(
                                                                      color: Color(0xFF059669),
                                                                      fontSize: 9,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontFamily: 'Cairo',
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedSupplierId = null;
                                                    selectedSupplierName = null;
                                                    supplierSearchCtrl.clear();
                                                    supplierCurrency = 'EGP';
                                                    exchangeRateCtrl.text = '';
                                                  });
                                                },
                                                child: const Icon(Icons.close, color: AppTheme.danger, size: 16),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    )
                                  : supplierType == 'deduction'
                                      ? Builder(
                                          builder: (ctx) {
                                            final s = _suppliers.firstWhere(
                                              (sup) => sup.id == selectedSupplierId,
                                              orElse: () => SupplierModel(name: '', supplierCode: ''),
                                            );
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF0F2338) : const Color(0xFFFAF5FF),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.assignment_rounded, color: Color(0xFF7C3AED), size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('مورد التخصيمات: ${s.displayName}',
                                                            style: TextStyle(
                                                                color: isDark ? Colors.white : Colors.black,
                                                                fontWeight: FontWeight.bold,
                                                                fontFamily: 'Cairo',
                                                                fontSize: 13)),
                                                        if (s.categories.isNotEmpty) ...[
                                                          Builder(
                                                            builder: (_) {
                                                              final selectedCatName = categories[selectedCategoryId] ?? '';
                                                              final matchingCats = s.categories.where((c) =>
                                                                  c.trim().toLowerCase() == selectedCatName.trim().toLowerCase() ||
                                                                  c.trim().toLowerCase().contains(selectedCatName.trim().toLowerCase()) ||
                                                                  selectedCatName.trim().toLowerCase().contains(c.trim().toLowerCase())
                                                              ).toList();
                                                              final displayCats = matchingCats.isNotEmpty ? matchingCats : s.categories;
                                                              final isFiltered = matchingCats.isNotEmpty && matchingCats.length < s.categories.length;
                                                              return Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      isFiltered
                                                                          ? 'البند المحدد: ${displayCats.join(' • ')}'
                                                                          : 'بنود التخصيم: ${displayCats.join(' • ')}',
                                                                      style: TextStyle(
                                                                        color: const Color(0xFF7C3AED),
                                                                        fontSize: 11,
                                                                        fontWeight: isFiltered ? FontWeight.bold : FontWeight.w600,
                                                                        fontFamily: 'Cairo',
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  if (isFiltered)
                                                                    Container(
                                                                      margin: const EdgeInsets.only(right: 4),
                                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0xFF7C3AED).withAlpha(20),
                                                                        borderRadius: BorderRadius.circular(4),
                                                                        border: Border.all(color: const Color(0xFF7C3AED).withAlpha(60)),
                                                                      ),
                                                                      child: Text(
                                                                        '+${s.categories.length - matchingCats.length} أخرى',
                                                                        style: const TextStyle(
                                                                          color: Color(0xFF7C3AED),
                                                                          fontSize: 9,
                                                                          fontWeight: FontWeight.bold,
                                                                          fontFamily: 'Cairo',
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        selectedSupplierId = null;
                                                        selectedSupplierName = null;
                                                        supplierSearchCtrl.clear();
                                                        supplierCurrency = 'EGP';
                                                        exchangeRateCtrl.text = '';
                                                      });
                                                    },
                                                    child: const Icon(Icons.close, color: AppTheme.danger, size: 16),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        )
                                      : Row(
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: AppTheme.success, size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'تم اختيار: ${_suppliers.firstWhere((s) => s.id == selectedSupplierId, orElse: () => SupplierModel(name: '', supplierCode: '')).displayName}',
                                                style: const TextStyle(
                                                    color: AppTheme.success,
                                                    fontSize: 11,
                                                    fontFamily: 'Cairo'),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                setDialogState(() {
                                                  selectedSupplierId = null;
                                                  selectedSupplierName = null;
                                                  supplierSearchCtrl.clear();
                                                  supplierCurrency = 'EGP';
                                                  isMultiCurrencySupplier = false;
                                                  supplierSupportedCurrencies = [];
                                                  exchangeRateCtrl.text = '';
                                                  isFetchingRate = false;
                                                });
                                              },
                                              child: const Icon(Icons.close,
                                                  color: AppTheme.danger, size: 14),
                                            ),
                                          ],
                                        ),
                        ),
                      if (selectedSupplierId != null && supplierType != 'transport') ...[
                        if (isMultiCurrencySupplier) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: supplierSupportedCurrencies.contains(supplierCurrency)
                                ? supplierCurrency
                                : (supplierSupportedCurrencies.isNotEmpty
                                    ? supplierSupportedCurrencies.first
                                    : 'EGP'),
                            dropdownColor: isDark ? const Color(0xFF0F2338) : Colors.white,
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                            decoration: _inputDecoration('عملة التعامل للبند *')
                                .copyWith(
                              prefixIcon: const Icon(Icons.currency_exchange,
                                  color: AppTheme.primary, size: 18),
                            ),
                            items: supplierSupportedCurrencies.map((cur) {
                              final sym = SupplierModel.getCurrencySymbol(cur);
                              return DropdownMenuItem<String>(
                                value: cur,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(cur,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo')),
                                    const SizedBox(width: 8),
                                    Text('($sym)',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppTheme.textSecondary : Colors.black54,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo')),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (newCur) {
                              if (newCur != null) {
                                onCurrencyChanged(newCur);
                              }
                            },
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isDark ? AppTheme.primary.withAlpha(60) : const Color(0xFF93C5FD)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'مورد متعدد العملات — العملة المختارة: $supplierCurrency (${SupplierModel.getCurrencySymbol(supplierCurrency)})',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                      fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.primary.withAlpha(25) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: isDark ? AppTheme.primary.withAlpha(80) : const Color(0xFF93C5FD)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline,
                                    size: 16, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'عملة المورد: $supplierCurrency (${SupplierModel.getCurrencySymbol(supplierCurrency)})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withAlpha(40),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    SupplierModel.getCurrencySymbol(supplierCurrency),
                                    style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (supplierCurrency != 'EGP') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: exchangeRateCtrl,
                            decoration: _inputDecoration(
                                    'سعر الصرف ($supplierCurrency → ج.م) *')
                                .copyWith(
                              prefixIcon: const Icon(Icons.trending_up,
                                  color: AppTheme.accent, size: 18),
                              suffixIcon: isFetchingRate
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.primary),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.sync,
                                          color: AppTheme.primary, size: 18),
                                      tooltip: 'تحديث سعر الصرف الحي',
                                      onPressed: refreshRate,
                                    ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*$'))
                            ],
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 15),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          if (rate > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 6),
                              child: Text(
                                'السعر الفوري: 1 $supplierCurrency = ${rate.toStringAsFixed(4)} ج.م',
                                style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'عدد النقلات المسحوبة من الدفعة (مثال: 0.5، 1، 1.5) *'
                                    : 'الكمية')
                            .copyWith(
                          helperText: isTransport
                              ? (selectedTransportBatch != null
                                  ? 'تكلفة النقلة بالدفعة: ${selectedTransportBatch!.formattedCostPerTruck} ج.م (المتاح: ${selectedTransportBatch!.formattedAvailableTrucks} نقلة)'
                                  : 'تُخصم من مخزون نقلات المورد (يدعم 0.5، 1.5 نقلة)')
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) {
                          if (isTransport && selectedTransportBatch != null) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            if (q > 0) {
                              final autoCost = q * selectedTransportBatch!.costPerTruck;
                              priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                            }
                          }
                          setDialogState(() {});
                        },
                      ),
                      if (isTransport && selectedTransportBatch != null) ...[
                        const SizedBox(height: 6),
                        Builder(
                          builder: (_) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            final isOver = q > (selectedTransportBatch!.availableTrucks + 0.0001);
                            final rem = (selectedTransportBatch!.availableTrucks - q).clamp(0.0, double.infinity);
                            if (isOver) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.danger.withAlpha(80)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'تنبيه: الكمية المطلوبة ($q نقلة) تتجاوز الرصيد المتاح في هذه الدفعة (${selectedTransportBatch!.formattedAvailableTrucks} نقلة)!',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.success.withAlpha(60)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'الحسبة: $q نقلة × ${selectedTransportBatch!.formattedCostPerTruck} ج.م = ${(q * selectedTransportBatch!.costPerTruck).toStringAsFixed(2)} ج.م | المتبقي في الدفعة: ${rem % 1 == 0 ? rem.toInt() : rem.toStringAsFixed(2)} نقلة',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: priceCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'تكلفة البند (إجمالي تكلفة النقل بالجنيه) *'
                                    : 'سعر الوحدة (${SupplierModel.getCurrencySymbol(supplierCurrency)}) *')
                            .copyWith(
                          helperText: isTransport
                              ? 'التكلفة المباشرة المضافة على أمر التعبئة (مستقلة عن عدد النقلات)'
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.success : const Color(0xFF059669)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (isInsufficientBalance) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withAlpha(35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.danger.withAlpha(90)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppTheme.danger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'تنبيه: المبلغ الإجمالي للبند (${totalInSupplierCurrency.toStringAsFixed(2)} $supplierCurrency) أكبر من الرصيد المتوفر في $sourceName (${availableBalance.toStringAsFixed(2)} $supplierCurrency)',
                                  style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo'),
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (selectedSupplierId != null &&
                          supplierCurrency != 'EGP') ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: isDark ? AppTheme.info.withAlpha(60) : const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                'المبلغ بالعملة الأصلية ($supplierCurrency)',
                                '${totalInSupplierCurrency.toStringAsFixed(2)} ${SupplierModel.getCurrencySymbol(supplierCurrency)}',
                                valueColor: AppTheme.info,
                              ),
                              Divider(
                                  color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0), height: 12),
                              _infoRow(
                                'المعادل بالجنيه المصري (EGP)',
                                '${totalEgp.toStringAsFixed(2)} ج.م',
                                valueColor: AppTheme.accent,
                              ),
                              if (rate > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'سعر الصرف المطبق:',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    Text(
                                      '1 $supplierCurrency = ${rate.toStringAsFixed(4)} ج.م',
                                      style: const TextStyle(
                                        color: AppTheme.success,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (selectedSupplierId != null &&
                          supplierCurrency == 'EGP' &&
                          (isTransport ? (price > 0) : (qty > 0 && price > 0))) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F2338) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                isTransport ? 'تكلفة النقل المضافة لأمر التعبئة' : 'إجمالي البند',
                                '${totalEgp.toStringAsFixed(2)} ج.م',
                                valueColor: AppTheme.accent,
                              ),
                              if (isTransport && qty > 0) ...[
                                const SizedBox(height: 4),
                                _infoRow(
                                  'النقلات المستهلكة من الرصيد',
                                  '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                                  valueColor: const Color(0xFF00B4D8),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                    if (!isAdmin && !isEngineer) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: _inputDecoration('البيان / تفاصيل وملاحظات البند').copyWith(
                          prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.primary, size: 18),
                          hintText: 'اكتب بيان أو تفاصيل إضافية للبند المحاسبي (اختياري)...',
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                    const SizedBox(height: 14),
                      _buildAllocationMethodPicker(
                        selectedCode: selectedAllocationMethod,
                        showAdvanced: showAdvancedMethods,
                        onToggleAdvanced: () => setDialogState(
                            () => showAdvancedMethods = !showAdvancedMethods),
                        onChanged: (code) => setDialogState(() {
                          selectedAllocationMethod = code;
                          if (code != 'MANUAL') {
                            selectedTargetLineIndex = null;
                          } else if (selectedTargetLineIndex == null && _lotEntries.isNotEmpty) {
                            selectedTargetLineIndex = 0;
                          }
                        }),
                      ),
                      if (selectedAllocationMethod == 'MANUAL') ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: selectedTargetLineIndex,
                          decoration: _inputDecoration('تحميل على محصول / مركز تكلفة محدد'),
                          dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: [
                            for (int li = 0; li < _lotEntries.length; li++)
                              DropdownMenuItem<int>(
                                value: li,
                                child: Text(
                                  'خط ${_lotEntries[li].lot?.productName ?? 'محصول #${li + 1}'}',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedTargetLineIndex = v),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () {
                        final isEngineer = supplierType == 'engineer';
                        final isAdmin = supplierType == 'admin';
                        final rate = double.tryParse(exchangeRateCtrl.text
                                .trim()
                                .replaceAll(',', '.')) ??
                            (supplierCurrency == 'EGP' ? 1.0 : 0.0);
                        final isTransport = supplierType == 'transport' ||
                            _transportSuppliers.any((ts) => ts.id.toString() == selectedSupplierId);
                        final totalInSupplierCurrency = (isTransport || isAdmin || isEngineer) ? price : (qty * price);
                        final totalInEgp = (isTransport || isAdmin || isEngineer)
                            ? price
                            : (supplierCurrency == 'EGP'
                                ? totalInSupplierCurrency
                                : (rate > 0
                                    ? CurrencyConversionService.instance
                                        .toBase(totalInSupplierCurrency, supplierCurrency, rate)
                                    : 0.0));
                        int? transportCatId;
                        if (isTransport) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('نقل') || cName.contains('لوجستيك') || cName.contains('logistics')) {
                              transportCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        int? adminCatId;
                        if (isAdmin) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('إدار') || cName.contains('ادار') || c['supplier_type'] == 'admin') {
                              adminCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        int? engineerCatId;
                        if (isEngineer) {
                          for (final c in _costCategories) {
                            final cName = (c['name'] as String? ?? '').toLowerCase();
                            if (cName.contains('مهندس') || cName.contains('مهندسين')) {
                              engineerCatId = c['id'] as int?;
                              break;
                            }
                          }
                        }
                        final effectiveCategoryId = isEngineer
                            ? engineerCatId
                            : (isAdmin
                                ? (adminCatId ?? (selectedCategoryId == 31251 ? null : selectedCategoryId))
                                : (isTransport ? (transportCatId ?? selectedCategoryId) : (selectedCategoryId == 31251 ? null : selectedCategoryId)));
                        final selectedCategoryName = isEngineer
                            ? 'مصاريف مهندسين'
                            : (isAdmin
                                ? 'مصاريف إدارية'
                                : (isTransport
                                    ? 'لوجستيك ونقل'
                                    : (filteredCategories[selectedCategoryId] ??
                                        categories[selectedCategoryId] ??
                                        (supplierType == 'station'
                                            ? 'خدمات محطة'
                                            : (supplierType == 'deduction'
                                                ? 'تخصيمات'
                                                : 'أخرى')))));
                        final isStation = supplierType == 'station' ||
                            _suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'station' || s.isStationSupplier));
                        final isDeduction = supplierType == 'deduction' ||
                            _suppliers.any((s) => s.id == selectedSupplierId && (s.supplierType == 'deduction' || s.isDeductionSupplier));
                        final effectiveSupplierType = isEngineer
                            ? 'engineer'
                            : (isAdmin
                                ? 'admin'
                                : (isTransport
                                    ? 'transport'
                                    : (isStation ? 'station' : (isDeduction ? 'deduction' : 'general'))));
                        final effectiveTruckCount = isTransport
                            ? (qty > 0 ? qty : 0.0)
                            : null;
                        final effectiveTransportSupplierId = isTransport
                            ? int.tryParse(selectedSupplierId ?? '')
                            : null;

                        final targetProduct = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? (_lotEntries[selectedTargetLineIndex!].lot?.productName ??
                               _lotEntries[selectedTargetLineIndex!].batch?.productName)
                            : null;
                        final targetProductId = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? (_lotEntries[selectedTargetLineIndex!].lot?.fruitTypeId ??
                               _lotEntries[selectedTargetLineIndex!].batch?.id?.toString())
                            : null;
                        final targetProductCode = (selectedAllocationMethod == 'MANUAL' &&
                                selectedTargetLineIndex != null &&
                                selectedTargetLineIndex! >= 0 &&
                                selectedTargetLineIndex! < _lotEntries.length)
                            ? _lotEntries[selectedTargetLineIndex!].batch?.productCode
                            : null;

                        final resolvedCc = targetProduct != null
                            ? CostCenterHelper.fromId(targetProduct, _costCenters)
                            : null;
                        final costCenterId = isEngineer
                            ? 'CC-ENG-EXP'
                            : (resolvedCc?.id ?? (targetProduct != null
                                ? 'CC-${targetProductCode ?? targetProduct}'
                                : (isAdmin ? 'CC-ADMIN-EXPENSES' : (selectedAllocationMethod == 'EQUAL' ? 'ALL' : null))));
                        final costCenterName = isEngineer
                            ? 'مصاريف مهندسين وإشراف'
                            : (resolvedCc?.nameAr ?? (targetProduct != null
                                ? '${CostCenter.canonicalCropName(targetProduct)} (موسم 2026-2027)'
                                : (isAdmin ? 'مصاريف إدارية' : (selectedAllocationMethod == 'EQUAL' ? 'توزيع بالتساوي على كل المنتجات' : null))));

                        setState(() {
                          _costItems[index] = {
                            if (item['id'] != null) 'id': item['id'],
                            'item_uuid': item['item_uuid'] ?? const Uuid().v4(),
                            if (item['variance_journal_entry_id'] != null)
                              'variance_journal_entry_id': item['variance_journal_entry_id'],
                            if (item['settlement_journal_entry_id'] != null)
                              'settlement_journal_entry_id': item['settlement_journal_entry_id'],
                            if (item['journal_entry_id'] != null)
                              'journal_entry_id': item['journal_entry_id'],
                            if (item['currency_snapshot'] != null)
                              'currency_snapshot': item['currency_snapshot'],
                            if (item['variance_cleared_at'] != null)
                              'variance_cleared_at': item['variance_cleared_at'],
                            if (item['variance_cleared_by'] != null)
                              'variance_cleared_by': item['variance_cleared_by'],
                            'name': name,
                            'category': isEngineer
                                ? 'engineer_expenses'
                                : (isAdmin
                                    ? 'admin'
                                    : (isTransport
                                        ? 'logistics'
                                        : _costCategoryDbKey(selectedCategoryName))),
                            'category_name': selectedCategoryName,
                            'report_category_id': effectiveCategoryId,
                            'supplier_type': effectiveSupplierType,
                            'supplier_id': isAdmin ? null : selectedSupplierId,
                            'transport_supplier_id': effectiveTransportSupplierId,
                            'truck_count': effectiveTruckCount,
                            'transport_batch_id': isTransport ? (selectedTransportBatch?.id ?? item['transport_batch_id']) : null,
                            'transport_batch_desc': isTransport ? (selectedTransportBatch?.description ?? item['transport_batch_desc']) : null,
                            'transport_batch_cost_per_truck': isTransport ? (selectedTransportBatch?.costPerTruck ?? item['transport_batch_cost_per_truck']) : null,
                            'transport_batch_ref': isTransport ? (selectedTransportBatch?.referenceId ?? item['transport_batch_ref']) : null,
                            'transport_batch_available': isTransport ? (selectedTransportBatch?.availableTrucks ?? item['transport_batch_available']) : null,
                            'custody_id': isEngineer ? null : item['custody_id'],
                            'engineer_name': isEngineer ? 'مجمع عهد الموظفين' : item['engineer_name'],
                            'is_engineer_cost_settled': isEngineer ? true : (item['is_engineer_cost_settled'] ?? false),
                            'allocation_type': isEngineer ? (isEngineerPercentageMode ? 'percentage' : 'fixed') : item['allocation_type'],
                            'allocation_percentage': isEngineer && isEngineerPercentageMode ? double.tryParse(engineerPercentageCtrl.text) : item['allocation_percentage'],
                            'pool_total_spent': isEngineer ? custodyPoolSummary?.totalSpent : item['pool_total_spent'],
                            'pool_total_allocated': isEngineer ? custodyPoolSummary?.totalAllocated : item['pool_total_allocated'],
                            'pool_remaining_pool': isEngineer ? custodyPoolSummary?.remainingPool : item['pool_remaining_pool'],
                            'expense_account_id': isEngineer ? null : item['expense_account_id'],
                            'expense_account_name': isEngineer ? null : item['expense_account_name'],
                            'expense_account_code': isEngineer ? null : item['expense_account_code'],
                            'supplier_name': isAdmin ? '' : (isEngineer ? 'مجمع عهد الموظفين' : (selectedSupplierName ?? item['supplier_name'] ?? '')),
                            'quantity': (isAdmin || isEngineer) ? 1.0 : qty,
                            'unit_price': (isTransport || isAdmin || isEngineer) ? price : price,
                            'total': (isAdmin || isEngineer) ? price : totalInSupplierCurrency,
                            'total_egp': (isAdmin || isEngineer) ? price : totalInEgp,
                            'exchange_rate': 1.0,
                            'supplier_currency': 'EGP',
                            'ledger_entry_id': item['ledger_entry_id'],
                            'payment_source_type': (isEngineer || isAdmin)
                                ? null
                                : (paymentSourceType == 'none' ? null : paymentSourceType),
                            'payment_source_id': (isEngineer || isAdmin)
                                ? null
                                : (paymentSourceType == 'none' ? null : selectedPaymentSourceId),
                            'allocation_method': selectedAllocationMethod,
                            'target_line_index':
                                selectedAllocationMethod == 'MANUAL'
                                    ? selectedTargetLineIndex
                                    : null,
                            'target_product_name': targetProduct,
                            'target_product_id': targetProductId,
                            'cost_center_id': costCenterId,
                            'cost_center_name': costCenterName,
                            'notes': notesCtrl.text.trim(),
                            'cost_status': (isTransport || isEngineer)
                                ? 'actual'
                                : (isAdmin
                                    ? ((item['cost_status'] == 'settled' || item['reconciled_at'] != null) && item['actual_amount'] != null ? 'actual' : 'expected')
                                    : (item['cost_status'] ??
                                        ((effectiveSupplierType == 'station' || effectiveSupplierType == 'deduction')
                                            ? 'expected'
                                            : 'actual'))),
                            'expected_amount': (isTransport || isEngineer)
                                ? totalInEgp
                                : ((effectiveSupplierType == 'station' || effectiveSupplierType == 'deduction')
                                    ? (item['expected_amount'] ?? totalInEgp)
                                    : (isAdmin ? price : totalInEgp)),
                            'actual_amount': (isTransport || isEngineer)
                                ? totalInEgp
                                : (isAdmin
                                    ? ((item['cost_status'] == 'settled' || item['reconciled_at'] != null) ? item['actual_amount'] : null)
                                    : ((effectiveSupplierType == 'station' || effectiveSupplierType == 'deduction')
                                        ? item['actual_amount']
                                        : (isAdmin ? price : totalInEgp))),
                            'variance_amount': isTransport ? 0.0 : (item['variance_amount'] ?? 0.0),
                            'invoice_ref': item['invoice_ref'],
                          };
                        });
                        Navigator.pop(ctx);
                        _syncFormStateToDb().then((_) {
                          _loadVarianceReport();
                          DataChangeEventBus.instance.notifyTransportSuppliersChanged();
                          DataChangeEventBus.instance.notifySuppliersChanged();
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppTheme.primary
                      : AppTheme.textSecondary.withAlpha(80),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text('حفظ التعديلات',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEngineerCostSettlementDialog(Map<String, dynamic> item, int index) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemName = item['name']?.toString() ?? 'مصاريف مهندسين';
    final engineerName = item['engineer_name']?.toString() ??
        item['supplier_name']?.toString() ??
        'عهدة مهندس';
    final custodyIdRaw = item['custody_id'] ??
        (item['payment_source_type'] == 'treasury' ? item['payment_source_id'] : item['supplier_id']);
    final int? custodyId = custodyIdRaw is int
        ? custodyIdRaw
        : int.tryParse(custodyIdRaw?.toString() ?? '');

    Map<String, dynamic> custody = {};
    if (custodyId != null) {
      custody = _treasuries.firstWhere(
        (t) => t['id'] == custodyId || t['id']?.toString() == custodyId.toString(),
        orElse: () => <String, dynamic>{},
      );
    }

    double custodyBal = 0.0;
    if (custodyId != null) {
      final info = await fetchCustodyBalanceInfo(custodyId);
      if (info.isNotEmpty && info['balance'] != null) {
        custodyBal = (info['balance'] as num).toDouble();
      } else if (custody.isNotEmpty) {
        final bList = custody['treasury_balances'];
        if (bList is List && bList.isNotEmpty) {
          final egpBal = bList.firstWhere(
            (b) => b['currency'] == 'EGP',
            orElse: () => bList.first,
          );
          custodyBal = (egpBal['balance'] as num?)?.toDouble() ?? 0.0;
        } else if (custody['balance'] != null) {
          custodyBal = (custody['balance'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final double estimatedAmt = (item['expected_amount'] as num?)?.toDouble() ??
        ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();
    final double initialActual = (item['actual_amount'] as num?)?.toDouble() ?? estimatedAmt;

    final actualAmtCtrl = TextEditingController(text: initialActual.toStringAsFixed(2));
    final invoiceRefCtrl = TextEditingController(text: item['invoice_ref']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: item['notes']?.toString() ?? '');

    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final double enteredActual = double.tryParse(actualAmtCtrl.text.trim()) ?? estimatedAmt;
            final double variance = enteredActual - estimatedAmt;
            final bool canSubmit = !isSubmitting && enteredActual >= 0;

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0F1E2E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.engineering_outlined, color: Color(0xFFF59E0B), size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تسوية مصاريف المهندس الفعلية والعهدة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'بند التكلفة: $itemName',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: isDark ? AppTheme.textMuted : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Custody Info Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('الموظف / المهندس المسؤول:',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(engineerName,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF59E0B))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('التكلفة التقديرية المحملة على الأمر:',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
                                Text('${estimatedAmt.toStringAsFixed(2)} ج.م',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accent)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('فرع التوجيه المحاسبي (المدين):',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(
                                  item['expense_account_name'] != null
                                      ? '${item['expense_account_code'] != null ? "[${item['expense_account_code']}] " : ""}${item['expense_account_name']}'
                                      : '31251 - مصاريف مهندسين وإشراف',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF59E0B)),
                                ),
                              ],
                            ),
                            if (custody.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('رصيد عهدة الموظف الحالي:',
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600)),
                                  Text('${custodyBal.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: custodyBal >= 0 ? AppTheme.success : AppTheme.danger)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Actual Amount Input
                      TextField(
                        controller: actualAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                        decoration: InputDecoration(
                          labelText: 'المبلغ الفعلي بالفواتير والمستندات (ج.م) *',
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          suffixText: 'ج.م',
                          prefixIcon: const Icon(Icons.receipt, color: Color(0xFFF59E0B)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF07213D) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        onChanged: (_) => setDlgState(() {}),
                      ),
                      const SizedBox(height: 12),

                      // Dynamic Variance & Accounting Impact Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: variance == 0
                              ? AppTheme.info.withAlpha(20)
                              : (variance > 0 ? AppTheme.warning.withAlpha(20) : AppTheme.success.withAlpha(20)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: variance == 0
                                ? AppTheme.info.withAlpha(60)
                                : (variance > 0 ? AppTheme.warning.withAlpha(80) : AppTheme.success.withAlpha(80)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  variance == 0
                                      ? Icons.check_circle_outline
                                      : (variance > 0 ? Icons.arrow_upward : Icons.arrow_downward),
                                  size: 18,
                                  color: variance == 0
                                      ? AppTheme.info
                                      : (variance > 0 ? const Color(0xFFF59E0B) : AppTheme.success),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  variance == 0
                                      ? 'الفارق: 0.00 ج.م (مطابق للتقديري تماماً)'
                                      : 'الفارق: ${variance > 0 ? "+" : ""}${variance.toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: variance == 0
                                        ? AppTheme.info
                                        : (variance > 0 ? const Color(0xFFF59E0B) : AppTheme.success),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              variance == 0
                                  ? '• تم اعتماد المصروف الفعلي المطابق، ولن يتغير رصيد عهدة الموظف.'
                                  : (variance > 0
                                      ? '• زيادة تكلفة: تم صرف ${variance.toStringAsFixed(2)} ج.م زيادة عن التقديري. سيتم تحميل الفارق على تكلفة أمر التعبئة وقيد خصم إضافي من عهدة $engineerName.'
                                      : '• توفير في المصروف: تم توفير ${(-variance).toStringAsFixed(2)} ج.م. سيتم تخفيض تكلفة أمر التعبئة وإعادة الفارق (+${(-variance).toStringAsFixed(2)} ج.م) كرصيد في عهدة $engineerName.'),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.textSecondary : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Invoice Reference
                      TextField(
                        controller: invoiceRefCtrl,
                        decoration: InputDecoration(
                          labelText: 'رقم الفاتورة / المستند المؤيد للصرف',
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          prefixIcon: const Icon(Icons.tag, color: AppTheme.primary),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF07213D) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 12),

                      // Notes
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات وتفاصيل التسوية',
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          prefixIcon: const Icon(Icons.notes, color: AppTheme.primary),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF07213D) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: canSubmit
                      ? () async {
                          setDlgState(() => isSubmitting = true);
                          try {
                            final costItemId = (item['id'] as num?)?.toInt();
                            if (_orderId != null) {
                              final res = await _dao.settleEngineerCostItem(
                                packingOrderId: _orderId!,
                                costItemId: costItemId,
                                custodyId: custodyId,
                                expenseAccountId: (item['expense_account_id'] as num?)?.toInt(),
                                actualAmount: enteredActual,
                                invoiceRef: invoiceRefCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                              );
                              if (res['success'] != true) {
                                throw Exception(res['error'] ?? 'فشلت تسوية مصاريف المهندس');
                              }
                            }

                            setState(() {
                              _costItems[index]['actual_amount'] = enteredActual;
                              _costItems[index]['variance_amount'] = variance;
                              _costItems[index]['is_engineer_cost_settled'] = true;
                              _costItems[index]['cost_status'] = 'actual';
                              _costItems[index]['invoice_ref'] = invoiceRefCtrl.text.trim();
                              if (notesCtrl.text.trim().isNotEmpty) {
                                _costItems[index]['notes'] = notesCtrl.text.trim();
                              }
                            });

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تمت تسوية مصاريف المهندس بنجاح وتحديث العهدة وتكاليف أمر التعبئة ✓',
                                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            }
                            if (_orderId != null) {
                              await _loadData();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('خطأ في التسوية: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                  backgroundColor: AppTheme.danger,
                                ),
                              );
                            }
                          } finally {
                            if (ctx.mounted) {
                              setDlgState(() => isSubmitting = false);
                            }
                          }
                        }
                      : null,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('تأكيد تسوية العهدة',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMaterialRequirementsPreview() {
    final totalCartons = _lotEntries.fold<int>(0, (s, e) => s + e.cartonCount);
    final totalNetWeight =
        _lotEntries.fold<double>(0, (s, e) => s + e.totalNetWeight);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 14, color: AppTheme.warning),
              const SizedBox(width: 6),
              const Text('احتياجات المنتجات',
                  style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(_lotEntries.length, (i) {
            final entry = _lotEntries[i];
            final name = entry.lot?.productName ?? 'منتج #${i + 1}';
            final netW = entry.totalNetWeight;
            final grossW = entry.totalGrossWeight;
            final cartons = entry.cartonCount;
            final pct = totalCartons > 0 ? (cartons / totalCartons * 100) : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('#${i + 1}',
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Cairo')),
                      ),
                      Text('${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontFamily: 'Cairo')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildReqChip(
                          'الوزن الخام', '${grossW.toStringAsFixed(1)} كجم'),
                      const SizedBox(width: 8),
                      _buildReqChip(
                          'الوزن الصافي', '${netW.toStringAsFixed(1)} كجم'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildReqChip('الكراتين', '$cartons'),
                      const SizedBox(width: 8),
                      _buildReqChip('الاحتياج المتوقع', '$cartons كرتونة',
                          isHighlighted: true),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.summarize, size: 12, color: AppTheme.warning),
                const SizedBox(width: 4),
                Text(
                  'الإجمالي: $totalCartons كرتونة — ${totalNetWeight.toStringAsFixed(1)} كجم',
                  style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReqChip(String label, String value,
      {bool isHighlighted = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppTheme.success.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(4),
          border: isHighlighted
              ? Border.all(color: AppTheme.success.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 9,
                    fontFamily: 'Cairo')),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: isHighlighted
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      fontSize: 10,
                      fontFamily: 'Cairo',
                      fontWeight:
                          isHighlighted ? FontWeight.bold : FontWeight.normal),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    final calc = _calcResult;
    final w = calc.weights;
    final m = calc.materials;
    final c = calc.costItems;
    final f = calc.finalCost;

    final rawPricePerKg = w.totalEffectiveWeight > 0
        ? f.totalRawCost / w.totalEffectiveWeight
        : 0.0;

    final wastePercent = w.totalEffectiveWeight > 0
        ? (w.totalWasteWeight / w.totalEffectiveWeight * 100)
        : 0.0;

    final costPerKgBeforePacking =
        w.totalNetWeight > 0 ? f.fruitCost / w.totalNetWeight : 0.0;

    // Calculate total raw weight in kg (handles both weight and carton modes)
    final totalRawWeightKg = _lotEntries.fold(0.0, (sum, e) {
      if (e.isCartonMode) {
        // For carton mode: cartons used × net weight per carton
        return sum + e.effectiveWeight * e.exactCartonNetWeight;
      } else {
        // For weight mode: used quantity weight (effectiveWeight) in kg
        return sum + e.effectiveWeight;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ══════════════════════════════════════════════
        // █  القسم 1: المحاصيل والأوزان
        // ══════════════════════════════════════════════
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.info.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.info.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 14, color: AppTheme.info.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  const Text('المحاصيل والأوزان',
                      style: TextStyle(
                          color: AppTheme.info,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow('عدد المحاصيل', '${w.totalCrops}',
                  valueColor: AppTheme.info),
              for (int i = 0; i < _lotEntries.length; i++) ...[
                if (_lotEntries[i].lot != null ||
                    _lotEntries[i].fallbackProductName != null) ...[
                  const SizedBox(height: 4),
                  _infoRow(
                    '  المحصول #${i + 1}',
                    '${_lotEntries[i].lot?.productName ?? _lotEntries[i].fallbackProductName ?? "—"} — ${_lotEntries[i].cartonCount} كرتونة — ${_fmtWeight(_lotEntries[i].totalNetWeight)} كجم',
                    valueColor: AppTheme.textSecondary,
                  ),
                  if (_lotEntries[i].wasteCost > 0) ...[
                    const SizedBox(height: 2),
                    _infoRow(
                      '    تكلفة الهالك',
                      '${_fmtMoney(_lotEntries[i].wasteCost)} ج.م',
                      valueColor: AppTheme.danger,
                    ),
                  ]
                ],
              ],
              const SizedBox(height: 8),
              Container(
                  height: 1, color: AppTheme.info.withValues(alpha: 0.12)),
              const SizedBox(height: 8),
              _infoRow('إجمالي الخام', '${_fmtWeight(totalRawWeightKg)} كجم',
                  valueColor: AppTheme.info),
              const SizedBox(height: 4),
              _infoRow('إجمالي الصافي', '${_fmtWeight(w.totalNetWeight)} كجم',
                  valueColor: AppTheme.info),
              if (w.totalCartons > 0) ...[
                const SizedBox(height: 4),
                _infoRow('عدد الكراتين', '${w.totalCartons} كرتونة',
                    valueColor: AppTheme.info),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ══════════════════════════════════════════════
        // █  القسم 2: تفاصيل التكلفة
        // ══════════════════════════════════════════════
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate_outlined,
                      size: 14, color: AppTheme.warning.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  const Text('تفاصيل التكلفة',
                      style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),

              // ── قسم التكاليف ──
              _buildOriginalCurrencyCostRow(),
              const SizedBox(height: 6),

              // تكلفة الخام (أصفر)
              _infoRow(
                  'تكلفة الخام (الإجمالي)', '${_fmtMoney(f.totalRawCost)} ج.م',
                  valueColor: AppTheme.warning, bold: true),
              const SizedBox(height: 4),

              if (_totalWasteCost > 0) ...[
                _infoRow(
                    '(+) تكلفة الهالك', '${_fmtMoney(_totalWasteCost)} ج.م',
                    valueColor: AppTheme.danger),
                const SizedBox(height: 4),
              ],

              // (-) تكلفة الفرز (أصفر)
              if (w.totalSortedWeight > 0) ...[
                _infoRow(
                    '(-) تكلفة الفرز', '${_fmtMoney(_totalSortingCost)} ج.م',
                    valueColor: AppTheme.warning),
                const SizedBox(height: 4),
              ],

              // = تكلفة المنتج بعد الفرز والهالك (أصفر)
              if (w.totalSortedWeight > 0 || _totalWasteCost > 0) ...[
                _infoRow('= تكلفة المنتج بعد الفرز والهالك',
                    '${_fmtMoney(f.fruitCost + f.cropWasteCost)} ج.م',
                    valueColor: AppTheme.warning, bold: true),
                const SizedBox(height: 4),
              ],

              Container(
                  height: 1, color: AppTheme.warning.withValues(alpha: 0.12)),
              const SizedBox(height: 6),

              // تكلفة مواد التعبئة (أصفر)
              _infoRow('تكلفة مواد التعبئة', '${_fmtMoney(m.materialCost)} ج.م',
                  valueColor: AppTheme.warning),
              if (m.wasteCost > 0) ...[
                const SizedBox(height: 4),
                // + فاقد مواد التعبئة (أحمر)
                _infoRow(
                    '+ فاقد مواد التعبئة الفعلي (${_fmtPercent(m.wastePercent)}%)',
                    '${_fmtMoney(m.wasteCost)} ج.م',
                    valueColor: AppTheme.danger),
              ],
              const SizedBox(height: 4),

              Container(
                  height: 1, color: AppTheme.warning.withValues(alpha: 0.12)),
              const SizedBox(height: 6),

              // التكاليف الإضافية (أصفر)
              _infoRow(
                  'التكاليف الإضافية', '${_fmtMoney(c.totalCostItems)} ج.م',
                  valueColor: AppTheme.warning),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ══════════════════════════════════════════════
        // █  القسم 3: الإجمالي
        // ══════════════════════════════════════════════
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.summarize_outlined,
                      size: 14, color: AppTheme.success.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  const Text('الإجمالي',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              // إجمالي التكلفة (أخضر)
              _infoRow('إجمالي التكلفة', '${_fmtMoney(f.totalCost)} ج.م',
                  valueColor: AppTheme.success, bold: true),
              const SizedBox(height: 6),
              // تكلفة الكرتونة (أخضر)
              if (w.totalCartons > 0) ...[
                _infoRow('تكلفة الكرتونة', '${_fmtMoney(f.costPerCarton)} ج.م',
                    valueColor: AppTheme.success, bold: true),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),

        // ── جدول تكلفة المنتجات (للorder المتعدد) ──
        if (_lotEntries.length > 1) ...[
          const SizedBox(height: 16),
          _buildProductCostSummaryTable(),
        ],
      ],
    );
  }

  Widget _buildAllocationMethodPicker({
    required String selectedCode,
    required bool showAdvanced,
    required VoidCallback onToggleAdvanced,
    required ValueChanged<String> onChanged,
    List<CostAllocationMethod>? availableMethods,
  }) {
    final isDark = AppTheme.isDark(context);
    final methods = availableMethods ??
        [
          ...CostAllocationMethod.defaultMethods,
          if (showAdvanced) ...CostAllocationMethod.advancedMethods,
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('طريقة توزيع التكلفة',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontSize: 12,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...methods.map((m) {
          final isSelected = selectedCode == m.code;
          return Tooltip(
            message: m.tooltip,
            preferBelow: false,
            child: GestureDetector(
              onTap: () => onChanged(m.code),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFEFF6FF))
                      : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: isSelected ? AppTheme.primary : (isDark ? AppTheme.textMuted : Colors.black38),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m.label,
                          style: TextStyle(
                              color: isSelected
                                  ? (isDark ? AppTheme.textPrimary : Colors.black)
                                  : (isDark ? AppTheme.textSecondary : Colors.black87),
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600)),
                    ),
                    Icon(Icons.info_outline,
                        size: 14, color: isDark ? AppTheme.textMuted.withAlpha(120) : Colors.black38),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOriginalCurrencyCostRow() {
    final Map<String, double> currencyTotals = {};
    final Map<String, double> currencyRates = {};
    for (final e in _lotEntries) {
      final cur = e.lot?.currency ?? 'EGP';
      currencyTotals[cur] =
          (currencyTotals[cur] ?? 0) + e.originalCurrencyTotalCost;
      currencyRates[cur] = e.lot?.exchangeRate ?? 1.0;
    }
    if (currencyTotals.isEmpty) return const SizedBox.shrink();
    return Column(
      children: currencyTotals.entries.map((entry) {
        final cur = entry.key;
        final originalAmount = entry.value;
        final rate = currencyRates[cur] ?? 1.0;
        final egpAmount = originalAmount * rate;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _infoRow(
            'سعر المحصول',
            cur == 'EGP'
                ? '${_fmt(originalAmount)} ج.م'
                : '${_fmt(originalAmount)} ${AppUtils.currencySymbol(cur)} × ${_fmt(rate)} = ${_fmt(egpAmount)} ج.م',
            valueColor: AppTheme.info,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProductCostSummaryTable() {
    if (_lotEntries.length <= 1) return const SizedBox.shrink();
    final calc = _calcResult;
    final productLines = calc.productLines;
    if (productLines.isEmpty) return const SizedBox.shrink();

    // Debug verification
    PackingCalculationService.printDebugVerification(calc);

    final isDark = AppTheme.isDark(context);
    final hStyle = TextStyle(
        color: isDark ? AppTheme.textPrimary : Colors.black,
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    final vStyle = TextStyle(
        color: isDark ? AppTheme.textSecondary : Colors.black87,
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    const tStyle = TextStyle(
        color: AppTheme.primary,
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    final aStyle = TextStyle(
        color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.table_chart, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('ملخص تكلفة المنتجات',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder.withAlpha(60) : const Color(0xFFCBD5E1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowColor: WidgetStateProperty.all(
                  AppTheme.primary.withValues(alpha: 0.1)),
              columns: [
                DataColumn(label: Text('المنتج', style: hStyle)),
                DataColumn(label: Text('الكراتين', style: hStyle)),
                DataColumn(label: Text('الوزن الصافي', style: hStyle)),
                DataColumn(label: Text('تكلفة الخام الإجمالي', style: hStyle)),
                DataColumn(
                    label: Text('تكلفة الهالك',
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold))),
                DataColumn(label: Text('تكلفة الفرز', style: hStyle)),
                DataColumn(label: Text('تكلفة مواد التعبئة', style: hStyle)),
                DataColumn(
                    label: Text('فاقد المواد',
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold))),
                DataColumn(label: Text('بنود التكلفة', style: hStyle)),
                DataColumn(
                    label: Text('إجمالي تكلفة المنتج',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('تكلفة الكرتونة',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 10,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold))),
              ],
              rows: [
                for (int i = 0; i < productLines.length; i++)
                  DataRow(cells: [
                    DataCell(Text(
                      productLines[i].productName.isNotEmpty
                          ? productLines[i].productName
                          : '#${i + 1}',
                      style: vStyle,
                    )),
                    DataCell(
                        Text('${productLines[i].cartonCount}', style: vStyle)),
                    DataCell(Text(
                        '${_fmtWeight(productLines[i].totalNetWeight)} كجم',
                        style: vStyle)),
                    DataCell(Text(_fmtMoney(productLines[i].rawCost),
                        style: vStyle)),
                    DataCell(Text(_fmtMoney(productLines[i].wasteCost),
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 10,
                            fontFamily: 'Cairo'))),
                    DataCell(Text(
                        _fmtMoney(productLines[i].sortingContribution),
                        style: vStyle)),
                    DataCell(Text(_fmtMoney(productLines[i].packagingCost),
                        style: vStyle)),
                    DataCell(Text(_fmtMoney(productLines[i].packagingLoss),
                        style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 10,
                            fontFamily: 'Cairo'))),
                    DataCell(Text(_fmtMoney(productLines[i].extraCosts),
                        style: vStyle)),
                    DataCell(Text(_fmtMoney(productLines[i].finalCost),
                        style: aStyle)),
                    DataCell(Text(
                        _fmtMoney(productLines[i].cartonCount > 0
                            ? (productLines[i].finalCost /
                                productLines[i].cartonCount)
                            : 0),
                        style: aStyle)),
                  ]),
                // صف الإجمالي
                DataRow(cells: [
                  const DataCell(Text('الإجمالي', style: tStyle)),
                  DataCell(Text(
                      '${productLines.fold(0, (s, l) => s + l.cartonCount)}',
                      style: tStyle)),
                  DataCell(Text(
                      '${_fmtWeight(productLines.fold(0.0, (s, l) => s + l.totalNetWeight))} كجم',
                      style: tStyle)),
                  DataCell(Text(
                      _fmtMoney(
                          productLines.fold(0.0, (s, l) => s + l.rawCost)),
                      style: tStyle)),
                  DataCell(Text(
                      _fmtMoney(
                          productLines.fold(0.0, (s, l) => s + l.wasteCost)),
                      style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 10,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold))),
                  DataCell(Text(
                      _fmtMoney(productLines.fold(
                          0.0, (s, l) => s + l.sortingContribution)),
                      style: tStyle)),
                  DataCell(Text(
                      _fmtMoney(productLines.fold(
                          0.0, (s, l) => s + l.packagingCost)),
                      style: tStyle)),
                  DataCell(Text(
                      _fmtMoney(productLines.fold(
                          0.0, (s, l) => s + l.packagingLoss)),
                      style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: 10,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold))),
                  DataCell(Text(
                      _fmtMoney(
                          productLines.fold(0.0, (s, l) => s + l.extraCosts)),
                      style: tStyle)),
                  DataCell(Text(
                      _fmtMoney(
                          productLines.fold(0.0, (s, l) => s + l.finalCost)),
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 10,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold))),
                  const DataCell(Text('—',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'Cairo'))),
                ]),
              ],
            ),
          ),
        ),
        if (calc.allocationTraces.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildAllocationTraceSection(
              calc.allocationTraces, calc.productLines),
        ],
      ],
    );
  }

  Widget _buildAllocationTraceSection(
      List<AllocationTraceGroup> traces, List<ProductCostLine> productLines) {
    const hStyle = TextStyle(
        color: AppTheme.textMuted,
        fontSize: 9,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    const vStyle = TextStyle(
        color: AppTheme.textSecondary, fontSize: 9, fontFamily: 'Cairo');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree, size: 14, color: AppTheme.info),
            const SizedBox(width: 4),
            const Text('تفاصيل التوزيع',
                style: TextStyle(
                    color: AppTheme.info,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo')),
          ],
        ),
        const SizedBox(height: 6),
        for (final itemTrace in traces) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.glassBorder.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Item name + total ──
                Row(children: [
                  Icon(
                    itemTrace.itemType == 'material'
                        ? Icons.inventory_2
                        : Icons.receipt,
                    size: 12,
                    color: itemTrace.itemType == 'material'
                        ? AppTheme.warning
                        : AppTheme.info,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${itemTrace.itemName}',
                      style: TextStyle(
                        color: itemTrace.itemType == 'material'
                            ? AppTheme.warning
                            : AppTheme.info,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  Text(
                    '${_fmtMoney(itemTrace.totalAmount)} ج.م',
                    style: TextStyle(
                      color: itemTrace.itemType == 'material'
                          ? AppTheme.warning
                          : AppTheme.info,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ]),
                // ── Allocation method label ──
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 16),
                  child: Text(
                    'طريقة التوزيع: ${CostAllocationMethod.fromCode(itemTrace.allocationMethod).label}',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // ── Compact table ──
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      // Header row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        child: Row(children: [
                          Expanded(
                              flex: 3, child: Text('المحصول', style: hStyle)),
                          Expanded(
                              flex: 1, child: Text('النسبة', style: hStyle)),
                          Expanded(
                              flex: 2, child: Text('القيمة', style: hStyle)),
                        ]),
                      ),
                      Container(height: 0.5, color: AppTheme.glassBorder),
                      // Data rows
                      for (final e in itemTrace.rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          child: Row(children: [
                            Expanded(
                                flex: 3,
                                child: Text(
                                  () {
                                    final idx = e.lineIndex;
                                    final name = e.productName;
                                    final cartons = productLines.length > idx
                                        ? productLines[idx].cartonCount
                                        : 0;
                                    return 'المنتج #${idx + 1} - $name ($cartons كرتونة)';
                                  }(),
                                  style: vStyle,
                                )),
                            Expanded(
                                flex: 1,
                                child: Text(
                                  '${_fmtPercent(e.basisPercent)}%',
                                  style: vStyle,
                                )),
                            Expanded(
                                flex: 2,
                                child: Text(
                                  _fmtMoney(e.allocatedAmount),
                                  style: vStyle,
                                  textAlign: TextAlign.left,
                                )),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCostVarianceSection() {
    final isDark = AppTheme.isDark(context);
    if (_loadingVariance) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final report = _varianceReport;
    if (report == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: isDark ? AppTheme.textMuted : Colors.black45, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'لم يتم تحميل تقرير مقارنة التكاليف بعد',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _loadVarianceReport(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('تحميل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }

    final isConfirmed = report.isOrderConfirmed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Notice Banner ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isConfirmed
                ? AppTheme.primary.withValues(alpha: 0.08)
                : AppTheme.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isConfirmed
                  ? AppTheme.primary.withValues(alpha: 0.25)
                  : AppTheme.warning.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isConfirmed ? Icons.verified_outlined : Icons.schedule_outlined,
                color: isConfirmed ? AppTheme.primary : AppTheme.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isConfirmed
                      ? (_currentOrder?.isFinalApproved == true || report.orderStatus == 'completed'
                          ? 'أمر التعبئة معتمد ومقفل بالكامل. تُستخرج التكاليف الفعلية مباشرة من أذونات صرف المخزون وقيود اليومية واستحقاقات الموردين المعتمدة.'
                          : 'تم تأكيد مراحل من أمر التعبئة بنجاح (المرحلة الحالية: ${_currentOrder?.currentStageIndex ?? 1} من 4). البنود المصروفة تظهر بقيمتها الفعلية المثبتة من قيد الصرف المخزني.')
                      : 'أمر التعبئة ما زال بحالة (${report.orderStatus == 'draft' ? 'مسودة' : 'قيد الانتظار'}). جميع القيم أدناه تقديرية/مخططة حتى يتم تأكيد الأمر وترحيل الحركات المخزنية والمحاسبية الفعلية.',
                  style: TextStyle(
                    color: isConfirmed ? (isDark ? AppTheme.textPrimary : Colors.black) : (isDark ? AppTheme.warning : const Color(0xFFB45309)),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo',
                    height: 1.4,
                  ),
                ),
              ),
              if (report.mainJournalEntryId != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: report.mainJournalEntryId,
                  ),
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: Text(
                    'قيد الأمر #${report.mainJournalEntryId}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.accent,
                    elevation: 0,
                    side: const BorderSide(color: AppTheme.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'تحديث بيانات المقارنة',
                icon: const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
                onPressed: () => _loadVarianceReport(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Summary KPI Cards ──
        LayoutBuilder(
          builder: (ctx, constraints) {
            final cardWidth = constraints.maxWidth > 700
                ? (constraints.maxWidth - (4 * 12)) / 5
                : (constraints.maxWidth - 12) / 2;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildVarianceKpiCard(
                  title: 'إجمالي التقديري',
                  value: '${report.totalEstimatedCost.toStringAsFixed(2)} ج.م',
                  subtext: 'مجموع التكاليف المخططة (${report.totalItemsCount} بند)',
                  color: AppTheme.primary,
                  icon: Icons.assignment_outlined,
                  width: cardWidth,
                ),
                _buildVarianceKpiCard(
                  title: 'إجمالي الفعلي المثبت',
                  value: report.items.any((i) => i.hasActualCost)
                      ? '${report.totalActualCost.toStringAsFixed(2)} ج.م'
                      : 'غير متاح',
                  subtext: '${report.actualItemsCount} بند مثبت من أصل ${report.totalItemsCount}',
                  color: report.items.any((i) => i.hasActualCost)
                      ? AppTheme.success
                      : AppTheme.warning,
                  icon: Icons.fact_check_outlined,
                  width: cardWidth,
                ),
                _buildVarianceKpiCard(
                  title: 'إجمالي الانحراف',
                  value: report.items.any((i) => i.hasActualCost)
                      ? '${report.totalVariance > 0 ? '+' : ''}${report.totalVariance.toStringAsFixed(2)} ج.م'
                      : '—',
                  subtext: 'مقارنة بالمقابل التقديري للبنود الفعلية',
                  color: report.totalVariance > 0.01
                      ? const Color(0xFFF97316)
                      : (report.totalVariance < -0.01
                          ? AppTheme.accent
                          : AppTheme.textSecondary),
                  icon: Icons.compare_arrows_outlined,
                  width: cardWidth,
                ),
                _buildVarianceKpiCard(
                  title: 'نسبة الانحراف والاتجاه',
                  value: report.variancePercent != null
                      ? '${report.variancePercent! > 0 ? '+' : ''}${report.variancePercent!.toStringAsFixed(1)}%'
                      : '—',
                  subtext: report.direction == 'higher'
                      ? 'الفعلي أعلى من المتوقع'
                      : (report.direction == 'lower'
                          ? 'الفعلي أقل من المتوقع'
                          : (report.direction == 'equal'
                              ? 'متطابق تماماً'
                              : 'في انتظار الصرف')),
                  color: report.direction == 'higher'
                      ? const Color(0xFFF97316)
                      : (report.direction == 'lower'
                          ? AppTheme.accent
                          : AppTheme.textPrimary),
                  icon: Icons.trending_up,
                  width: cardWidth,
                ),
                _buildVarianceKpiCard(
                  title: 'نسبة التغطية الفعلية',
                  value: '${report.actualCoveragePercent.toStringAsFixed(0)}%',
                  subtext: report.actualCoveragePercent >= 99.9 ? 'مكتمل بالكامل' : 'تغطية جزئية',
                  color: report.actualCoveragePercent >= 80
                      ? AppTheme.success
                      : (report.actualCoveragePercent >= 40
                          ? AppTheme.warning
                          : AppTheme.danger),
                  icon: Icons.pie_chart_outline,
                  width: cardWidth,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // ── Table Header ──
        Row(
          children: [
            const Icon(Icons.table_chart_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              'جدول المقارنة التفصيلي بين التقديري والفعلي',
              style: TextStyle(
                color: isDark ? AppTheme.textPrimary : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            const Spacer(),
            Text(
              'عدد البنود: ${report.totalItemsCount}',
              style: TextStyle(
                color: isDark ? AppTheme.textMuted : Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Comparison Table ──
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 900),
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 56,
                horizontalMargin: 16,
                columnSpacing: 18,
                headingTextStyle: TextStyle(
                  color: isDark ? AppTheme.textMuted : Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                columns: const [
                  DataColumn(label: Text('بند التكلفة')),
                  DataColumn(label: Text('التصنيف')),
                  DataColumn(label: Text('التقديري (ج.م)', textAlign: TextAlign.center)),
                  DataColumn(label: Text('الفعلي (ج.م)', textAlign: TextAlign.center)),
                  DataColumn(label: Text('الفرق (ج.م)', textAlign: TextAlign.center)),
                  DataColumn(label: Text('الانحراف %', textAlign: TextAlign.center)),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('المصدر والمستند')),
                  DataColumn(label: Text('إجراء')),
                ],
                rows: report.items.map((item) {
                  final isDark = AppTheme.isDark(context);
                  final name = item.name;
                  final category = item.category;
                  final suppName = item.supplierName;

                  final bool isEngineer = category == 'engineer_expenses' ||
                      category == 'engineer' ||
                      name.contains('مهندس') ||
                      name.contains('مهندسين') ||
                      (suppName != null && suppName.contains('مهندس'));
                  final bool isStation = category == 'station' ||
                      item.isStation ||
                      name.contains('محطة') ||
                      (suppName != null && suppName.contains('محطة'));
                  final bool isDeduction = category == 'deduction' ||
                      item.isDeduction ||
                      name.contains('تخصيم') ||
                      (suppName != null && suppName.contains('تخصيم'));
                  final bool isAdmin = category == 'admin' ||
                      name == 'مصاريف إدارية' ||
                      name.contains('إدار') ||
                      name.contains('ادار');
                  final bool isTransport = !isStation &&
                      !isDeduction &&
                      (item.isActualOnly ||
                          category == 'logistics' ||
                          category == 'transport' ||
                          name.contains('نقل') ||
                          name.contains('شحن'));

                  // Items settled externally via accounts/statements (admin expenses, station suppliers, deductions suppliers)
                  final bool isExternalSettlementItem = isAdmin || isStation || isDeduction;
                  final Color settlementThemeColor = isStation
                      ? const Color(0xFF0D9488)
                      : (isDeduction
                          ? const Color(0xFF6366F1)

                          : const Color(0xFF8B5CF6));

                  // Any additional cost can be settled directly (all except raw produce, packaging materials, transport which is directly actual, and external settlement items)
                  final bool isSettlableCost = category != 'fruit' &&
                      category != 'material' &&
                      !isTransport &&
                      !isExternalSettlementItem;
                  final int costId = item.costItemId ?? name.hashCode;

                  final bool isSettledCost = isEngineer || (isSettlableCost &&
                      (item.status == PackingCostStatus.fullyActual || item.hasActualCost) &&
                      !_adminForceEditingIds.contains(costId));

                  String actionLabel = 'تسوية التكلفة الفعلية';
                  IconData actionIcon = Icons.check_circle_outline;
                  Color actionColor = AppTheme.primary;

                  if (isEngineer) {
                    actionLabel = 'تسوية مصاريف المهندس';
                    actionIcon = Icons.engineering_outlined;
                    actionColor = const Color(0xFFF59E0B);
                  } else if (isTransport) {
                    actionLabel = 'تسوية مصاريف النقل';
                    actionIcon = Icons.local_shipping_outlined;
                    actionColor = const Color(0xFF2563EB);
                  }

                  return DataRow(
                    cells: [
                      // 1. بند التكلفة
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _getCategoryIcon(item.category),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  color: isDark ? AppTheme.textPrimary : Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 2. التصنيف
                      DataCell(
                        _buildCategoryChip(item.category),
                      ),
                      // 3. التقديري
                      DataCell(
                        Text(
                          (isTransport || isEngineer)
                              ? (item.actualCost?.toStringAsFixed(2) ?? item.estimatedCost.toStringAsFixed(2))
                              : item.estimatedCost.toStringAsFixed(2),
                          style: TextStyle(
                            color: isDark ? AppTheme.textPrimary : Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      // 4. الفعلي
                      DataCell(
                        isExternalSettlementItem
                            ? (item.hasActualCost
                                ? Text(
                                    item.actualCost!.toStringAsFixed(2),
                                    style: const TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  )
                                : InkWell(
                                    onTap: () {
                                      if (isStation) {
                                        _navigateToSupplierSettlement(supplierType: 'station', item: item);
                                      } else if (isDeduction) {
                                        _navigateToSupplierSettlement(supplierType: 'deduction', item: item);
                                      } else {
                                        _navigateToAccountSettlement(
                                          accountCode: '31331',
                                          item: item,
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Tooltip(
                                      message: isStation
                                          ? 'اضغط للانتقال إلى شاشة تسوية مستحقات مورد المحطة'
                                          : (isDeduction
                                              ? 'اضغط للانتقال إلى شاشة تسوية مستحقات مورد التخصيمات'
                                              : 'اضغط للانتقال إلى شاشة تفاصيل وتسوية حساب المصاريف الإدارية (31331)'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: settlementThemeColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: settlementThemeColor.withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.open_in_new_rounded, size: 12, color: settlementThemeColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              'عرض فقط',
                                              style: TextStyle(
                                                color: settlementThemeColor,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ))
                            : (isSettlableCost
                                ? (isSettledCost
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            (item.actualCost ?? 0.0).toStringAsFixed(2),
                                            style: const TextStyle(
                                              color: AppTheme.success,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          if (!isEngineer) ...[
                                          IconButton(
                                            icon: Icon(Icons.edit_outlined, size: 16, color: isDark ? Colors.white : Colors.black),
                                            tooltip: 'تعديل التكلفة الفعلية',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              setState(() {
                                                _adminForceEditingIds.add(costId);
                                                _getAdminActualController(costId, item.actualCost ?? (isTransport ? 0.0 : item.estimatedCost)).text =
                                                    (item.actualCost ?? (isTransport ? 0.0 : item.estimatedCost)).toStringAsFixed(2);
                                              });
                                            },
                                          ),
                                          ],
                                        ],
                                      )
                                    : SizedBox(
                                        width: 105,
                                        height: 36,
                                        child: TextFormField(
                                          controller: _getAdminActualController(costId, isTransport ? 0.0 : item.estimatedCost),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: isTransport ? 'المبلغ الفعلي' : null,
                                            suffixText: 'ج.م',
                                            suffixStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.textMuted),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            filled: true,
                                            fillColor: isDark ? const Color(0xFF04192F) : Colors.white,
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: actionColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: actionColor.withValues(alpha: 0.5),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: BorderSide(color: actionColor, width: 1.5),
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ))
                                : (item.hasActualCost
                                    ? Text(
                                        item.actualCost!.toStringAsFixed(2),
                                        style: const TextStyle(
                                          color: AppTheme.success,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                          border: isDark ? null : Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Text(
                                          'غير متاح',
                                          style: TextStyle(
                                            color: isDark ? AppTheme.textMuted : Colors.black54,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ))),
                      ),
                      // 5. الفرق
                      DataCell(
                        isExternalSettlementItem
                            ? (item.hasActualCost
                                ? Text(
                                    (item.variance ?? 0.0).abs() < 0.01
                                        ? '0.00'
                                        : '${(item.variance ?? 0.0) > 0 ? '+' : ''}${(item.variance ?? 0.0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: (item.variance ?? 0.0).abs() < 0.01
                                          ? AppTheme.success
                                          : ((item.variance ?? 0.0) > 0.01 ? const Color(0xFFF97316) : AppTheme.accent),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  )
                                : Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold)))
                            : (isTransport
                                ? Text(
                                    (item.variance ?? 0.0).abs() < 0.01
                                        ? '0.00'
                                        : '${(item.variance ?? 0.0) > 0 ? '+' : ''}${(item.variance ?? 0.0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: (item.variance ?? 0.0).abs() < 0.01
                                          ? AppTheme.success
                                          : ((item.variance ?? 0.0) > 0.01 ? const Color(0xFFF97316) : AppTheme.accent),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  )
                                : (isSettlableCost
                                    ? (isSettledCost
                                        ? Text(
                                            '${(item.variance ?? 0.0) > 0 ? '+' : ''}${(item.variance ?? 0.0).toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: (item.variance ?? 0.0) > 0.01
                                                  ? const Color(0xFFF97316)
                                                  : ((item.variance ?? 0.0) < -0.01
                                                      ? AppTheme.accent
                                                      : (isDark ? AppTheme.textSecondary : Colors.black87)),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          )
                                        : Builder(builder: (_) {
                                            final text = _getAdminActualController(costId, item.estimatedCost).text.trim();
                                            final entered = double.tryParse(text);
                                            if (entered == null) {
                                              return Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold));
                                            }
                                            final diff = entered - item.estimatedCost;
                                            final col = diff > 0.01
                                                ? const Color(0xFFF97316)
                                                : (diff < -0.01 ? AppTheme.accent : (isDark ? AppTheme.textSecondary : Colors.black87));
                                            return Text(
                                              '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: col,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            );
                                          }))
                                    : (item.hasActualCost
                                        ? Text(
                                            '${item.variance! > 0 ? '+' : ''}${item.variance!.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: item.variance! > 0.01
                                                  ? const Color(0xFFF97316)
                                                  : (item.variance! < -0.01
                                                      ? AppTheme.accent
                                                      : (isDark ? AppTheme.textSecondary : Colors.black87)),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          )
                                        : Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold))))),
                      ),
                      // 6. الانحراف %
                      DataCell(
                        isExternalSettlementItem
                            ? (item.hasActualCost && item.variancePercent != null
                                ? Text(
                                    '${item.variancePercent! > 0 ? '+' : ''}${item.variancePercent!.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: item.variancePercent! > 0.01
                                          ? const Color(0xFFF97316)
                                          : (item.variancePercent! < -0.01
                                              ? AppTheme.accent
                                              : (isDark ? AppTheme.textSecondary : Colors.black87)),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  )
                                : Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold)))
                            : (isTransport
                                ? Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold))
                                : (isSettlableCost
                                    ? (isSettledCost
                                        ? (item.variancePercent != null
                                            ? Text(
                                                '${item.variancePercent! > 0 ? '+' : ''}${item.variancePercent!.toStringAsFixed(1)}%',
                                                style: TextStyle(
                                                  color: item.variancePercent! > 0.01
                                                      ? const Color(0xFFF97316)
                                                      : (item.variancePercent! < -0.01
                                                          ? AppTheme.accent
                                                          : (isDark ? AppTheme.textSecondary : Colors.black87)),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Cairo',
                                                ),
                                              )
                                            : Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold)))
                                        : Builder(builder: (_) {
                                            final text = _getAdminActualController(costId, item.estimatedCost).text.trim();
                                            final entered = double.tryParse(text);
                                            if (entered == null || item.estimatedCost <= 0) {
                                              return Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold));
                                            }
                                            final diff = entered - item.estimatedCost;
                                            final pct = diff / item.estimatedCost * 100;
                                            final col = pct > 0.01
                                                ? const Color(0xFFF97316)
                                                : (pct < -0.01 ? AppTheme.accent : (isDark ? AppTheme.textSecondary : Colors.black87));
                                            return Text(
                                              '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                color: col,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            );
                                          }))
                                    : (item.hasActualCost && item.variancePercent != null
                                        ? Text(
                                            '${item.variancePercent! > 0 ? '+' : ''}${item.variancePercent!.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              color: item.variancePercent! > 0.01
                                                  ? const Color(0xFFF97316)
                                                  : (item.variancePercent! < -0.01
                                                      ? AppTheme.accent
                                                      : (isDark ? AppTheme.textSecondary : Colors.black87)),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          )
                                        : Text('—', style: TextStyle(color: isDark ? AppTheme.textMuted : Colors.black54, fontWeight: FontWeight.bold))))),
                      ),
                      // 7. الحالة
                      DataCell(
                        isExternalSettlementItem
                            ? (item.hasActualCost || item.status == PackingCostStatus.fullyActual
                                ? _buildStatusBadge(PackingCostStatus.fullyActual)
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: settlementThemeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: settlementThemeColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.account_balance_wallet_outlined, size: 12, color: settlementThemeColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          'تسوية بالحساب',
                                          style: TextStyle(
                                            color: settlementThemeColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                            : (isSettlableCost
                                ? _buildStatusBadge(isSettledCost ? PackingCostStatus.fullyActual : (isTransport ? PackingCostStatus.estimatedOnly : item.status))
                                : _buildStatusBadge(item.status)),
                      ),
                      // 8. المصدر والمستند
                      DataCell(
                        isExternalSettlementItem
                            ? ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Tooltip(
                                  message: isStation
                                      ? 'تتم تسوية تكاليف مورد المحطة عبر كشف حساب المورد وإثبات فواتير الخدمات ومطابقتها.'
                                      : (isDeduction
                                          ? 'تتم تسوية تكاليف مورد التخصيمات عبر كشف حسابه ومطابقة التسويات الدائنة والمدينة.'
                                          : 'تتم تسوية المصاريف الإدارية من خلال شاشة تفاصيل حساب المصاريف الإدارية (كود 31331) لكافة الأوامر دفعة واحدة.'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isStation
                                            ? Icons.factory_outlined
                                            : (isDeduction ? Icons.assignment_outlined : Icons.account_tree_outlined),
                                        size: 14,
                                        color: settlementThemeColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          item.hasActualCost
                                              ? (item.source.isNotEmpty ? item.source : 'تسوية معتمدة بالحساب')
                                              : (item.supplierName != null && item.supplierName!.isNotEmpty
                                                  ? item.supplierName!
                                                  : (isStation ? 'مورد محطة' : (isDeduction ? 'مورد تخصيمات' : 'حساب المصاريف الإدارية (31331)'))),
                                          style: TextStyle(
                                            color: item.hasActualCost
                                                ? (isDark ? AppTheme.textSecondary : Colors.black87)
                                                : settlementThemeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : (isSettlableCost
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSettledCost ? Icons.check_circle_outline : Icons.schedule_outlined,
                                        size: 14,
                                        color: isSettledCost ? AppTheme.success : AppTheme.warning,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isEngineer
                                            ? (item.source.isNotEmpty ? item.source : 'مجمع عهد الموظفين (تكلفة فعلية منصرفة ومحملة)')
                                            : (isSettledCost
                                                ? (item.source.isNotEmpty ? item.source : 'تسوية فعلية معتمدة')
                                                : (isTransport ? 'تكلفة نقل (فعلي فقط - بانتظار التسوية)' : 'تقديري - بانتظار التسوية')),
                                        style: TextStyle(
                                          color: isSettledCost ? (isDark ? AppTheme.textSecondary : Colors.black87) : AppTheme.warning,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  )
                                : ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 220),
                                    child: Tooltip(
                                      message: item.reasonNotAvailable ?? item.source,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            item.hasActualCost ? Icons.check_circle_outline : Icons.help_outline,
                                            size: 14,
                                            color: item.hasActualCost ? AppTheme.success : AppTheme.warning,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              item.hasActualCost ? item.source : (item.reasonNotAvailable ?? item.source),
                                              style: TextStyle(
                                                color: item.hasActualCost ? (isDark ? AppTheme.textSecondary : Colors.black87) : AppTheme.warning,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )),
                      ),
                      // 9. إجراء (تسوية التكلفة الفعلية أو عرض القيد)
                      DataCell(
                        isExternalSettlementItem
                            ? (item.hasActualCost
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.success.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check, size: 12, color: AppTheme.success),
                                            SizedBox(width: 4),
                                            Text(
                                              'تمت التسوية بالحساب',
                                              style: TextStyle(
                                                color: AppTheme.success,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.journalEntryId != null) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'عرض القيد المحاسبي (${item.journalEntryId})',
                                          icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.primary),
                                          onPressed: () => JournalEntryNavigationService.openById(
                                            context,
                                            journalEntryId: item.journalEntryId,
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : InkWell(
                                    onTap: () {
                                      if (isStation) {
                                        _navigateToSupplierSettlement(supplierType: 'station', item: item);
                                      } else if (isDeduction) {
                                        _navigateToSupplierSettlement(supplierType: 'deduction', item: item);
                                      } else {
                                        _navigateToAccountSettlement(
                                          accountCode: '31331',
                                          item: item,
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Tooltip(
                                      message: isStation
                                          ? 'اضغط للانتقال إلى شاشة تسوية مستحقات مورد المحطة'
                                          : (isDeduction
                                              ? 'اضغط للانتقال إلى شاشة تسوية مستحقات مورد التخصيمات'
                                              : 'اضغط للانتقال إلى شاشة تفاصيل وتسوية حساب المصاريف الإدارية (كود 31331)'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: settlementThemeColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: settlementThemeColor.withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.account_balance_wallet_outlined, size: 13, color: settlementThemeColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              'تسوية من كشف الحساب',
                                              style: TextStyle(
                                                color: settlementThemeColor,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ))
                            : (isSettlableCost
                                ? (!isSettledCost
                                    ? ElevatedButton.icon(
                                        onPressed: _adminSettlingIds.contains(costId)
                                            ? null
                                            : () => _settleCostItemRow(item, costId),
                                        icon: _adminSettlingIds.contains(costId)
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Icon(actionIcon, size: 14),
                                        label: Text(
                                          actionLabel,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: actionColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          elevation: 1,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.success.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check, size: 12, color: AppTheme.success),
                                                SizedBox(width: 4),
                                                Text(
                                                  'تمت التسوية',
                                                  style: TextStyle(
                                                    color: AppTheme.success,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (item.journalEntryId != null) ...[
                                            const SizedBox(width: 4),
                                            IconButton(
                                              tooltip: 'عرض القيد المحاسبي (${item.journalEntryId})',
                                              icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.primary),
                                              onPressed: () => JournalEntryNavigationService.openById(
                                                context,
                                                journalEntryId: item.journalEntryId,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.success.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                                            const SizedBox(width: 4),
                                            Text(
                                              isTransport ? 'فعلي معتمد' : 'مكتمل فعلياً',
                                              style: const TextStyle(
                                                color: AppTheme.success,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.journalEntryId != null) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'عرض القيد المحاسبي (${item.journalEntryId})',
                                          icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.primary),
                                          onPressed: () => JournalEntryNavigationService.openById(
                                            context,
                                            journalEntryId: item.journalEntryId,
                                          ),
                                        ),
                                      ],
                                    ],
                                  )),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Informative Accounting Note ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? AppTheme.glassBorder.withValues(alpha: 0.5) : const Color(0xFFCBD5E1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'قاعدة الدقة المحاسبية: أي بند لا يملك مستند صرف مخزني فعلي أو قيد استحقاق مورد محدد يظهر كـ "غير متاح"، ولا يتم تخمين أي تكلفة فعلية له. سداد الموردين يُعتبر تسوية التزام (Settlement of Liability) ولا يُكرر كتكلفة.',
                  style: TextStyle(
                    color: isDark ? AppTheme.textMuted : Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo',
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVarianceKpiCard({
    required String title,
    required String value,
    required String subtext,
    required Color color,
    required IconData icon,
    required double width,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppTheme.textPrimary : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: TextStyle(
              color: isDark ? AppTheme.textMuted : Colors.black54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'Cairo',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _getCategoryIcon(String category) {
    switch (category) {
      case 'engineer_expenses':
      case 'engineer':
        return const Icon(Icons.engineering_outlined, size: 15, color: Color(0xFFF59E0B));
      case 'fruit':
        return const Icon(Icons.apple_outlined, size: 15, color: Color(0xFFF59E0B));
      case 'material':
        return const Icon(Icons.inventory_2_outlined, size: 15, color: AppTheme.primary);
      case 'logistics':
      case 'transport':
        return const Icon(Icons.local_shipping_outlined, size: 15, color: AppTheme.accent);
      case 'labor':
        return const Icon(Icons.engineering_outlined, size: 15, color: Color(0xFF10B981));
      case 'admin':
        return const Icon(Icons.admin_panel_settings_outlined, size: 15, color: Color(0xFF8B5CF6));
      default:
        return const Icon(Icons.miscellaneous_services_outlined, size: 15, color: AppTheme.textSecondary);
    }
  }

  Widget _buildCategoryChip(String category) {
    String label = 'أخرى';
    Color col = AppTheme.textSecondary;
    switch (category) {
      case 'engineer_expenses':
      case 'engineer':
        label = 'مهندسين 👷';
        col = const Color(0xFFF59E0B);
        break;
      case 'fruit':
        label = 'خام';
        col = const Color(0xFFF59E0B);
        break;
      case 'material':
        label = 'مواد';
        col = AppTheme.primary;
        break;
      case 'logistics':
      case 'transport':
        label = 'شحن';
        col = AppTheme.accent;
        break;
      case 'labor':
        label = 'عمالة';
        col = const Color(0xFF10B981);
        break;
      case 'admin':
        label = 'إدارية';
        col = const Color(0xFF8B5CF6);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
      ),
    );
  }

  Widget _buildStatusBadge(PackingCostStatus status) {
    Color col;
    switch (status) {
      case PackingCostStatus.fullyActual:
        col = AppTheme.success;
        break;
      case PackingCostStatus.partiallyActual:
        col = AppTheme.accent;
        break;
      case PackingCostStatus.estimatedOnly:
        col = AppTheme.warning;
        break;
      case PackingCostStatus.noActualSource:
        col = AppTheme.textMuted;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.labelAr,
        style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isDark = AppTheme.isDark(context);
    final isCostOnly = _stockFieldsLocked;
    final hasMismatch =
        isCostOnly ? false : _lotEntries.any((e) => e.isCartonWeightMismatch);
    final validationErrors = <String>[];
    if (!isCostOnly) {
      for (int i = 0; i < _lotEntries.length; i++) {
        final e = _lotEntries[i];
        final label = _lotEntries.length > 1 ? 'محصول #${i + 1}' : 'المحصول';
        final available = e.batch != null
            ? _getBatchRemainingForEntry(e.batch!, e)
            : e.grossWeight;
        if (e.effectiveWeight > available + 0.001 && available >= 0) {
          validationErrors.add(
              'الكمية المستخدمة ($label) تتجاوز المتاح (${available.toStringAsFixed(1)})');
        }
        if (e.hasSorting && e.sortedWeight > e.effectiveWeight) {
          validationErrors.add('الفرز ($label) يتجاوز الكمية المستخدمة');
        }
        if (e.hasSorting &&
            e.sortedWeight +
                    (e.isCartonMode
                        ? e.cartonCount.toDouble()
                        : e.totalNetWeight) >
                e.effectiveWeight + 0.01) {
          validationErrors
              .add('مجموع الفرز والمعبأ ($label) يتجاوز الكمية المستخدمة');
        }
        if (!e.isCartonMode) {
          final totalAllocated = e.totalNetWeight +
              (e.hasSorting ? e.sortedWeight : 0.0) +
              e.wasteWeight;
          if (e.cartonCount > 0 &&
              e.exactCartonNetWeight > 0 &&
              (totalAllocated - e.effectiveWeight).abs() > 0.01) {
            validationErrors.add(
                'يجب أن يكون (عدد الكراتين × الوزن الصافي + الفرز + الهالك = ${totalAllocated.toStringAsFixed(1)} كجم) مساوياً للوزن المستخدم (${e.effectiveWeight.toStringAsFixed(1)} كجم) في $label');
          }
        }
      }

      final batchTotals = <int, double>{};
      final batchObjects = <int, StationProductBatch>{};
      for (final entry in _lotEntries) {
        if (entry.batch?.id != null) {
          final bId = entry.batch!.id!;
          batchTotals[bId] = (batchTotals[bId] ?? 0.0) + entry.effectiveWeight;
          batchObjects[bId] = entry.batch!;
        }
      }
      for (final bEntry in batchTotals.entries) {
        final bId = bEntry.key;
        final totalUsed = bEntry.value;
        final batchObj = batchObjects[bId]!;
        final baseAvail = _getBatchBaseAvailable(batchObj);
        if (totalUsed > baseAvail + 0.001) {
          validationErrors.add(
              'إجمالي المستخدم من الدفعة ${batchObj.productCode} (${totalUsed.toStringAsFixed(1)}) يتجاوز المتاح (${baseAvail.toStringAsFixed(1)})');
        }
      }
    }
    if (_lotEntries.length > 1) {
      for (final m in _materialItems) {
        final applyTo = (m['apply_to'] as String?) ?? 'all';
        if (applyTo.startsWith('line:')) {
          final idx = int.tryParse(applyTo.substring(5));
          if (idx == null || idx < 0 || idx >= _lotEntries.length) {
            validationErrors
                .add('مادة مرتبط بخط غير صالح: ${m['product_name'] ?? ''}');
          }
        }
      }
      for (final item in _costItems) {
        final method = item['allocation_method'] as String?;
        if (method == null || method.isEmpty) {
          validationErrors
              .add('بند تكلفة بدون طريقة توزيع: ${item['name'] ?? ''}');
        }
      }
      // Allocation balance validation
      final balanceIssues = PackingCalculationService.validateAllocationBalance(
        materialItems: _materialItems,
        costItems: _costItems,
      );
      for (final issue in balanceIssues) {
        validationErrors.add(issue.message);
      }

      // ── Data consistency validation (product lines vs summary) ──
      if (_lotEntries.length > 1) {
        final calc = _calcResult;
        final productLines = calc.productLines;
        if (productLines.isNotEmpty) {
          const eps = 0.02;

          // ═══ Per-line equation verification ═══
          for (var i = 0; i < productLines.length; i++) {
            final pl = productLines[i];
            final expectedNetProductCost = pl.rawCost - pl.sortingContribution;
            final expectedFinalCost = expectedNetProductCost +
                pl.wasteCost +
                pl.packagingCost +
                pl.packagingLoss +
                pl.extraCosts;
            final expectedCostPerKg = pl.totalNetWeight > 0
                ? expectedFinalCost / pl.totalNetWeight
                : 0.0;

            if ((pl.fruitCostAfterSort - expectedNetProductCost).abs() > eps) {
              validationErrors.add(
                  'خطأ في المنتج #${i + 1}: NetProductCost != RawCost - SortingCost');
            }
            if ((pl.finalCost - expectedFinalCost).abs() > eps) {
              validationErrors.add(
                  'خطأ في المنتج #${i + 1}: FinalCost != NetProductCost + Packaging + Loss + Extra');
            }
            if (pl.totalNetWeight > 0 &&
                (pl.finalUnitCost - expectedCostPerKg).abs() > eps) {
              validationErrors.add(
                  'خطأ في المنتج #${i + 1}: CostPerKg != FinalCost / NetWeight');
            }
          }

          // ═══ Aggregate verification ═══
          // Net weight
          final tableNetWeight =
              productLines.fold(0.0, (s, l) => s + l.totalNetWeight);
          if ((tableNetWeight - calc.weights.totalNetWeight).abs() > eps) {
            validationErrors.add('الوزن الصافي في الجدول لا يطابق الملخص');
          }
          // Raw cost
          final tableRawCost = productLines.fold(0.0, (s, l) => s + l.rawCost);
          if ((tableRawCost - calc.finalCost.totalRawCost).abs() > eps) {
            validationErrors.add('تكلفة الخام في الجدول لا تطابق الملخص');
          }
          // Sorting cost
          final tableSorting =
              productLines.fold(0.0, (s, l) => s + l.sortingContribution);
          if ((tableSorting - _totalSortingCost).abs() > eps) {
            validationErrors.add('تكلفة الفرز في الجدول لا تطابق الملخص');
          }
          // Packaging cost
          final tablePackaging =
              productLines.fold(0.0, (s, l) => s + l.packagingCost);
          if ((tablePackaging - calc.materials.materialCost).abs() > eps) {
            validationErrors
                .add('تكلفة المواد في الجدول لا تطابق إجمالي المواد');
          }
          // Packaging loss
          final tableLoss =
              productLines.fold(0.0, (s, l) => s + l.packagingLoss);
          if ((tableLoss - calc.materials.wasteCost).abs() > eps) {
            validationErrors.add('فاقد المواد في الجدول لا يطابق فاقد الملخص');
          }
          // Extra costs
          final tableExtra = productLines.fold(0.0, (s, l) => s + l.extraCosts);
          if ((tableExtra - calc.costItems.totalCostItems).abs() > eps) {
            validationErrors
                .add('بنود التكلفة في الجدول لا تطابق إجمالي البنود');
          }
          // Final cost = overall total cost
          final tableFinalCost =
              productLines.fold(0.0, (s, l) => s + l.finalCost);
          if ((tableFinalCost - calc.finalCost.totalCost).abs() > eps) {
            validationErrors.add(
                'إجمالي تكلفة المنتجات (${tableFinalCost.toStringAsFixed(2)}) لا يطابق إجمالي التكلفة (${calc.finalCost.totalCost.toStringAsFixed(2)})');
          }
        }
      }
    }
    final hasValidationErrors = validationErrors.isNotEmpty || hasMismatch;
    return Column(
      children: [
        if (hasMismatch)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppTheme.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'يجب أن يكون (عدد الكراتين × الوزن الصافي) + الفرز + الهالك مساوياً للوزن المستخدم من المحصول',
                      style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
        if (validationErrors.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: validationErrors
                  .map((err) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 16, color: AppTheme.danger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(err,
                                  style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 12,
                                      fontFamily: 'Cairo')),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        if (_isFinalApproved)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified, color: AppTheme.success, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'أمر التعبئة معتمد نهائياً ومغلق بالكامل',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
                if (_currentOrder?.finalApprovedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'تاريخ الاعتماد النهائي: ${_formatStageDate(_currentOrder?.finalApprovedAt)}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark ? AppTheme.textSecondary : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          )
        else if (!_isViewOnly)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_saving || _stageLoading || hasValidationErrors) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_isEditing ? Icons.save_outlined : Icons.add_circle_outline, size: 20),
                  label: Text(
                    _saving
                        ? 'جاري الحفظ...'
                        : (_isEditing ? 'تحديث المسودة' : 'حفظ كمسودة'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              if (_isCostsConfirmed && !_isFinalApproved) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_saving || _stageLoading) ? null : _confirmFinalStage,
                    icon: _stageLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.verified, size: 20, color: Colors.white),
                    label: const Text(
                      'اعتماد نهائي وإغلاق (المرحلة 4)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _buildLotEntriesData() {
    return _lotEntries
        .map((e) => {
              'product_name': e.lot?.productName ?? '',
              'lot_number': e.lot?.lotNumber ?? '',
              'supplier_name': e.lot?.supplierName ?? '',
              'is_carton_mode': e.isCartonMode,
              'gross_weight': e.grossWeight,
              'effective_weight': e.effectiveWeight,
              'use_partial_crop': e.usePartialCrop,
              'partial_weight_kg': e.usePartialCrop ? e.effectiveWeight : 0.0,
              'waste_weight': e.wasteWeight,
              'net_weight': e.netWeight,
              'sorted_weight': e.sortedWeight,
              'carton_count': e.cartonCount,
              'net_carton_count': e.netCartonCount,
              'net_weight_per_carton': e.exactCartonNetWeight,
              'gross_weight_per_carton': e.grossWeightPerCartonValue,
              'total_net_weight': e.totalNetWeight,
              'total_gross_weight': e.totalGrossWeight,
              'available_weight': e.availableWeight,
              'total_purchase_cost': e.totalPurchaseCost,
              'fruit_cost': e.fruitCost,
              'sorting_cost': e.sortingCost,
              'has_sorting': e.hasSorting,
              'cost_per_unit': e.costPerUnit,
              'cost_per_carton': e._costPerCarton,
              'adjusted_cost_per_kg': e.adjustedCostPerKg,
              'display_currency': e.lot?.currency ?? 'EGP',
            })
        .toList();
  }

  Future<void> _savePdf() async {
    final warehouseName = _stations
        .firstWhere(
            (s) =>
                s.id == _selectedStationId?.toString() ||
                int.tryParse(s.id ?? '') == _selectedStationId,
            orElse: () => _stations.first)
        .name;
    final path = await PackingOrderPdfService.savePdf(
      warehouseName: warehouseName,
      lotEntries: _buildLotEntriesData(),
      materialItems: _materialItems,
      costItems: _costItems,
      totalFruitCostBeforeWaste: _totalFruitCost,
      totalWasteCost: _totalWasteCost,
      totalFruitCostAfterWaste: _totalAdjustedCost,
      totalMaterialCost: _totalMaterialCost,
      totalMaterialWasteCost: _totalMaterialWasteCost,
      totalCostItems: _totalCostItems,
      totalAll: _totalAdjustedCost +
          _totalMaterialCost +
          _totalMaterialWasteCost +
          _totalCostItems,
      packingCostPerCarton: _packingCostPerCarton,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('تم حفظ PDF في: $path', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportExcel() async {
    final calc = _calcResult;
    final warehouseName = _stations
            .where((s) =>
                s.id == _selectedStationId?.toString() ||
                int.tryParse(s.id ?? '') == _selectedStationId)
            .firstOrNull
            ?.name ??
        '';

    final productSummaries = _lotEntries
        .map((e) => {
              'productName': e.lot?.productName ?? '',
              'cartonCount': e.cartonCount,
              'totalNetWeight': e.totalNetWeight,
              'currency': e.lot?.currency ?? 'EGP',
              'originalCurrencyTotalCost': e.originalCurrencyTotalCost,
              'wastePercent': e.wastePercent,
              'wasteCost': e.wasteCost,
            })
        .toList();

    final totalRawWeightKg = _lotEntries.fold(0.0, (sum, e) {
      if (e.isCartonMode) {
        return sum + e.effectiveWeight * e.exactCartonNetWeight;
      } else {
        return sum + e.effectiveWeight;
      }
    });

    await PackingExcelExporter.export(
      context,
      order: PackingOrderModel(
        orderNumber: widget.existingOrder?.orderNumber ?? '',
        lotId: '',
        grade: '',
      ),
      productSummaries: productSummaries,
      rawCostItems: _costItems,
      calc: calc,
      warehouseName: warehouseName,
      totalSortingCost: _totalSortingCost,
      totalRawWeightKg: totalRawWeightKg,
    );
  }

  Widget _infoRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    final isDark = AppTheme.isDark(context);
    Color finalValColor = valueColor ?? (isDark ? AppTheme.textPrimary : Colors.black);
    if (!isDark) {
      if (valueColor == AppTheme.textSecondary) {
        finalValColor = Colors.black87;
      } else if (valueColor == AppTheme.textPrimary) {
        finalValColor = Colors.black;
      }
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label,
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: finalValColor,
                  fontSize: bold ? 15 : 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  Widget _poolCategoryPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCustodyDateFilterBar({
    required BuildContext context,
    required bool isDark,
    required DateTime? fromDate,
    required DateTime? toDate,
    required void Function(DateTime? from, DateTime? to) onDatesChanged,
  }) {
    final now = DateTime.now();
    final bool isThisMonth = fromDate != null &&
        toDate != null &&
        fromDate.year == now.year &&
        fromDate.month == now.month &&
        fromDate.day == 1 &&
        toDate.year == now.year &&
        toDate.month == now.month &&
        toDate.day == now.day;

    final bool isToday = fromDate != null &&
        toDate != null &&
        fromDate.year == now.year &&
        fromDate.month == now.month &&
        fromDate.day == now.day &&
        toDate.year == now.year &&
        toDate.month == now.month &&
        toDate.day == now.day;

    final bool isAllTime = fromDate == null && toDate == null;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (fromDate != null || toDate != null)
              ? const Color(0xFFF59E0B).withAlpha(120)
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              Text(
                'تحديد الفترة الزمنية للعهد المنصرفة:',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              if (fromDate != null || toDate != null)
                InkWell(
                  onTap: () => onDatesChanged(null, null),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 12, color: Color(0xFFEF4444)),
                        SizedBox(width: 2),
                        Text(
                          'إلغاء الفلترة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Start Date Picker
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'من تاريخ صرف العهدة',
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: const Color(0xFFF59E0B),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      onDatesChanged(picked, toDate);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: fromDate != null
                            ? const Color(0xFFF59E0B)
                            : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                        width: fromDate != null ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 13,
                          color: fromDate != null
                              ? const Color(0xFFF59E0B)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'من تاريخ',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                              Text(
                                fromDate != null
                                    ? DateFormat('yyyy-MM-dd').format(fromDate)
                                    : 'بداية الفترة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: fromDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark ? Colors.white38 : Colors.black38),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // End Date Picker
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: toDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'إلى تاريخ صرف العهدة',
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: const Color(0xFFF59E0B),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      onDatesChanged(fromDate, picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: toDate != null
                            ? const Color(0xFFF59E0B)
                            : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                        width: toDate != null ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 13,
                          color: toDate != null
                              ? const Color(0xFFF59E0B)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'إلى تاريخ',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                              Text(
                                toDate != null
                                    ? DateFormat('yyyy-MM-dd').format(toDate)
                                    : 'نهاية الفترة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: toDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark ? Colors.white38 : Colors.black38),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Quick Presets
          Row(
            children: [
              _buildCustodyPresetChip(
                label: 'الكل',
                isSelected: isAllTime,
                isDark: isDark,
                onTap: () => onDatesChanged(null, null),
              ),
              const SizedBox(width: 4),
              _buildCustodyPresetChip(
                label: 'اليوم',
                isSelected: isToday,
                isDark: isDark,
                onTap: () => onDatesChanged(now, now),
              ),
              const SizedBox(width: 4),
              _buildCustodyPresetChip(
                label: 'هذا الشهر',
                isSelected: isThisMonth,
                isDark: isDark,
                onTap: () => onDatesChanged(DateTime(now.year, now.month, 1), now),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustodyPresetChip({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withAlpha(isDark ? 80 : 40)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint, Widget? suffixIcon, String? helperText}) {
    final isDark = AppTheme.isDark(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      helperStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : Colors.black54, fontSize: 11, fontFamily: 'Cairo'),
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : Colors.black54, fontSize: 14, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      labelStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : Colors.black87, fontSize: 15, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      filled: true,
      fillColor: isDark ? const Color(0x1AFFFFFF) : Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;

    // ═══════════════════════════════════════════════
    // Cost-only save for confirmed/cancelled orders
    // ═══════════════════════════════════════════════
    if (_isFinalApproved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أمر التعبئة معتمد نهائياً ومقفل ولا يمكن تعديله'),
          backgroundColor: AppTheme.warning));
      return;
    }

    if (_stockFieldsLocked) {
      final ord = _currentOrder ?? widget.existingOrder;
      final ordId = _orderId;
      if (ord != null && ordId != null) {
        setState(() => _saving = true);
        try {
          final calc = _calcResult;
          Map<String, dynamic> notes = {};
          if (ord.notes != null && ord.notes!.isNotEmpty) {
            try {
              notes = jsonDecode(ord.notes!) as Map<String, dynamic>;
            } catch (_) {}
          }
          notes['materials'] = _materialItems;
          notes['material_items'] = _materialItems;
          notes['material_waste_percent'] =
              double.tryParse(_materialWastePercentCtrl.text) ?? _materialWastePercent;
          notes['waste_percentage'] = notes['material_waste_percent'];
          if (!_isCostsLocked) {
            notes['cost_items'] = _costItems;
          }
          final safeStatus = ord.isCostsConfirmed
              ? 'costs_confirmed'
              : (ord.isPackagingConfirmed
                  ? 'packaging_confirmed'
                  : (ord.isCropsConfirmed ? 'crops_confirmed' : ord.status));

          await _dao.update(
            ordId,
            ord.copyWith(
              status: safeStatus,
              exportShipmentNo: _exportShipmentNoCtrl.text.trim().isNotEmpty
                  ? _exportShipmentNoCtrl.text.trim()
                  : null,
              customerName: _customerNameCtrl.text.trim().isNotEmpty
                  ? _customerNameCtrl.text.trim()
                  : null,
              notes: jsonEncode(notes),
              actualMaterialCost: calc.materials.totalMaterialsWithWaste,
              estimatedMaterialCost: calc.materials.materialCost,
              materialCostBase: calc.materials.materialCost,
              otherCostBase: calc.costItems.totalCostItems,
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم حفظ وتحديث بيانات أمر التعبئة بنجاح'),
                backgroundColor: AppTheme.success));
            await _refreshCurrentOrder();
            context.pop(true);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('خطأ: $e'), backgroundColor: AppTheme.danger));
          }
        } finally {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
    }

    // ═══════════════════════════════════════════════
    // Full validation for draft orders
    // ═══════════════════════════════════════════════

    for (int i = 0; i < _lotEntries.length; i++) {
      final entry = _lotEntries[i];
      final label = _lotEntries.length > 1 ? 'المحصول #${i + 1}' : 'المحصول';

      if (entry.lot == null) {
        _showError('يرجى اختيار $label');
        return;
      }

      if (entry.cartonCount <= 0 || entry.exactCartonNetWeight <= 0) {
        _showError('يرجى إدخال بيانات الكراتين في $label');
        return;
      }

      final available = entry.batch != null
          ? _getBatchRemainingForEntry(entry.batch!, entry)
          : entry.grossWeight;
      if (entry.effectiveWeight > available + 0.001 && available >= 0) {
        _showError(
            'الكمية المستخدمة ($label) تتجاوز المتاح (${available.toStringAsFixed(1)})');
        return;
      }

      if (entry.hasSorting && entry.sortedWeight > entry.effectiveWeight) {
        _showError('الفرز ($label) لا يمكن أن يتجاوز الكمية المستخدمة');
        return;
      }

      if (entry.hasSorting &&
          entry.sortedWeight +
                  (entry.isCartonMode
                      ? entry.cartonCount.toDouble()
                      : entry.totalNetWeight) >
              entry.effectiveWeight + 0.01) {
        _showError(
            'مجموع الفرز والمعبأ ($label) لا يمكن أن يتجاوز الكمية المستخدمة');
        return;
      }

      if (!entry.isCartonMode) {
        final totalAllocated = entry.totalNetWeight +
            (entry.hasSorting ? entry.sortedWeight : 0.0) +
            entry.wasteWeight;
        if ((totalAllocated - entry.effectiveWeight).abs() > 0.01) {
          _showError(
              'يجب أن يكون (عدد الكراتين × الوزن الصافي + الفرز + الهالك = ${totalAllocated.toStringAsFixed(1)} كجم) مساوياً للوزن المستخدم (${entry.effectiveWeight.toStringAsFixed(1)} كجم) في $label');
          return;
        }
      }

      if (entry.lot!.fruitTypeId == null && entry.lot!.productName == null) {
        _showError('بيانات $label غير مكتملة');
        return;
      }
    }

    // Total batch consumption validation across all entries in the order
    final batchTotals = <int, double>{};
    final batchObjects = <int, StationProductBatch>{};
    for (final entry in _lotEntries) {
      if (entry.batch?.id != null) {
        final bId = entry.batch!.id!;
        batchTotals[bId] = (batchTotals[bId] ?? 0.0) + entry.effectiveWeight;
        batchObjects[bId] = entry.batch!;
      }
    }
    for (final bEntry in batchTotals.entries) {
      final bId = bEntry.key;
      final totalUsed = bEntry.value;
      final batchObj = batchObjects[bId]!;
      final baseAvail = _getBatchBaseAvailable(batchObj);
      if (totalUsed > baseAvail + 0.001) {
        _showError(
            'إجمالي الكمية المستخدمة للدفعة (${batchObj.productCode} - ${batchObj.productName}) وهو ${totalUsed.toStringAsFixed(1)} يتجاوز الرصيد المتاح (${baseAvail.toStringAsFixed(1)})');
        return;
      }
    }

    for (final m in _materialItems) {
      final mCode = m['product_code']?.toString() ?? '';
      final mName = m['product_name']?.toString() ?? '';
      final usedQty = (m['used_qty'] as num?)?.toDouble() ?? 0.0;
      if (mCode.isEmpty || usedQty <= 0) {
        _showError('بيانات مادة التعبئة ($mName) غير مكتملة');
        return;
      }
    }

    setState(() => _saving = true);

    try {
      // ═══════════════════════════════════════════════
      // Build packing_order_lines from _calcResult
      // ═══════════════════════════════════════════════
      final calc = _calcResult;
      final totalCartons = calc.weights.totalCartons;
      final totalFruitCost = calc.finalCost.fruitCost;
      final totalPkgCost = calc.finalCost.totalCost;
      final pkgCostPerCarton = calc.finalCost.costPerCarton;

      final lines = <PackingOrderLineModel>[];
      for (int i = 0; i < _lotEntries.length; i++) {
        final entry = _lotEntries[i];
        final calcLine =
            i < calc.packingLines.length ? calc.packingLines[i] : null;
        final prodName = entry.lot?.productName ??
            entry.batch?.productName ??
            entry.fallbackProductName ??
            '';
        final fTypeId = int.tryParse(entry.lot?.fruitTypeId ?? '') ??
            entry.batch?.fruitTypeId;
        lines.add(PackingOrderLineModel(
          id: entry.lineId,
          packingOrderId: 0,
          fruitTypeId: fTypeId,
          productName: prodName,
          grade: 'A',
          sourceLotId: entry.lot?.id,
          batchId: entry.batch?.id.toString(),
          quantity: entry.effectiveWeight,
          cartonCount: entry.cartonCount,
          netWeightPerCarton: entry.exactCartonNetWeight,
          grossWeightPerCarton: entry.grossWeightPerCartonValue > 0
              ? entry.grossWeightPerCartonValue
              : entry.exactCartonNetWeight,
          totalNetWeight: calcLine?.totalNetWeight ?? entry.totalNetWeight,
          totalGrossWeight:
              calcLine?.totalGrossWeight ?? entry.totalGrossWeight,
          unitCost: entry.costPerUnit / (entry.lot?.exchangeRate ?? 1.0),
          rawMaterialCost: calcLine?.rawMaterialCost ?? entry.totalPurchaseCost,
          wasteWeightKg: entry.wasteWeight > 0
              ? entry.wasteWeight
              : (entry.wastePercent > 0 ? entry.effectiveWeight * (entry.wastePercent / 100.0) : 0.0),
          wasteCost: entry.wasteCost,
          sortedWeightKg: entry.hasSorting ? entry.sortedWeight : 0,
          sortingCost: calcLine?.sortingCost ?? entry.sortingCost,
          specificPackagingCost: calcLine?.specificPackagingCost ?? 0,
          allocatedSharedPackaging: calcLine?.allocatedSharedPackaging ?? 0,
          allocatedCostItems: calcLine?.allocatedCostItems ?? 0,
          finalCost: calcLine?.finalCost ?? 0,
          finalUnitCost: calcLine?.finalUnitCost ?? 0,
        ));
      }

      // ═══════════════════════════════════════════════
      // Build notes JSON (shared data for RPC)
      // ═══════════════════════════════════════════════
      final notesMap = <String, dynamic>{};
      final firstEntry = _lotEntries.first;

      final distinctProductNames = _lotEntries
          .map((e) =>
              e.lot?.productName ??
              e.batch?.productName ??
              e.fallbackProductName ??
              '')
          .where((name) => name.trim().isNotEmpty)
          .toSet()
          .toList();
      final headerProductName = distinctProductNames.length > 1
          ? distinctProductNames.join(' + ')
          : (distinctProductNames.isNotEmpty
              ? distinctProductNames.first
              : (firstEntry.lot?.productName ?? ''));

      // Fruit allocations (all entries)
      final fruitAllocations = <Map<String, dynamic>>[];
      for (final entry in _lotEntries) {
        if (entry.batch != null) {
          fruitAllocations.add({
            'batch_id': entry.batch!.id,
            'quantity': entry.effectiveWeight,
            'product_name': entry.batch!.productName,
            'product_code': entry.batch!.productCode,
          });
        }
        if (entry.usePartialCrop) {
          notesMap['use_partial_crop'] = true;
          notesMap['partial_weight_kg'] =
              entry.partialWeightCtrl.text.isNotEmpty
                  ? double.tryParse(entry.partialWeightCtrl.text) ?? 0
                  : 0;
        }
      }
      if (fruitAllocations.isNotEmpty) {
        notesMap['fruit_allocation'] = fruitAllocations.length == 1
            ? fruitAllocations.first
            : fruitAllocations;
      }

      notesMap['all_stations'] = _isAllStations;
      notesMap['selected_station_ids'] = _selectedStationIds.toList();
      notesMap['is_multi_warehouse'] = _isAllStations || _selectedStationIds.length > 1;

      notesMap['total_raw_weight_kg'] = _lotEntries.fold(0.0, (sum, e) {
        if (e.isCartonMode) {
          return sum + e.effectiveWeight * e.exactCartonNetWeight;
        } else {
          return sum + e.effectiveWeight;
        }
      });

      // Save per-entry waste/sorting/partial data for multi-entry orders
      final wasteData = <Map<String, dynamic>>[];
      final sortingData = <Map<String, dynamic>>[];
      for (int i = 0; i < _lotEntries.length; i++) {
        final entry = _lotEntries[i];
        if (entry.usePartialCrop) {
          notesMap['use_partial_crop'] = true;
          notesMap['partial_weight_kg'] =
              entry.partialWeightCtrl.text.isNotEmpty
                  ? double.tryParse(entry.partialWeightCtrl.text) ?? 0
                  : 0;
        }
        if (entry.wasteCost > 0) {
          final wWeight = entry.wasteWeight > 0
              ? entry.wasteWeight
              : (entry.wastePercent > 0 ? entry.effectiveWeight * (entry.wastePercent / 100.0) : 0.0);
          final wUnitPrice = wWeight > 0 ? (entry.wasteCost / wWeight) : entry.costPerUnit;
          wasteData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'waste_percent': entry.wastePercent,
            'waste_weight_kg': wWeight,
            'waste_cost': entry.wasteCost,
            'quantity': wWeight,
            'unit_price': wUnitPrice,
          });
        }
        if (entry.hasSorting && entry.sortedWeight > 0) {
          final sWeight = entry.sortedWeight;
          final sUnitPrice = sWeight > 0 ? (entry.sortingCost / sWeight) : entry.costPerUnit;
          sortingData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'sorted_weight_kg': sWeight,
            'sorting_cost': entry.sortingCost,
            'quantity': sWeight,
            'unit_price': sUnitPrice,
          });
        }
      }
      if (wasteData.isNotEmpty) {
        notesMap['waste_data'] =
            wasteData.length == 1 ? wasteData.first : wasteData;
        notesMap['waste_weight_kg'] = wasteData.fold<double>(
            0, (s, w) => s + (w['waste_weight_kg'] as num).toDouble());
        notesMap['waste_cost'] = wasteData.fold<double>(
            0, (s, w) => s + (w['waste_cost'] as num).toDouble());
      }
      if (sortingData.isNotEmpty) {
        notesMap['sorting_data'] =
            sortingData.length == 1 ? sortingData.first : sortingData;
        notesMap['sorted_weight_kg'] = sortingData.fold<double>(
            0, (s, w) => s + (w['sorted_weight_kg'] as num).toDouble());
        notesMap['sorting_cost'] = sortingData.fold<double>(
            0, (s, w) => s + (w['sorting_cost'] as num).toDouble());
      }
      notesMap['product_cost_per_kg'] = firstEntry.productCostPerKg;
      notesMap['materials'] = _materialItems;
      notesMap['material_items'] = _materialItems;
      if (_materialWastePercent > 0) {
        notesMap['material_waste_percent'] = _materialWastePercent;
      }
      if (_costItems.isNotEmpty) notesMap['cost_items'] = _costItems;
      if (_isRollingWasteMode || _returnPackagingWasteCost > 0) {
        notesMap['waste_settlement_summary'] = {
          'cumulative_waste_pool': _cumulativePendingWastePool,
          'current_order_waste': _currentOrderCalculatedWaste,
          'settled_amount': _rollingSettledWasteAmount,
          'remaining_unsettled': _unsettledMaterialWasteCost,
          'status': _wasteSettlementStatusLabel,
        };
      }

      // ═══════════════════════════════════════════════
      // Save single packing order with lines (draft)
      // ═══════════════════════════════════════════════

      if (_isEditing) {
        final orderId = int.parse(widget.existingOrder!.id!);
        await _dao.update(
          orderId,
          widget.existingOrder!.copyWith(
            lotId: firstEntry.lot!.id!,
            grade: 'A',
            fruitTypeId: firstEntry.lot!.fruitTypeId,
            productName: headerProductName,
            cartonCount: totalCartons,
            netWeightPerCarton: firstEntry.exactCartonNetWeight,
            grossWeightPerCarton: firstEntry.grossWeightPerCartonValue > 0
                ? firstEntry.grossWeightPerCartonValue
                : firstEntry.exactCartonNetWeight,
            totalNetWeight: calc.weights.totalNetWeight,
            totalGrossWeight: calc.weights.totalEffectiveWeight,
            status: widget.existingOrder!.status,
            stationId: _selectedStationId?.toString(),
            exportShipmentNo: _exportShipmentNoCtrl.text.trim().isNotEmpty
                ? _exportShipmentNoCtrl.text.trim()
                : null,
            customerName: _customerNameCtrl.text.trim().isNotEmpty
                ? _customerNameCtrl.text.trim()
                : null,
            packingCostPerCarton: pkgCostPerCarton,
            totalPackingCost: totalPkgCost,
            fruitCostAllocated: calc.finalCost.fruitCost,
            fruitCostBase: calc.finalCost.totalRawCost,
            actualMaterialCost: calc.materials.totalMaterialsWithWaste,
            estimatedMaterialCost: calc.materials.materialCost,
            materialCostBase: calc.materials.materialCost,
            otherCostBase: calc.costItems.totalCostItems,
            notes: notesMap.isNotEmpty ? jsonEncode(notesMap) : null,
            lines: lines,
          ),
        );

        // Update sortings
        await _syncSortingsToDb(orderId);
      } else {
        final order = PackingOrderModel(
          orderNumber: '',
          lotId: firstEntry.lot!.id!,
          grade: 'A',
          fruitTypeId: firstEntry.lot!.fruitTypeId,
          productName: headerProductName,
          cartonCount: totalCartons,
          netWeightPerCarton: firstEntry.exactCartonNetWeight,
          grossWeightPerCarton: firstEntry.grossWeightPerCartonValue > 0
              ? firstEntry.grossWeightPerCartonValue
              : firstEntry.exactCartonNetWeight,
          totalNetWeight:
              lines.fold<double>(0.0, (s, l) => s + l.totalNetWeight),
          totalGrossWeight:
              lines.fold<double>(0.0, (s, l) => s + l.totalGrossWeight),
          status: 'pending',
          stationId: _selectedStationId?.toString(),
          exportShipmentNo: _exportShipmentNoCtrl.text.trim().isNotEmpty
              ? _exportShipmentNoCtrl.text.trim()
              : null,
          customerName: _customerNameCtrl.text.trim().isNotEmpty
              ? _customerNameCtrl.text.trim()
              : null,
          packingCostPerCarton: pkgCostPerCarton,
          totalPackingCost: totalPkgCost,
          fruitCostAllocated: calc.finalCost.fruitCost,
          fruitCostBase: calc.finalCost.totalRawCost,
          actualMaterialCost: calc.materials.totalMaterialsWithWaste,
          estimatedMaterialCost: calc.materials.materialCost,
          materialCostBase: calc.materials.materialCost,
          otherCostBase: calc.costItems.totalCostItems,
          notes: notesMap.isNotEmpty ? jsonEncode(notesMap) : null,
          lines: lines,
        );

        final newOrderId = await _dao.insert(order);

        // Create sorting entries
        await _syncSortingsToDb(newOrderId);
      }

      // ═══════════════════════════════════════════════
      // Stock deduction happens on CONFIRM, not on save
      // ═══════════════════════════════════════════════

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم ${_isEditing ? 'تعديل' : 'حفظ'} أمر التعبئة (${_lotEntries.length} ${_lotEntries.length > 1 ? 'أصناف' : 'صنف'}) كمسودة',
                textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
        context.pop(true);
      }
    } catch (e, st) {
      debugPrint('❌ PackingOrderForm save error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e', textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>> _captureStationSnapshot(
      int stationId, String productName) async {
    final client = Supabase.instance.client;
    final product = await client
        .from('station_products')
        .select()
        .eq('station_id', stationId)
        .eq('product_name', productName)
        .maybeSingle();
    if (product == null) return {};
    final batches = await client
        .from('station_product_batches')
        .select()
        .eq('station_id', stationId)
        .eq('product_name', productName);
    return {
      'station_product': product,
      'batches': batches,
    };
  }

  Future<void> _restoreStationSnapshot(
      Map<String, dynamic> snapshot, int stationId) async {
    final client = Supabase.instance.client;
    final sp = snapshot['station_product'] as Map<String, dynamic>?;
    final batches = snapshot['batches'] as List?;
    if (sp == null) return;
    final productName = sp['product_name'] as String?;
    if (productName == null) return;
    final existing = await _stationProductDao.findByStationAndProduct(
        stationId, productName);
    if (existing == null) {
      await client.from('station_products').insert({
        'station_id': stationId,
        'product_name': productName,
        'product_code': sp['product_code'] ?? '',
        'quantity': sp['quantity'],
      });
    } else {
      await client.from('station_products').update({
        'quantity': sp['quantity'],
      }).eq('id', existing.id!);
    }
    if (batches != null) {
      for (final b in batches) {
        final bMap = Map<String, dynamic>.from(b as Map);
        bMap.remove('id');
        bMap['station_id'] = stationId;
        bMap['product_name'] = productName;
        await client.from('station_product_batches').insert(bMap);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: AppTheme.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
