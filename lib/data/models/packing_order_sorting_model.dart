class PackingOrderSortingModel {
  final int? id;
  final int packingOrderId;
  final String productName;
  final String? lotNumber;
  final double weightKg;
  final double remainingWeightKg;
  final double costPerKg;
  final double totalCost;
  final double totalSaleAmount;
  final String status;
  final DateTime? soldAt;
  final int? stationId;
  final DateTime? createdAt;
  final String? treasuryNames;
  final String? exportShipmentNo;
  final String? customerName;
  final int? customerId;

  const PackingOrderSortingModel({
    this.id,
    required this.packingOrderId,
    required this.productName,
    this.lotNumber,
    this.weightKg = 0,
    this.remainingWeightKg = 0,
    this.costPerKg = 0,
    this.totalCost = 0,
    this.totalSaleAmount = 0,
    this.status = 'pending',
    this.soldAt,
    this.stationId,
    this.createdAt,
    this.treasuryNames,
    this.exportShipmentNo,
    this.customerName,
    this.customerId,
  });

  factory PackingOrderSortingModel.fromMap(Map<String, dynamic> map) {
    final weight = (map['weight_kg'] as num?)?.toDouble() ?? 0;
    final remaining = (map['remaining_weight_kg'] as num?)?.toDouble() ?? weight;
    return PackingOrderSortingModel(
      id: map['id'] as int?,
      packingOrderId: (map['packing_order_id'] as num?)?.toInt() ?? 0,
      productName: (map['product_name'] as String?) ?? '',
      lotNumber: map['lot_number'] as String?,
      weightKg: weight,
      remainingWeightKg: remaining,
      costPerKg: (map['cost_per_kg'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      totalSaleAmount: (map['total_sale_amount'] as num?)?.toDouble() ?? 0,
      status: (map['status'] as String?) ?? 'pending',
      soldAt: map['sold_at'] != null ? DateTime.tryParse(map['sold_at'] as String) : null,
      stationId: map['station_id'] as int?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      treasuryNames: map['treasury_names'] as String?,
      exportShipmentNo: map['export_shipment_no'] as String?,
      customerName: map['customer_name'] as String?,
      customerId: (map['customer_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'packing_order_id': packingOrderId,
      'product_name': productName,
      if (lotNumber != null) 'lot_number': lotNumber,
      'weight_kg': weightKg,
      'remaining_weight_kg': remainingWeightKg,
      'cost_per_kg': costPerKg,
      'total_cost': totalCost,
      'total_sale_amount': totalSaleAmount,
      'status': status,
      if (soldAt != null) 'sold_at': soldAt!.toIso8601String(),
      if (stationId != null) 'station_id': stationId,
      if (treasuryNames != null) 'treasury_names': treasuryNames,
      if (exportShipmentNo != null) 'export_shipment_no': exportShipmentNo,
      if (customerName != null) 'customer_name': customerName,
      if (customerId != null) 'customer_id': customerId,
    };
  }

  PackingOrderSortingModel copyWith({
    int? id,
    int? packingOrderId,
    String? productName,
    String? lotNumber,
    double? weightKg,
    double? remainingWeightKg,
    double? costPerKg,
    double? totalCost,
    double? totalSaleAmount,
    String? status,
    DateTime? soldAt,
    int? stationId,
    DateTime? createdAt,
    String? treasuryNames,
    String? exportShipmentNo,
    String? customerName,
    int? customerId,
  }) {
    return PackingOrderSortingModel(
      id: id ?? this.id,
      packingOrderId: packingOrderId ?? this.packingOrderId,
      productName: productName ?? this.productName,
      lotNumber: lotNumber ?? this.lotNumber,
      weightKg: weightKg ?? this.weightKg,
      remainingWeightKg: remainingWeightKg ?? this.remainingWeightKg,
      costPerKg: costPerKg ?? this.costPerKg,
      totalCost: totalCost ?? this.totalCost,
      totalSaleAmount: totalSaleAmount ?? this.totalSaleAmount,
      status: status ?? this.status,
      soldAt: soldAt ?? this.soldAt,
      stationId: stationId ?? this.stationId,
      createdAt: createdAt ?? this.createdAt,
      treasuryNames: treasuryNames ?? this.treasuryNames,
      exportShipmentNo: exportShipmentNo ?? this.exportShipmentNo,
      customerName: customerName ?? this.customerName,
      customerId: customerId ?? this.customerId,
    );
  }

  bool get isPending => status == 'pending';
  bool get isSold => status == 'sold';
  bool get isSoldOut => remainingWeightKg <= 0;
  double get remainingValue => remainingWeightKg * costPerKg;
}
