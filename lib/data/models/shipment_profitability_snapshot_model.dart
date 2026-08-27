class ShipmentProfitabilitySnapshotModel {
  final int? id;
  final int shipmentId;
  final String shipmentNo;
  
  // Revenue
  final double revenueForeign;
  final double revenueLocal;
  
  // Cost components
  final double fruitCost;
  final double packingCost;
  final double logisticsCost;
  final double administrativeCost;
  final double otherCost;
  final double totalCost;
  
  // Profit
  final double grossProfit;
  final double netProfit;
  final double grossMargin;
  final double netMargin;
  
  // Cost distribution metrics
  final double costPerCarton;
  final double costPerKg;
  final double costPerPallet;
  
  // Shipment metrics
  final int cartons;
  final double netWeight;
  final int pallets;
  
  // Exchange rate and currency
  final double exchangeRate;
  final String currencyCode;
  
  // Metadata
  final DateTime? createdAt;
  final String? createdBy;

  const ShipmentProfitabilitySnapshotModel({
    this.id,
    required this.shipmentId,
    required this.shipmentNo,
    this.revenueForeign = 0.0,
    this.revenueLocal = 0.0,
    this.fruitCost = 0.0,
    this.packingCost = 0.0,
    this.logisticsCost = 0.0,
    this.administrativeCost = 0.0,
    this.otherCost = 0.0,
    this.totalCost = 0.0,
    this.grossProfit = 0.0,
    this.netProfit = 0.0,
    this.grossMargin = 0.0,
    this.netMargin = 0.0,
    this.costPerCarton = 0.0,
    this.costPerKg = 0.0,
    this.costPerPallet = 0.0,
    this.cartons = 0,
    this.netWeight = 0.0,
    this.pallets = 0,
    this.exchangeRate = 1.0,
    this.currencyCode = 'USD',
    this.createdAt,
    this.createdBy,
  });

  factory ShipmentProfitabilitySnapshotModel.fromMap(Map<String, dynamic> map) {
    return ShipmentProfitabilitySnapshotModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      shipmentNo: (map['shipment_no'] as String?) ?? '',
      revenueForeign: (map['revenue_foreign'] as num?)?.toDouble() ?? 0.0,
      revenueLocal: (map['revenue_local'] as num?)?.toDouble() ?? 0.0,
      fruitCost: (map['fruit_cost'] as num?)?.toDouble() ?? 0.0,
      packingCost: (map['packing_cost'] as num?)?.toDouble() ?? 0.0,
      logisticsCost: (map['logistics_cost'] as num?)?.toDouble() ?? 0.0,
      administrativeCost: (map['administrative_cost'] as num?)?.toDouble() ?? 0.0,
      otherCost: (map['other_cost'] as num?)?.toDouble() ?? 0.0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (map['gross_profit'] as num?)?.toDouble() ?? 0.0,
      netProfit: (map['net_profit'] as num?)?.toDouble() ?? 0.0,
      grossMargin: (map['gross_margin'] as num?)?.toDouble() ?? 0.0,
      netMargin: (map['net_margin'] as num?)?.toDouble() ?? 0.0,
      costPerCarton: (map['cost_per_carton'] as num?)?.toDouble() ?? 0.0,
      costPerKg: (map['cost_per_kg'] as num?)?.toDouble() ?? 0.0,
      costPerPallet: (map['cost_per_pallet'] as num?)?.toDouble() ?? 0.0,
      cartons: (map['cartons'] as num?)?.toInt() ?? 0,
      netWeight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      pallets: (map['pallets'] as num?)?.toInt() ?? 0,
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      currencyCode: (map['currency_code'] as String?) ?? 'USD',
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'] as String) 
          : null,
      createdBy: map['created_by']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      'shipment_no': shipmentNo,
      'revenue_foreign': revenueForeign,
      'revenue_local': revenueLocal,
      'fruit_cost': fruitCost,
      'packing_cost': packingCost,
      'logistics_cost': logisticsCost,
      'administrative_cost': administrativeCost,
      'other_cost': otherCost,
      'total_cost': totalCost,
      'gross_profit': grossProfit,
      'net_profit': netProfit,
      'gross_margin': grossMargin,
      'net_margin': netMargin,
      'cost_per_carton': costPerCarton,
      'cost_per_kg': costPerKg,
      'cost_per_pallet': costPerPallet,
      'cartons': cartons,
      'net_weight': netWeight,
      'pallets': pallets,
      'exchange_rate': exchangeRate,
      'currency_code': currencyCode,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  ShipmentProfitabilitySnapshotModel copyWith({
    int? id,
    int? shipmentId,
    String? shipmentNo,
    double? revenueForeign,
    double? revenueLocal,
    double? fruitCost,
    double? packingCost,
    double? logisticsCost,
    double? administrativeCost,
    double? otherCost,
    double? totalCost,
    double? grossProfit,
    double? netProfit,
    double? grossMargin,
    double? netMargin,
    double? costPerCarton,
    double? costPerKg,
    double? costPerPallet,
    int? cartons,
    double? netWeight,
    int? pallets,
    double? exchangeRate,
    String? currencyCode,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return ShipmentProfitabilitySnapshotModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      shipmentNo: shipmentNo ?? this.shipmentNo,
      revenueForeign: revenueForeign ?? this.revenueForeign,
      revenueLocal: revenueLocal ?? this.revenueLocal,
      fruitCost: fruitCost ?? this.fruitCost,
      packingCost: packingCost ?? this.packingCost,
      logisticsCost: logisticsCost ?? this.logisticsCost,
      administrativeCost: administrativeCost ?? this.administrativeCost,
      otherCost: otherCost ?? this.otherCost,
      totalCost: totalCost ?? this.totalCost,
      grossProfit: grossProfit ?? this.grossProfit,
      netProfit: netProfit ?? this.netProfit,
      grossMargin: grossMargin ?? this.grossMargin,
      netMargin: netMargin ?? this.netMargin,
      costPerCarton: costPerCarton ?? this.costPerCarton,
      costPerKg: costPerKg ?? this.costPerKg,
      costPerPallet: costPerPallet ?? this.costPerPallet,
      cartons: cartons ?? this.cartons,
      netWeight: netWeight ?? this.netWeight,
      pallets: pallets ?? this.pallets,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      currencyCode: currencyCode ?? this.currencyCode,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
