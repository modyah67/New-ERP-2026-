import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import '../../core/data_change_event_bus.dart';
import 'packing_order_pdf_service.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class _LotEntry {
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

  double wastePercent = 0.0;

  double get grossWeight => batch?.remainingQuantity ?? lot?.grossWeightKg ?? 0;
  double get _partialWeight => double.tryParse(partialWeightCtrl.text) ?? 0;
  double get effectiveWeight {
    if (isCartonMode) {
      return usePartialCrop && retailCartons > 0
          ? retailCartons.toDouble()
          : totalCartonsFromLot.toDouble();
    }
    return usePartialCrop && _partialWeight > 0 ? _partialWeight : grossWeight;
  }

  double get wasteWeight =>
      isCartonMode ? 0.0 : effectiveWeight * (wastePercent / 100.0);

  bool get hasWaste => wasteCost > 0;
  double get netWeight => effectiveWeight;
  double get sortedWeight => isCartonMode
      ? sortingCartons.toDouble()
      : (double.tryParse(sortedWeightCtrl.text) ?? 0);

  int get cartonCount => int.tryParse(cartonCountCtrl.text) ?? 0;
  double get netWeightPerCartonValue =>
      double.tryParse(netWeightPerCartonCtrl.text) ?? 0;
  double get grossWeightPerCartonValue =>
      double.tryParse(grossWeightPerCartonCtrl.text) ?? 0;
  double get rawCartonWeight => cartonCount * netWeightPerCartonValue;

  double get totalNetWeight => cartonCount * netWeightPerCartonValue;
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
      return productCostPerKg * netWeightPerCartonValue;
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
      lot != null && cartonCount > 0 && netWeightPerCartonValue > 0;
  bool get isCartonWeightMismatch {
    if (lot == null || cartonCount == 0 || netWeightPerCartonValue == 0) {
      return false;
    }
    if (isCartonMode) {
      return (cartonCount + sortingCartons) > effectiveWeight + 0.01;
    }
    final totalAllocated =
        totalNetWeight + (hasSorting ? sortedWeight : 0.0) + wasteWeight;
    return (totalAllocated - effectiveWeight).abs() > 0.01;
  }

  void dispose() {
    partialWeightCtrl.dispose();
    sortedWeightCtrl.dispose();
    cartonCountCtrl.dispose();
    netWeightPerCartonCtrl.dispose();
    grossWeightPerCartonCtrl.dispose();
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
  final _lotDao = LotDao();
  final _stationDao = StationDao();
  final _stationProductDao = StationProductDao();
  final _sortingDao = PackingOrderSortingDao();
  final _rawMaterialDao = RawMaterialDao();

  List<StationModel> _stations = [];
  List<LotReceiptModel> _allLots = [];
  List<LotReceiptModel> _filteredLots = [];
  List<SupplierModel> _suppliers = [];
  List<StationProductBatch> _availableBatches = [];
  Map<String, double> _lotRemainingQuantities = {};
  List<Map<String, dynamic>> _costCategories = [];

  int? _selectedStationId;
  bool _loading = true;
  bool _saving = false;

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

  List<Map<String, dynamic>> _treasuries = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  final List<Map<String, dynamic>> _materialItems = [];
  final List<Map<String, dynamic>> _costItems = [];
  final List<_LotEntry> _lotEntries = [_LotEntry()];
  final _materialWastePercentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isEditing => widget.existingOrder != null;
  bool get _isViewOnly => widget.viewOnly;
  bool get _isConfirmed =>
      widget.existingOrder != null &&
      (widget.existingOrder!.status == 'completed' ||
          widget.existingOrder!.status == 'confirmed' ||
          widget.existingOrder!.journalEntryId != null);
  bool get _stockFieldsLocked => _isViewOnly || _isConfirmed;

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
        suppliers = await SupplierDao().getAll();
      } catch (e) {
        debugPrint('Error fetching suppliers: $e');
      }

      try {
        final catRes = await Supabase.instance.client
            .rpc('list_cost_report_categories', params: {'p_scope': 'packing'});
        if (catRes is List) {
          costCategories =
              catRes.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('Error fetching categories: $e');
      }

      try {
        final trRes = await Supabase.instance.client
            .from('treasuries')
            .select('id, name, treasury_balances(balance, currency)')
            .order('name');
        if (trRes is List) {
          treasuries = List<Map<String, dynamic>>.from(trRes);
        }
      } catch (e) {
        debugPrint('Error fetching treasuries: $e');
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

      if (mounted) {
        setState(() {
          _stations = stations;
          _allLots = lots;
          _suppliers = suppliers;
          _costCategories = costCategories;
          _treasuries = treasuries;
          _bankAccounts = bankAccounts;
          _loading = false;
        });

        if (_isEditing) {
          await _prefillFromOrder(widget.existingOrder!);
        }
      }
    } catch (e) {
      debugPrint('Error in _loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _prefillFromOrder(PackingOrderModel order) async {
    _selectedStationId = int.tryParse(order.stationId ?? '');

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

    if (notes.containsKey('materials')) {
      final mats = notes['materials'] as List?;
      if (mats != null) {
        for (final m in mats) {
          final map = Map<String, dynamic>.from(m as Map);
          map['total'] = ((map['used_qty'] ?? 0) as num).toDouble() *
              ((map['unit_cost'] ?? 0) as num).toDouble();
          _materialItems.add(map);
        }
      }
    }

    List<Map<String, dynamic>> dbCostItems = [];
    if (orderId != null) {
      dbCostItems = await _dao.getCostItemsRaw(orderId);
    }

    if (dbCostItems.isNotEmpty) {
      for (final c in dbCostItems) {
        _costItems.add(c);
      }
    } else if (notes.containsKey('cost_items')) {
      final items = notes['cost_items'] as List?;
      if (items != null) {
        for (final c in items) {
          _costItems.add(Map<String, dynamic>.from(c as Map));
        }
      }
    }

    if (notes.containsKey('material_waste_percent')) {
      _materialWastePercentCtrl.text =
          (notes['material_waste_percent'] as num?)?.toString() ?? '';
    }

    setState(() {});
  }

  Future<void> _filterLots(int stationId, {String? keepLotId}) async {
    try {
      final lots = await _lotDao.getAll();
      if (mounted) _allLots = lots;
    } catch (_) {}
    final stationStr = stationId.toString();
    _filteredLots = _allLots
        .where((l) =>
            l.stationId == stationStr &&
            (l.status == 'received' ||
                l.status == 'sorting' ||
                l.id == keepLotId))
        .toList();
  }

  void _filterLotsFromCache(int stationId) {
    final stationStr = stationId.toString();
    _filteredLots = _allLots
        .where((l) =>
            l.stationId == stationStr &&
            (l.status == 'received' || l.status == 'sorting'))
        .toList();
  }

  Future<void> _fetchLotRemainingQuantities(int stationId,
      {String? keepBatchId, Set<String>? keepBatchIds}) async {
    try {
      final batchesData = await Supabase.instance.client
          .from('station_product_batches')
          .select()
          .eq('station_id', stationId)
          .order('created_at', ascending: true);

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

      final Map<String, double> remQtys = {};
      final Map<String, double> origQtys = {};
      for (final b in cropBatches) {
        final code = b.productCode;
        if (code.isNotEmpty) {
          remQtys[code] = (remQtys[code] ?? 0.0) + b.remainingQuantity;
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
          _availableBatches = cropBatches
              .where((b) =>
                  b.remainingQuantity > 0 || keepIds.contains(b.id.toString()))
              .toList();
          _lotRemainingQuantities = newRemQuantities;
        });
      }
    } catch (e) {
      debugPrint('Error fetching remaining quantities: $e');
    }
  }

  Future<void> _loadMaterialProducts(int stationId) async {
    try {
      List<RawMaterialModel> rawMats = [];
      try {
        rawMats = await _rawMaterialDao.getAll();
      } catch (e) {
        debugPrint('Error fetching raw materials: $e');
      }

      final batchData = await Supabase.instance.client
          .from('station_product_batches')
          .select(
              'id, product_code, product_name, remaining_quantity, quantity, source_type')
          .eq('station_id', stationId)
          .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual']);

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
          final name =
              batchNameByCode[entry.key] ?? 'مادة تعبئة ${entry.key}';
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
            netWeightPerCarton: e.netWeightPerCartonValue,
            grossWeightPerCarton: e.grossWeightPerCartonValue > 0
                ? e.grossWeightPerCartonValue
                : e.netWeightPerCartonValue,
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
      );

  double get _totalFruitCost => _calcResult.finalCost.fruitCost;
  double get _totalMaterialCost => _calcResult.materials.materialCost;
  double get _totalMaterialWasteCost => _calcResult.materials.wasteCost;
  double get _totalCostItems => _calcResult.costItems.totalCostItems;
  int get _totalCartons => _calcResult.weights.totalCartons;
  double get _totalNetWeight => _calcResult.weights.totalNetWeight;
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
    _materialWastePercentCtrl.dispose();
    for (final e in _lotEntries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: AppTheme.backgroundGradient,
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
                        _buildHeader(),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildCard(
                                  'اختر المخزن', _buildWarehouseSection()),
                              const SizedBox(height: 16),
                              if (_selectedStationId != null) ...[
                                ..._buildLotEntries(),
                                const SizedBox(height: 16),
                                _buildCard(
                                    'مواد التعبئة', _buildMaterialsSection()),
                                const SizedBox(height: 16),
                                _buildCard('نسبة فقد مواد التعبئة',
                                    _buildMaterialWasteSection()),
                                const SizedBox(height: 16),
                                _buildCard(
                                    'بنود التكلفة', _buildCostItemsSection()),
                                const SizedBox(height: 16),
                                _buildCard('الملخص', _buildSummarySection()),
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

  Widget _buildHeader() {
    final status = widget.existingOrder?.status ?? 'pending';
    final isDraft = status == 'pending' || status == 'draft';
    final isCompleted = status == 'completed';
    final statusColor = isDraft
        ? AppTheme.warning
        : (isCompleted ? AppTheme.success : AppTheme.danger);
    final statusLabel = isDraft ? 'مسودة' : (isCompleted ? 'مؤكد' : 'ملغي');

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
            color: const Color(0x3805192D),
            border: Border(
                bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
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
                              fontWeight: FontWeight.w600,
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
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  if (_isEditing &&
                      isCompleted &&
                      widget.existingOrder?.journalEntryId != null)
                    _buildHeaderViewEntryButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderConfirmButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton.icon(
        onPressed: _saving ? null : () => _confirmOrder(),
        icon: const Icon(Icons.check_circle_outline,
            size: 18, color: Colors.white),
        label: const Text('تأكيد',
            style: TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.success,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildHeaderViewEntryButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton.icon(
        onPressed: () async {
          final journalEntryId = widget.existingOrder!.journalEntryId;
          final packingOrderId = widget.existingOrder!.id;
          debugPrint('═══════════════════════════════════════════');
          debugPrint('PackingOrder: عرض القيد المحاسبي');
          debugPrint('  PackingOrder ID = $packingOrderId');
          debugPrint(
              '  PackingOrder Number = ${widget.existingOrder!.orderNumber}');
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
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('هل أنت متأكد من حذف المسودة؟',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text(
            'سيتم حذف المسودة نهائياً ولن يمكنك التراجع عن هذا الإجراء.',
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('حذف',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
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


  Future<void> _confirmOrder() async {
    if (widget.existingOrder?.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('تأكيد أمر التعبئة',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: const Text(
            'سيتم خصم المحاصيل ومواد التعبئة من المخزن.\nهل أنت متأكد؟',
            style:
                TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('تأكيد',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);

    final error = await _dao.confirmOrder(int.parse(widget.existingOrder!.id!));
    if (mounted) {
      setState(() => _saving = false);
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تأكيد أمر التعبئة بنجاح'),
            backgroundColor: AppTheme.success));
        DataChangeEventBus.instance.notifyStationsChanged();
        DataChangeEventBus.instance.notifyCropPurchasesChanged();
        DataChangeEventBus.instance.notifyItemsChanged();
        DataChangeEventBus.instance.notifySuppliersChanged();
        context.pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('خطأ: $error'), backgroundColor: AppTheme.danger));
      }
    }
  }


  Widget _buildCard(String title, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0x8C05192D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.15),
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
                    style: const TextStyle(
                        color: AppTheme.primary,
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

  Widget _buildWarehouseSection() {
    int getStationKey(StationModel s) {
      return int.tryParse(s.id ?? '') ?? s.id.hashCode.abs();
    }

    final validStationIds = _stations.map(getStationKey).toSet();

    final selectedValue = validStationIds.contains(_selectedStationId)
        ? _selectedStationId
        : null;

    return DropdownButtonFormField<int>(
      value: selectedValue,
      decoration: _inputDecoration('المخزن'),
      dropdownColor: const Color(0xFF05192D),
      style: const TextStyle(
          color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
      items: _stations.map((s) {
        final stId = getStationKey(s);
        return DropdownMenuItem<int>(
          value: stId,
          child: Text(
            s.name,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
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

  bool _hasAnyLotsSelected() => _lotEntries.any((e) => e.lot != null);

  Future<bool> _showWarehouseChangeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2940),
        title: const Text('تأكيد تغيير المخزن',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        content: const Text('سيتم مسح جميع المحاصيل المحددة. هل أنت متأكد؟',
            style:
                TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            child: const Text('تأكيد', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  List<Widget> _buildLotEntries() {
    final widgets = <Widget>[];
    for (int i = 0; i < _lotEntries.length; i++) {
      widgets.add(_buildLotEntryCard(i));
      widgets.add(const SizedBox(height: 16));
    }
    if (!_isViewOnly && !_stockFieldsLocked) {
      widgets.add(_buildAddLotButton());
      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
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
    final selectedIds = _lotEntries
        .where((e) => e != entry && e.batch != null)
        .map((e) => e.batch!.id)
        .toSet();
    final options = entry.batch != null
        ? [
            ..._availableBatches.where(
                (b) => b.id != entry.batch!.id && !selectedIds.contains(b.id)),
            entry.batch!,
          ]
        : _availableBatches.where((b) => !selectedIds.contains(b.id)).toList();

    return DropdownButtonFormField<int>(
      initialValue: entry.batch?.id,
      decoration: _inputDecoration('اختر الدفعة'),
      dropdownColor: const Color(0xFF05192D),
      style: const TextStyle(
          color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
      isExpanded: true,
      items: options.map((b) {
        final matchedLot = _allLots.firstWhere(
          (l) => l.lotNumber == b.productCode,
          orElse: () => LotReceiptModel(
              lotNumber: b.productCode,
              productName: b.productName,
              receiptDate: DateTime.now(),
              purchaseMode: 'weight'),
        );
        final isCarton = matchedLot.purchaseMode == 'carton';
        final remainingDisplay = b.remainingQuantity.toStringAsFixed(0);
        final unit = isCarton ? 'كرتونة' : 'كجم';
        final displayPrice = b.unitCost;
        return DropdownMenuItem<int>(
          value: b.id!,
          child: Text(
            '${b.productCode} — ${b.productName} (سعر ${displayPrice.toStringAsFixed(2)}) — متاح $remainingDisplay $unit',
            style: const TextStyle(fontFamily: 'Cairo'),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: (v) {
        setState(() {
          final batch =
              v != null ? _availableBatches.firstWhere((b) => b.id == v) : null;
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
                lot.weightPerCartonKg != null && lot.weightPerCartonKg! > 0
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

          if (entry.lot != null) {
            final lot = entry.lot!;
            final remaining = entry.batch?.remainingQuantity ?? 0.0;
            final isCarton = lot.purchaseMode == 'carton';
            entry.usePartialCrop = true;
            if (isCarton) {
              entry.partialWeightCtrl.text = remaining.toInt().toString();
            } else {
              entry.partialWeightCtrl.text = remaining.toStringAsFixed(2);
            }
            entry.updateCartonCountFromDeductions();
          }
        });
      },
      validator: (v) => v == null ? 'اختر الدفعة' : null,
    );
  }

  Widget _buildEntryWeightSection(_LotEntry entry) {
    final lot = entry.lot!;
    final isCarton = entry.isCartonMode;
    final remaining = entry.batch?.remainingQuantity ?? 0.0;
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
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontFamily: 'Cairo')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
              ),
            ),
          ],
        ),
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
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            onChanged: (_) {
              setState(() {});
              entry.updateCartonCountFromDeductions();
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
              if (n > remaining && !_stockFieldsLocked)
                return 'الكمية تتجاوز الوزن المتبقي (${remaining.toStringAsFixed(1)} كجم)';
              return null;
            },
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                value: entry.wastePercent == 2.0,
                onChanged: _stockFieldsLocked
                    ? null
                    : (v) {
                        setState(() {
                          entry.wastePercent = (v == true) ? 2.0 : 0.0;
                        });
                      },
                title: const Text('هالك 2%',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontFamily: 'Cairo')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CheckboxListTile(
                value: entry.wastePercent == 5.0,
                onChanged: _stockFieldsLocked
                    ? null
                    : (v) {
                        setState(() {
                          entry.wastePercent = (v == true) ? 5.0 : 0.0;
                        });
                      },
                title: const Text('هالك 5%',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontFamily: 'Cairo')),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
              ),
            ),
          ],
        ),
        if (entry.wastePercent > 0) ...[
          const SizedBox(height: 4),
          if (!isCarton) ...[
            _infoRow(
                'وزن الهالك (${entry.wastePercent.toInt()}%)',
                '${entry.wasteWeight.toStringAsFixed(2)} كجم',
                valueColor: AppTheme.warning),
            const SizedBox(height: 4),
          ],
          _infoRow(
              'تكلفة الهالك (${entry.wastePercent.toInt()}%)',
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
                        });
                      },
                title: const Text('يوجد فرز',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
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
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            onChanged: (_) {
              setState(() {});
              entry.updateCartonCountFromDeductions();
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
              color: isCartonMode ? AppTheme.info : Colors.white,
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: isCartonMode ? FontWeight.bold : FontWeight.normal),
          onChanged: isCartonMode ? null : (_) => setState(() {}),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            if (n == null || n <= 0) return 'أدخل عدداً صحيحاً موجباً';
            return null;
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: entry.netWeightPerCartonCtrl,
          readOnly: isCartonMode,
          decoration: _inputDecoration('الوزن الصافي للكرتونة (كجم)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
          ],
          style: TextStyle(
              color: isCartonMode ? AppTheme.textSecondary : Colors.white,
              fontFamily: 'Cairo',
              fontSize: 15),
          onChanged: isCartonMode ? null : (_) => setState(() {}),
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
              color: isCartonMode ? AppTheme.textSecondary : Colors.white,
              fontFamily: 'Cairo',
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
            entry.netWeightPerCartonValue > 0) ...[
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
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _materialItems) {
      final code = item['product_code']?.toString() ?? (item['product_name'] as String);
      grouped.putIfAbsent(code, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(firstItem['product_name'] as String,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ),
                    Text('${groupTotal.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                    const SizedBox(width: 8),
                    GestureDetector(
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    itemCode.isNotEmpty
                        ? 'كود: $itemCode | الإجمالي: ${groupQty.toStringAsFixed(1)} وحدة'
                        : 'الإجمالي: ${groupQty.toStringAsFixed(1)} وحدة',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
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
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Builder(builder: (context) {
                          final sName = item['supplier_name']?.toString() ?? '';
                          final invNum = item['invoice_number']?.toString() ?? '';
                          var title = 'دفعة $batchNum';
                          if (sName.isNotEmpty) title += ' ($sName)';
                          if (invNum.isNotEmpty) title += ' (فاتورة $invNum)';
                          return Text(title,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
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
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontFamily: 'Cairo'),
                              overflow: TextOverflow.ellipsis,
                            );
                          }),
                        ),
                        Text(
                            '${(((item['used_qty'] ?? 0) as num).toDouble() * ((item['unit_cost'] ?? 0) as num).toDouble()).toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 12,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: GestureDetector(
                            onTap: () {
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
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
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
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        if (!_isViewOnly) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addMaterialItem,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('إضافة مادة تعبئة',
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

  void _addMaterialItem() => _showMaterialForm();

  void _showMaterialForm({String? editProductCode}) {
    int? selectedIdx;
    String selectedApplyTo = 'all';
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
        selectedApplyTo = (existingItem['apply_to'] as String?) ?? 'all';
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
        final data = await Supabase.instance.client
            .from('station_product_batches')
            .select(
                'id, unit_cost, remaining_quantity, created_at, source_type, supplier_name, exchange_rate, currency, product_code, product_name, purchase_invoices(invoice_number, suppliers(name))')
            .eq('station_id', _selectedStationId!)
            .eq('product_code', selectedProduct.productCode)
            .gt('remaining_quantity', 0)
            .inFilter('source_type', ['purchase', 'opening', 'transfer', 'manual'])
            .order('created_at', ascending: true);

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
            backgroundColor: const Color(0xFF1A2940),
            title: Text(
                editProductCode != null
                    ? 'تعديل مادة التعبئة'
                    : 'إضافة مادة تعبئة',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
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
                            valueColor: AppTheme.textPrimary),
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
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  'المتوفر: ${rem.toStringAsFixed(1)} | كود: ${p.productCode}',
                                  style: TextStyle(
                                      color: rem > 0
                                          ? AppTheme.textSecondary
                                          : AppTheme.danger,
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
                              style: const TextStyle(
                                  color: Colors.white,
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
                            valueColor: AppTheme.success),
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
                          style: const TextStyle(
                              color: Colors.white,
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
                            var title = 'الدفعة الوحيدة';
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
                            style: const TextStyle(
                                color: Colors.white,
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
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: overLimit
                                        ? AppTheme.danger
                                        : AppTheme.glassBorder),
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
                                          var title = 'دفعة ${i + 1} — $bDate';
                                          if (sName.isNotEmpty)
                                            title += ' | $sName';
                                          if (isOpening)
                                            title += ' (رصيد سابق)';
                                          final invNum =
                                              b['invoice_number']?.toString() ??
                                                  '';
                                          if (invNum.isNotEmpty)
                                            title += ' | فاتورة: $invNum';
                                          return Text(title,
                                              style: const TextStyle(
                                                  color: AppTheme.textSecondary,
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
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
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
                                                  : Colors.white,
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
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
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
                                      ? AppTheme.primary.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : AppTheme.glassBorder,
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
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(label,
                                              style: TextStyle(
                                                  color: isSelected
                                                      ? AppTheme.textPrimary
                                                      : AppTheme.textSecondary,
                                                  fontSize: 13,
                                                  fontFamily: 'Cairo')),
                                          if (!isShared && entry != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'الوزن الصافي: ${entry.totalNetWeight.toStringAsFixed(1)} كجم | الكراتين: ${entry.cartonCount}',
                                              style: const TextStyle(
                                                  color: AppTheme.textMuted,
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
                                color: AppTheme.info.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color:
                                        AppTheme.info.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 14, color: AppTheme.info),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'إجمالي الاحتياج: ${_lotEntries.fold(0, (s, e) => s + e.cartonCount)} كرتونة',
                                      style: const TextStyle(
                                          color: AppTheme.info,
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
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: AppTheme.textSecondary,
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
                              'exchange_rate': bExchangeRate,
                              'currency': bCurrency,
                              'invoice_number': batches[i]['invoice_number'],
                              'supplier_name': batches[i]['supplier_name'],
                              'apply_to': selectedApplyTo,
                              'allocation_method': selectedApplyTo == 'all'
                                  ? selectedMaterialAllocationMethod
                                  : 'EQUAL',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _materialWastePercentCtrl,
          enabled: !_stockFieldsLocked,
          decoration: _inputDecoration('نسبة الفقد (%)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
          ],
          style: const TextStyle(
              color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            final n = double.tryParse(v);
            if (n == null || n < 0) return 'أدخل نسبة صحيحة';
            if (n > 100) return 'النسبة لا تتجاوز 100%';
            return null;
          },
        ),
        if (_materialWastePercent > 0) ...[
          const SizedBox(height: 8),
          _infoRow(
              'تكلفة فقد مواد التعبئة', '${_fmt(_totalMaterialWasteCost)} ج.م',
              valueColor: AppTheme.danger),
        ],
      ],
    );
  }

  Widget _buildCostItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._costItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final totalEgp =
              ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();
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

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
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
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                          ),
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
                          'التصنيف: $categoryLabel | التوزيع: ${CostAllocationMethod.fromCode(item['allocation_method'] as String?).label} | المورد: ${item['supplier_name'] ?? ''} | الكمية: ${((item['quantity'] ?? 0) as num).toDouble().toStringAsFixed(1)} | سعر الوحدة: ${((item['unit_price'] ?? 0) as num).toDouble().toStringAsFixed(2)} ج.م',
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontFamily: 'Cairo')),
                    ],
                  ),
                ),
                Text('${totalEgp.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                IconButton(
                  icon:
                      const Icon(Icons.edit, color: AppTheme.accent, size: 20),
                  onPressed: () => _editCostItem(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      color: AppTheme.danger, size: 20),
                  onPressed: () => setState(() => _costItems.removeAt(i)),
                ),
              ],
            ),
          );
        }),
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
    if (lower.contains('تعبئة') ||
        lower.contains('packing') ||
        lower.contains('material')) return 'material';
    return displayOrKey;
  }

  void _addCostItem() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final exchangeRateCtrl = TextEditingController(text: '');
    final supplierSearchCtrl = TextEditingController();
    String? selectedSupplierId;
    String? selectedSupplierName;
    String supplierCurrency = 'EGP';
    int? selectedCategoryId =
        _costCategories.isNotEmpty ? _costCategories.first['id'] as int? : null;

    String paymentSourceType = 'none';
    int? selectedPaymentSourceId;
    String selectedAllocationMethod = 'EQUAL';
    int? selectedTargetLineIndex;
    bool showAdvancedMethods = false;
    final notesCtrl = TextEditingController();

    final categories = {
      for (final c in _costCategories) c['id'] as int: c['name'] as String,
    };
    if (categories.isEmpty) {
      categories[-1] = 'أخرى';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final qty =
              double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final price =
              double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final rate = double.tryParse(
                  exchangeRateCtrl.text.trim().replaceAll(',', '.')) ??
              0;
          final totalEgp = qty * price;

          double availableBalance = 0;
          String sourceName = '';

          if (paymentSourceType == 'treasury' &&
              selectedPaymentSourceId != null) {
            final t = _treasuries.firstWhere(
                (e) => e['id'] == selectedPaymentSourceId,
                orElse: () => {});
            sourceName = t['name'] as String? ?? 'الخزينة المختارة';
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
          } else if (paymentSourceType == 'bank' &&
              selectedPaymentSourceId != null) {
            final b = _bankAccounts.firstWhere(
                (e) => e['id'] == selectedPaymentSourceId,
                orElse: () => {});
            sourceName = '${b['name'] ?? ''} (${b['bank_name'] ?? ''})';
            availableBalance = (b['balance'] as num?)?.toDouble() ?? 0;
          }

          final totalInSupplierCurrency = supplierCurrency == 'EGP'
              ? totalEgp
              : (rate > 0 ? totalEgp / rate : totalEgp);
          final isInsufficientBalance = (paymentSourceType != 'none') &&
              (selectedPaymentSourceId != null) &&
              (totalInSupplierCurrency > availableBalance);

          final canSubmit = name.isNotEmpty &&
              qty > 0 &&
              price > 0 &&
              selectedSupplierId != null &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: const Text('إضافة بند تكلفة',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: _inputDecoration('اسم البند'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: categories.containsKey(selectedCategoryId)
                            ? selectedCategoryId
                            : null,
                        decoration: _inputDecoration('تصنيف البند'),
                        dropdownColor: const Color(0xFF1A2940),
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 14),
                        isExpanded: true,
                        items: categories.entries.map((e) {
                          return DropdownMenuItem<int>(
                            value: e.key,
                            child: Text(e.value,
                                style: const TextStyle(fontFamily: 'Cairo')),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null)
                            setDialogState(() => selectedCategoryId = v);
                        },
                      ),
                      const SizedBox(height: 14),
                      _buildAllocationMethodPicker(
                        selectedCode: selectedAllocationMethod,
                        showAdvanced: showAdvancedMethods,
                        onToggleAdvanced: () => setDialogState(
                            () => showAdvancedMethods = !showAdvancedMethods),
                        onChanged: (code) => setDialogState(() {
                          selectedAllocationMethod = code;
                          if (code != 'MANUAL') selectedTargetLineIndex = null;
                        }),
                      ),
                      if (selectedAllocationMethod == 'MANUAL') ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: selectedTargetLineIndex,
                          decoration: _inputDecoration('تحميل على محصول محدد'),
                          dropdownColor: const Color(0xFF1A2940),
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: [
                            for (int li = 0; li < _lotEntries.length; li++)
                              DropdownMenuItem<int>(
                                value: li,
                                child: Text(
                                  _lotEntries[li].lot?.productName ??
                                      'محصول #${li + 1}',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedTargetLineIndex = v),
                        ),
                      ],
                      if (false) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: paymentSourceType,
                          decoration: _inputDecoration('مصدر الدفع'),
                          dropdownColor: const Color(0xFF1A2940),
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('آجل (بدون خصم مباشر)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.warning)),
                            ),
                            DropdownMenuItem(
                              value: 'treasury',
                              child: Text('خزينة رئيسية (نقداً)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.success)),
                            ),
                            DropdownMenuItem(
                              value: 'bank',
                              child: Text('حساب بنكي (تحويل / بنك)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Color(0xFF8B5CF6))),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() {
                                paymentSourceType = v;
                                selectedPaymentSourceId = null;
                              });
                            }
                          },
                        ),
                        if (paymentSourceType == 'treasury') ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            value: selectedPaymentSourceId,
                            decoration:
                                _inputDecoration('اختر الخزينة الرئيسية'),
                            dropdownColor: const Color(0xFF1A2940),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                            isExpanded: true,
                            items: _treasuries.where((t) {
                              final balances = t['treasury_balances'];
                              if (balances is! List || balances.isEmpty)
                                return false;
                              return balances.any((b) =>
                                  (b['currency']?.toString() ?? 'EGP')
                                      .toUpperCase() ==
                                  supplierCurrency.toUpperCase());
                            }).map((t) {
                              final tid = t['id'] as int;
                              final balances = t['treasury_balances'];
                              double bal = 0;
                              if (balances is List) {
                                final match = balances
                                    .where((b) =>
                                        (b['currency']?.toString() ?? 'EGP')
                                            .toUpperCase() ==
                                        supplierCurrency.toUpperCase())
                                    .toList();
                                if (match.isNotEmpty) {
                                  bal = (match.first['balance'] as num)
                                      .toDouble();
                                }
                              }
                              return DropdownMenuItem<int>(
                                value: tid,
                                child: Text(
                                  '${t['name']} (المتاح: ${bal.toStringAsFixed(2)} $supplierCurrency)',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(
                                () => selectedPaymentSourceId = v),
                          ),
                        ],
                        if (paymentSourceType == 'bank') ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            value: selectedPaymentSourceId,
                            decoration: _inputDecoration('اختر الحساب البنكي'),
                            dropdownColor: const Color(0xFF1A2940),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                            isExpanded: true,
                            items: _bankAccounts.where((b) {
                              final bc = (b['currency']?.toString() ?? '')
                                  .toUpperCase();
                              return bc == supplierCurrency.toUpperCase();
                            }).map((b) {
                              final bid = b['id'] as int;
                              final bal =
                                  (b['balance'] as num?)?.toDouble() ?? 0;
                              final bc = b['currency'] ?? 'EGP';
                              return DropdownMenuItem<int>(
                                value: bid,
                                child: Text(
                                  '${b['name'] ?? ''} (المتاح: ${bal.toStringAsFixed(2)} $bc)',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(
                                () => selectedPaymentSourceId = v),
                          ),
                        ],
                      ], // End of if (false) block
                      const SizedBox(height: 14),
                      TypeAheadField<String>(
                        key: ValueKey(selectedSupplierId),
                        controller: supplierSearchCtrl,
                        autoFlipDirection: true,
                        hideOnEmpty: false,
                        hideOnError: true,
                        suggestionsCallback: (query) {
                          final egpSuppliers = _suppliers.where((s) => (s.currency ?? 'EGP').toUpperCase() == 'EGP').toList();
                          if (query.isEmpty)
                            return egpSuppliers.map((s) => s.id!).toList();
                          final q = query.toLowerCase();
                          return egpSuppliers
                              .where((s) =>
                                  s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q))
                              .map((s) => s.id!)
                              .toList();
                        },
                        itemBuilder: (context, supplierId) {
                          final s =
                              _suppliers.firstWhere((s) => s.id == supplierId);
                          return ListTile(
                            dense: true,
                            title: Text(s.displayName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                          );
                        },
                        onSelected: (supplierId) async {
                          final s =
                              _suppliers.firstWhere((s) => s.id == supplierId);
                          setDialogState(() {
                            selectedSupplierId = s.id;
                            selectedSupplierName = s.name;
                            supplierSearchCtrl.text = s.displayName;
                            supplierCurrency = s.currency;
                            selectedPaymentSourceId = null;
                          });
                          if (supplierCurrency != 'EGP') {
                            try {
                              final rate = await CurrencyConversionService
                                  .instance
                                  .getRate(supplierCurrency);
                              setDialogState(() {
                                exchangeRateCtrl.text = rate.toStringAsFixed(4);
                              });
                            } catch (_) {
                              setDialogState(() => exchangeRateCtrl.text = '');
                            }
                          } else {
                            setDialogState(() => exchangeRateCtrl.text = '');
                          }
                        },
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: _inputDecoration(
                                'المورد (إجباري) - بحث بالاسم أو الكود'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                          );
                        },
                      ),
                      if (selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.success, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'تم اختيار: ${_suppliers.firstWhere((s) => s.id == selectedSupplierId).displayName}',
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
                                    exchangeRateCtrl.text = '';
                                  });
                                },
                                child: const Icon(Icons.close,
                                    color: AppTheme.danger, size: 14),
                              ),
                            ],
                          ),
                        ),
                      if (selectedSupplierId != null &&
                          supplierCurrency != 'EGP') ...[
                        const SizedBox(height: 10),
                        _infoRow('عملة المورد', supplierCurrency,
                            valueColor: AppTheme.info),
                        const SizedBox(height: 8),
                        TextField(
                          controller: exchangeRateCtrl,
                          decoration: _inputDecoration(
                              'سعر الصرف ($supplierCurrency → ج.م)'),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*$'))
                          ],
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 15),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration('الكمية'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: priceCtrl,
                        decoration: _inputDecoration('سعر الوحدة (ج.م)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: const TextStyle(
                            color: Colors.white,
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
                        const SizedBox(height: 8),
                        Builder(
                          builder: (_) {
                            final rate = double.tryParse(exchangeRateCtrl.text
                                    .trim()
                                    .replaceAll(',', '.')) ??
                                1;
                            final totalForeign = rate > 0
                                ? CurrencyConversionService.instance
                                    .fromBase(totalEgp, supplierCurrency, rate)
                                : 0.0;
                            return Column(
                              children: [
                                _infoRow(
                                  'المبلغ بعملة المورد',
                                  '${totalForeign.toStringAsFixed(2)} $supplierCurrency',
                                  valueColor: AppTheme.info,
                                ),
                                const SizedBox(height: 4),
                                _infoRow(
                                  'المبلغ بالجنيه',
                                  '${totalEgp.toStringAsFixed(2)} ج.م',
                                  valueColor: AppTheme.accent,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      // TextFormField(
                      //   controller: notesCtrl,
                      //   decoration: _inputDecoration('ملاحظات'),
                      //   style: const TextStyle(
                      //       color: Colors.white,
                      //       fontFamily: 'Cairo',
                      //       fontSize: 15),
                      //   maxLines: 2,
                      // ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: AppTheme.textSecondary,
                        fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () {
                        final rate = double.tryParse(exchangeRateCtrl.text
                                .trim()
                                .replaceAll(',', '.')) ??
                            1;
                        final totalInEgp = qty * price;
                        final totalInSupplierCurrency =
                            supplierCurrency == 'EGP'
                                ? totalInEgp
                                : (rate > 0 ? totalInEgp / rate : totalInEgp);
                        final selectedCategoryName =
                            categories[selectedCategoryId] ?? 'أخرى';
                        setState(() {
                          _costItems.add({
                            'name': name,
                            'category':
                                _costCategoryDbKey(selectedCategoryName),
                            'category_name': selectedCategoryName,
                            'report_category_id': selectedCategoryId,
                            'supplier_id': selectedSupplierId,
                            'supplier_name': selectedSupplierName ?? '',
                            'quantity': qty,
                            'unit_price': price,
                            'total': totalInSupplierCurrency,
                            'total_egp': totalInEgp,
                            'exchange_rate': rate,
                            'supplier_currency': supplierCurrency,
                            'ledger_entry_id': null,
                            'payment_source_type': paymentSourceType == 'none'
                                ? null
                                : paymentSourceType,
                            'payment_source_id': paymentSourceType == 'none'
                                ? null
                                : selectedPaymentSourceId,
                            'allocation_method': selectedAllocationMethod,
                            'target_line_index':
                                selectedAllocationMethod == 'MANUAL'
                                    ? selectedTargetLineIndex
                                    : null,
                            'notes': notesCtrl.text.trim(),
                          });
                        });
                        Navigator.pop(ctx);
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
    final qtyCtrl = TextEditingController(
        text: ((item['quantity'] ?? 0) as num).toDouble().toStringAsFixed(1));
    final priceCtrl = TextEditingController(
        text: ((item['unit_price'] ?? 0) as num).toDouble().toStringAsFixed(2));
    final exchangeRateCtrl = TextEditingController(
        text: (item['exchange_rate'] as num?)?.toDouble().toStringAsFixed(4) ??
            '');
    final supplierSearchCtrl =
        TextEditingController(text: item['supplier_name'] as String? ?? '');
    String? selectedSupplierId = item['supplier_id'] as String?;
    String? selectedSupplierName = item['supplier_name'] as String?;
    String supplierCurrency = item['supplier_currency'] as String? ?? 'EGP';
    int? selectedCategoryId = item['report_category_id'] as int?;

    String paymentSourceType = 'none'; // Forced to none as requested
    int? selectedPaymentSourceId = (item['payment_source_id'] as num?)?.toInt();
    String selectedAllocationMethod =
        (item['allocation_method'] as String?) ?? 'EQUAL';
    int? selectedTargetLineIndex = (item['target_line_index'] as num?)?.toInt();
    bool showAdvancedMethods =
        CostAllocationMethod.fromCode(selectedAllocationMethod).isAdvanced;
    final notesCtrl =
        TextEditingController(text: item['notes'] as String? ?? '');

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
    if (selectedCategoryId == null && _costCategories.isNotEmpty) {
      selectedCategoryId = _costCategories.first['id'] as int?;
    }

    final categories = {
      for (final c in _costCategories) c['id'] as int: c['name'] as String,
    };
    if (categories.isEmpty) {
      categories[-1] = 'أخرى';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final qty =
              double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final price =
              double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
          final rate = double.tryParse(
                  exchangeRateCtrl.text.trim().replaceAll(',', '.')) ??
              0;
          final totalEgp = qty * price;

          double availableBalance = 0;
          String sourceName = '';

          if (paymentSourceType == 'treasury' &&
              selectedPaymentSourceId != null) {
            final t = _treasuries.firstWhere(
                (e) => e['id'] == selectedPaymentSourceId,
                orElse: () => {});
            sourceName = t['name'] as String? ?? 'الخزينة المختارة';
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
          } else if (paymentSourceType == 'bank' &&
              selectedPaymentSourceId != null) {
            final b = _bankAccounts.firstWhere(
                (e) => e['id'] == selectedPaymentSourceId,
                orElse: () => {});
            sourceName = '${b['name'] ?? ''} (${b['bank_name'] ?? ''})';
            availableBalance = (b['balance'] as num?)?.toDouble() ?? 0;
          }

          final totalInSupplierCurrency = supplierCurrency == 'EGP'
              ? totalEgp
              : (rate > 0 ? totalEgp / rate : totalEgp);
          final isInsufficientBalance = (paymentSourceType != 'none') &&
              (selectedPaymentSourceId != null) &&
              (totalInSupplierCurrency > availableBalance);

          final canSubmit = name.isNotEmpty &&
              qty > 0 &&
              price > 0 &&
              selectedSupplierId != null &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: const Text('تعديل بند التكلفة',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: _inputDecoration('اسم البند'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: categories.containsKey(selectedCategoryId)
                            ? selectedCategoryId
                            : null,
                        decoration: _inputDecoration('تصنيف البند'),
                        dropdownColor: const Color(0xFF1A2940),
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 14),
                        isExpanded: true,
                        items: categories.entries.map((e) {
                          return DropdownMenuItem<int>(
                            value: e.key,
                            child: Text(e.value,
                                style: const TextStyle(fontFamily: 'Cairo')),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null)
                            setDialogState(() => selectedCategoryId = v);
                        },
                      ),
                      if (false) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: paymentSourceType,
                          decoration: _inputDecoration('مصدر الدفع'),
                          dropdownColor: const Color(0xFF1A2940),
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('آجل (بدون خصم مباشر)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.warning)),
                            ),
                            DropdownMenuItem(
                              value: 'treasury',
                              child: Text('خزينة رئيسية (نقداً)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.success)),
                            ),
                            DropdownMenuItem(
                              value: 'bank',
                              child: Text('حساب بنكي (تحويل / بنك)',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Color(0xFF8B5CF6))),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() {
                                paymentSourceType = v;
                                selectedPaymentSourceId = null;
                              });
                            }
                          },
                        ),
                        if (paymentSourceType == 'treasury') ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            value: selectedPaymentSourceId,
                            decoration:
                                _inputDecoration('اختر الخزينة الرئيسية'),
                            dropdownColor: const Color(0xFF1A2940),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                            isExpanded: true,
                            items: _treasuries.where((t) {
                              final balances = t['treasury_balances'];
                              if (balances is! List || balances.isEmpty)
                                return false;
                              return balances.any((b) =>
                                  (b['currency']?.toString() ?? 'EGP')
                                      .toUpperCase() ==
                                  supplierCurrency.toUpperCase());
                            }).map((t) {
                              final tid = t['id'] as int;
                              final balances = t['treasury_balances'];
                              double bal = 0;
                              if (balances is List) {
                                final match = balances
                                    .where((b) =>
                                        (b['currency']?.toString() ?? 'EGP')
                                            .toUpperCase() ==
                                        supplierCurrency.toUpperCase())
                                    .toList();
                                if (match.isNotEmpty) {
                                  bal = (match.first['balance'] as num)
                                      .toDouble();
                                }
                              }
                              return DropdownMenuItem<int>(
                                value: tid,
                                child: Text(
                                  '${t['name']} (المتاح: ${bal.toStringAsFixed(2)} $supplierCurrency)',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(
                                () => selectedPaymentSourceId = v),
                          ),
                        ],
                        if (paymentSourceType == 'bank') ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            value: selectedPaymentSourceId,
                            decoration: _inputDecoration('اختر الحساب البنكي'),
                            dropdownColor: const Color(0xFF1A2940),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                            isExpanded: true,
                            items: _bankAccounts.where((b) {
                              final bc = (b['currency']?.toString() ?? '')
                                  .toUpperCase();
                              return bc == supplierCurrency.toUpperCase();
                            }).map((b) {
                              final bid = b['id'] as int;
                              final bal =
                                  (b['balance'] as num?)?.toDouble() ?? 0;
                              final bc = b['currency'] ?? 'EGP';
                              return DropdownMenuItem<int>(
                                value: bid,
                                child: Text(
                                  '${b['name'] ?? ''} (المتاح: ${bal.toStringAsFixed(2)} $bc)',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setDialogState(
                                () => selectedPaymentSourceId = v),
                          ),
                        ],
                      ], // End of if (false) block
                      const SizedBox(height: 14),
                      TypeAheadField<String>(
                        key: ValueKey('edit_$selectedSupplierId'),
                        controller: supplierSearchCtrl,
                        autoFlipDirection: true,
                        hideOnEmpty: false,
                        hideOnError: true,
                        suggestionsCallback: (query) {
                          final egpSuppliers = _suppliers.where((s) => (s.currency ?? 'EGP').toUpperCase() == 'EGP').toList();
                          if (query.isEmpty)
                            return egpSuppliers.map((s) => s.id!).toList();
                          final q = query.toLowerCase();
                          return egpSuppliers
                              .where((s) =>
                                  s.name.toLowerCase().contains(q) ||
                                  s.displayName.toLowerCase().contains(q) ||
                                  s.supplierCode.toLowerCase().contains(q))
                              .map((s) => s.id!)
                              .toList();
                        },
                        itemBuilder: (context, supplierId) {
                          final s =
                              _suppliers.firstWhere((s) => s.id == supplierId);
                          return ListTile(
                            dense: true,
                            title: Text(s.displayName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                          );
                        },
                        onSelected: (supplierId) async {
                          final s =
                              _suppliers.firstWhere((s) => s.id == supplierId);
                          setDialogState(() {
                            selectedSupplierId = s.id;
                            selectedSupplierName = s.name;
                            supplierSearchCtrl.text = s.displayName;
                            supplierCurrency = s.currency;
                            selectedPaymentSourceId = null;
                          });
                          if (supplierCurrency != 'EGP') {
                            try {
                              final rate = await CurrencyConversionService
                                  .instance
                                  .getRate(supplierCurrency);
                              setDialogState(() {
                                exchangeRateCtrl.text = rate.toStringAsFixed(4);
                              });
                            } catch (_) {
                              setDialogState(() => exchangeRateCtrl.text = '');
                            }
                          } else {
                            setDialogState(() => exchangeRateCtrl.text = '');
                          }
                        },
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: _inputDecoration(
                                'المورد (إجباري) - بحث بالاسم أو الكود'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                          );
                        },
                      ),
                      if (selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.success, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'تم اختيار: ${_suppliers.firstWhere((s) => s.id == selectedSupplierId).displayName}',
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
                                    exchangeRateCtrl.text = '';
                                  });
                                },
                                child: const Icon(Icons.close,
                                    color: AppTheme.danger, size: 14),
                              ),
                            ],
                          ),
                        ),
                      if (selectedSupplierId != null &&
                          supplierCurrency != 'EGP') ...[
                        const SizedBox(height: 10),
                        _infoRow('عملة المورد', supplierCurrency,
                            valueColor: AppTheme.info),
                        const SizedBox(height: 8),
                        TextField(
                          controller: exchangeRateCtrl,
                          decoration: _inputDecoration(
                              'سعر الصرف ($supplierCurrency → ج.م)'),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*$'))
                          ],
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 15),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration('الكمية'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: priceCtrl,
                        decoration: _inputDecoration('سعر الوحدة (ج.م)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*$'))
                        ],
                        style: const TextStyle(
                            color: Colors.white,
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
                        const SizedBox(height: 8),
                        Builder(
                          builder: (_) {
                            final rate = double.tryParse(exchangeRateCtrl.text
                                    .trim()
                                    .replaceAll(',', '.')) ??
                                1;
                            final totalForeign = rate > 0
                                ? CurrencyConversionService.instance
                                    .fromBase(totalEgp, supplierCurrency, rate)
                                : 0.0;
                            return Column(
                              children: [
                                _infoRow(
                                  'المبلغ بعملة المورد',
                                  '${totalForeign.toStringAsFixed(2)} $supplierCurrency',
                                  valueColor: AppTheme.info,
                                ),
                                const SizedBox(height: 4),
                                _infoRow(
                                  'المبلغ بالجنيه',
                                  '${totalEgp.toStringAsFixed(2)} ج.م',
                                  valueColor: AppTheme.accent,
                                ),
                              ],
                            );
                          },
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
                          if (code != 'MANUAL') selectedTargetLineIndex = null;
                        }),
                      ),
                      if (selectedAllocationMethod == 'MANUAL') ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: selectedTargetLineIndex,
                          decoration: _inputDecoration('تحميل على محصول محدد'),
                          dropdownColor: const Color(0xFF1A2940),
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                          isExpanded: true,
                          items: [
                            for (int li = 0; li < _lotEntries.length; li++)
                              DropdownMenuItem<int>(
                                value: li,
                                child: Text(
                                  _lotEntries[li].lot?.productName ??
                                      'محصول #${li + 1}',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => selectedTargetLineIndex = v),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // TextFormField(
                      //   controller: notesCtrl,
                      //   decoration: _inputDecoration('ملاحظات'),
                      //   style: const TextStyle(
                      //       color: Colors.white,
                      //       fontFamily: 'Cairo',
                      //       fontSize: 15),
                      //   maxLines: 2,
                      // ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: AppTheme.textSecondary,
                        fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () {
                        final rate = double.tryParse(exchangeRateCtrl.text
                                .trim()
                                .replaceAll(',', '.')) ??
                            1;
                        final totalInEgp = qty * price;
                        final totalInSupplierCurrency =
                            supplierCurrency == 'EGP'
                                ? totalInEgp
                                : (rate > 0 ? totalInEgp / rate : totalInEgp);
                        final selectedCategoryName =
                            categories[selectedCategoryId] ?? 'أخرى';
                        setState(() {
                          _costItems[index] = {
                            'name': name,
                            'category':
                                _costCategoryDbKey(selectedCategoryName),
                            'category_name': selectedCategoryName,
                            'report_category_id': selectedCategoryId,
                            'supplier_id': selectedSupplierId,
                            'supplier_name': selectedSupplierName ?? '',
                            'quantity': qty,
                            'unit_price': price,
                            'total': totalInSupplierCurrency,
                            'total_egp': totalInEgp,
                            'exchange_rate': rate,
                            'supplier_currency': supplierCurrency,
                            'ledger_entry_id': item['ledger_entry_id'],
                            'payment_source_type': paymentSourceType == 'none'
                                ? null
                                : paymentSourceType,
                            'payment_source_id': paymentSourceType == 'none'
                                ? null
                                : selectedPaymentSourceId,
                            'allocation_method': selectedAllocationMethod,
                            'target_line_index':
                                selectedAllocationMethod == 'MANUAL'
                                    ? selectedTargetLineIndex
                                    : null,
                            'notes': notesCtrl.text.trim(),
                          };
                        });
                        Navigator.pop(ctx);
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
        return sum + e.effectiveWeight * e.netWeightPerCartonValue;
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
                    '+ فاقد مواد التعبئة (${_fmtPercent(m.wastePercent)}%)',
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
    final methods = availableMethods ??
        [
          ...CostAllocationMethod.defaultMethods,
          if (showAdvanced) ...CostAllocationMethod.advancedMethods,
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('طريقة توزيع التكلفة',
            style: TextStyle(
                color: AppTheme.textSecondary,
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
                      ? AppTheme.primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.glassBorder,
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
                      color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m.label,
                          style: TextStyle(
                              color: isSelected
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ),
                    Icon(Icons.info_outline,
                        size: 14, color: AppTheme.textMuted.withAlpha(120)),
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

    const hStyle = TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    const vStyle = TextStyle(
        color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo');
    const tStyle = TextStyle(
        color: AppTheme.primary,
        fontSize: 10,
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold);
    const aStyle = TextStyle(
        color: AppTheme.accent,
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
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder.withAlpha(60)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowColor: WidgetStateProperty.all(
                  AppTheme.primary.withValues(alpha: 0.1)),
              columns: const [
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

  Widget _buildActionButtons() {
    final isCostOnly = _stockFieldsLocked;
    final hasMismatch =
        isCostOnly ? false : _lotEntries.any((e) => e.isCartonWeightMismatch);
    final validationErrors = <String>[];
    if (!isCostOnly) {
      for (int i = 0; i < _lotEntries.length; i++) {
        final e = _lotEntries[i];
        final label = _lotEntries.length > 1 ? 'محصول #${i + 1}' : 'المحصول';
        final available = e.batch?.remainingQuantity ?? e.grossWeight;
        if (e.effectiveWeight > available && available > 0) {
          validationErrors.add('الكمية المستخدمة ($label) تتجاوز المتاح');
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
              e.netWeightPerCartonValue > 0 &&
              (totalAllocated - e.effectiveWeight).abs() > 0.01) {
            validationErrors.add(
                'يجب أن يكون (عدد الكراتين × الوزن الصافي + الفرز + الهالك = ${totalAllocated.toStringAsFixed(1)} كجم) مساوياً للوزن المستخدم (${e.effectiveWeight.toStringAsFixed(1)} كجم) في $label');
          }
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
        if (!_isViewOnly)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: (_saving || hasValidationErrors) ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEditing ? 'تعديل' : 'حفظ',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                ),
              ),
              const SizedBox(width: 8),
              // Expanded(
              //   child: OutlinedButton(
              //     onPressed: _saving ? null : _savePdf,
              //     style: OutlinedButton.styleFrom(
              //       foregroundColor: Colors.white,
              //       side: const BorderSide(color: AppTheme.primary, width: 1.5),
              //       padding: const EdgeInsets.symmetric(vertical: 14),
              //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              //     ),
              //     child: const Text('PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
              'net_weight_per_carton': e.netWeightPerCartonValue,
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
        return sum + e.effectiveWeight * e.netWeightPerCartonValue;
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: valueColor ?? AppTheme.textPrimary,
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 14, fontFamily: 'Cairo'),
      labelStyle: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 15, fontFamily: 'Cairo'),
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;

    // ═══════════════════════════════════════════════
    // Cost-only save for confirmed/cancelled orders
    // ═══════════════════════════════════════════════
    if (_stockFieldsLocked) {
      setState(() => _saving = true);
      try {
        Map<String, dynamic> notes = {};
        if (widget.existingOrder!.notes != null &&
            widget.existingOrder!.notes!.isNotEmpty) {
          try {
            notes = jsonDecode(widget.existingOrder!.notes!)
                as Map<String, dynamic>;
          } catch (_) {}
        }
        if (_costItems.isNotEmpty) {
          notes['cost_items'] = _costItems;
        }
        await _dao.update(int.parse(widget.existingOrder!.id!),
            widget.existingOrder!.copyWith(notes: jsonEncode(notes)));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم حفظ بنود التكلفة'),
              backgroundColor: AppTheme.success));
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

      if (entry.cartonCount <= 0 || entry.netWeightPerCartonValue <= 0) {
        _showError('يرجى إدخال بيانات الكراتين في $label');
        return;
      }

      final available = entry.batch?.remainingQuantity ?? entry.grossWeight;
      if (entry.effectiveWeight > available && available > 0) {
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
        lines.add(PackingOrderLineModel(
          packingOrderId: 0,
          fruitTypeId: int.tryParse(entry.lot!.fruitTypeId ?? ''),
          productName: entry.lot!.productName ?? '',
          grade: 'A',
          sourceLotId: entry.lot!.id,
          batchId: entry.batch?.id.toString(),
          quantity: entry.effectiveWeight,
          cartonCount: entry.cartonCount,
          netWeightPerCarton: entry.netWeightPerCartonValue,
          grossWeightPerCarton: entry.grossWeightPerCartonValue > 0
              ? entry.grossWeightPerCartonValue
              : entry.netWeightPerCartonValue,
          totalNetWeight: calcLine?.totalNetWeight ?? entry.totalNetWeight,
          totalGrossWeight:
              calcLine?.totalGrossWeight ?? entry.totalGrossWeight,
          unitCost: entry.costPerUnit / (entry.lot?.exchangeRate ?? 1.0),
          rawMaterialCost: calcLine?.rawMaterialCost ?? entry.totalPurchaseCost,
          wasteWeightKg: entry.wasteWeight,
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

      notesMap['total_raw_weight_kg'] = _lotEntries.fold(0.0, (sum, e) {
        if (e.isCartonMode) {
          return sum + e.effectiveWeight * e.netWeightPerCartonValue;
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
          wasteData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'waste_percent': entry.wastePercent,
            'waste_weight_kg': entry.wasteWeight,
            'waste_cost': entry.wasteCost,
          });
        }
        if (entry.hasSorting && entry.sortedWeight > 0) {
          sortingData.add({
            'line_index': i,
            'product_name': entry.lot?.productName ?? '',
            'sorted_weight_kg': entry.sortedWeight,
            'sorting_cost': entry.sortingCost,
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
      if (_materialItems.isNotEmpty) notesMap['materials'] = _materialItems;
      if (_materialWastePercent > 0)
        notesMap['material_waste_percent'] = _materialWastePercent;
      if (_costItems.isNotEmpty) notesMap['cost_items'] = _costItems;

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
            productName: firstEntry.lot!.productName,
            cartonCount: totalCartons,
            netWeightPerCarton: firstEntry.netWeightPerCartonValue,
            grossWeightPerCarton: firstEntry.grossWeightPerCartonValue > 0
                ? firstEntry.grossWeightPerCartonValue
                : firstEntry.netWeightPerCartonValue,
            totalNetWeight: calc.weights.totalNetWeight,
            totalGrossWeight: calc.weights.totalEffectiveWeight,
            status: widget.existingOrder!.status,
            stationId: _selectedStationId?.toString(),
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
        final existingSortings =
            await _sortingDao.getAll(packingOrderId: orderId);
        for (final s in existingSortings) {
          if (s.id != null) await _sortingDao.delete(s.id!);
        }
        for (final entry in _lotEntries) {
          if (entry.hasSorting && entry.sortedWeight > 0) {
            await _sortingDao.insert(PackingOrderSortingModel(
              packingOrderId: orderId,
              productName: entry.lot!.productName ?? '',
              lotNumber: entry.lot?.lotNumber,
              weightKg: entry.sortedWeight,
              remainingWeightKg: entry.sortedWeight,
              costPerKg: _packingCostPerCarton,
              totalCost: entry.sortedWeight * _packingCostPerCarton,
              status: 'pending',
              stationId: _selectedStationId,
            ));
          }
        }
      } else {
        final order = PackingOrderModel(
          orderNumber: '',
          lotId: firstEntry.lot!.id!,
          grade: 'A',
          fruitTypeId: firstEntry.lot!.fruitTypeId,
          productName: firstEntry.lot!.productName,
          cartonCount: totalCartons,
          netWeightPerCarton: firstEntry.netWeightPerCartonValue,
          grossWeightPerCarton: firstEntry.grossWeightPerCartonValue > 0
              ? firstEntry.grossWeightPerCartonValue
              : firstEntry.netWeightPerCartonValue,
          totalNetWeight:
              lines.fold<double>(0.0, (s, l) => s + l.totalNetWeight),
          totalGrossWeight:
              lines.fold<double>(0.0, (s, l) => s + l.totalGrossWeight),
          status: 'pending',
          stationId: _selectedStationId?.toString(),
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
        for (final entry in _lotEntries) {
          if (entry.hasSorting && entry.sortedWeight > 0) {
            await _sortingDao.insert(PackingOrderSortingModel(
              packingOrderId: newOrderId,
              productName: entry.lot!.productName ?? '',
              lotNumber: entry.lot?.lotNumber,
              weightKg: entry.sortedWeight,
              remainingWeightKg: entry.sortedWeight,
              costPerKg: _packingCostPerCarton,
              totalCost: entry.sortedWeight * _packingCostPerCarton,
              status: 'pending',
              stationId: _selectedStationId,
            ));
          }
        }
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
