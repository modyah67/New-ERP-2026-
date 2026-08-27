class PrepCenterCostItemModel {
  final int? id;
  final int shipmentId;
  final String costType;
  final String description;
  final double qty;
  final double unitPrice;
  final double totalCost;
  final String? notes;
  final DateTime? createdAt;

  const PrepCenterCostItemModel({
    this.id,
    required this.shipmentId,
    this.costType = 'OTHER',
    this.description = '',
    this.qty = 1,
    this.unitPrice = 0,
    this.totalCost = 0,
    this.notes,
    this.createdAt,
  });

  String get costTypeLabel {
    switch (costType) {
      case 'PACKAGING': return 'تعبئة وتغليف';
      case 'LABOR': return 'عمالة';
      case 'DIESEL': return 'ديزل';
      case 'AGRICULTURE': return 'أجرة زراعية';
      case 'TRANSPORT': return 'نقل';
      case 'COOLING': return 'تبريد';
      case 'LABELS': return 'ليبل';
      case 'STICKERS': return 'استيكر';
      default: return 'أخرى';
    }
  }

  static const List<String> costTypes = [
    'PACKAGING', 'LABOR', 'DIESEL', 'AGRICULTURE',
    'TRANSPORT', 'COOLING', 'LABELS', 'STICKERS', 'OTHER',
  ];

  factory PrepCenterCostItemModel.fromMap(Map<String, dynamic> map) {
    return PrepCenterCostItemModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      costType: (map['cost_type'] as String?) ?? 'OTHER',
      description: (map['description'] as String?) ?? '',
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      'cost_type': costType,
      'description': description,
      'qty': qty,
      'unit_price': unitPrice,
      if (notes != null) 'notes': notes,
    };
  }

  PrepCenterCostItemModel copyWith({
    int? id,
    int? shipmentId,
    String? costType,
    String? description,
    double? qty,
    double? unitPrice,
    double? totalCost,
    String? notes,
  }) {
    return PrepCenterCostItemModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      costType: costType ?? this.costType,
      description: description ?? this.description,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      totalCost: totalCost ?? this.totalCost,
      notes: notes ?? this.notes,
    );
  }
}
