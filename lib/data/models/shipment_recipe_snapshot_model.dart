class ShipmentRecipeSnapshotModel {
  final int? id;
  final int shipmentId;
  final String? packingRecipeId;
  final String? recipeName;
  final int? productId;
  final String? grade;
  final int recipeVersion;
  final String? materialId;
  final String? materialName;
  final String? unit;
  final double quantityPerCarton;
  final double unitCost;
  final double totalQuantity;
  final double totalCost;
  final DateTime? createdAt;

  const ShipmentRecipeSnapshotModel({
    this.id,
    required this.shipmentId,
    this.packingRecipeId,
    this.recipeName,
    this.productId,
    this.grade,
    this.recipeVersion = 1,
    this.materialId,
    this.materialName,
    this.unit,
    this.quantityPerCarton = 0,
    this.unitCost = 0,
    this.totalQuantity = 0,
    this.totalCost = 0,
    this.createdAt,
  });

  factory ShipmentRecipeSnapshotModel.fromMap(Map<String, dynamic> map) {
    return ShipmentRecipeSnapshotModel(
      id: map['id'] as int?,
      shipmentId: map['shipment_id'] as int,
      packingRecipeId: map['packing_recipe_id']?.toString(),
      recipeName: map['recipe_name'] as String?,
      productId: map['product_id'] as int?,
      grade: map['grade'] as String?,
      recipeVersion: (map['recipe_version'] as int?) ?? 1,
      materialId: map['material_id']?.toString(),
      materialName: map['material_name'] as String?,
      unit: map['unit'] as String?,
      quantityPerCarton: (map['quantity_per_carton'] as num?)?.toDouble() ?? 0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0,
      totalQuantity: (map['total_quantity'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      if (packingRecipeId != null) 'packing_recipe_id': packingRecipeId,
      if (recipeName != null) 'recipe_name': recipeName,
      if (productId != null) 'product_id': productId,
      if (grade != null) 'grade': grade,
      'recipe_version': recipeVersion,
      if (materialId != null) 'material_id': materialId,
      if (materialName != null) 'material_name': materialName,
      if (unit != null) 'unit': unit,
      'quantity_per_carton': quantityPerCarton,
      'unit_cost': unitCost,
      'total_quantity': totalQuantity,
      'total_cost': totalCost,
    };
  }
}
