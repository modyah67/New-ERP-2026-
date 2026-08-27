class FinishedProductModel {
  final String? id;
  final String code;
  final String name;
  final String? barcode;
  final String? category;
  final String? packingRecipeId;
  final double salePrice;
  final String unit;
  final bool isActive;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  FinishedProductModel({
    this.id,
    required this.code,
    required this.name,
    this.barcode,
    this.category,
    this.packingRecipeId,
    this.salePrice = 0,
    this.unit = 'carton',
    this.isActive = true,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory FinishedProductModel.fromMap(Map<String, dynamic> map) {
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    return FinishedProductModel(
      id: map['id']?.toString(),
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      category: map['category']?.toString(),
      packingRecipeId: map['packing_recipe_id']?.toString(),
      salePrice: n(map['sale_price']) ?? 0,
      unit: map['unit']?.toString() ?? 'carton',
      isActive: map['is_active'] is bool ? map['is_active'] : (map['is_active']?.toString() == 'true'),
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      if (barcode != null) 'barcode': barcode,
      if (category != null) 'category': category,
      if (packingRecipeId != null) 'packing_recipe_id': packingRecipeId,
      'sale_price': salePrice,
      'unit': unit,
      'is_active': isActive,
      if (notes != null) 'notes': notes,
    };
  }

  FinishedProductModel copyWith({
    String? id,
    String? code,
    String? name,
    String? barcode,
    String? category,
    String? packingRecipeId,
    double? salePrice,
    String? unit,
    bool? isActive,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FinishedProductModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      packingRecipeId: packingRecipeId ?? this.packingRecipeId,
      salePrice: salePrice ?? this.salePrice,
      unit: unit ?? this.unit,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinishedProductModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
