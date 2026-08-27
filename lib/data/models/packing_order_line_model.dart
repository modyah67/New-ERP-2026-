/// Model representing a single product line within a multi-product packing order.
/// Maps to the `packing_order_lines` database table.
class PackingOrderLineModel {
  final String? id;
  final int packingOrderId;
  final int? productId;
  final int? fruitTypeId;
  final String productName;
  final String grade;
  final String? sourceLotId;
  final String? batchId;
  final double quantity;
  final int cartonCount;
  final double netWeightPerCarton;
  final double grossWeightPerCarton;
  final double totalNetWeight;
  final double totalGrossWeight;
  final double unitCost;
  final double rawMaterialCost;
  final double expectedLossPercent;
  final double wasteWeightKg;
  final double wasteCost;
  final double sortedWeightKg;
  final double sortingCost;
  final double specificPackagingCost;
  final double allocatedSharedPackaging;
  final double allocatedCostItems;
  final double finalCost;
  final double finalUnitCost;
  final int soldCartons;
  final Map<String, dynamic>? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get remainingCartons => cartonCount - soldCartons;
  bool get hasStock => remainingCartons > 0;

  const PackingOrderLineModel({
    this.id,
    required this.packingOrderId,
    this.productId,
    this.fruitTypeId,
    this.productName = '',
    this.grade = 'A',
    this.sourceLotId,
    this.batchId,
    this.quantity = 0,
    this.cartonCount = 0,
    this.netWeightPerCarton = 0.0,
    this.grossWeightPerCarton = 0.0,
    this.totalNetWeight = 0.0,
    this.totalGrossWeight = 0.0,
    this.unitCost = 0.0,
    this.rawMaterialCost = 0.0,
    this.expectedLossPercent = 0.0,
    this.wasteWeightKg = 0.0,
    this.wasteCost = 0.0,
    this.sortedWeightKg = 0.0,
    this.sortingCost = 0.0,
    this.specificPackagingCost = 0.0,
    this.allocatedSharedPackaging = 0.0,
    this.allocatedCostItems = 0.0,
    this.finalCost = 0.0,
    this.finalUnitCost = 0.0,
    this.soldCartons = 0,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory PackingOrderLineModel.fromMap(Map<String, dynamic> map) {
    return PackingOrderLineModel(
      id: map['id']?.toString(),
      packingOrderId: (map['packing_order_id'] as num?)?.toInt() ?? 0,
      productId: (map['product_id'] as num?)?.toInt(),
      fruitTypeId: (map['fruit_type_id'] as num?)?.toInt(),
      productName: (map['product_name'] as String?) ?? '',
      grade: (map['grade'] as String?) ?? 'A',
      sourceLotId: map['source_lot_id']?.toString(),
      batchId: map['batch_id']?.toString(),
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      cartonCount: (map['carton_count'] as num?)?.toInt() ?? 0,
      netWeightPerCarton: (map['net_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
      grossWeightPerCarton: (map['gross_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
      totalNetWeight: (map['total_net_weight'] as num?)?.toDouble() ?? 0.0,
      totalGrossWeight: (map['total_gross_weight'] as num?)?.toDouble() ?? 0.0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0.0,
      rawMaterialCost: (map['raw_material_cost'] as num?)?.toDouble() ?? 0.0,
      expectedLossPercent: (map['expected_loss_percent'] as num?)?.toDouble() ?? 0.0,
      wasteWeightKg: (map['waste_weight_kg'] as num?)?.toDouble() ?? 0.0,
      wasteCost: (map['waste_cost'] as num?)?.toDouble() ?? 0.0,
      sortedWeightKg: (map['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0,
      sortingCost: (map['sorting_cost'] as num?)?.toDouble() ?? 0.0,
      specificPackagingCost: (map['specific_packaging_cost'] as num?)?.toDouble() ?? 0.0,
      allocatedSharedPackaging: (map['allocated_shared_packaging'] as num?)?.toDouble() ?? 0.0,
      allocatedCostItems: (map['allocated_cost_items'] as num?)?.toDouble() ?? 0.0,
      finalCost: (map['final_cost'] as num?)?.toDouble() ?? 0.0,
      finalUnitCost: (map['final_unit_cost'] as num?)?.toDouble() ?? 0.0,
      soldCartons: (map['sold_cartons'] as num?)?.toInt() ?? 0,
      notes: map['notes'] is Map ? Map<String, dynamic>.from(map['notes'] as Map) : null,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'packing_order_id': packingOrderId,
      if (productId != null) 'product_id': productId,
      if (fruitTypeId != null) 'fruit_type_id': fruitTypeId,
      'product_name': productName,
      'grade': grade,
      if (sourceLotId != null) 'source_lot_id': sourceLotId,
      if (batchId != null) 'batch_id': batchId,
      'quantity': quantity,
      'carton_count': cartonCount,
      'net_weight_per_carton': netWeightPerCarton,
      'gross_weight_per_carton': grossWeightPerCarton,
      'unit_cost': unitCost,
      'raw_material_cost': rawMaterialCost,
      'expected_loss_percent': expectedLossPercent,
      'waste_weight_kg': wasteWeightKg,
      'waste_cost': wasteCost,
      'sorted_weight_kg': sortedWeightKg,
      'sorting_cost': sortingCost,
      'specific_packaging_cost': specificPackagingCost,
      'allocated_shared_packaging': allocatedSharedPackaging,
      'allocated_cost_items': allocatedCostItems,
      'final_cost': finalCost,
      'final_unit_cost': finalUnitCost,
      'sold_cartons': soldCartons,
    };
  }

  /// Insert map — excludes generated columns (total_net_weight, total_gross_weight)
  Map<String, dynamic> toInsertMap() {
    final m = toMap();
    m.remove('id');
    return m;
  }

  PackingOrderLineModel copyWith({
    String? id,
    int? packingOrderId,
    int? productId,
    int? fruitTypeId,
    String? productName,
    String? grade,
    String? sourceLotId,
    String? batchId,
    double? quantity,
    int? cartonCount,
    double? netWeightPerCarton,
    double? grossWeightPerCarton,
    double? totalNetWeight,
    double? totalGrossWeight,
    double? unitCost,
    double? rawMaterialCost,
    double? expectedLossPercent,
    double? wasteWeightKg,
    double? wasteCost,
    double? sortedWeightKg,
    double? sortingCost,
    double? specificPackagingCost,
    double? allocatedSharedPackaging,
    double? allocatedCostItems,
    double? finalCost,
    double? finalUnitCost,
    int? soldCartons,
    Map<String, dynamic>? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PackingOrderLineModel(
      id: id ?? this.id,
      packingOrderId: packingOrderId ?? this.packingOrderId,
      productId: productId ?? this.productId,
      fruitTypeId: fruitTypeId ?? this.fruitTypeId,
      productName: productName ?? this.productName,
      grade: grade ?? this.grade,
      sourceLotId: sourceLotId ?? this.sourceLotId,
      batchId: batchId ?? this.batchId,
      quantity: quantity ?? this.quantity,
      cartonCount: cartonCount ?? this.cartonCount,
      netWeightPerCarton: netWeightPerCarton ?? this.netWeightPerCarton,
      grossWeightPerCarton: grossWeightPerCarton ?? this.grossWeightPerCarton,
      totalNetWeight: totalNetWeight ?? this.totalNetWeight,
      totalGrossWeight: totalGrossWeight ?? this.totalGrossWeight,
      unitCost: unitCost ?? this.unitCost,
      rawMaterialCost: rawMaterialCost ?? this.rawMaterialCost,
      expectedLossPercent: expectedLossPercent ?? this.expectedLossPercent,
      wasteWeightKg: wasteWeightKg ?? this.wasteWeightKg,
      wasteCost: wasteCost ?? this.wasteCost,
      sortedWeightKg: sortedWeightKg ?? this.sortedWeightKg,
      sortingCost: sortingCost ?? this.sortingCost,
      specificPackagingCost: specificPackagingCost ?? this.specificPackagingCost,
      allocatedSharedPackaging: allocatedSharedPackaging ?? this.allocatedSharedPackaging,
      allocatedCostItems: allocatedCostItems ?? this.allocatedCostItems,
      finalCost: finalCost ?? this.finalCost,
      finalUnitCost: finalUnitCost ?? this.finalUnitCost,
      soldCartons: soldCartons ?? this.soldCartons,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Enum for cost allocation methods used in multi-product packing orders.
enum CostAllocationMethod {
  byNetWeight,
  byInputWeight,
  byProductValue,
  byPackages,
  equal,
  byWeight,
  byQuantity,
  manual;

  String get code {
    switch (this) {
      case CostAllocationMethod.byWeight: return 'BY_WEIGHT';
      case CostAllocationMethod.byNetWeight: return 'BY_NET_WEIGHT';
      case CostAllocationMethod.byInputWeight: return 'BY_INPUT_WEIGHT';
      case CostAllocationMethod.byProductValue: return 'BY_PRODUCT_VALUE';
      case CostAllocationMethod.byQuantity: return 'BY_QUANTITY';
      case CostAllocationMethod.byPackages: return 'BY_PACKAGES';
      case CostAllocationMethod.equal: return 'EQUAL';
      case CostAllocationMethod.manual: return 'MANUAL';
    }
  }

  String get label {
    switch (this) {
      case CostAllocationMethod.byWeight: return 'حسب الوزن الإجمالي للكراتين';
      case CostAllocationMethod.byNetWeight: return 'حسب الوزن الصافي (بعد الفرز)';
      case CostAllocationMethod.byInputWeight: return 'حسب الوزن الخام (قبل الفرز)';
      case CostAllocationMethod.byProductValue: return 'حسب القيمة المالية للمحصول';
      case CostAllocationMethod.byQuantity: return 'حسب الكمية';
      case CostAllocationMethod.byPackages: return 'حسب عدد الكراتين';
      case CostAllocationMethod.equal: return 'بالتساوي';
      case CostAllocationMethod.manual: return 'تخصيص لمحصول محدد';
    }
  }

  String get tooltip {
    switch (this) {
      case CostAllocationMethod.byWeight:
        return 'يتم توزيع التكلفة بناءً على الوزن الإجمالي (صافي + تغليف) لكل محصول.';
      case CostAllocationMethod.byNetWeight:
        return 'يتم توزيع التكلفة بناءً على الوزن النهائي بعد استبعاد الفرز والهالك.';
      case CostAllocationMethod.byInputWeight:
        return 'يتم توزيع التكلفة على كمية الخام قبل عمليات الفرز.';
      case CostAllocationMethod.byProductValue:
        return 'يتم توزيع التكلفة بنسبة قيمة كل محصول من إجمالي قيمة المحاصيل.';
      case CostAllocationMethod.byQuantity:
        return 'يتم توزيع التكلفة حسب الكمية المدخلة لكل محصول.';
      case CostAllocationMethod.byPackages:
        return 'يتم توزيع التكلفة حسب عدد الكراتين المنتجة لكل محصول.';
      case CostAllocationMethod.equal:
        return 'يتم توزيع التكلفة بالتساوي على جميع المحاصيل.';
      case CostAllocationMethod.manual:
        return 'تحديد محصول معين لتحمل هذه التكلفة بالكامل.';
    }
  }

  /// Whether this method is shown only under "Advanced" toggle.
  bool get isAdvanced => false;

  static const List<CostAllocationMethod> defaultMethods = [
    CostAllocationMethod.equal,
    CostAllocationMethod.manual,
  ];

  /// Advanced methods hidden behind toggle.
  static const List<CostAllocationMethod> advancedMethods = [];

  static CostAllocationMethod fromCode(String? code) {
    switch (code) {
      case 'BY_WEIGHT': return CostAllocationMethod.byWeight;
      case 'BY_NET_WEIGHT': return CostAllocationMethod.byNetWeight;
      case 'BY_INPUT_WEIGHT': return CostAllocationMethod.byInputWeight;
      case 'BY_PRODUCT_VALUE': return CostAllocationMethod.byProductValue;
      case 'BY_QUANTITY': return CostAllocationMethod.byQuantity;
      case 'BY_PACKAGES': return CostAllocationMethod.byPackages;
      case 'EQUAL': return CostAllocationMethod.equal;
      case 'MANUAL': return CostAllocationMethod.manual;
      default: return CostAllocationMethod.byNetWeight;
    }
  }
}
