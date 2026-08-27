import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/station_model.dart';
import '../../data/models/station_product_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/station_product_batch.dart';
import '../../data/dao/packing_waste_dao.dart';
import '../../data/models/packing_waste_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';

class PackingWastePage extends StatefulWidget {
  final int? existingWasteId;
  final bool viewOnly;
  const PackingWastePage({super.key, this.existingWasteId, this.viewOnly = false});

  @override
  State<PackingWastePage> createState() => _PackingWastePageState();
}

class _PackingWastePageState extends State<PackingWastePage> {
  final _dao = PackingWasteDao();
  final _stationDao = StationDao();
  final _supplierDao = SupplierDao();
  final _rawMaterialDao = RawMaterialDao();
  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  int? _wasteId;
  String _wasteNumber = '';
  String _status = 'draft';
  int? _selectedStationId;
  DateTime _date = DateTime.now();
  int? _journalEntryId;

  List<StationModel> _stations = [];
  List<SupplierModel> _egpSuppliers = [];
  List<Map<String, dynamic>> _costCategories = [];

  List<StationProductBatch> _availableCropBatches = [];
  List<StationProductBatch> _availableMaterialBatches = [];
  List<StationProductModel> _materialProducts = [];

  // أقسام الإدخال
  final List<Map<String, dynamic>> _cropWasteItems = [];
  final List<Map<String, dynamic>> _materialWasteItems = [];
  final List<Map<String, dynamic>> _costItems = [];

  @override
  void initState() {
    super.initState();
    _wasteId = widget.existingWasteId;
    _loadInitialData();
  }

  bool get _isViewOnly => widget.viewOnly || _status != 'draft';

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final stations = await _stationDao.getAll();
      final allSuppliers = await _supplierDao.getAll();
      // فلترة الموردين بالجنيه المصري (EGP) فقط
      final egpSuppliers = allSuppliers.where((s) => s.currency == 'EGP').toList();

      // جلب تصنيفات التكاليف الديناميكية
      List<Map<String, dynamic>> categories = [];
      try {
        final List catRes = await _client.rpc('list_cost_report_categories', params: {'p_scope': 'packing_waste'});
        categories = catRes.map((c) => Map<String, dynamic>.from(c as Map)).toList();
      } catch (e) {
        debugPrint('Error loading cost categories: $e');
      }

      if (mounted) {
        setState(() {
          _stations = stations;
          _egpSuppliers = egpSuppliers;
          _costCategories = categories;
          if (_selectedStationId == null && stations.isNotEmpty) {
            _selectedStationId = int.tryParse(stations.first.id ?? '');
          }
        });

        if (_selectedStationId != null) {
          await _loadStationBatches(_selectedStationId!);
        }
        if (_wasteId != null) {
          await _loadExistingWaste(_wasteId!);
        } else {
          final nextNum = await _dao.getNextWasteNumber();
          if (mounted) setState(() => _wasteNumber = nextNum);
        }
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStationBatches(int stationId) async {
    try {
      final data = await _client
          .from('station_product_batches')
          .select()
          .eq('station_id', stationId)
          .gt('remaining_quantity', 0)
          .order('created_at', ascending: true);

      final batches = (data as List).map((b) => StationProductBatch.fromMap(Map<String, dynamic>.from(b as Map))).toList();

      List<RawMaterialModel> rawMats = [];
      try {
        rawMats = await _rawMaterialDao.getAll();
      } catch (e) {
        debugPrint('Error fetching raw materials: $e');
      }

      final batchData = await _client
          .from('station_product_batches')
          .select('id, product_code, product_name, remaining_quantity, quantity, source_type')
          .eq('station_id', stationId)
          .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual']);

      final batchList = List<Map<String, dynamic>>.from(batchData as List);
      final batchQtyByCode = <String, double>{};
      final batchNameByCode = <String, String>{};
      for (final b in batchList) {
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
          stationId: stationId,
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
          final name = batchNameByCode[entry.key] ?? 'مادة تعبئة ${entry.key}';
          materialList.add(StationProductModel(
            stationId: stationId,
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
          _availableCropBatches = batches.where((b) => b.itemType != 'material').toList();
          _availableMaterialBatches = batches.where((b) => b.itemType == 'material' || ['purchase', 'opening'].contains(b.sourceType)).toList();
          _materialProducts = materialList;
        });
      }
    } catch (e) {
      debugPrint('Error loading batches: $e');
    }
  }

  Future<void> _loadExistingWaste(int id) async {
    final list = await _dao.getAll();
    final item = list.where((w) => w.id == id).firstOrNull;
    if (item != null) {
      _wasteNumber = item.wasteNumber;
      _selectedStationId = item.stationId;
      _date = item.date;
      _status = item.status;
      _journalEntryId = item.journalEntryId;
      final notes = item.notes;
      _cropWasteItems.clear();
      _materialWasteItems.clear();
      _costItems.clear();

      if (notes['fruit_waste_items'] is List) {
        for (final row in notes['fruit_waste_items']) {
          final m = Map<String, dynamic>.from(row as Map);
          final wasteW = (m['waste_weight'] as num?)?.toDouble() ?? 0.0;
          final sortW = (m['sorting_weight'] as num?)?.toDouble() ?? 0.0;
          final totalD = (m['total_drawn_weight'] as num?)?.toDouble() ?? (wasteW + sortW);
          m['total_drawn_weight'] = totalD;
          _cropWasteItems.add(m);
        }
      }
      if (notes['material_waste_items'] is List) {
        _materialWasteItems.addAll(List<Map<String, dynamic>>.from(notes['material_waste_items']));
      }
      if (notes['cost_items'] is List) {
        _costItems.addAll(List<Map<String, dynamic>>.from(notes['cost_items']));
      }
    }
  }

  double get _totalCropWasteCost => _cropWasteItems.fold(0.0, (s, i) => s + ((i['waste_cost'] ?? 0.0) as num).toDouble());
  double get _totalSortingCost => _cropWasteItems.fold(0.0, (s, i) => s + ((i['sorting_cost'] ?? 0.0) as num).toDouble());
  double get _totalMaterialWasteCost => _materialWasteItems.fold(0.0, (s, i) => s + ((i['total_cost'] ?? 0.0) as num).toDouble());
  double get _totalCostItemsCost => _costItems.fold(0.0, (s, i) => s + ((i['total_egp'] ?? 0.0) as num).toDouble());
  double get _grandTotal => _totalCropWasteCost + _totalSortingCost + _totalMaterialWasteCost + _totalCostItemsCost;

  bool get _canSave => _costItems.isNotEmpty && !_saving && !_isViewOnly;

  String? _validateInputs() {
    if (_selectedStationId == null) {
      return 'يرجى اختيار المحطة / المخزن أولاً';
    }
    // فحص المحاصيل
    for (int i = 0; i < _cropWasteItems.length; i++) {
      final item = _cropWasteItems[i];
      final totalDrawn = (item['total_drawn_weight'] as num?)?.toDouble() ?? 0.0;
      final waste = (item['waste_weight'] as num?)?.toDouble() ?? 0.0;
      final sorting = (item['sorting_weight'] as num?)?.toDouble() ?? 0.0;
      final batchId = item['batch_id'] as int?;

      if (totalDrawn <= 0) {
        return 'المحصول رقم ${i + 1}: يجب إدخال الكمية الإجمالية المسحوبة أكبر من 0';
      }

      if ((waste + sorting - totalDrawn).abs() > 0.01) {
        return 'المحصول رقم ${i + 1}: مجموع الهالك ($waste) والفرز ($sorting) يجب أن يساوي تماماً الكمية المسحوبة ($totalDrawn)';
      }

      // التحقق من توفر الرصيد
      final batch = _availableCropBatches.firstWhere((b) => b.id == batchId, orElse: () => StationProductBatch(id: 0, stationId: 0, productName: '', productCode: '', quantity: 0, unitCost: 0, remainingQuantity: 0, sourceType: '', createdAt: DateTime.now().toIso8601String()));
      if (batch.id != 0 && totalDrawn > batch.remainingQuantity + 0.001) {
        return 'المحصول رقم ${i + 1}: الكمية المسحوبة ($totalDrawn كجم) أكبر من الرصيد المتاح (${batch.remainingQuantity} كجم)';
      }
    }

    // فحص مواد التعبئة
    for (int i = 0; i < _materialWasteItems.length; i++) {
      final item = _materialWasteItems[i];
      final qty = (item['waste_qty'] as num?)?.toDouble() ?? 0.0;
      if (qty <= 0) {
        return 'مادة التعبئة رقم ${i + 1}: يجب تحديد كمية الهالك أكبر من 0';
      }
    }

    // فحص بنود التكلفة (إجباري)
    if (_costItems.isEmpty) {
      return 'يجب إضافة بند تكلفة واحد على الأقل (مصاريف فرز، نقل، عمالة) للمتابعة';
    }

    for (int i = 0; i < _costItems.length; i++) {
      final item = _costItems[i];
      final total = (item['total_egp'] as num?)?.toDouble() ?? 0.0;
      if (total <= 0) {
        return 'بند التكلفة رقم ${i + 1}: يجب تحديد مبلغ أكبر من 0';
      }
      if (item['supplier_id'] == null || item['supplier_id'].toString().isEmpty) {
        return 'بند التكلفة رقم ${i + 1}: يجب اختيار المورد بالجنيه المصري (EGP)';
      }
    }

    return null;
  }

  Future<void> _saveDraft() async {
    final validationErr = _validateInputs();
    if (validationErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(validationErr), backgroundColor: AppTheme.danger));
      return;
    }

