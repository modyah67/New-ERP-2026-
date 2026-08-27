import 'package:equatable/equatable.dart';

class InventorySnapshot extends Equatable {
  final int? id;
  final int fiscalYearId;
  final String snapshotType;
  final int? productId;
  final int? warehouseId;
  final int? batchId;
  final double quantity;
  final double unitCost;
  final double totalCost;
  final String? costMethod;
  final Map<String, dynamic>? currencySnapshot;
  final DateTime createdAt;

  const InventorySnapshot({
    this.id,
    required this.fiscalYearId,
    required this.snapshotType,
    this.productId,
    this.warehouseId,
    this.batchId,
    this.quantity = 0,
    this.unitCost = 0,
    this.totalCost = 0,
    this.costMethod,
    this.currencySnapshot,
    required this.createdAt,
  });

  factory InventorySnapshot.fromJson(Map<String, dynamic> json) {
    return InventorySnapshot(
      id: json['id'] as int?,
      fiscalYearId: json['fiscal_year_id'] as int,
      snapshotType: json['snapshot_type'] as String,
      productId: json['product_id'] as int?,
      warehouseId: json['warehouse_id'] as int?,
      batchId: json['batch_id'] as int?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0.0,
      costMethod: json['cost_method'] as String?,
      currencySnapshot: json['currency_snapshot'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'fiscal_year_id': fiscalYearId,
      'snapshot_type': snapshotType,
      'product_id': productId,
      'warehouse_id': warehouseId,
      'batch_id': batchId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'cost_method': costMethod,
      'currency_snapshot': currencySnapshot,
    };
  }

  @override
  List<Object?> get props => [id, fiscalYearId, snapshotType, productId, batchId];
}
