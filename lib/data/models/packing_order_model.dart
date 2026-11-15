import 'dart:convert';
import 'packing_order_line_model.dart';
import '../services/packing_calculation_service.dart';

class PackingOrderModel {
  final String? id;
  final String orderNumber;
  final String lotId;
  final String? lotNumber;
  final String grade;
  final String? fruitTypeId;
  final String? productName;
  final int cartonCount;
  final double netWeightPerCarton;
  final double grossWeightPerCarton;
  final double totalNetWeight;
  final double totalGrossWeight;
  final String status;
  final DateTime? packedAt;
  final String? stationId;
  final String? exportShipmentId;
  final String? exportShipmentNo;
  final String? customerName;
  final String? batchId;
  final double packingCostPerCarton;
  final double totalPackingCost;
  final double fruitCostAllocated;
  final double actualMaterialCost;
  final double estimatedMaterialCost;
  final String? recipeId;
  final String? recipeName;
  final int? recipeVersion;
  final String? supplierName;
  final String? notes;
  final DateTime? createdAt;
  final int soldCartons;
  final double fruitCostBase;
  final double materialCostBase;
  final double otherCostBase;
  final String displayCurrency;
  final double displayExchangeRate;
  final bool needsPriceRefresh;
  final String? journalEntryId;
  final String? reversalJournalEntryId;
  final dynamic costSnapshot;
  final List<PackingOrderLineModel> lines;
  final int? lineId;

  // Multi-stage workflow tracking
  final DateTime? cropsConfirmedAt;
  final String? cropsJournalEntryId;
  final DateTime? packagingConfirmedAt;
  final String? packagingJournalEntryId;
  final DateTime? costsConfirmedAt;
  final String? costsJournalEntryId;
  final DateTime? finalApprovedAt;

  int get remainingCartons => cartonCount - soldCartons;
  bool get hasStock => remainingCartons > 0;

  bool get isDraft => status == 'draft' || status == 'pending';
  bool get isCropsConfirmed =>
      status == 'crops_confirmed' ||
      status == 'packaging_confirmed' ||
      status == 'costs_confirmed' ||
      status == 'final_approved' ||
      status == 'completed' ||
      cropsConfirmedAt != null;
  bool get isPackagingConfirmed =>
      status == 'packaging_confirmed' ||
      status == 'costs_confirmed' ||
      status == 'final_approved' ||
      status == 'completed' ||
      packagingConfirmedAt != null;
  bool get isCostsConfirmed =>
      status == 'costs_confirmed' ||
      status == 'final_approved' ||
      status == 'completed' ||
      costsConfirmedAt != null;
  bool get isFinalApproved =>
      status == 'final_approved' ||
      status == 'completed' ||
      status == 'confirmed' ||
      finalApprovedAt != null;

  int get currentStageIndex {
    if (isFinalApproved) return 4;
    if (isCostsConfirmed) return 3;
    if (isPackagingConfirmed) return 2;
    if (isCropsConfirmed) return 1;
    return 0;
  }

  const PackingOrderModel({
    this.id,
    required this.orderNumber,
    required this.lotId,
    this.lotNumber,
    required this.grade,
    this.fruitTypeId,
    this.productName,
    this.recipeId,
    this.recipeName,
    this.recipeVersion,
    this.cartonCount = 0,
    this.netWeightPerCarton = 0.0,
    this.grossWeightPerCarton = 0.0,
    this.totalNetWeight = 0.0,
    this.totalGrossWeight = 0.0,
    this.status = 'pending',
    this.packedAt,
    this.stationId,
    this.exportShipmentId,
    this.exportShipmentNo,
    this.customerName,
    this.batchId,
    this.packingCostPerCarton = 0.0,
    this.totalPackingCost = 0.0,
    this.fruitCostAllocated = 0.0,
    this.actualMaterialCost = 0.0,
    this.estimatedMaterialCost = 0.0,
    this.supplierName,
    this.notes,
    this.createdAt,
    this.soldCartons = 0,
    this.fruitCostBase = 0.0,
    this.materialCostBase = 0.0,
    this.otherCostBase = 0.0,
    this.displayCurrency = 'EGP',
    this.displayExchangeRate = 1.0,
    this.needsPriceRefresh = false,
    this.journalEntryId,
    this.reversalJournalEntryId,
    this.costSnapshot,
    this.lines = const [],
    this.lineId,
    this.cropsConfirmedAt,
    this.cropsJournalEntryId,
    this.packagingConfirmedAt,
    this.packagingJournalEntryId,
    this.costsConfirmedAt,
    this.costsJournalEntryId,
    this.finalApprovedAt,
  });

