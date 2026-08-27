class ShipmentCostBreakdownModel {
  final int? id;
  final int shipmentId;
  final String costType;
  final String? costCategory;
  final String itemName;
  final double quantity;
  final double unitCost;
  final double totalCost;
  final String currency;
  final String? supplier;
  final String? notes;
  final int sortOrder;
  final double fruitCostPerKg;
  final DateTime? createdAt;

  const ShipmentCostBreakdownModel({
    this.id,
    required this.shipmentId,
    required this.costType,
    this.costCategory,
    required this.itemName,
    this.quantity = 0,
    this.unitCost = 0,
    this.totalCost = 0,
    this.currency = 'EGP',
    this.supplier,
    this.notes,
    this.sortOrder = 0,
    this.fruitCostPerKg = 0,
    this.createdAt,
  });

  String get costTypeLabel {
    switch (costType) {
      case 'fruit': return 'تكلفة الفاكهة';
      case 'packing_material': return 'مواد التعبئة';
      case 'logistics': return 'لوجستيك';
      case 'export_cost': return 'تكاليف التصدير';
      case 'admin': return 'مصاريف إدارية';
      default: return 'أخرى';
    }
  }

  factory ShipmentCostBreakdownModel.fromMap(Map<String, dynamic> map) {
    return ShipmentCostBreakdownModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      costType: (map['cost_type'] as String?) ?? 'other',
      costCategory: map['cost_category'] as String?,
      itemName: (map['item_name'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] as String?) ?? 'EGP',
      supplier: map['supplier'] as String?,
      notes: map['notes'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      fruitCostPerKg: (map['fruit_cost_per_kg'] as num?)?.toDouble() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      'cost_type': costType,
      if (costCategory != null) 'cost_category': costCategory,
      'item_name': itemName,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'currency': currency,
      if (supplier != null) 'supplier': supplier,
      if (notes != null) 'notes': notes,
      'sort_order': sortOrder,
      'fruit_cost_per_kg': fruitCostPerKg,
    };
  }

  ShipmentCostBreakdownModel copyWith({
    int? id,
    int? shipmentId,
    String? costType,
    String? costCategory,
    String? itemName,
    double? quantity,
    double? unitCost,
    double? totalCost,
    String? currency,
    String? supplier,
    String? notes,
    int? sortOrder,
    double? fruitCostPerKg,
    DateTime? createdAt,
  }) {
    return ShipmentCostBreakdownModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      costType: costType ?? this.costType,
      costCategory: costCategory ?? this.costCategory,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      totalCost: totalCost ?? this.totalCost,
      currency: currency ?? this.currency,
      supplier: supplier ?? this.supplier,
      notes: notes ?? this.notes,
      sortOrder: sortOrder ?? this.sortOrder,
      fruitCostPerKg: fruitCostPerKg ?? this.fruitCostPerKg,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
