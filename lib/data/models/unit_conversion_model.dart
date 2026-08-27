class UnitConversionModel {
  final int? id;
  final String fromUnit;
  final String toUnit;
  final double conversionFactor;
  final int? productId;
  final DateTime? createdAt;

  UnitConversionModel({
    this.id,
    required this.fromUnit,
    required this.toUnit,
    required this.conversionFactor,
    this.productId,
    this.createdAt,
  });

  factory UnitConversionModel.fromMap(Map<String, dynamic> map) {
    return UnitConversionModel(
      id: map['id'] as int?,
      fromUnit: map['from_unit'] as String,
      toUnit: map['to_unit'] as String,
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      productId: map['product_id'] as int?,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'from_unit': fromUnit,
      'to_unit': toUnit,
      'conversion_factor': conversionFactor,
      'product_id': productId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UnitConversionModel copyWith({
    int? id,
    String? fromUnit,
    String? toUnit,
    double? conversionFactor,
    int? productId,
    DateTime? createdAt,
  }) {
    return UnitConversionModel(
      id: id ?? this.id,
      fromUnit: fromUnit ?? this.fromUnit,
      toUnit: toUnit ?? this.toUnit,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      productId: productId ?? this.productId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitConversionModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
