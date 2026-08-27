class SupplierSettlementModel {
  final int? id;
  final int shipmentId;
  final String supplierId;
  final int productId;
  final String grade;
  final double weightKg;
  final double unitPrice;
  final double totalAmount;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? supplierName;
  final String? productName;

  const SupplierSettlementModel({
    this.id,
    required this.shipmentId,
    required this.supplierId,
    required this.productId,
    this.grade = 'A',
    this.weightKg = 0,
    this.unitPrice = 0,
    this.totalAmount = 0,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.supplierName,
    this.productName,
  });

  factory SupplierSettlementModel.fromMap(Map<String, dynamic> map) {
    return SupplierSettlementModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      supplierId: map['supplier_id']?.toString() ?? '',
      productId: (map['product_id'] as num?)?.toInt() ?? 0,
      grade: (map['grade'] as String?) ?? 'A',
      weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      supplierName: map['supplier_name'] as String?,
      productName: map['product_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      'supplier_id': supplierId,
      'product_id': productId,
      'grade': grade,
      'weight_kg': weightKg,
      'unit_price': unitPrice,
      if (notes != null) 'notes': notes,
    };
  }

  SupplierSettlementModel copyWith({
    int? id,
    int? shipmentId,
    String? supplierId,
    int? productId,
    String? grade,
    double? weightKg,
    double? unitPrice,
    double? totalAmount,
    String? notes,
    String? supplierName,
    String? productName,
  }) {
    return SupplierSettlementModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      supplierId: supplierId ?? this.supplierId,
      productId: productId ?? this.productId,
      grade: grade ?? this.grade,
      weightKg: weightKg ?? this.weightKg,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
      supplierName: supplierName ?? this.supplierName,
      productName: productName ?? this.productName,
    );
  }
}
