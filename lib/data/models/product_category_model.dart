class ProductCategoryModel {
  final dynamic id;
  final String name;
  final dynamic parentId;
  final String? parentName;
  final String? icon;
  final String? color;
  final int sortOrder;
  final bool isActive;
  final String categoryType;
  final DateTime? createdAt;

  ProductCategoryModel({
    this.id,
    required this.name,
    this.parentId,
    this.parentName,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
    this.categoryType = 'material',
    this.createdAt,
  });

  factory ProductCategoryModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    bool? boolVal(dynamic v) => v is bool ? v : (v?.toString() == 'true');
    DateTime? dtVal(dynamic v) => v != null ? DateTime.tryParse(v.toString()) : null;

    // Keep original id type (int or String/UUID)
    final rawId = map['id'];
    final parsedId = rawId is int ? rawId : (rawId is String ? rawId : intVal(rawId));

    return ProductCategoryModel(
      id: parsedId,
      name: str(map['name']) ?? '',
      parentId: map['parent_id'], // keep original type
      parentName: str(map['parent_name']),
      icon: str(map['icon']),
      color: str(map['color']),
      sortOrder: intVal(map['sort_order']) ?? 0,
      isActive: boolVal(map['is_active']) ?? true,
      categoryType: str(map['category_type']) ?? 'material',
      createdAt: dtVal(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'is_active': isActive,
      'category_type': categoryType,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  ProductCategoryModel copyWith({
    dynamic id,
    String? name,
    dynamic parentId,
    String? parentName,
    String? icon,
    String? color,
    int? sortOrder,
    bool? isActive,
    String? categoryType,
    DateTime? createdAt,
  }) {
    return ProductCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      categoryType: categoryType ?? this.categoryType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductCategoryModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
