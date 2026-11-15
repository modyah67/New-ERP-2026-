import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/station_dao.dart';
import '../../data/models/station_model.dart';
import '../../data/services/cost_center_service.dart';
import '../../data/models/cost_center.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';

class ExportShipmentReturnPage extends StatefulWidget {
  final dynamic shipmentId;
  final ExportShipmentModel? initialShipment;

  const ExportShipmentReturnPage({
    super.key,
    required this.shipmentId,
    this.initialShipment,
  });

  @override
  State<ExportShipmentReturnPage> createState() => _ExportShipmentReturnPageState();
}

class _ExportShipmentReturnPageState extends State<ExportShipmentReturnPage> {
  final _shipmentDao = ExportShipmentDao();
  final _itemDao = ExportShipmentItemDao();
  final _stationDao = StationDao();

  bool _loading = true;
  bool _submitting = false;
  ExportShipmentModel? _shipment;

  // Form Controllers & State
  List<StationModel> _stations = [];
  int? _selectedStationId;
  DateTime _returnDate = DateTime.now();

  List<CostCenter> _costCenters = [];
  String? _selectedCostCenterId;

  String _returnReason = 'فحص الحجر الزراعي بالمطار';
  final _customReasonController = TextEditingController();
  final _notesController = TextEditingController();

  // Item allocation rows
  // Each element:
  // {
  //   'item_id': int,
  //   'product_name': String,
  //   'fruit_type_id': int?,
  //   'packing_order_id': int?,
  //   'packing_order_line_id': int?,
  //   'total_cartons': int,
  //   'intact_cartons': int,
  //   'damaged_cartons': int,
  //   'carton_unit_cost': double,
  //   'weight_per_carton': double,
  //   'total_weight': double,
  //   'intact_weight': double,
  //   'damaged_weight': double,
  //   'crop_unit_cost': double,
  //   'controllers': Map<String, TextEditingController>
  // }
  final List<Map<String, dynamic>> _itemRows = [];

  // Extra expenses rows: [{'name': String, 'amount': double, 'supplier_category': String, 'supplier_id': String?, 'supplier_name': String?, 'supplier_type': String?, 'notes': String}]
  final List<Map<String, dynamic>> _extraExpenses = [];
  List<Map<String, dynamic>> _suppliersList = [];

  static const List<Map<String, String>> _supplierCategoryOptions = [
    {'key': 'packaging', 'label': 'مورد مواد تعبئة 📦'},
    {'key': 'transport', 'label': 'مورد نقل 🚛'},
    {'key': 'shipping', 'label': 'شركة شحن 🚢'},
    {'key': 'shared', 'label': 'مورد مشارك 🔄'},
    {'key': 'crop', 'label': 'مورد محاصيل 🌾'},
    {'key': 'clearing', 'label': 'مخلص جمركي 📑'},
    {'key': 'all', 'label': 'الكل (جميع الموردين)'},
  ];

