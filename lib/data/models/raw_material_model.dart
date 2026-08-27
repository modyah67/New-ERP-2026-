class RawMaterialModel {
  final String? id;
  final String code;
  final String name;
  final String unit;
  final double quantity;
  final double defaultPurchasePrice;
  final double minimumStock;
  final String? defaultSupplierId;
  final bool isActive;
  final String? notes;
  final String? categoryId;
  final String? categoryName;
  final String currency;
  final double initialQuantity;
  final double initialAvgPrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RawMaterialModel({
    this.id,
    required this.code,
    required this.name,
    this.unit = 'piece',
    this.quantity = 0,
    this.defaultPurchasePrice = 0,
    this.minimumStock = 0,
    this.defaultSupplierId,
    this.isActive = true,
    this.notes,
    this.categoryId,
    this.categoryName,
    this.currency = 'EGP',
    this.initialQuantity = 0,
    this.initialAvgPrice = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isLowStock => isActive && minimumStock > 0 && quantity > 0 && quantity <= minimumStock;
  bool get isOutOfStock => quantity == 0;

  factory RawMaterialModel.fromMap(Map<String, dynamic> map) {
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    return RawMaterialModel(
      id: map['id']?.toString(),
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? 'piece',
      quantity: n(map['quantity']) ?? 0,
      defaultPurchasePrice: n(map['default_purchase_price']) ?? 0,
      minimumStock: n(map['minimum_stock']) ?? 0,
      defaultSupplierId: map['default_supplier_id']?.toString(),
      isActive: map['is_active'] is bool ? map['is_active'] : (map['is_active']?.toString() == 'true'),
      notes: map['notes']?.toString(),
      categoryId: map['category_id']?.toString(),
      categoryName: map['category_name']?.toString() ?? map['raw_material_categories']?['name']?.toString(),
      currency: map['currency']?.toString() ?? 'EGP',
      initialQuantity: n(map['initial_quantity']) ?? 0,
      initialAvgPrice: n(map['initial_avg_price']) ?? 0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'unit': unit,
      'quantity': quantity,
      'default_purchase_price': defaultPurchasePrice,
      'minimum_stock': minimumStock,
      if (defaultSupplierId != null) 'default_supplier_id': defaultSupplierId,
      'is_active': isActive,
      if (notes != null) 'notes': notes,
      if (categoryId != null) 'category_id': categoryId,
      'currency': currency,
    };
  }

  RawMaterialModel copyWith({
    String? id,
    String? code,
    String? name,
    String? unit,
    double? quantity,
    double? defaultPurchasePrice,
    double? minimumStock,
    String? defaultSupplierId,
    bool? isActive,
    String? notes,
    String? categoryId,
    String? categoryName,
    String? currency,
    double? initialQuantity,
    double? initialAvgPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RawMaterialModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      defaultPurchasePrice: defaultPurchasePrice ?? this.defaultPurchasePrice,
      minimumStock: minimumStock ?? this.minimumStock,
      defaultSupplierId: defaultSupplierId ?? this.defaultSupplierId,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      currency: currency ?? this.currency,
      initialQuantity: initialQuantity ?? this.initialQuantity,
      initialAvgPrice: initialAvgPrice ?? this.initialAvgPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawMaterialModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