    setState(() => _saving = true);
    try {
      final model = PackingWasteModel(
        id: _wasteId,
        wasteNumber: _wasteNumber,
        stationId: _selectedStationId,
        date: _date,
        status: 'draft',
        totalCropWasteCost: _totalCropWasteCost,
        totalSortingCost: _totalSortingCost,
        totalMaterialWasteCost: _totalMaterialWasteCost,
        totalCostItems: _totalCostItemsCost,
        totalWasteAmount: _grandTotal,
        notes: {
          'fruit_waste_items': _cropWasteItems,
          'material_waste_items': _materialWasteItems,
          'cost_items': _costItems,
        },
      );
      _wasteId = await _dao.saveDraft(model);
      DataChangeEventBus.instance.notifyPackingWastesChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المسودة بنجاح'), backgroundColor: AppTheme.success));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppTheme.background, body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: Text(
            'إذن هالك تعبئة - $_wasteNumber',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            if (_status == 'completed' && _journalEntryId != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ElevatedButton.icon(
                  onPressed: () {
                    JournalEntryNavigationService.openById(context, journalEntryId: _journalEntryId!);
                  },
                  icon: const Icon(Icons.receipt_long, size: 16, color: Colors.white),
                  label: const Text('عرض القيد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            if (!_isViewOnly) ...[
              ElevatedButton.icon(
                onPressed: _canSave ? _saveDraft : null,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('حفظ كمسودة', style: TextStyle(fontFamily: 'Cairo')),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 16),
              _buildCropWasteSection(),
              const SizedBox(height: 16),
              _buildMaterialWasteSection(),
              const SizedBox(height: 16),
              _buildCostItemsSection(),
              const SizedBox(height: 16),
              _buildSummaryCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            if (isNarrow) {
              return Column(
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _selectedStationId,
                    decoration: const InputDecoration(labelText: 'المحطة / المخزن', labelStyle: TextStyle(fontFamily: 'Cairo')),
                    items: _stations.map((s) {
                      final sId = int.tryParse(s.id ?? '') ?? 0;
                      return DropdownMenuItem(value: sId, child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')));
                    }).toList(),
                    onChanged: !_isViewOnly
                        ? (val) {
                            if (val != null) {
                              setState(() => _selectedStationId = val);
                              _loadStationBatches(val);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    readOnly: true,
                    controller: TextEditingController(text: DateFormat('yyyy/MM/dd').format(_date)),
                    decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today)),
                    onTap: !_isViewOnly
                        ? () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                              locale: const Locale('ar'),
                            );
                            if (picked != null) setState(() => _date = picked);
                          }
                        : null,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedStationId,
                    decoration: const InputDecoration(labelText: 'المحطة / المخزن', labelStyle: TextStyle(fontFamily: 'Cairo')),
                    items: _stations.map((s) {
                      final sId = int.tryParse(s.id ?? '') ?? 0;
                      return DropdownMenuItem(value: sId, child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')));
                    }).toList(),
                    onChanged: !_isViewOnly
                        ? (val) {
                            if (val != null) {
                              setState(() => _selectedStationId = val);
                              _loadStationBatches(val);
                            }
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    controller: TextEditingController(text: DateFormat('yyyy/MM/dd').format(_date)),
                    decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today)),
                    onTap: !_isViewOnly
                        ? () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                              locale: const Locale('ar'),
                            );
                            if (picked != null) setState(() => _date = picked);
                          }
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── 1. قسم المحاصيل (الإجمالي المسحوب = الهالك + الفرز) ──
  Widget _buildCropWasteSection() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text('🌾 هالك وفرز المحاصيل', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Text('(اختياري)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                  ],
                ),
                if (!_isViewOnly)
                  ElevatedButton.icon(
                    onPressed: _addCropWasteRow,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('إضافة محصول', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.navyLight),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (_cropWasteItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لم يتم تحديد هالك محاصيل في هذا الإذن', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _cropWasteItems.length,
                itemBuilder: (ctx, idx) => _buildCropRow(idx),
              ),
          ],
        ),
      ),
    );
  }