  static const List<String> _commonReasons = [
    'فحص الحجر الزراعي بالمطار',
    'إلغاء رحلة الطيران / الباخرة',
    'تأخر الشحن وتلف المحصول جزئياً',
    'عدم مطابقة مواصفات التصدير',
    'مشكلة في بوليصة الشحن الجوي',
    'أخرى (تحديد يدوي)',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _customReasonController.dispose();
    _notesController.dispose();
    for (final row in _itemRows) {
      final ctrlMap = row['controllers'] as Map<String, TextEditingController>?;
      ctrlMap?.forEach((_, c) => c.dispose());
    }
    for (final exp in _extraExpenses) {
      (exp['nameController'] as TextEditingController?)?.dispose();
      (exp['amountController'] as TextEditingController?)?.dispose();
      (exp['controller'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch shipment
      ExportShipmentModel? s = widget.initialShipment;
      s ??= await _shipmentDao.getById(widget.shipmentId);
      if (s == null) {
        throw Exception('لم يتم العثور على الشحنة التصديرية');
      }

      // 2. Fetch items
      final items = await _itemDao.getByShipmentId(s.id!);

      // 3. Fetch stations & cost centers
      final stations = await _stationDao.getAll();
      final costCenters = await CostCenterService.instance.fetchCostCenters();

      // Pre-populate items rows with actual costs from packing order/costing
      _itemRows.clear();
      for (final itm in items) {
        final totalCartons = (itm['quantity'] as num?)?.toInt() ?? 0;
        final wtPerCarton = (itm['weight_per_carton'] as num?)?.toDouble() ?? 15.0;
        final totalWeight = (itm['net_weight'] as num?)?.toDouble() ?? (totalCartons * wtPerCarton);

        // Fetch actual costs from linked packing order or shipment costing
        final costResolution = await _shipmentDao.resolveActualItemCosts(
          shipmentId: int.tryParse(s.id ?? '') ?? 0,
          item: itm,
        );

        final actualCropCost = (costResolution['crop_unit_cost'] as num).toDouble();
        final actualCartonCost = (costResolution['carton_unit_cost'] as num).toDouble();
        final cartonProdName = costResolution['carton_product_name'] as String?;
        final cartonProdCode = costResolution['carton_product_code'] as String?;
        final cartonRawMatId = costResolution['carton_raw_material_id'] as String?;
        final fruitTypeId = costResolution['fruit_type_id'] as int? ?? itm['finished_product_id'];
        final fruitCode = costResolution['fruit_type_code'] as String? ?? itm['product_code'] ?? '';
        final isActual = costResolution['is_actual'] as bool? ?? false;
        final costSource = costResolution['cost_source'] as String? ?? '';

        final intactCartonsCtrl = TextEditingController(text: totalCartons.toString());
        final damagedCartonsCtrl = TextEditingController(text: '0');
        final intactWeightCtrl = TextEditingController(text: totalWeight.toStringAsFixed(1));
        final damagedWeightCtrl = TextEditingController(text: '0');
        final cropCostCtrl = TextEditingController(text: actualCropCost.toStringAsFixed(2));
        final cartonCostCtrl = TextEditingController(text: actualCartonCost.toStringAsFixed(2));

        _itemRows.add({
          'item_id': itm['id'],
          'product_name': itm['product_name'] ?? itm['invoice_product_name'] ?? 'صنف تصديري',
          'product_code': fruitCode,
          'fruit_type_id': fruitTypeId,
          'packing_order_id': itm['packing_order_id'],
          'packing_order_line_id': itm['packing_order_line_id'],
          'carton_product_name': cartonProdName,
          'carton_product_code': cartonProdCode,
          'raw_material_id': cartonRawMatId,
          'is_actual_cost': isActual,
          'cost_source': costSource,
          'total_cartons': totalCartons,
          'intact_cartons': totalCartons,
          'damaged_cartons': 0,
          'carton_unit_cost': actualCartonCost,
          'weight_per_carton': wtPerCarton,
          'total_weight': totalWeight,
          'intact_weight': totalWeight,
          'damaged_weight': 0.0,
          'crop_unit_cost': actualCropCost,
          'controllers': {
            'intact_cartons': intactCartonsCtrl,
            'damaged_cartons': damagedCartonsCtrl,
            'intact_weight': intactWeightCtrl,
            'damaged_weight': damagedWeightCtrl,
            'crop_cost': cropCostCtrl,
            'carton_cost': cartonCostCtrl,
          },
        });
      }

      int? initialStationId;
      if (stations.isNotEmpty) {
        initialStationId = int.tryParse(stations.first.id ?? '');
      }

      String? initialCostCenterId;
      if (costCenters.isNotEmpty) {
        initialCostCenterId = costCenters.first.id;
      }

      // 4. Fetch all supplier categories for extra expenses
      List<Map<String, dynamic>> loadedSuppliers = [];
      try {
        final supps = await SupplierDao().getAll(limit: 2000);
        for (final sp in supps) {
          final rawType = sp.supplierType.toLowerCase().trim();
          String catType = 'crop';
          if (rawType.contains('pack') || rawType.contains('تعبئ') || rawType.contains('كرتون') || rawType.contains('sticker')) {
            catType = 'packaging';
          } else if (rawType.contains('trans') || rawType.contains('نقل')) {
            catType = 'transport';
          } else if (rawType.contains('share') || rawType.contains('مشترك')) {
            catType = 'shared';
          } else if (rawType.contains('ship') || rawType.contains('شحن')) {
            catType = 'shipping';
          } else if (rawType.contains('clear') || rawType.contains('تخليص')) {
            catType = 'clearing';
          } else {
            final cNum = int.tryParse(sp.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            if (cNum >= 60000 && cNum < 70000) {
              catType = 'transport';
            } else if (cNum >= 70000 && cNum < 75000) {
              catType = 'packaging';
            } else if (cNum >= 75000 && cNum < 80000) {
              catType = 'shared';
            } else if (cNum >= 90000 && cNum < 100000) {
              catType = 'shipping';
            } else if (cNum >= 20000 && cNum < 30000) {
              catType = 'clearing';
            } else {
              catType = 'crop';
            }
          }

          String typeArabic = 'محاصيل';
          if (catType == 'packaging') typeArabic = 'تعبئة';
          if (catType == 'transport') typeArabic = 'نقل';
          if (catType == 'shared') typeArabic = 'مشترك';
          if (catType == 'shipping') typeArabic = 'شحن';
          if (catType == 'clearing') typeArabic = 'تخليص';

          loadedSuppliers.add({
            'id': sp.id?.toString() ?? '',
            'name': sp.name,
            'code': sp.supplierCode.isNotEmpty ? sp.supplierCode : '',
            'type': catType,
            'display': '${sp.name} ($typeArabic - ${sp.supplierCode.isNotEmpty ? sp.supplierCode : (sp.id ?? '')})',
          });
        }

        // Transport suppliers
        try {
          final transSupps = await TransportSupplierDao().getAll();
          for (final t in transSupps) {
            final tId = t.id?.toString() ?? '';
            if (!loadedSuppliers.any((e) => e['id'] == tId && e['type'] == 'transport')) {
              loadedSuppliers.add({
                'id': tId,
                'name': t.name,
                'code': t.code,
                'type': 'transport',
                'display': '${t.name} (نقل - ${t.code})',
              });
            }
          }
        } catch (_) {}

        // Shipping companies
        try {
          final shipComps = await ShippingCompanyDao().getAll(limit: 500);
          for (final sc in shipComps) {
            final scId = sc.id?.toString() ?? '';
            if (!loadedSuppliers.any((e) => e['id'] == scId && e['type'] == 'shipping')) {
              loadedSuppliers.add({
                'id': scId,
                'name': sc.name,
                'code': sc.code,
                'type': 'shipping',
                'display': '${sc.name} (شحن - ${sc.code})',
              });
            }
          }
        } catch (_) {}

        // Clearing agents
        try {
          final clearAgents = await ClearingAgentDao().getAll(limit: 500);
          for (final ca in clearAgents) {
            final caId = ca.id?.toString() ?? '';
            if (!loadedSuppliers.any((e) => e['id'] == caId && e['type'] == 'clearing')) {
              loadedSuppliers.add({
                'id': caId,
                'name': ca.name,
                'code': ca.code,
                'type': 'clearing',
                'display': '${ca.name} (تخليص - ${ca.code})',
              });
            }
          }
        } catch (_) {}

        loadedSuppliers.sort((a, b) {
          return (a['name'] as String).compareTo(b['name'] as String);
        });
      } catch (e) {
        debugPrint('⚠️ Error loading suppliers for return: $e');
      }

      if (mounted) {
        setState(() {
          _shipment = s;
          _stations = stations;
          _costCenters = costCenters;
          _suppliersList = loadedSuppliers;
          _selectedStationId = initialStationId;
          _selectedCostCenterId = initialCostCenterId;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل بيانات الشحنة: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Helper calculations
  int get _grandTotalCartons => _itemRows.fold(0, (s, r) => s + (r['total_cartons'] as int));
  int get _grandIntactCartons => _itemRows.fold(0, (s, r) => s + (r['intact_cartons'] as int));
  int get _grandDamagedCartons => _itemRows.fold(0, (s, r) => s + (r['damaged_cartons'] as int));

  double get _grandTotalWeight => _itemRows.fold(0.0, (s, r) => s + (r['total_weight'] as double));
  double get _grandIntactWeight => _itemRows.fold(0.0, (s, r) => s + (r['intact_weight'] as double));
  double get _grandDamagedWeight => _itemRows.fold(0.0, (s, r) => s + (r['damaged_weight'] as double));

  double get _grandIntactCropValue => _itemRows.fold(0.0, (s, r) => s + ((r['intact_weight'] as double) * (r['crop_unit_cost'] as double)));
  double get _grandDamagedCropWasteCost => _itemRows.fold(0.0, (s, r) => s + ((r['damaged_weight'] as double) * (r['crop_unit_cost'] as double)));

  double get _grandIntactCartonsValue => _itemRows.fold(0.0, (s, r) => s + ((r['intact_cartons'] as int) * (r['carton_unit_cost'] as double)));
  double get _grandDamagedCartonsWasteCost => _itemRows.fold(0.0, (s, r) => s + ((r['damaged_cartons'] as int) * (r['carton_unit_cost'] as double)));

  double get _grandExtraExpenses => _extraExpenses.fold(0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));

  double get _totalWasteExpense => _grandDamagedCropWasteCost + _grandDamagedCartonsWasteCost + _grandExtraExpenses;

  // Actions
  void _setAllIntact(int index) {
    final row = _itemRows[index];
    final totalC = row['total_cartons'] as int;
    final totalW = row['total_weight'] as double;
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['intact_cartons'] = totalC;
      row['damaged_cartons'] = 0;
      row['intact_weight'] = totalW;
      row['damaged_weight'] = 0.0;
      ctrls['intact_cartons']!.text = totalC.toString();
      ctrls['damaged_cartons']!.text = '0';
      ctrls['intact_weight']!.text = totalW.toStringAsFixed(1);
      ctrls['damaged_weight']!.text = '0';
    });
  }

  void _setAllDamaged(int index) {
    final row = _itemRows[index];
    final totalC = row['total_cartons'] as int;
    final totalW = row['total_weight'] as double;
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['intact_cartons'] = 0;
      row['damaged_cartons'] = totalC;
      row['intact_weight'] = 0.0;
      row['damaged_weight'] = totalW;
      ctrls['intact_cartons']!.text = '0';
      ctrls['damaged_cartons']!.text = totalC.toString();
      ctrls['intact_weight']!.text = '0';
      ctrls['damaged_weight']!.text = totalW.toStringAsFixed(1);
    });
  }

  void _onIntactCartonsChanged(int index, String val) {
    final row = _itemRows[index];
    final totalC = row['total_cartons'] as int;
    final parsed = int.tryParse(val) ?? 0;
    final clamped = parsed.clamp(0, totalC);
    final damaged = totalC - clamped;
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['intact_cartons'] = clamped;
      row['damaged_cartons'] = damaged;
      ctrls['damaged_cartons']!.text = damaged.toString();

      // Proportional crop weight update
      if (totalC > 0) {
        final totalW = row['total_weight'] as double;
        final iWeight = (clamped / totalC) * totalW;
        final dWeight = totalW - iWeight;
        row['intact_weight'] = iWeight;
        row['damaged_weight'] = dWeight;
        ctrls['intact_weight']!.text = iWeight.toStringAsFixed(1);
        ctrls['damaged_weight']!.text = dWeight.toStringAsFixed(1);
      }
    });
  }

  void _onDamagedCartonsChanged(int index, String val) {
    final row = _itemRows[index];
    final totalC = row['total_cartons'] as int;
    final parsed = int.tryParse(val) ?? 0;
    final clamped = parsed.clamp(0, totalC);
    final intact = totalC - clamped;
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['damaged_cartons'] = clamped;
      row['intact_cartons'] = intact;
      ctrls['intact_cartons']!.text = intact.toString();

      if (totalC > 0) {
        final totalW = row['total_weight'] as double;
        final dWeight = (clamped / totalC) * totalW;
        final iWeight = totalW - dWeight;
        row['intact_weight'] = iWeight;
        row['damaged_weight'] = dWeight;
        ctrls['intact_weight']!.text = iWeight.toStringAsFixed(1);
        ctrls['damaged_weight']!.text = dWeight.toStringAsFixed(1);
      }
    });
  }

  void _onIntactWeightChanged(int index, String val) {
    final row = _itemRows[index];
    final totalW = row['total_weight'] as double;
    final parsed = double.tryParse(val) ?? 0.0;
    final clamped = parsed.clamp(0.0, totalW);
    final damaged = (totalW - clamped).clamp(0.0, totalW);
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['intact_weight'] = clamped;
      row['damaged_weight'] = damaged;
      ctrls['damaged_weight']!.text = damaged.toStringAsFixed(1);
    });
  }

  void _onDamagedWeightChanged(int index, String val) {
    final row = _itemRows[index];
    final totalW = row['total_weight'] as double;
    final parsed = double.tryParse(val) ?? 0.0;
    final clamped = parsed.clamp(0.0, totalW);
    final intact = (totalW - clamped).clamp(0.0, totalW);
    final ctrls = row['controllers'] as Map<String, TextEditingController>;

    setState(() {
      row['damaged_weight'] = clamped;
      row['intact_weight'] = intact;
      ctrls['intact_weight']!.text = intact.toStringAsFixed(1);
    });
  }

  void _addExtraExpense() {
    setState(() {
      _extraExpenses.add({
        'name': 'نولون نقل عودة من المطار',
        'amount': 0.0,
        'supplier_category': 'transport',
        'supplier_id': null,
        'supplier_name': null,
        'supplier_type': null,
        'notes': '',
        'nameController': TextEditingController(text: 'نولون نقل عودة من المطار'),
        'amountController': TextEditingController(text: '0'),
        'controller': TextEditingController(text: '0'),
      });
    });
  }

  void _onCategoryChanged(Map<String, dynamic> exp, String newCat) {
    setState(() {
      exp['supplier_category'] = newCat;
      final filtered = _getFilteredSuppliers(newCat);
      final currentId = exp['supplier_id']?.toString();
      // If the selected supplier does not belong to the newly selected category, clear selection
      if (currentId != null && !filtered.any((s) => s['id'] == currentId)) {
        exp['supplier_id'] = null;
        exp['supplier_name'] = null;
        exp['supplier_type'] = null;
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredSuppliers(String category) {
    if (category == 'all') {
      return _suppliersList;
    }
    return _suppliersList.where((s) => s['type'] == category).toList();
  }

  void _removeExtraExpense(int idx) {
    setState(() {
      (_extraExpenses[idx]['nameController'] as TextEditingController?)?.dispose();
      (_extraExpenses[idx]['amountController'] as TextEditingController?)?.dispose();
      (_extraExpenses[idx]['controller'] as TextEditingController?)?.dispose();
      _extraExpenses.removeAt(idx);
    });
  }

  String? _validate() {
    if (_selectedStationId == null) {
      return 'يرجى اختيار المحطة / المخزن المستلم للبضاعة المرتجعة';
    }
    if (_itemRows.isEmpty) {
      return 'لا توجد أصناف في الشحنة لتسجيل رجوعها';
    }
    for (int i = 0; i < _itemRows.length; i++) {
      final r = _itemRows[i];
      final totalC = r['total_cartons'] as int;
      final iC = r['intact_cartons'] as int;
      final dC = r['damaged_cartons'] as int;
      if (iC + dC != totalC) {
        return 'الصنف ${r['product_name']}: مجموع السليم ($iC) والتالف ($dC) يجب أن يساوي إجمالي الكراتين ($totalC)';
      }
    }
    return null;
  }

  Future<void> _submitReturn() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AppTheme.danger));
      return;
    }

    final reason = _returnReason == 'أخرى (تحديد يدوي)'
        ? _customReasonController.text.trim()
        : _returnReason;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.keyboard_return_rounded, color: Color(0xFFEA580C)),
              SizedBox(width: 8),
              Text(
                'تأكيد تسجيل رجوع الشحنة من المطار',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من تنفيذ حركة رجوع الشحنة رقم ${_shipment?.shipmentNo}؟',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dialogSummaryRow('📦 كراتين سليمة للمخزن:', '$_grandIntactCartons كرتونة (${AppUtils.formatNumber(_grandIntactCartonsValue)} ج.م)'),
                    _dialogSummaryRow('🌾 محصول سليم للمخزن:', '${_grandIntactWeight.toStringAsFixed(1)} كجم (${AppUtils.formatNumber(_grandIntactCropValue)} ج.م)'),
                    _dialogSummaryRow('🗑️ هالك محصول وتعبئة:', '${AppUtils.formatNumber(_totalWasteExpense)} ج.م (محمل على مركز التكلفة)'),
                    _dialogSummaryRow('🚫 مديونية العميل الملغاة:', '${AppUtils.formatNumber(_shipment?.totalRevenueForeign ?? 0)} ${_shipment?.currency ?? 'USD'}'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEA580C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('تأكيد واستلام المرتجع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      final itemsPayload = _itemRows.map((r) => {
        'item_id': r['item_id'],
        'product_name': r['product_name'],
        'product_code': r['product_code'],
        'fruit_type_id': r['fruit_type_id'],
        'packing_order_id': r['packing_order_id'],
        'packing_order_line_id': r['packing_order_line_id'],
        'carton_product_name': r['carton_product_name'],
        'carton_product_code': r['carton_product_code'],
        'raw_material_id': r['raw_material_id'],
        'total_cartons': r['total_cartons'],
        'intact_cartons': r['intact_cartons'],
        'damaged_cartons': r['damaged_cartons'],
        'carton_unit_cost': r['carton_unit_cost'],
        'weight_per_carton': r['weight_per_carton'],
        'total_weight': r['total_weight'],
        'intact_weight': r['intact_weight'],
        'damaged_weight': r['damaged_weight'],
        'crop_unit_cost': r['crop_unit_cost'],
      }).toList();

      final extraPayload = _extraExpenses.map((e) => {
        'name': e['name'],
        'amount': e['amount'],
        'supplier_id': e['supplier_id'],
        'supplier_name': e['supplier_name'],
        'supplier_type': e['supplier_type'],
        'supplier_category': e['supplier_category'],
        'notes': e['notes'] ?? '',
      }).toList();

      final res = await _shipmentDao.processShipmentReturn(
        shipmentId: int.parse(_shipment!.id!),
        stationId: _selectedStationId!,
        returnDate: _returnDate,
        costCenterId: _selectedCostCenterId,
        returnReason: reason,
        items: itemsPayload,
        extraExpenses: extraPayload,
        notes: _notesController.text.trim(),
      );

      DataChangeEventBus.instance.notifyCustomersChanged();
      DataChangeEventBus.instance.notifyStationsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyCostCentersChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifyShippingCompaniesChanged();
      DataChangeEventBus.instance.notifyClearingAgentsChanged();
      DataChangeEventBus.instance.notifyPackingOrdersChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'تم تسجيل رجوع الشحنة بنجاح'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تسجيل المرتجع: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _dialogSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppTheme.background : const Color(0xFFF8FAFC);
    final cardBg = isDark ? AppTheme.surface : Colors.white;
    final borderCol = isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1);
    final textCol = isDark ? Colors.white : const Color(0xFF0F172A);

    if (_loading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          elevation: isDark ? 0 : 1,
          iconTheme: IconThemeData(color: textCol),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تسجيل رجوع شحنة من المطار - ${_shipment?.shipmentNo ?? ''}',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17, color: textCol),
              ),
              Text(
                'العميل: ${_shipment?.customerName ?? '—'} | العملة: ${_shipment?.currency ?? 'USD'}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submitReturn,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('تأكيد واستلام المرتجع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. General Return Info Card
              _buildGeneralInfoCard(cardBg, borderCol, textCol),
              const SizedBox(height: 16),

              // 2. Items Allocation Cards
              _buildItemsSection(cardBg, borderCol, textCol),
              const SizedBox(height: 16),

              // 3. Extra Expenses Section
              _buildExtraExpensesSection(cardBg, borderCol, textCol),
              const SizedBox(height: 16),

              // 4. Financial & Inventory Impact Preview Card
              _buildAccountingPreviewCard(cardBg, borderCol, textCol),
              const SizedBox(height: 32),

              // Bottom Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submitReturn,
                  icon: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.keyboard_return_rounded, size: 22),
                  label: const Text(
                    'تأكيد واستلام رجوع الشحنة من المطار وفك أمر التعبئة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 1. General Info Card
  Widget _buildGeneralInfoCard(Color cardBg, Color borderCol, Color textCol) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warehouse_outlined, color: Color(0xFFEA580C), size: 20),
              SizedBox(width: 8),
              Text(
                'بيانات الاستلام ووجهة المرتجع',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: [
              // Destination Station
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<int>(
                  value: _selectedStationId,
                  decoration: InputDecoration(
                    labelText: 'المحطة / المخزن المستلم *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _stations.map((st) {
                    final sid = int.tryParse(st.id ?? '') ?? 0;
                    return DropdownMenuItem<int>(
                      value: sid,
                      child: Text(st.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedStationId = v),
                ),
              ),

              // Return Date
              SizedBox(
                width: 220,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _returnDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => _returnDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'تاريخ عودة الشحنة *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: const Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(
                      AppUtils.formatDate(_returnDate),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),

              // Cost Center
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  value: _selectedCostCenterId,
                  decoration: InputDecoration(
                    labelText: 'مركز التكلفة لتحميل الهالك والتلف *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _costCenters.map((cc) {
                    return DropdownMenuItem<String>(
                      value: cc.id,
                      child: Text(
                        cc.nameAr.isNotEmpty ? cc.nameAr : cc.nameEn,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedCostCenterId = v),
                ),
              ),

              // Return Reason
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  value: _returnReason,
                  decoration: InputDecoration(
                    labelText: 'سبب رجوع الشحنة *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _commonReasons.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(r, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _returnReason = v ?? _returnReason),
                ),
              ),

              if (_returnReason == 'أخرى (تحديد يدوي)')
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _customReasonController,
                    decoration: InputDecoration(
                      labelText: 'توضيح سبب الرجوع',
                      labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),

              // Notes
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات إضافية على حالة الشحنة المرتجعة',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2. Items Allocation Cards
  Widget _buildItemsSection(Color cardBg, Color borderCol, Color textCol) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Color(0xFF0F172A), size: 20),
                const SizedBox(width: 8),
                Text(
                  'تفاصيل الأصناف وفرز السليم والهالك (${_itemRows.length} صنف)',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                'إجمالي المحمل: $_grandTotalCartons كرتونة | ${_grandTotalWeight.toStringAsFixed(1)} كجم',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(_itemRows.length, (idx) => _buildItemRowCard(idx, cardBg, borderCol, textCol)),
      ],
    );
  }

  Widget _buildItemRowCard(int idx, Color cardBg, Color borderCol, Color textCol) {
    final row = _itemRows[idx];
    final ctrls = row['controllers'] as Map<String, TextEditingController>;
    final totalC = row['total_cartons'] as int;
    final totalW = row['total_weight'] as double;
    final intactC = row['intact_cartons'] as int;
    final damagedC = row['damaged_cartons'] as int;
    final intactW = row['intact_weight'] as double;
    final damagedW = row['damaged_weight'] as double;
    final cropCost = row['crop_unit_cost'] as double;
    final cartonCost = row['carton_unit_cost'] as double;

    final intactCartonVal = intactC * cartonCost;
    final damagedCartonVal = damagedC * cartonCost;
    final intactCropVal = intactW * cropCost;
    final damagedCropVal = damagedW * cropCost;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row Header: Product name & Quick actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['product_name'],
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                      if (row['packing_order_id'] != null)
                        Text(
                          'أمر تعبئة مرتبط: #${row['packing_order_id']}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _setAllIntact(idx),
                    icon: const Icon(Icons.check, size: 14, color: Color(0xFF16A34A)),
                    label: const Text('الكل سليم', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF86EFAC)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _setAllDamaged(idx),
                    icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFDC2626)),
                    label: const Text('الكل هالك', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),

          // Total Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('الكراتين المحملة: $totalC كرتونة', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                const Text('|', style: TextStyle(color: Color(0xFFCBD5E1))),
                Text('الوزن الصافي المحمل: ${totalW.toStringAsFixed(1)} كجم', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                const Text('|', style: TextStyle(color: Color(0xFFCBD5E1))),
                Text('وزن الكرتونة: ${(row['weight_per_carton'] as double).toStringAsFixed(1)} كجم', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Side-by-side allocation blocks
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 650;
              final cartonWidget = _buildCartonAllocationBlock(idx, row, ctrls, intactCartonVal, damagedCartonVal);
              final cropWidget = _buildCropAllocationBlock(idx, row, ctrls, intactCropVal, damagedCropVal);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cartonWidget),
                    const SizedBox(width: 14),
                    Expanded(child: cropWidget),
                  ],
                );
              } else {
                return Column(
                  children: [
                    cartonWidget,
                    const SizedBox(height: 12),
                    cropWidget,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // Sub-block: Carton Allocation
  Widget _buildCartonAllocationBlock(
    int idx,
    Map<String, dynamic> row,
    Map<String, TextEditingController> ctrls,
    double intactVal,
    double damagedVal,
  ) {
    final isActual = row['is_actual_cost'] == true;
    final costSource = row['cost_source'] as String? ?? '';
    final cartonName = row['carton_product_name'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_rounded, size: 16, color: Color(0xFF15803D)),
              const SizedBox(width: 6),
              const Text(
                'كراتين التعبئة والتغليف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D)),
              ),
              if (cartonName != null && cartonName.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cartonName,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                  ),
                ),
              ],
              const Spacer(),
              if (isActual)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Text(
                        'تكلفة فعلية ($costSource)',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrls['intact_cartons'],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'سليم للمخزن',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => _onIntactCartonsChanged(idx, v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrls['damaged_cartons'],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'تالف / هالك',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => _onDamagedCartonsChanged(idx, v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrls['carton_cost'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'تكلفة الكرتونة EGP',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    setState(() {
                      row['carton_unit_cost'] = parsed ?? 0.0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('سليم: ${AppUtils.formatNumber(intactVal)} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
              Text('هالك: ${AppUtils.formatNumber(damagedVal)} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            ],
          ),
        ],
      ),
    );
  }

  // Sub-block: Crop Allocation
  Widget _buildCropAllocationBlock(
    int idx,
    Map<String, dynamic> row,
    Map<String, TextEditingController> ctrls,
    double intactVal,
    double damagedVal,
  ) {
    final isActual = row['is_actual_cost'] == true;
    final costSource = row['cost_source'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grass_rounded, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              const Text(
                'المحصول الخام (كجم)',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB45309)),
              ),
              const Spacer(),
              if (isActual)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFFB45309)),
                      const SizedBox(width: 4),
                      Text(
                        'تكلفة فعلية ($costSource)',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrls['intact_weight'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'سليم للمخزن (كجم)',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => _onIntactWeightChanged(idx, v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrls['damaged_weight'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'تالف / هالك (كجم)',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => _onDamagedWeightChanged(idx, v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrls['crop_cost'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'تكلفة الكيلو EGP',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    setState(() {
                      row['crop_unit_cost'] = parsed ?? 0.0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('سليم: ${AppUtils.formatNumber(intactVal)} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
              Text('هالك: ${AppUtils.formatNumber(damagedVal)} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            ],
          ),
        ],
      ),
    );
  }

  // 3. Extra Expenses Section
  Widget _buildExtraExpensesSection(Color cardBg, Color borderCol, Color textCol) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_shipping_outlined, color: Color(0xFF0F172A), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'مصاريف إضافية لرجوع الشحنة (نولون عودة / عمالة تفريغ - اختياري)',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _addExtraExpense,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('إضافة بند مصروف', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          if (_extraExpenses.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'لا توجد مصاريف نقل أو تفريغ إضافية مسجلة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
              ),
            )
          else ...[
            const Divider(height: 20),
            ...List.generate(_extraExpenses.length, (i) {
              final exp = _extraExpenses[i];
              final nameCtrl = exp['nameController'] as TextEditingController? ??
                  (exp['nameController'] = TextEditingController(text: exp['name'] ?? ''));
              final amtCtrl = exp['amountController'] as TextEditingController? ??
                  exp['controller'] as TextEditingController? ??
                  (exp['amountController'] = TextEditingController(text: exp['amount']?.toString() ?? '0'));

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: LayoutBuilder(builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. Expense Name
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'اسم المصروف',
                              prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (v) {
                              exp['name'] = v;
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 2. Supplier Category Filter
                        Expanded(
                          flex: 2,
                          child: _buildSupplierCategoryDropdown(exp),
                        ),
                        const SizedBox(width: 8),

                        // 3. Supplier (Optional, Filtered)
                        Expanded(
                          flex: 4,
                          child: _buildSupplierDropdown(exp),
                        ),
                        const SizedBox(width: 8),

                        // 4. Amount EGP
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'المبلغ ج.م',
                              prefixIcon: const Icon(Icons.attach_money, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (v) {
                              setState(() {
                                exp['amount'] = double.tryParse(v) ?? 0.0;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Delete
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 22),
                          tooltip: 'حذف المصروف',
                          onPressed: () => _removeExtraExpense(i),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: nameCtrl,
                                decoration: InputDecoration(
                                  labelText: 'اسم المصروف',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onChanged: (v) {
                                  exp['name'] = v;
                                  setState(() {});
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
                              onPressed: () => _removeExtraExpense(i),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildSupplierCategoryDropdown(exp),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: amtCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'المبلغ ج.م',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onChanged: (v) {
                                  setState(() {
                                    exp['amount'] = double.tryParse(v) ?? 0.0;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildSupplierDropdown(exp),
                      ],
                    );
                  }
                }),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSupplierCategoryDropdown(Map<String, dynamic> exp) {
    final curCat = exp['supplier_category'] as String? ?? 'transport';
    final hasMatch = _supplierCategoryOptions.any((c) => c['key'] == curCat);

    return DropdownButtonFormField<String>(
      value: hasMatch ? curCat : 'transport',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'نوع المورد',
        prefixIcon: const Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF0284C7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        filled: true,
        fillColor: Colors.white,
      ),
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
      dropdownColor: Colors.white,
      items: _supplierCategoryOptions.map((opt) {
        return DropdownMenuItem<String>(
          value: opt['key']!,
          child: Text(
            opt['label']!,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          _onCategoryChanged(exp, val);
        }
      },
    );
  }

  Widget _buildSupplierDropdown(Map<String, dynamic> exp) {
    final cat = exp['supplier_category'] as String? ?? 'transport';
    final filtered = _getFilteredSuppliers(cat);
    final currentId = exp['supplier_id']?.toString();
    final hasMatch = currentId != null && filtered.any((s) => s['id'] == currentId);
    final countLabel = filtered.isNotEmpty ? ' (${filtered.length})' : '';

    return DropdownButtonFormField<String?>(
      value: hasMatch ? currentId : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'المورد / جهة الاستحقاق$countLabel',
        prefixIcon: const Icon(Icons.person_outline, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.white,
      ),
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
      dropdownColor: Colors.white,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'بدون مورد (تسوية مصروفات عامة)',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
          ),
        ),
        ...filtered.map((s) {
          final type = s['type']?.toString();
          IconData icon;
          Color iconColor;
          switch (type) {
            case 'transport':
              icon = Icons.local_shipping_outlined;
              iconColor = const Color(0xFF0284C7);
              break;
            case 'packaging':
            case 'sticker':
              icon = Icons.inventory_2_outlined;
              iconColor = const Color(0xFFD97706);
              break;
            case 'shipping':
              icon = Icons.directions_boat_outlined;
              iconColor = const Color(0xFF7C3AED);
              break;
            case 'shared':
              icon = Icons.sync_alt;
              iconColor = const Color(0xFF0D9488);
              break;
            case 'clearing':
              icon = Icons.assignment_outlined;
              iconColor = const Color(0xFFE11D48);
              break;
            case 'crop':
            default:
              icon = Icons.grass;
              iconColor = const Color(0xFF16A34A);
              break;
          }

          return DropdownMenuItem<String?>(
            value: s['id'] as String,
            child: Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s['display'] as String,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
      onChanged: (val) {
        setState(() {
          exp['supplier_id'] = val;
          if (val != null) {
            final found = _suppliersList.where((s) => s['id'] == val).firstOrNull;
            exp['supplier_name'] = found?['name'];
            exp['supplier_type'] = found?['type'];
          } else {
            exp['supplier_name'] = null;
            exp['supplier_type'] = null;
          }
        });
      },
    );
  }

  // 4. Financial & Inventory Impact Preview Card
  Widget _buildAccountingPreviewCard(Color cardBg, Color borderCol, Color textCol) {
    final currency = _shipment?.currency ?? 'USD';
    final rate = _shipment?.exchangeRate ?? 1.0;
    final totalRevForeign = _shipment?.totalRevenueForeign ?? 0.0;
    final totalRevEgp = totalRevForeign * rate;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_outlined, color: Color(0xFF0F172A), size: 20),
              SizedBox(width: 8),
              Text(
                'الملخص المالي والمخزني وأثر القيود المتولدة',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const Divider(height: 24),

          // 4 Grid KPI Cards
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _kpiBox(
                  width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                  title: 'محصول خام للمخزن',
                  value: '${_grandIntactWeight.toStringAsFixed(1)} كجم',
                  sub: '${AppUtils.formatNumber(_grandIntactCropValue)} ج.م',
                  icon: Icons.grass,
                  color: const Color(0xFF16A34A),
                ),
                _kpiBox(
                  width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                  title: 'كراتين للمخزن',
                  value: '$_grandIntactCartons كرتونة',
                  sub: '${AppUtils.formatNumber(_grandIntactCartonsValue)} ج.م',
                  icon: Icons.inventory_2,
                  color: const Color(0xFF0284C7),
                ),
                _kpiBox(
                  width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                  title: 'إجمالي الهالك والتلف',
                  value: '${AppUtils.formatNumber(_totalWasteExpense)} ج.م',
                  sub: 'تالف: $_grandDamagedCartons كرتونة | ${_grandDamagedWeight.toStringAsFixed(1)} كجم',
                  icon: Icons.delete_sweep,
                  color: const Color(0xFFDC2626),
                ),
                _kpiBox(
                  width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                  title: 'إلغاء مديونية العميل',
                  value: '${AppUtils.formatNumber(totalRevForeign)} $currency',
                  sub: '${AppUtils.formatNumber(totalRevEgp)} ج.م',
                  icon: Icons.money_off,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            );
          }),
          const SizedBox(height: 18),

          // Detailed Table of the Planned Journal Entry
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'معاينة القيد المحاسبي المتولد (Double-Entry GL Posting):',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                _glRow('من حـ/ إيرادات التصدير (عكس الإيراد)', AppUtils.formatNumber(totalRevEgp), '—', const Color(0xFF475569)),
                _glRow('إلى حـ/ العملاء التجاريين (إلغاء المديونية)', '—', AppUtils.formatNumber(totalRevEgp), const Color(0xFF475569)),
                if (_grandIntactCropValue > 0)
                  _glRow('من حـ/ مخزون المحاصيل الخام (12413)', AppUtils.formatNumber(_grandIntactCropValue), '—', const Color(0xFF16A34A)),
                if (_grandIntactCartonsValue > 0)
                  _glRow('من حـ/ مخزون مواد التعبئة (12414)', AppUtils.formatNumber(_grandIntactCartonsValue), '—', const Color(0xFF0284C7)),
                if (_grandDamagedCropWasteCost > 0)
                  _glRow('من حـ/ مصروف هالك المحاصيل (3211)', AppUtils.formatNumber(_grandDamagedCropWasteCost), '—', const Color(0xFFDC2626)),
                if (_grandDamagedCartonsWasteCost > 0)
                  _glRow('من حـ/ مصروف هالك مواد التعبئة (3213)', AppUtils.formatNumber(_grandDamagedCartonsWasteCost), '—', const Color(0xFFDC2626)),
                if (_grandExtraExpenses > 0) ...[
                  for (final exp in _extraExpenses)
                    if (((exp['amount'] as num?)?.toDouble() ?? 0) > 0)
                      _glRow(
                        'من حـ/ مصروفات نقل وعمالة مرتجع (${exp['name'] ?? 'مصروف'})',
                        AppUtils.formatNumber((exp['amount'] as num).toDouble()),
                        '—',
                        const Color(0xFFD97706),
                      ),
                ],
                _glRow(
                  'إلى حـ/ تسوية تكلفة البضاعة المباعة (COGS)',
                  '—',
                  AppUtils.formatNumber(_grandIntactCropValue + _grandIntactCartonsValue + _grandDamagedCropWasteCost + _grandDamagedCartonsWasteCost),
                  const Color(0xFF334155),
                ),
                if (_grandExtraExpenses > 0) ...[
                  for (final exp in _extraExpenses)
                    if (((exp['amount'] as num?)?.toDouble() ?? 0) > 0)
                      if (exp['supplier_name'] != null && (exp['supplier_name'] as String).isNotEmpty)
                        _glRow(
                          'إلى حـ/ استحقاق مورد: ${exp['supplier_name']} (أرصدة دائنة)',
                          '—',
                          AppUtils.formatNumber((exp['amount'] as num).toDouble()),
                          const Color(0xFF0F766E),
                        )
                      else
                        _glRow(
                          'إلى حـ/ مخصص مصروفات رجوع مستحقة / وسيط (${exp['name'] ?? 'مصروف'})',
                          '—',
                          AppUtils.formatNumber((exp['amount'] as num).toDouble()),
                          const Color(0xFF64748B),
                        ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiBox({
    required double width,
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                Text(sub, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glRow(String accountTitle, String debit, String credit, Color titleColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Text(
              accountTitle,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: titleColor),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              debit,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              credit,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }
}
