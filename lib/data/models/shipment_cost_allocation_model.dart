class ShipmentCostAllocationModel {
  final int? id;
  final int shipmentId;
  final int? sourceCostItemId;
  final int finishedProductId;
  final String allocationBasis;
  final double allocatedAmount;
  final double allocationPercentage;
  final DateTime? createdAt;

  ShipmentCostAllocationModel({
    this.id,
    required this.shipmentId,
    this.sourceCostItemId,
    required this.finishedProductId,
    required this.allocationBasis,
    this.allocatedAmount = 0.0,
    this.allocationPercentage = 0.0,
    this.createdAt,
  });

  factory ShipmentCostAllocationModel.fromMap(Map<String, dynamic> map) {
    return ShipmentCostAllocationModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      sourceCostItemId: (map['source_cost_item_id'] as num?)?.toInt(),
      finishedProductId: (map['finished_product_id'] as num?)?.toInt() ?? 0,
      allocationBasis: (map['allocation_basis'] as String?) ?? 'weight_based',
      allocatedAmount: (map['allocated_amount'] as num?)?.toDouble() ?? 0.0,
      allocationPercentage: (map['allocation_percentage'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      if (sourceCostItemId != null) 'source_cost_item_id': sourceCostItemId,
      'finished_product_id': finishedProductId,
      'allocation_basis': allocationBasis,
      'allocated_amount': allocatedAmount,
      'allocation_percentage': allocationPercentage,
    };
  }

  ShipmentCostAllocationModel copyWith({
    int? id,
    int? shipmentId,
    int? sourceCostItemId,
    int? finishedProductId,
    String? allocationBasis,
    double? allocatedAmount,
    double? allocationPercentage,
    DateTime? createdAt,
  }) {
    return ShipmentCostAllocationModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      sourceCostItemId: sourceCostItemId ?? this.sourceCostItemId,
      finishedProductId: finishedProductId ?? this.finishedProductId,
      allocationBasis: allocationBasis ?? this.allocationBasis,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      allocationPercentage: allocationPercentage ?? this.allocationPercentage,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
