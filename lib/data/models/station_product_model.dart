import '../../core/utils/inventory_identity.dart';

class StationProductModel {
  final int? id;
  final int stationId;
  final String productName;
  final String productCode;
  final double quantity;
  final String unit;
  final String itemType;
  final String? rawMaterialId;
  final int? fruitTypeId;
  final String createdAt;
  final String updatedAt;

  const StationProductModel({
    this.id,
    required this.stationId,
    required this.productName,
    this.productCode = '',
    required this.quantity,
    this.unit = 'kg',
    this.itemType = 'material',
    this.rawMaterialId,
    this.fruitTypeId,
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Canonical composite item key ensuring zero collision
  String get itemKey => InventoryIdentity.computeItemKey(
        itemType: itemType,
        rawMaterialId: rawMaterialId,
        fruitTypeId: fruitTypeId?.toString(),
        fallbackCode: productCode,
        fallbackName: productName,
      );

  factory StationProductModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    final rawMatId = str(map['raw_material_id']);
    final fruitId = intVal(map['fruit_type_id']);
    final pName = str(map['product_name']) ?? '';
    final pUnit = str(map['unit']) ?? 'kg';
    var detectedType = str(map['item_type']) ?? '';
    if (detectedType.isEmpty) {
      if (fruitId != null && fruitId > 0) {
        detectedType = 'fruit';
      } else if (rawMatId != null && rawMatId.isNotEmpty) {
        detectedType = 'material';
      } else if (pName.contains('(مادة تعبئة)')) {
        detectedType = 'material';
      } else if (pUnit == 'carton') {
        detectedType = 'fruit';
      } else {
        detectedType = 'material';
      }
    }

    return StationProductModel(
      id: intVal(map['id']),
      stationId: intVal(map['station_id']) ?? 0,
      productName: str(map['product_name']) ?? '',
      productCode: str(map['product_code']) ?? '',
      quantity: numVal(map['quantity'])?.toDouble() ?? 0.0,
      unit: str(map['unit']) ?? 'kg',
      itemType: detectedType,
      rawMaterialId: rawMatId,
      fruitTypeId: fruitId,
      createdAt: str(map['created_at']) ?? '',
      updatedAt: str(map['updated_at']) ?? '',
    );
  }

  Map<String, dynamic> toInsertMap() {
    final map = <String, dynamic>{
      'station_id': stationId,
      'product_name': productName,
      'product_code': productCode,
      'quantity': quantity,
      'unit': unit,
    };
    if (itemType.isNotEmpty) map['item_type'] = itemType;
    if (rawMaterialId != null) map['raw_material_id'] = rawMaterialId;
    if (fruitTypeId != null) map['fruit_type_id'] = fruitTypeId;
    return map;
  }

  StationProductModel copyWith({
    int? id,
    int? stationId,
    String? productName,
    String? productCode,
    double? quantity,
    String? unit,
    String? itemType,
    String? rawMaterialId,
    int? fruitTypeId,
    String? createdAt,
    String? updatedAt,
  }) {
    return StationProductModel(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      itemType: itemType ?? this.itemType,
      rawMaterialId: rawMaterialId ?? this.rawMaterialId,
      fruitTypeId: fruitTypeId ?? this.fruitTypeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
