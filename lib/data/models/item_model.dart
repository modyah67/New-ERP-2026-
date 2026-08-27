class ItemModel {
  final String? id;
  final String code;
  final String name;
  final String type;
  final double pricePerUnit;
  final double costPrice;
  final String unit;
  final double stockQuantity;
  final String? supplierId;
  final String? supplierName;
  final String currency;
  final String createdAt;

  ItemModel({
    this.id,
    required this.code,
    required this.name,
    required this.type,
    this.pricePerUnit = 0,
    this.costPrice = 0,
    this.unit = 'كجم',
    this.stockQuantity = 0.0,
    this.supplierId,
    this.supplierName,
    this.currency = 'EGP',
    required this.createdAt,
  });

  /// --- 🚀 Factory Constructor (Type Safe & Crash Proof) ---
  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id']?.toString(),
      code: _str(map['code']),
      name: _str(map['name']),
      type: _str(map['type']),
      pricePerUnit: _num(map['price_per_unit']),
      costPrice: _num(map['cost_price']),
      unit: _str(map['unit']).isEmpty
          ? 'كجم'
          : _str(map['unit']),
      stockQuantity: _num(map['stock_quantity']),
      supplierId: map['supplier_id']?.toString(),
      supplierName: _strOrNull(map['supplier_name']),
      currency: _str(map['currency']).isEmpty ? 'EGP' : _str(map['currency']),
      createdAt: _str(map['created_at']),
    );
  }

  /// --- 📦 To Map ---
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'type': type,
      'price_per_unit': pricePerUnit,
      'cost_price': costPrice,
      'unit': unit,
      'stock_quantity': stockQuantity,
      'supplier_id': supplierId,
      'currency': currency,
      'created_at': createdAt,
    };
  }

  /// --- 🔄 Copy With ---
  ItemModel copyWith({
    String? id,
    String? code,
    String? name,
    String? type,
    double? pricePerUnit,
    double? costPrice,
    String? unit,
    double? stockQuantity,
    String? supplierId,
    String? supplierName,
    String? currency,
    String? createdAt,
  }) {
    return ItemModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      costPrice: costPrice ?? this.costPrice,
      unit: unit ?? this.unit,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;

  /// --- 🛠️ Static Performance-Friendly Helpers (Inside Class) ---

  // تحويل آمن للنصوص غير القابلة للـ null
  static String _str(dynamic v) {
    if (v == null) return '';
    return v.toString();
  }

  // تحويل آمن لنص nullable (للـ supplier_name مثلاً)
  static String? _strOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.trim().isEmpty ? null : s;
  }

  // تحويل آمن للـ double (يمنع الـ runtime cast mismatch)
  static double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
