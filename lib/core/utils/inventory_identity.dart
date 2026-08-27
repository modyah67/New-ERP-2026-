/// Unified Inventory Identity Helper
///
/// Enforces true item identity based on:
/// - Material: `item_type = 'material'`, `item_id = raw_material_id`
/// - Fruit: `item_type = 'fruit'`, `item_id = fruit_type_id`
///
/// `product_code` and `product_name` are NEVER used as unique identities.

enum InventoryItemType {
  material,
  fruit,
  unknown,
}

class InventoryIdentity {
  final InventoryItemType itemType;
  final String itemId;
  final String itemCode;
  final String itemName;

  const InventoryIdentity({
    required this.itemType,
    required this.itemId,
    required this.itemCode,
    required this.itemName,
  });

  /// Unique composite key: e.g. 'material_0e49ae02-d7e8-48ba-aa52-74f4b16404e6' or 'fruit_1'
  String get itemKey {
    if (itemType == InventoryItemType.material) {
      return 'material_$itemId';
    } else if (itemType == InventoryItemType.fruit) {
      return 'fruit_$itemId';
    }
    return 'unknown_${itemCode}_$itemName';
  }

  /// Helper function to generate a canonical inventory item key.
  static String computeItemKey({
    required String itemType,
    String? rawMaterialId,
    String? fruitTypeId,
    String? fallbackCode,
    String? fallbackName,
  }) {
    final type = itemType.toLowerCase().trim();
    final isFruit = type == 'fruit' ||
        type == 'fruit_type' ||
        (fruitTypeId != null && fruitTypeId.isNotEmpty && fruitTypeId != '0');

    if (isFruit) {
      if (fruitTypeId != null && fruitTypeId.isNotEmpty && fruitTypeId != '0') {
        return 'fruit_$fruitTypeId';
      }
      if (fallbackCode != null && fallbackCode.trim().isNotEmpty) {
        return 'fruit_code_${fallbackCode.trim()}';
      }
      if (fallbackName != null && fallbackName.trim().isNotEmpty) {
        return 'fruit_name_${fallbackName.trim().toLowerCase()}';
      }
      return 'fruit_unknown';
    }

    // Material / Non-fruit
    if (rawMaterialId != null && rawMaterialId.isNotEmpty) {
      return 'material_$rawMaterialId';
    }
    if (fallbackCode != null && fallbackCode.trim().isNotEmpty) {
      return 'material_code_${fallbackCode.trim()}';
    }
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return 'material_name_${fallbackName.trim().toLowerCase()}';
    }
    return 'material_unknown';
  }
}