  factory PackingOrderModel.fromMap(Map<String, dynamic> map) {
    final computedCost = PackingCalculationService.computeEffectiveCostPerCarton(map);
    final cartonCountVal = (map['carton_count'] as num?)?.toInt() ?? 0;

    Map<String, dynamic>? workflowStages;
    if (map['notes'] != null) {
      try {
        final parsed = map['notes'] is Map ? map['notes'] : jsonDecode(map['notes'].toString());
        if (parsed is Map && parsed['workflow_stages'] is Map) {
          workflowStages = Map<String, dynamic>.from(parsed['workflow_stages'] as Map);
        }
      } catch (_) {}
    }

    final cropsConfirmedAtVal = map['crops_confirmed_at'] != null
        ? DateTime.tryParse(map['crops_confirmed_at'].toString())
        : (workflowStages?['crops_confirmed_at'] != null
            ? DateTime.tryParse(workflowStages!['crops_confirmed_at'].toString())
            : (workflowStages?['crops']?['confirmed_at'] != null
                ? DateTime.tryParse(workflowStages!['crops']['confirmed_at'].toString())
                : null));

    final cropsJournalEntryIdVal = map['crops_journal_entry_id']?.toString() ??
        workflowStages?['crops_journal_entry_id']?.toString() ??
        workflowStages?['crops']?['journal_entry_id']?.toString();

    final packagingConfirmedAtVal = map['packaging_confirmed_at'] != null
        ? DateTime.tryParse(map['packaging_confirmed_at'].toString())
        : (workflowStages?['packaging_confirmed_at'] != null
            ? DateTime.tryParse(workflowStages!['packaging_confirmed_at'].toString())
            : (workflowStages?['packaging']?['confirmed_at'] != null
                ? DateTime.tryParse(workflowStages!['packaging']['confirmed_at'].toString())
                : null));

    final packagingJournalEntryIdVal = map['packaging_journal_entry_id']?.toString() ??
        workflowStages?['packaging_journal_entry_id']?.toString() ??
        workflowStages?['packaging']?['journal_entry_id']?.toString();

    final costsConfirmedAtVal = map['costs_confirmed_at'] != null
        ? DateTime.tryParse(map['costs_confirmed_at'].toString())
        : (workflowStages?['costs_confirmed_at'] != null
            ? DateTime.tryParse(workflowStages!['costs_confirmed_at'].toString())
            : (workflowStages?['costs']?['confirmed_at'] != null
                ? DateTime.tryParse(workflowStages!['costs']['confirmed_at'].toString())
                : null));

    final costsJournalEntryIdVal = map['costs_journal_entry_id']?.toString() ??
        workflowStages?['costs_journal_entry_id']?.toString() ??
        workflowStages?['costs']?['journal_entry_id']?.toString();

    final finalApprovedAtVal = map['final_approved_at'] != null
        ? DateTime.tryParse(map['final_approved_at'].toString())
        : (workflowStages?['final_approved_at'] != null
            ? DateTime.tryParse(workflowStages!['final_approved_at'].toString())
            : (workflowStages?['final_approved']?['approved_at'] != null
                ? DateTime.tryParse(workflowStages!['final_approved']['approved_at'].toString())
                : null));
    return PackingOrderModel(
      id: map['id']?.toString(),
      orderNumber: (map['order_number'] as String?) ?? '',
      lotId: map['lot_id']?.toString() ?? '',
      lotNumber: map['lot_number'] as String?,
      grade: map['grade']?.toString() ?? '',
      fruitTypeId: map['fruit_type_id']?.toString(),
      productName: map['product_name'] as String?,
      recipeId: map['recipe_id']?.toString(),
      recipeName: map['recipe_name'] as String?,
      recipeVersion: map['recipe_version'] as int?,
      cartonCount: cartonCountVal,
      netWeightPerCarton:
          (map['net_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
      grossWeightPerCarton:
          (map['gross_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
      totalNetWeight:
          (map['total_net_weight'] as num?)?.toDouble() ?? 0.0,
      totalGrossWeight:
          (map['total_gross_weight'] as num?)?.toDouble() ?? 0.0,
      status: (map['status'] as String?) ?? 'pending',
      packedAt: map['packed_at'] != null
          ? DateTime.tryParse(map['packed_at'] as String)
          : null,
      stationId: map['station_id']?.toString(),
      exportShipmentId: map['export_shipment_id']?.toString(),
      batchId: map['batch_id']?.toString(),
      packingCostPerCarton: computedCost > 0
          ? computedCost
          : ((map['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0),
      totalPackingCost: computedCost > 0 && cartonCountVal > 0
          ? (computedCost * cartonCountVal)
          : ((map['total_packing_cost'] as num?)?.toDouble() ?? 0.0),
      fruitCostAllocated:
          (map['fruit_cost_allocated'] as num?)?.toDouble() ?? 0.0,
      actualMaterialCost:
          (map['actual_material_cost'] as num?)?.toDouble() ?? 0.0,
      estimatedMaterialCost:
          (map['estimated_material_cost'] as num?)?.toDouble() ?? 0.0,
      supplierName: map['supplier_name'] as String?,
      exportShipmentNo: map['export_shipment_no'] as String?,
      customerName: map['customer_name'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      soldCartons: (map['sold_cartons'] as num?)?.toInt() ?? 0,
      fruitCostBase: (map['fruit_cost_base'] as num?)?.toDouble() ?? 0.0,
      materialCostBase: (map['material_cost_base'] as num?)?.toDouble() ?? 0.0,
      otherCostBase: (map['other_cost_base'] as num?)?.toDouble() ?? 0.0,
      displayCurrency: (map['display_currency'] as String?) ?? 'EGP',
      displayExchangeRate: (map['display_exchange_rate'] as num?)?.toDouble() ?? 1.0,
      needsPriceRefresh: map['needs_price_refresh'] == true,
      journalEntryId: map['journal_entry_id']?.toString(),
      reversalJournalEntryId: map['reversal_journal_entry_id']?.toString(),
      costSnapshot: map['cost_snapshot'],
      lines: (map['packing_order_lines'] is List)
          ? ((map['packing_order_lines'] as List)
              .map((e) => PackingOrderLineModel.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList()
            ..sort((a, b) => (int.tryParse(a.id ?? '') ?? 0).compareTo(int.tryParse(b.id ?? '') ?? 0)))
          : const [],
      lineId: (map['line_id'] as num?)?.toInt(),
      cropsConfirmedAt: cropsConfirmedAtVal,
      cropsJournalEntryId: cropsJournalEntryIdVal,
      packagingConfirmedAt: packagingConfirmedAtVal,
      packagingJournalEntryId: packagingJournalEntryIdVal,
      costsConfirmedAt: costsConfirmedAtVal,
      costsJournalEntryId: costsJournalEntryIdVal,
      finalApprovedAt: finalApprovedAtVal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'order_number': orderNumber,
      'lot_id': lotId,
      'grade': grade,
      if (fruitTypeId != null) 'fruit_type_id': fruitTypeId,
      if (productName != null) 'product_name': productName,
      'carton_count': cartonCount,
      'net_weight_per_carton': netWeightPerCarton,
      'gross_weight_per_carton': grossWeightPerCarton,
      'status': (isCropsConfirmed && (status == 'draft' || status == 'pending'))
          ? (isCostsConfirmed
              ? 'costs_confirmed'
              : (isPackagingConfirmed ? 'packaging_confirmed' : 'crops_confirmed'))
          : status,
      if (packedAt != null)
        'packed_at': packedAt!.toIso8601String(),
      if (stationId != null) 'station_id': stationId,
      if (exportShipmentId != null)
        'export_shipment_id': exportShipmentId,
      if (exportShipmentNo != null)
        'export_shipment_no': exportShipmentNo,
      if (customerName != null)
        'customer_name': customerName,
      if (recipeId != null) 'recipe_id': recipeId,
      if (recipeName != null) 'recipe_name': recipeName,
      if (recipeVersion != null) 'recipe_version': recipeVersion,
      if (batchId != null) 'batch_id': batchId,
      'packing_cost_per_carton': packingCostPerCarton,
      'total_packing_cost': totalPackingCost,
      'fruit_cost_allocated': fruitCostAllocated,
      'actual_material_cost': actualMaterialCost,
      'estimated_material_cost': estimatedMaterialCost,
      'fruit_cost_base': fruitCostBase,
      'material_cost_base': materialCostBase,
      'other_cost_base': otherCostBase,
      'display_currency': displayCurrency,
      'display_exchange_rate': displayExchangeRate,
      'needs_price_refresh': needsPriceRefresh,
      'notes': notes ?? '',
      if (lineId != null) 'line_id': lineId,
      if (cropsConfirmedAt != null)
        'crops_confirmed_at': cropsConfirmedAt!.toIso8601String(),
      if (cropsJournalEntryId != null)
        'crops_journal_entry_id': cropsJournalEntryId,
      if (packagingConfirmedAt != null)
        'packaging_confirmed_at': packagingConfirmedAt!.toIso8601String(),
      if (packagingJournalEntryId != null)
        'packaging_journal_entry_id': packagingJournalEntryId,
      if (costsConfirmedAt != null)
        'costs_confirmed_at': costsConfirmedAt!.toIso8601String(),
      if (costsJournalEntryId != null)
        'costs_journal_entry_id': costsJournalEntryId,
      if (finalApprovedAt != null)
        'final_approved_at': finalApprovedAt!.toIso8601String(),
    };
  }

  PackingOrderModel copyWith({
    String? id,
    String? orderNumber,
    String? lotId,
    String? lotNumber,
    String? grade,
    String? fruitTypeId,
    String? productName,
    int? cartonCount,
    double? netWeightPerCarton,
    double? grossWeightPerCarton,
    double? totalNetWeight,
    double? totalGrossWeight,
    String? status,
    DateTime? packedAt,
    String? stationId,
    String? exportShipmentId,
    String? exportShipmentNo,
    String? customerName,
    String? recipeId,
    String? recipeName,
    int? recipeVersion,
    String? batchId,
    double? packingCostPerCarton,
    double? totalPackingCost,
    double? fruitCostAllocated,
    double? actualMaterialCost,
    double? estimatedMaterialCost,
    String? supplierName,
    String? notes,
    DateTime? createdAt,
    int? soldCartons,
    double? fruitCostBase,
    double? materialCostBase,
    double? otherCostBase,
    String? displayCurrency,
    double? displayExchangeRate,
    bool? needsPriceRefresh,
    String? journalEntryId,
    String? reversalJournalEntryId,
    dynamic costSnapshot,
    List<PackingOrderLineModel>? lines,
    int? lineId,
    DateTime? cropsConfirmedAt,
    String? cropsJournalEntryId,
    DateTime? packagingConfirmedAt,
    String? packagingJournalEntryId,
    DateTime? costsConfirmedAt,
    String? costsJournalEntryId,
    DateTime? finalApprovedAt,
  }) {
    return PackingOrderModel(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      lotId: lotId ?? this.lotId,
      lotNumber: lotNumber ?? this.lotNumber,
      grade: grade ?? this.grade,
      fruitTypeId: fruitTypeId ?? this.fruitTypeId,
      productName: productName ?? this.productName,
      supplierName: supplierName ?? this.supplierName,
      cartonCount: cartonCount ?? this.cartonCount,
      netWeightPerCarton:
          netWeightPerCarton ?? this.netWeightPerCarton,
      grossWeightPerCarton:
          grossWeightPerCarton ?? this.grossWeightPerCarton,
      totalNetWeight: totalNetWeight ?? this.totalNetWeight,
      totalGrossWeight: totalGrossWeight ?? this.totalGrossWeight,
      status: status ?? this.status,
      packedAt: packedAt ?? this.packedAt,
      stationId: stationId ?? this.stationId,
      exportShipmentId: exportShipmentId ?? this.exportShipmentId,
      exportShipmentNo: exportShipmentNo ?? this.exportShipmentNo,
      customerName: customerName ?? this.customerName,
      recipeId: recipeId ?? this.recipeId,
      recipeName: recipeName ?? this.recipeName,
      recipeVersion: recipeVersion ?? this.recipeVersion,
      batchId: batchId ?? this.batchId,
      packingCostPerCarton:
          packingCostPerCarton ?? this.packingCostPerCarton,
      totalPackingCost: totalPackingCost ?? this.totalPackingCost,
      fruitCostAllocated: fruitCostAllocated ?? this.fruitCostAllocated,
      actualMaterialCost: actualMaterialCost ?? this.actualMaterialCost,
      estimatedMaterialCost: estimatedMaterialCost ?? this.estimatedMaterialCost,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      soldCartons: soldCartons ?? this.soldCartons,
      fruitCostBase: fruitCostBase ?? this.fruitCostBase,
      materialCostBase: materialCostBase ?? this.materialCostBase,
      otherCostBase: otherCostBase ?? this.otherCostBase,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      displayExchangeRate: displayExchangeRate ?? this.displayExchangeRate,
      needsPriceRefresh: needsPriceRefresh ?? this.needsPriceRefresh,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      reversalJournalEntryId:
          reversalJournalEntryId ?? this.reversalJournalEntryId,
      costSnapshot: costSnapshot ?? this.costSnapshot,
      lines: lines ?? this.lines,
      lineId: lineId ?? this.lineId,
      cropsConfirmedAt: cropsConfirmedAt ?? this.cropsConfirmedAt,
      cropsJournalEntryId: cropsJournalEntryId ?? this.cropsJournalEntryId,
      packagingConfirmedAt: packagingConfirmedAt ?? this.packagingConfirmedAt,
      packagingJournalEntryId: packagingJournalEntryId ?? this.packagingJournalEntryId,
      costsConfirmedAt: costsConfirmedAt ?? this.costsConfirmedAt,
      costsJournalEntryId: costsJournalEntryId ?? this.costsJournalEntryId,
      finalApprovedAt: finalApprovedAt ?? this.finalApprovedAt,
    );
  }
}