  void _addCropWasteRow() {
    if (_availableCropBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد دفعات محاصيل متوفرة في المحطة المختارة')));
      return;
    }
    final b = _availableCropBatches.first;
    final unitCostEgp = b.unitCost * (b.exchangeRate > 0 ? b.exchangeRate : 1.0);
    setState(() {
      _cropWasteItems.add({
        'batch_id': b.id,
        'product_name': b.productName,
        'product_code': b.productCode,
        'unit_cost': unitCostEgp,
        'unit_cost_orig': b.unitCost,
        'currency': b.currency,
        'exchange_rate': b.exchangeRate,
        'total_drawn_weight': 0.0,
        'waste_weight': 0.0,
        'sorting_weight': 0.0,
        'waste_cost': 0.0,
        'sorting_cost': 0.0,
      });
    });
  }

  Widget _buildCropRow(int idx) {
    final item = _cropWasteItems[idx];
    final totalDrawn = (item['total_drawn_weight'] as num?)?.toDouble() ?? 0.0;
    final wasteWeight = (item['waste_weight'] as num?)?.toDouble() ?? 0.0;
    final sortingWeight = (item['sorting_weight'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final origCost = (item['unit_cost_orig'] as num?)?.toDouble() ?? unitCost;
    final currency = (item['currency'] as String?) ?? 'EGP';
    final exRate = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;

    return Container(
      key: ValueKey('crop_item_${idx}_${item['batch_id']}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x15FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                DropdownButtonFormField<int>(
                  initialValue: item['batch_id'] as int?,
                  decoration: const InputDecoration(labelText: 'دفعة المحصول'),
                  isExpanded: true,
                  items: _availableCropBatches.map((b) {
                    final costEgp = b.unitCost * (b.exchangeRate > 0 ? b.exchangeRate : 1.0);
                    final costLabel = b.currency != 'EGP' && b.currency.isNotEmpty
                        ? '${b.unitCost.toStringAsFixed(2)} ${b.currency} (×${b.exchangeRate.toStringAsFixed(2)} = ${costEgp.toStringAsFixed(2)} ج.م/كجم)'
                        : '${costEgp.toStringAsFixed(2)} ج.م/كجم';
                    return DropdownMenuItem(
                      value: b.id,
                      child: Text('${b.productName} (متاح: ${b.remainingQuantity} كجم) | $costLabel', style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                    );
                  }).toList(),
                  onChanged: !_isViewOnly
                      ? (val) {
                          final b = _availableCropBatches.firstWhere((e) => e.id == val);
                          final unitCostEgp = b.unitCost * (b.exchangeRate > 0 ? b.exchangeRate : 1.0);
                          setState(() {
                            item['batch_id'] = b.id;
                            item['product_name'] = b.productName;
                            item['product_code'] = b.productCode;
                            item['unit_cost'] = unitCostEgp;
                            item['unit_cost_orig'] = b.unitCost;
                            item['currency'] = b.currency;
                            item['exchange_rate'] = b.exchangeRate;
                            item['waste_cost'] = wasteWeight * unitCostEgp;
                            item['sorting_cost'] = sortingWeight * unitCostEgp;
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.navyLight.withAlpha(80),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Text(
                    'سعر تكلفة الكيلو: ${unitCost.toStringAsFixed(2)} ج.م${currency != 'EGP' ? ' (${origCost.toStringAsFixed(2)} $currency @ صرف $exRate)' : ''}',
                    style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: totalDrawn > 0 ? totalDrawn.toString() : '',
                        decoration: const InputDecoration(
                          labelText: 'الكمية المسحوبة (كجم)',
                          hintText: 'إجمالي السحب',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final d = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['total_drawn_weight'] = d;
                            item['waste_cost'] = wasteWeight * unitCost;
                            item['sorting_cost'] = sortingWeight * unitCost;
                          });
                        },
                      ),
                    ),
                    if (!_isViewOnly) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: AppTheme.danger, size: 20),
                        onPressed: () => setState(() => _cropWasteItems.removeAt(idx)),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: item['batch_id'] as int?,
                            decoration: const InputDecoration(labelText: 'دفعة المحصول'),
                            isExpanded: true,
                            items: _availableCropBatches.map((b) {
                              final costEgp = b.unitCost * (b.exchangeRate > 0 ? b.exchangeRate : 1.0);
                              final costLabel = b.currency != 'EGP' && b.currency.isNotEmpty
                                  ? '${b.unitCost.toStringAsFixed(2)} ${b.currency} (×${b.exchangeRate.toStringAsFixed(2)} = ${costEgp.toStringAsFixed(2)} ج.م/كجم)'
                                  : '${costEgp.toStringAsFixed(2)} ج.م/كجم';
                              return DropdownMenuItem(
                                value: b.id,
                                child: Text('${b.productName} (متاح: ${b.remainingQuantity} كجم) | $costLabel', style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                              );
                            }).toList(),
                            onChanged: !_isViewOnly
                                ? (val) {
                                    final b = _availableCropBatches.firstWhere((e) => e.id == val);
                                    final unitCostEgp = b.unitCost * (b.exchangeRate > 0 ? b.exchangeRate : 1.0);
                                    setState(() {
                                      item['batch_id'] = b.id;
                                      item['product_name'] = b.productName;
                                      item['product_code'] = b.productCode;
                                      item['unit_cost'] = unitCostEgp;
                                      item['unit_cost_orig'] = b.unitCost;
                                      item['currency'] = b.currency;
                                      item['exchange_rate'] = b.exchangeRate;
                                      item['waste_cost'] = wasteWeight * unitCostEgp;
                                      item['sorting_cost'] = sortingWeight * unitCostEgp;
                                    });
                                  }
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'سعر الكيلو: ${unitCost.toStringAsFixed(2)} ج.م${currency != 'EGP' ? ' (${origCost.toStringAsFixed(2)} $currency @ صرف $exRate)' : ''}',
                            style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: totalDrawn > 0 ? totalDrawn.toString() : '',
                        decoration: const InputDecoration(
                          labelText: 'الكمية المسحوبة (كجم)',
                          hintText: 'إجمالي السحب',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final d = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['total_drawn_weight'] = d;
                            item['waste_cost'] = wasteWeight * unitCost;
                            item['sorting_cost'] = sortingWeight * unitCost;
                          });
                        },
                      ),
                    ),
                    if (!_isViewOnly)
                      IconButton(
                        icon: const Icon(Icons.delete, color: AppTheme.danger, size: 20),
                        onPressed: () => setState(() => _cropWasteItems.removeAt(idx)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (isNarrow) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: wasteWeight > 0 ? wasteWeight.toString() : '',
                        decoration: const InputDecoration(labelText: 'كمية الهالك (كجم)', hintText: 'حساب 51102'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final w = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['waste_weight'] = w;
                            item['waste_cost'] = w * unitCost;
                            if (totalDrawn > 0 && w <= totalDrawn && sortingWeight == 0.0) {
                              final rem = totalDrawn - w;
                              item['sorting_weight'] = rem;
                              item['sorting_cost'] = rem * unitCost;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: sortingWeight > 0 ? sortingWeight.toString() : '',
                        decoration: const InputDecoration(labelText: 'كمية الفرز (كجم)', hintText: 'مخزون 1032'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final s = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['sorting_weight'] = s;
                            item['sorting_cost'] = s * unitCost;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: wasteWeight > 0 ? wasteWeight.toString() : '',
                        decoration: const InputDecoration(labelText: 'كمية الهالك (كجم)', hintText: 'حساب 51102'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final w = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['waste_weight'] = w;
                            item['waste_cost'] = w * unitCost;
                            if (totalDrawn > 0 && w <= totalDrawn && sortingWeight == 0.0) {
                              final rem = totalDrawn - w;
                              item['sorting_weight'] = rem;
                              item['sorting_cost'] = rem * unitCost;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: sortingWeight > 0 ? sortingWeight.toString() : '',
                        decoration: const InputDecoration(labelText: 'كمية الفرز (كجم)', hintText: 'مخزون 1032'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        readOnly: _isViewOnly,
                        onChanged: (val) {
                          final s = double.tryParse(val) ?? 0.0;
                          setState(() {
                            item['sorting_weight'] = s;
                            item['sorting_cost'] = s * unitCost;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── 2. قسم مواد التعبئة والتغليف ──
  Widget _buildMaterialWasteSection() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in _materialWasteItems) {
      final code = item['product_code']?.toString() ?? item['product_name']?.toString() ?? '';
      grouped.putIfAbsent(code, () => []).add(item);
    }

    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text('📦 هالك مواد التعبئة والتغليف',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Text('(اختياري)',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                  ],
                ),
                if (!_isViewOnly)
                  ElevatedButton.icon(
                    onPressed: () => _showMaterialWasteForm(),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('إضافة مادة تالفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.navyLight),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (_materialWasteItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لم يتم تحديد هالك مواد تعبئة في هذا الإذن',
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
              )
            else
              ...grouped.entries.map((group) {
                final items = group.value;
                final firstItem = items.first;
                final cleanName = (firstItem['product_name']?.toString() ?? '').replaceAll(' (مادة تعبئة)', '');
                final productCode = firstItem['product_code']?.toString() ?? '';
                final groupQty = items.fold<double>(0.0, (s, i) => s + ((i['waste_qty'] ?? 0) as num).toDouble());
                final groupTotal = items.fold<double>(0.0, (s, i) => s + ((i['total_cost'] ?? 0) as num).toDouble());

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x15FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cleanName,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                            ),
                          ),
                          Text(
                            '${groupTotal.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                          if (!_isViewOnly) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _showMaterialWasteForm(editProductCode: productCode.isNotEmpty ? productCode : cleanName),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _materialWasteItems.removeWhere((item) =>
                                      (productCode.isNotEmpty && item['product_code'] == productCode) ||
                                      item['product_name'] == firstItem['product_name']);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        productCode.isNotEmpty
                            ? 'كود: $productCode | إجمالي الهالك: ${groupQty.toStringAsFixed(1)} وحدة'
                            : 'إجمالي الهالك: ${groupQty.toStringAsFixed(1)} وحدة',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 6),
                      ...items.asMap().entries.map((entry) {
                        final batchIdx = entry.key;
                        final item = entry.value;
                        final batchNum = batchIdx + 1;
                        final invNum = item['invoice_number']?.toString() ?? '';
                        final sName = item['supplier_name']?.toString() ?? '';
                        final isOpening = item['source_type'] == 'opening';
                        final qty = ((item['waste_qty'] ?? 0) as num).toDouble();
                        final unitCost = ((item['unit_cost'] ?? 0) as num).toDouble();
                        final lineTotal = ((item['total_cost'] ?? (qty * unitCost)) as num).toDouble();

                        var badgeText = 'دفعة $batchNum';
                        if (invNum.isNotEmpty) badgeText += ' (فاتورة $invNum)';
                        if (sName.isNotEmpty) badgeText += ' | $sName';
                        if (isOpening) badgeText += ' (رصيد سابق)';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Text(
                                badgeText,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${qty.toStringAsFixed(1)} × ${unitCost.toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${lineTotal.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  double _getRemainingMaterialQty(StationProductModel product, {String? excludeProductCode}) {
    double totalBatchRem = 0;
    for (final b in _availableMaterialBatches) {
      if ((b.productCode.isNotEmpty && b.productCode == product.productCode) ||
          (b.productName == product.productName)) {
        if (b.remainingQuantity > 0) {
          totalBatchRem += b.remainingQuantity;
        }
      }
    }
    double alreadyClaimed = 0;
    for (final item in _materialWasteItems) {
      if (excludeProductCode != null &&
          (item['product_code'] == excludeProductCode || item['product_name'] == excludeProductCode)) {
        continue;
      }
      if ((item['product_code'] != null && item['product_code'] == product.productCode) ||
          (item['product_name'] == product.productName)) {
        alreadyClaimed += ((item['waste_qty'] ?? 0) as num).toDouble();
      }
    }
    final rem = totalBatchRem > 0 ? totalBatchRem : product.quantity;
    return (rem - alreadyClaimed).clamp(0.0, double.infinity);
  }

  void _showMaterialWasteForm({String? editProductCode}) {
    if (_selectedStationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المحطة / المخزن أولاً'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    int? selectedIdx;
    if (editProductCode != null) {
      selectedIdx = _materialProducts.indexWhere((p) => p.productCode == editProductCode || p.productName == editProductCode);
      if (selectedIdx == -1) selectedIdx = null;
    }

    final requestedQtyCtrl = TextEditingController();
    final materialSearchCtrl = TextEditingController();
    if (selectedIdx != null) {
      materialSearchCtrl.text = _materialProducts[selectedIdx].productName.replaceAll(' (مادة تعبئة)', '');
    }

    List<Map<String, dynamic>> batches = [];
    List<TextEditingController> batchQtyCtrls = [];
    bool loadingBatches = false;
    int currentFetchId = 0;

    Future<void> fetchBatches(int idx, void Function(void Function()) setDialogState) async {
      if (idx < 0 || idx >= _materialProducts.length) return;
      final selectedProduct = _materialProducts[idx];
      final fetchId = ++currentFetchId;

      setDialogState(() {
        loadingBatches = true;
        batches = [];
        batchQtyCtrls = [];
      });

      try {
        final data = await _client
            .from('station_product_batches')
            .select('id, unit_cost, remaining_quantity, created_at, source_type, supplier_name, exchange_rate, currency, product_code, product_name, purchase_invoices(invoice_number)')
            .eq('station_id', _selectedStationId!)
            .gt('remaining_quantity', 0)
            .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual'])
            .order('created_at', ascending: true);

        if (fetchId != currentFetchId) return;

        final filteredData = (data as List).where((b) {
          final bCode = b['product_code']?.toString() ?? '';
          final bName = b['product_name']?.toString() ?? '';
          final bSrc = b['source_type']?.toString() ?? '';
          if (bSrc == 'lot_receipt' || bSrc == 'crop_purchase') return false;
          if (selectedProduct.productCode.isNotEmpty && bCode == selectedProduct.productCode) return true;
          if (bName == selectedProduct.productName || bName.replaceAll(' (مادة تعبئة)', '') == selectedProduct.productName.replaceAll(' (مادة تعبئة)', '')) return true;
          return false;
        }).toList();

        final mappedBatches = filteredData.map((b) {
          final rawEx = (b['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          return {
            'batch_id': b['id'],
            'product_code': b['product_code']?.toString() ?? '',
            'product_name': b['product_name']?.toString() ?? '',
            'unit_cost': (b['unit_cost'] as num?)?.toDouble() ?? 0.0,
            'remaining': (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
            'created_at': b['created_at']?.toString() ?? '',
            'source_type': b['source_type']?.toString() ?? '',
            'supplier_name': b['supplier_name']?.toString() ?? '',
            'exchange_rate': rawEx == 0.0 ? 1.0 : rawEx,
            'currency': b['currency']?.toString() ?? 'EGP',
            'invoice_number': (b['purchase_invoices'] is Map) ? (b['purchase_invoices']['invoice_number']?.toString() ?? '') : '',
          };
        }).toList();

        for (int i = 0; i < mappedBatches.length; i++) {
          final bId = mappedBatches[i]['batch_id'];
          double claimedQty = 0;
          for (final item in _materialWasteItems) {
            if (editProductCode != null &&
                (item['product_code'] == editProductCode || item['product_name'] == editProductCode)) {
              continue;
            }
            if ((item['product_code'] == selectedProduct.productCode || item['product_name'] == selectedProduct.productName) &&
                item['batch_id'] == bId) {
              claimedQty += ((item['waste_qty'] ?? 0) as num).toDouble();
            }
          }
          final currentRem = ((mappedBatches[i]['remaining'] ?? 0) as num).toDouble();
          mappedBatches[i]['remaining'] = (currentRem - claimedQty).clamp(0.0, double.infinity);
        }

        mappedBatches.removeWhere((b) => ((b['remaining'] ?? 0) as num).toDouble() <= 0);

        batches = mappedBatches;
        batchQtyCtrls = List.generate(batches.length, (_) => TextEditingController());

        if (editProductCode != null) {
          double totalUsed = 0;
          for (int i = 0; i < batches.length; i++) {
            final bId = batches[i]['batch_id'];
            final existingItem = _materialWasteItems.where((item) =>
                (item['product_code'] == editProductCode || item['product_name'] == editProductCode) &&
                (item['batch_id'] == bId || (item['batch_id'] == null && batches.length == 1))).firstOrNull;
            if (existingItem != null) {
              final used = ((existingItem['waste_qty'] ?? 0) as num).toDouble();
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
          if (editProductCode != null && selectedIdx != null && batches.isEmpty && loadingBatches) {
            fetchBatches(selectedIdx!, setDialogState);
          }

          final totalAllocated = batchQtyCtrls.fold<double>(0.0, (s, c) => s + (double.tryParse(c.text) ?? 0));
          final requestedQty = double.tryParse(requestedQtyCtrl.text) ?? 0;
          final hasMismatch = requestedQty > 0 && (totalAllocated - requestedQty).abs() > 0.01;
          final hasOverflow = batches.asMap().entries.any((e) {
            final ctrl = batchQtyCtrls[e.key];
            final entered = double.tryParse(ctrl.text) ?? 0;
            return entered > ((e.value['remaining'] ?? 0) as num).toDouble() + 0.001;
          });
          final canAdd = selectedIdx != null && totalAllocated > 0 && !hasMismatch && !hasOverflow;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: Text(
              editProductCode != null ? 'تعديل مادة التعبئة التالفة' : 'إضافة مادة تعبئة تالفة',
              style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
                          _materialProducts[selectedIdx!].productName.replaceAll(' (مادة تعبئة)', ''),
                          valueColor: AppTheme.textPrimary,
                        ),
                      ] else ...[
                        TypeAheadField<int>(
                          controller: materialSearchCtrl,
                          autoFlipDirection: true,
                          hideOnEmpty: false,
                          hideOnError: true,
                          suggestionsCallback: (query) {
                            final available = _materialProducts.asMap().entries.toList();
                            if (query.isEmpty) {
                              return available.map((e) => e.key).toList();
                            }
                            final q = query.toLowerCase().trim();
                            return available
                                .where((e) =>
                                    e.value.productName.toLowerCase().contains(q) ||
                                    e.value.productCode.toLowerCase().contains(q))
                                .map((e) => e.key)
                                .toList();
                          },
                          itemBuilder: (context, idx) {
                            final p = _materialProducts[idx];
                            final rem = _getRemainingMaterialQty(p, excludeProductCode: editProductCode);
                            final cleanName = p.productName.replaceAll(' (مادة تعبئة)', '');
                            return ListTile(
                              dense: true,
                              title: Text(cleanName,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'المتوفر: ${rem.toStringAsFixed(1)} | كود: ${p.productCode}',
                                style: TextStyle(color: rem > 0 ? AppTheme.textSecondary : AppTheme.danger, fontFamily: 'Cairo', fontSize: 11),
                              ),
                            );
                          },
                          onSelected: (idx) {
                            selectedIdx = idx;
                            batches = [];
                            batchQtyCtrls = [];
                            requestedQtyCtrl.clear();
                            materialSearchCtrl.text = _materialProducts[idx].productName.replaceAll(' (مادة تعبئة)', '');
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
                              decoration: _inputDecoration('بحث بالاسم أو الكود'),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                            );
                          },
                        ),
                      ],
                      if (selectedIdx != null) ...[
                        const SizedBox(height: 14),
                        _infoRow(
                          'الكمية المتوفرة بالمخزن',
                          '${_getRemainingMaterialQty(_materialProducts[selectedIdx!], excludeProductCode: editProductCode).toStringAsFixed(1)} وحدة',
                          valueColor: AppTheme.success,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: requestedQtyCtrl,
                          decoration: _inputDecoration('الكمية التالفة المطلوبة'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                          onChanged: (v) {
                            final qty = double.tryParse(v) ?? 0;
                            if (qty <= 0 || batches.isEmpty) return;
                            double remaining = qty;
                            for (int i = 0; i < batches.length; i++) {
                              if (remaining <= 0) {
                                batchQtyCtrls[i].text = '';
                              } else {
                                final batchRem = ((batches[i]['remaining'] ?? 0) as num).toDouble();
                                final take = remaining < batchRem ? remaining : batchRem;
                                batchQtyCtrls[i].text = take > 0 ? take.toStringAsFixed(1) : '';
                              }
                              remaining -= (double.tryParse(batchQtyCtrls[i].text) ?? 0);
                            }
                            setDialogState(() {});
                          },
                        ),
                        if (loadingBatches)
                          const Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        if (!loadingBatches && batches.isEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'لا توجد دفعات متاحة لهذه المادة في هذا المخزن',
                                    style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
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
                            var title = 'الدفعة الوحيدة';
                            if (sName.isNotEmpty) title += ' | $sName';
                            if (isOpening) title += ' (رصيد سابق)';
                            final invNum = b['invoice_number']?.toString() ?? '';
                            if (invNum.isNotEmpty) title += ' | فاتورة: $invNum';
                            return _infoRow(
                              title,
                              '${((b['remaining'] ?? 0) as num).toDouble().toStringAsFixed(1)} وحدة',
                              valueColor: AppTheme.info,
                            );
                          }),
                          const SizedBox(height: 8),
                          TextField(
                            controller: batchQtyCtrls.isNotEmpty ? batchQtyCtrls[0] : null,
                            decoration: _inputDecoration('الكمية التالفة'),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ],
                        if (!loadingBatches && batches.length > 1) ...[
                          const SizedBox(height: 14),
                          ...List.generate(batches.length, (i) {
                            final b = batches[i];
                            final bDate = (b['created_at'] as String).length >= 10 ? (b['created_at'] as String).substring(0, 10) : '—';
                            final bRem = ((b['remaining'] ?? 0) as num).toDouble();
                            final bCost = ((b['unit_cost'] ?? 0) as num).toDouble();
                            final rawEx = (b['exchange_rate'] as num?)?.toDouble() ?? 1.0;
                            final bExchangeRate = rawEx == 0.0 ? 1.0 : rawEx;
                            final bCostEgp = bCost * bExchangeRate;
                            final bCurrency = b['currency']?.toString() ?? 'EGP';
                            final entered = double.tryParse(batchQtyCtrls[i].text) ?? 0;
                            final overLimit = entered > bRem + 0.001;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: overLimit ? AppTheme.danger : AppTheme.glassBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Builder(builder: (context) {
                                          final isOpening = b['source_type'] == 'opening';
                                          final sName = b['supplier_name']?.toString() ?? '';
                                          var title = 'دفعة ${i + 1} — $bDate';
                                          if (sName.isNotEmpty) title += ' | $sName';
                                          if (isOpening) title += ' (رصيد سابق)';
                                          final invNum = b['invoice_number']?.toString() ?? '';
                                          if (invNum.isNotEmpty) title += ' | فاتورة: $invNum';
                                          return Text(title,
                                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold));
                                        }),
                                      ),
                                      const SizedBox(width: 6),
                                      Builder(builder: (context) {
                                        final costStr = (bCurrency != 'EGP' && bExchangeRate != 1.0)
                                            ? '${bCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(bCurrency)}'
                                            : '${bCost.toStringAsFixed(2)} ج.م';
                                        return Text('متاح: ${bRem.toStringAsFixed(1)} | $costStr',
                                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo'));
                                      }),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: batchQtyCtrls[i],
                                          decoration: _inputDecoration('الكمية التالفة'),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                                          style: TextStyle(color: overLimit ? AppTheme.danger : Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                          onChanged: (_) => setDialogState(() {}),
                                        ),
                                      ),
                                      if (entered > 0) ...[
                                        const SizedBox(width: 8),
                                        Text('${(entered * bCostEgp).toStringAsFixed(2)} ج.م',
                                            textAlign: TextAlign.start,
                                            style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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
                              border: Border.all(color: hasMismatch || hasOverflow ? AppTheme.danger : AppTheme.success.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasMismatch || hasOverflow ? Icons.error_outline : Icons.check_circle_outline,
                                  size: 16,
                                  color: hasMismatch || hasOverflow ? AppTheme.danger : AppTheme.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    requestedQty > 0
                                        ? 'الإجمالي المسحوب: ${totalAllocated.toStringAsFixed(1)} / ${requestedQty.toStringAsFixed(1)}'
                                        : 'الإجمالي المسحوب: ${totalAllocated.toStringAsFixed(1)} وحدة',
                                    style: TextStyle(
                                      color: hasMismatch || hasOverflow ? AppTheme.danger : AppTheme.success,
                                      fontSize: 12,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (hasMismatch)
                                  const Text('يجب المطابقة', style: TextStyle(color: AppTheme.danger, fontSize: 11, fontFamily: 'Cairo')),
                                if (hasOverflow && !hasMismatch)
                                  const Text('كمية زائدة عن المتاح', style: TextStyle(color: AppTheme.danger, fontSize: 11, fontFamily: 'Cairo')),
                              ],
                            ),
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
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canAdd
                    ? () {
                        final product = _materialProducts[selectedIdx!];
                        setState(() {
                          if (editProductCode != null) {
                            _materialWasteItems.removeWhere((item) =>
                                (product.productCode.isNotEmpty && item['product_code'] == product.productCode) ||
                                item['product_name'] == product.productName);
                          }

                          for (int i = 0; i < batches.length; i++) {
                            final usedQty = double.tryParse(batchQtyCtrls[i].text) ?? 0;
                            if (usedQty <= 0) continue;

                            final rawEx = (batches[i]['exchange_rate'] as num?)?.toDouble() ?? 1.0;
                            final bExchangeRate = rawEx == 0.0 ? 1.0 : rawEx;
                            final bUnitCost = ((batches[i]['unit_cost'] ?? 0) as num).toDouble();
                            final bUnitCostEgp = bUnitCost * bExchangeRate;
                            final bCurrency = (batches[i]['currency'] as String?) ?? 'EGP';

                            _materialWasteItems.add({
                              'product_name': product.productName,
                              'product_code': product.productCode,
                              'waste_qty': usedQty,
                              'unit_cost': bUnitCostEgp,
                              'total_cost': usedQty * bUnitCostEgp,
                              'batch_id': batches[i]['batch_id'],
                              'exchange_rate': bExchangeRate,
                              'currency': bCurrency,
                              'invoice_number': batches[i]['invoice_number'],
                              'supplier_name': batches[i]['supplier_name'],
                              'source_type': batches[i]['source_type'],
                              'created_at': batches[i]['created_at'],
                            });
                          }
                        });
                        Navigator.pop(ctx);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: Text(
                  editProductCode != null ? 'حفظ التعديلات' : 'إضافة',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
      hintStyle: const TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo', fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.glassBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.glassBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor ?? AppTheme.textPrimary, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── 3. قسم بنود التكلفة الإضافية (نافذة منبثقة Dialog + تصنيفات ديناميكية) ──
  Widget _buildCostItemsSection() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _costItems.isEmpty ? AppTheme.danger : Colors.transparent, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    const Text('💰 بنود التكلفة والخدمات الإضافية', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.danger.withAlpha(35), borderRadius: BorderRadius.circular(6)),
                      child: const Text('إجباري (EGP فقط)', style: TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ],
                ),
                if (!_isViewOnly)
                  ElevatedButton.icon(
                    onPressed: _showCostItemDialog,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('إضافة بند تكلفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (_costItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '⚠️ يجب إضافة بند تكلفة واحد على الأقل (نقل، فرز وتدريج، عمالة) لتتمكن من حفظ وتأكيد إذن الهالك.',
                  style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo', fontSize: 13),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _costItems.length,
                itemBuilder: (ctx, idx) => _buildCostCard(idx),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostCard(int idx) {
    final item = _costItems[idx];
    final totalEgp = ((item['total_egp'] ?? item['amount'] ?? 0) as num).toDouble();
    const pText = 'آجل (حساب المورد)';
    const pColor = AppTheme.warning;
    final catName = item['category_name'] as String? ?? 'عام';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x15FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 500;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: pColor.withAlpha(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: pColor.withAlpha(80))),
                      child: const Text(pText, style: TextStyle(color: pColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'التصنيف: $catName | المورد: ${item['supplier_name'] ?? ''} | الكمية: ${((item['quantity'] ?? 1) as num).toDouble().toStringAsFixed(1)} | سعر الوحدة: ${((item['unit_price'] ?? totalEgp) as num).toDouble().toStringAsFixed(2)} ج.م',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${totalEgp.toStringAsFixed(2)} ج.م', style: const TextStyle(color: AppTheme.accent, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    if (!_isViewOnly)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppTheme.accent, size: 20),
                            onPressed: () => _showCostItemDialog(editIndex: idx),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppTheme.danger, size: 20),
                            onPressed: () => setState(() => _costItems.removeAt(idx)),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(item['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: pColor.withAlpha(25), borderRadius: BorderRadius.circular(12), border: Border.all(color: pColor.withAlpha(80))),
                          child: const Text(pText, style: TextStyle(color: pColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التصنيف: $catName | المورد: ${item['supplier_name'] ?? ''} | الكمية: ${((item['quantity'] ?? 1) as num).toDouble().toStringAsFixed(1)} | سعر الوحدة: ${((item['unit_price'] ?? totalEgp) as num).toDouble().toStringAsFixed(2)} ج.م',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
              ),
              Text('${totalEgp.toStringAsFixed(2)} ج.م', style: const TextStyle(color: AppTheme.accent, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              if (!_isViewOnly) ...[
                IconButton(
                  icon: const Icon(Icons.edit, color: AppTheme.accent, size: 20),
                  onPressed: () => _showCostItemDialog(editIndex: idx),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppTheme.danger, size: 20),
                  onPressed: () => setState(() => _costItems.removeAt(idx)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showCostItemDialog({int? editIndex}) {
    final isEdit = editIndex != null;
    final initialItem = isEdit ? _costItems[editIndex] : <String, dynamic>{};

    final nameCtrl = TextEditingController(text: initialItem['name'] as String? ?? '');
    final qtyCtrl = TextEditingController(text: ((initialItem['quantity'] ?? 1.0) as num).toDouble().toString());
    final priceCtrl = TextEditingController(text: ((initialItem['unit_price'] ?? (initialItem['total_egp'] ?? 0.0)) as num).toDouble().toString());
    final notesCtrl = TextEditingController(text: initialItem['notes'] as String? ?? '');

    String? selectedSupplierId = initialItem['supplier_id'] as String? ?? (_egpSuppliers.isNotEmpty ? _egpSuppliers.first.id : null);
    String? selectedSupplierName = initialItem['supplier_name'] as String? ?? (_egpSuppliers.isNotEmpty ? _egpSuppliers.first.name : '');
    int? selectedCategoryId = initialItem['report_category_id'] as int? ?? (_costCategories.isNotEmpty ? _costCategories.first['id'] as int? : null);
    String selectedCategoryName = initialItem['category_name'] as String? ?? (_costCategories.isNotEmpty ? _costCategories.first['name'] as String : 'عام');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final qty = double.tryParse(qtyCtrl.text) ?? 1.0;
          final unitPrice = double.tryParse(priceCtrl.text) ?? 0.0;
          final totalAmount = qty * unitPrice;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF102640),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(isEdit ? 'تعديل بند تكلفة' : 'إضافة بند تكلفة جديد', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'بيان الخدمة / التكلفة *', hintText: 'مثال: مصاريف فرز وتدريج، نقل عوادم'),
                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(labelText: 'تصنيف التكلفة *'),
                        items: _costCategories.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String, style: const TextStyle(fontFamily: 'Cairo')))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final matched = _costCategories.firstWhere((c) => c['id'] == val);
                            setDialogState(() {
                              selectedCategoryId = val;
                              selectedCategoryName = matched['name'] as String;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSupplierId,
                        decoration: const InputDecoration(labelText: 'المورد (بالجنيه المصري EGP فقط) *'),
                        items: _egpSuppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final s = _egpSuppliers.firstWhere((e) => e.id == val);
                            setDialogState(() {
                              selectedSupplierId = val;
                              selectedSupplierName = s.name;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: qtyCtrl,
                              decoration: const InputDecoration(labelText: 'الكمية'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: priceCtrl,
                              decoration: const InputDecoration(labelText: 'سعر الوحدة (ج.م) *'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primary.withAlpha(20), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.primary.withAlpha(50))),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text('الإجمالي المستحق:', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            Text('${totalAmount.toStringAsFixed(2)} ج.م', style: const TextStyle(color: AppTheme.primary, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(labelText: 'ملاحظات إضافية'),
                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
                ElevatedButton(
                  onPressed: nameCtrl.text.trim().isNotEmpty && totalAmount > 0 && selectedSupplierId != null
                      ? () {
                          final itemData = {
                            'name': nameCtrl.text.trim(),
                            'report_category_id': selectedCategoryId,
                            'category_name': selectedCategoryName,
                            'category': selectedCategoryName,
                            'supplier_id': selectedSupplierId,
                            'supplier_name': selectedSupplierName,
                            'currency': 'EGP',
                            'quantity': qty,
                            'unit_price': unitPrice,
                            'amount': totalAmount,
                            'total_egp': totalAmount,
                            'payment_source_type': 'none',
                            'payment_source_id': null,
                            'notes': notesCtrl.text.trim(),
                          };
                          setState(() {
                            if (isEdit) {
                              _costItems[editIndex] = itemData;
                            } else {
                              _costItems.add(itemData);
                            }
                          });
                          Navigator.pop(ctx);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: Text(isEdit ? 'حفظ التعديل' : 'إضافة', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ملخص التكلفة والقيد المحاسبي المتولد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(height: 12),
            _buildSummaryRow('هالك المحاصيل (مدين 51102):', _totalCropWasteCost),
            _buildSummaryRow('مخزون الفرز المستخرج (مدين 1032):', _totalSortingCost),
            _buildSummaryRow('هالك مواد التعبئة (مدين 51104):', _totalMaterialWasteCost),
            _buildSummaryRow('بنود التكلفة والخدمات الإضافية (مدين 51101):', _totalCostItemsCost),
            const Divider(height: 24),
            _buildSummaryRow('إجمالي حركة الهالك والفرز:', _grandTotal, isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, double val, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isTotal ? AppTheme.primary : AppTheme.textSecondary,
              fontFamily: 'Cairo',
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 15 : 13,
            ),
          ),
          Text(
            '${val.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              color: isTotal ? AppTheme.primary : Colors.white,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: isTotal ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
