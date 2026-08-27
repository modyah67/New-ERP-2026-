class PackingRecipeModel {
  final String? id;
  final String? name;
  final String? description;
  final String grade;
  final String? rawMaterialId;
  final String? rawMaterialName;
  final double quantityPerCarton;
  final String unit;
  final String? notes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PackingRecipeModel({
    this.id,
    this.name,
    this.description,
    this.grade = 'A',
    this.rawMaterialId,
    this.rawMaterialName,
    this.quantityPerCarton = 0,
    this.unit = 'قطعة',
    this.notes,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PackingRecipeModel.fromMap(Map<String, dynamic> map) {
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    return PackingRecipeModel(
      id: map['id']?.toString(),
      name: map['name']?.toString(),
      description: map['description']?.toString(),
      grade: map['grade']?.toString() ?? 'A',
      rawMaterialId: map['raw_material_id']?.toString(),
      rawMaterialName: map['raw_material_name']?.toString(),
      quantityPerCarton: n(map['quantity_per_carton']) ?? 0,
      unit: map['unit']?.toString() ?? 'قطعة',
      notes: map['notes']?.toString(),
      isActive: map['is_active'] is bool ? map['is_active'] : (map['is_active']?.toString() == 'true'),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      'grade': grade,
      if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
      'quantity_per_carton': quantityPerCarton,
      'unit': unit,
      if (notes != null) 'notes': notes,
      'is_active': isActive,
    };
  }
}
