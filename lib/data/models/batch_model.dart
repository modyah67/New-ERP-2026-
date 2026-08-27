class BatchModel {
  final String? id;
  final String batchNumber;
  final String productId;
  final String? productName;
  final String? productSku;
  final String? purchaseInvoiceId;
  final String? supplierId;
  final String? supplierName;
  final double quantity;
  final double remainingQuantity;
  final double purchaseCost;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final String qualityGrade;
  final String? category;
  final String? notes;
  final String status;
  final String? warehouseId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BatchModel({
    this.id,
    required this.batchNumber,
    required this.productId,
    this.productName,
    this.productSku,
    this.purchaseInvoiceId,
    this.supplierId,
    this.supplierName,
    this.quantity = 0.0,
    this.remainingQuantity = 0.0,
    this.purchaseCost = 0.0,
    this.productionDate,
    this.expiryDate,
    this.qualityGrade = 'A',
    this.category,
    this.notes,
    this.status = 'active',
    this.warehouseId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isExpired => expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final days = expiryDate!.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }
  bool get isActive => status == 'active';
  bool get isDepleted => status == 'depleted' || remainingQuantity <= 0;

  factory BatchModel.fromMap(Map<String, dynamic> map) {
    return BatchModel(
      id: map['id']?.toString(),
      batchNumber: map['batch_number'] as String,
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name'] as String?,
      productSku: map['product_sku'] as String?,
      purchaseInvoiceId: map['purchase_invoice_id']?.toString(),
      supplierId: map['supplier_id']?.toString(),
      supplierName: map['supplier_name'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      remainingQuantity: (map['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
      purchaseCost: (map['purchase_cost'] as num?)?.toDouble() ?? 0.0,
      productionDate: map['production_date'] != null ? DateTime.tryParse(map['production_date'] as String) : null,
      expiryDate: map['expiry_date'] != null ? DateTime.tryParse(map['expiry_date'] as String) : null,
      qualityGrade: map['quality_grade'] as String? ?? 'A',
      category: map['category'] as String? ?? map['fruit_category'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? 'active',
      warehouseId: map['warehouse_id']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'batch_number': batchNumber,
      'product_id': productId,
      if (purchaseInvoiceId != null) 'purchase_invoice_id': purchaseInvoiceId,
      if (supplierId != null) 'supplier_id': supplierId,
      'quantity': quantity,
      'remaining_quantity': remainingQuantity,
      'purchase_cost': purchaseCost,
      if (productionDate != null) 'production_date': productionDate?.toIso8601String(),
      if (expiryDate != null) 'expiry_date': expiryDate?.toIso8601String(),
      'quality_grade': qualityGrade,
      if (category != null) 'category': category,
      if (notes != null) 'notes': notes,
      'status': status,
      if (warehouseId != null) 'warehouse_id': warehouseId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  BatchModel copyWith({
    String? id,
    String? batchNumber,
    String? productId,
    String? productName,
    String? productSku,
    String? purchaseInvoiceId,
    String? supplierId,
    String? supplierName,
    double? quantity,
    double? remainingQuantity,
    double? purchaseCost,
    DateTime? productionDate,
    DateTime? expiryDate,
    String? qualityGrade,
    String? category,
    String? notes,
    String? status,
    String? warehouseId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BatchModel(
      id: id ?? this.id,
      batchNumber: batchNumber ?? this.batchNumber,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      purchaseInvoiceId: purchaseInvoiceId ?? this.purchaseInvoiceId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      quantity: quantity ?? this.quantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      purchaseCost: purchaseCost ?? this.purchaseCost,
      productionDate: productionDate ?? this.productionDate,
      expiryDate: expiryDate ?? this.expiryDate,
      qualityGrade: qualityGrade ?? this.qualityGrade,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      warehouseId: warehouseId ?? this.warehouseId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
