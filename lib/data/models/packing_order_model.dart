import 'packing_order_line_model.dart';

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

  int get remainingCartons => cartonCount - soldCartons;
  bool get hasStock => remainingCartons > 0;

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
  });

  factory PackingOrderModel.fromMap(Map<String, dynamic> map) {
    return PackingOrderModel(
      id: map['id']?.toString(),
      orderNumber: (map['order_number'] as String?) ?? '',
      lotId: map['lot_id']?.toString() ?? '',
      lotNumber: map['lot_number'] as String?,
      grade: map['grade'] as String,
      fruitTypeId: map['fruit_type_id']?.toString(),
      productName: map['product_name'] as String?,
      recipeId: map['recipe_id']?.toString(),
      recipeName: map['recipe_name'] as String?,
      recipeVersion: map['recipe_version'] as int?,
      cartonCount: (map['carton_count'] as num?)?.toInt() ?? 0,
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
      packingCostPerCarton:
          (map['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0,
      totalPackingCost:
          (map['total_packing_cost'] as num?)?.toDouble() ?? 0.0,
      fruitCostAllocated:
          (map['fruit_cost_allocated'] as num?)?.toDouble() ?? 0.0,
      actualMaterialCost:
          (map['actual_material_cost'] as num?)?.toDouble() ?? 0.0,
      estimatedMaterialCost:
          (map['estimated_material_cost'] as num?)?.toDouble() ?? 0.0,
      supplierName: map['supplier_name'] as String?,
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
      'status': status,
      if (packedAt != null)
        'packed_at': packedAt!.toIso8601String(),
      if (stationId != null) 'station_id': stationId,
      if (exportShipmentId != null)
        'export_shipment_id': exportShipmentId,
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
    );
  }
}
