class FruitTypeModel {
  final String? id;
  final String code;
  final String name;
  final String icon;
  final String? imageUrl;
  final String? color;
  final int sortOrder;
  final bool isActive;
  final String currency;
  final String? purchaseMode;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Computed fields (from view, not stored)
  final double? latestPurchasePrice;
  final double? averagePurchasePrice;
  final String? lastPurchaseDate;
  final double? totalQuantity;
  final String? latestPurchaseMode;
  final int? latestCartonCount;
  final double? latestWeightPerCartonKg;
  final double? latestGrossWeightPerCartonKg;
  final double? latestPricePerCarton;
  double? totalStockQuantity;
  double? totalStockValue;

  FruitTypeModel({
    this.id,
    required this.code,
    required this.name,
    this.icon = 'eco',
    this.imageUrl,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
    this.currency = 'EGP',
    this.purchaseMode,
    this.createdAt,
    this.updatedAt,
    this.latestPurchasePrice,
    this.averagePurchasePrice,
    this.lastPurchaseDate,
    this.totalQuantity,
    this.latestPurchaseMode,
    this.latestCartonCount,
    this.latestWeightPerCartonKg,
    this.latestGrossWeightPerCartonKg,
    this.latestPricePerCarton,
    this.totalStockQuantity,
    this.totalStockValue,
  });

  factory FruitTypeModel.fromMap(Map<String, dynamic> map) {
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    return FruitTypeModel(
      id: map['id']?.toString(),
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      icon: map['icon']?.toString() ?? 'eco',
      imageUrl: map['image_url']?.toString(),
      color: map['color']?.toString(),
      sortOrder: map['sort_order'] is int ? map['sort_order'] : int.tryParse('${map['sort_order']}') ?? 0,
      isActive: map['is_active'] is bool ? map['is_active'] : (map['is_active']?.toString() == 'true'),
      currency: map['currency']?.toString() ?? 'EGP',
      purchaseMode: map['purchase_mode']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
      latestPurchasePrice: n(map['latest_price']),
      averagePurchasePrice: n(map['avg_price']),
      lastPurchaseDate: map['last_purchase_date']?.toString(),
      totalQuantity: n(map['total_quantity']),
      latestPurchaseMode: map['purchase_mode']?.toString(),
      latestCartonCount: (map['carton_count'] as num?)?.toInt(),
      latestWeightPerCartonKg: n(map['weight_per_carton_kg']),
      latestGrossWeightPerCartonKg: n(map['gross_weight_per_carton_kg']),
      latestPricePerCarton: n(map['price_per_carton']),
      totalStockQuantity: n(map['total_stock_quantity']),
      totalStockValue: n(map['total_stock_value']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'icon': icon,
      'currency': currency,
      'purchase_mode': purchaseMode,
    };
  }

  FruitTypeModel copyWith({
    String? id,
    String? code,
    String? name,
    String? icon,
    String? imageUrl,
    String? color,
    int? sortOrder,
    bool? isActive,
    String? currency,
    String? purchaseMode,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? latestPurchasePrice,
    double? averagePurchasePrice,
    String? lastPurchaseDate,
    double? totalQuantity,
    String? latestPurchaseMode,
    int? latestCartonCount,
    double? latestWeightPerCartonKg,
    double? latestGrossWeightPerCartonKg,
    double? latestPricePerCarton,
    double? totalStockQuantity,
    double? totalStockValue,
  }) {
    return FruitTypeModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      imageUrl: imageUrl ?? this.imageUrl,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      currency: currency ?? this.currency,
      purchaseMode: purchaseMode ?? this.purchaseMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      latestPurchasePrice: latestPurchasePrice ?? this.latestPurchasePrice,
      averagePurchasePrice: averagePurchasePrice ?? this.averagePurchasePrice,
      lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      latestPurchaseMode: latestPurchaseMode ?? this.latestPurchaseMode,
      latestCartonCount: latestCartonCount ?? this.latestCartonCount,
      latestWeightPerCartonKg: latestWeightPerCartonKg ?? this.latestWeightPerCartonKg,
      latestGrossWeightPerCartonKg: latestGrossWeightPerCartonKg ?? this.latestGrossWeightPerCartonKg,
      latestPricePerCarton: latestPricePerCarton ?? this.latestPricePerCarton,
      totalStockQuantity: totalStockQuantity ?? this.totalStockQuantity,
      totalStockValue: totalStockValue ?? this.totalStockValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FruitTypeModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
