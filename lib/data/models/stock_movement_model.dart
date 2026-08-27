class StockMovementModel {
  final String? id;
  final String movementType;
  final String productId;
  final String? productName;
  final String? batchId;
  final String? batchNumber;
  final String? fromWarehouseId;
  final String? toWarehouseId;
  final double quantity;
  final double beforeQuantity;
  final double afterQuantity;
  final double unitCost;
  final double totalCost;
  final String? referenceType;
  final String? referenceId;
  final String? description;
  final DateTime? createdAt;
  final String? userName;

  StockMovementModel({
    this.id,
    required this.movementType,
    required this.productId,
    this.productName,
    this.batchId,
    this.batchNumber,
    this.fromWarehouseId,
    this.toWarehouseId,
    this.quantity = 0.0,
    this.beforeQuantity = 0.0,
    this.afterQuantity = 0.0,
    this.unitCost = 0.0,
    this.totalCost = 0.0,
    this.referenceType,
    this.referenceId,
    this.description,
    this.createdAt,
    this.userName,
  });

  factory StockMovementModel.fromMap(Map<String, dynamic> map) {
    return StockMovementModel(
      id: map['id']?.toString(),
      movementType: map['movement_type'] as String,
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name'] as String?,
      batchId: map['batch_id']?.toString(),
      batchNumber: map['batch_number'] as String?,
      fromWarehouseId: map['from_warehouse_id']?.toString(),
      toWarehouseId: map['to_warehouse_id']?.toString(),
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      beforeQuantity: (map['before_quantity'] as num?)?.toDouble() ?? 0.0,
      afterQuantity: (map['after_quantity'] as num?)?.toDouble() ?? 0.0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0.0,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id']?.toString(),
      description: map['description'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      userName: map['user_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'movement_type': movementType,
      'product_id': productId,
      if (batchId != null) 'batch_id': batchId,
      if (fromWarehouseId != null) 'from_warehouse_id': fromWarehouseId,
      if (toWarehouseId != null) 'to_warehouse_id': toWarehouseId,
      'quantity': quantity,
      'before_quantity': beforeQuantity,
      'after_quantity': afterQuantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      if (referenceType != null) 'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      'description': description,
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
    };
  }

  StockMovementModel copyWith({
    String? id,
    String? movementType,
    String? productId,
    String? productName,
    String? batchId,
    String? batchNumber,
    String? fromWarehouseId,
    String? toWarehouseId,
    double? quantity,
    double? beforeQuantity,
    double? afterQuantity,
    double? unitCost,
    double? totalCost,
    String? referenceType,
    String? referenceId,
    String? description,
    DateTime? createdAt,
    String? userName,
  }) {
    return StockMovementModel(
      id: id ?? this.id,
      movementType: movementType ?? this.movementType,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      batchId: batchId ?? this.batchId,
      batchNumber: batchNumber ?? this.batchNumber,
      fromWarehouseId: fromWarehouseId ?? this.fromWarehouseId,
      toWarehouseId: toWarehouseId ?? this.toWarehouseId,
      quantity: quantity ?? this.quantity,
      beforeQuantity: beforeQuantity ?? this.beforeQuantity,
      afterQuantity: afterQuantity ?? this.afterQuantity,
      unitCost: unitCost ?? this.unitCost,
      totalCost: totalCost ?? this.totalCost,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      userName: userName ?? this.userName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockMovementModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
