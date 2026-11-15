import 'fruit_type_model.dart';

/// Represents a unified visual and analytical grouping of fruit items.
/// When an item is created in "Shared" mode, two underlying database records
/// ([Item Name] - وزن and [Item Name] - كراتين) are merged into this single group.
class FruitTypeGroupModel {
  final String baseName;
  FruitTypeModel? weightItem;
  FruitTypeModel? cartonItem;
  final List<FruitTypeModel> otherItems;

  FruitTypeGroupModel({
    required this.baseName,
    this.weightItem,
    this.cartonItem,
    List<FruitTypeModel>? otherItems,
  }) : otherItems = otherItems ?? [];

  bool get isDualMode => weightItem != null && cartonItem != null;
  bool get hasWeight => weightItem != null;
  bool get hasCarton => cartonItem != null;

  FruitTypeModel get primaryItem {
    if (weightItem != null) return weightItem!;
    if (cartonItem != null) return cartonItem!;
    if (otherItems.isNotEmpty) return otherItems.first;
    return FruitTypeModel(code: '', name: baseName);
  }

  String get currency => primaryItem.currency;
  String get icon => primaryItem.icon;
  String? get color => primaryItem.color;

  /// Returns all underlying records belonging to this group.
  List<FruitTypeModel> get allItems {
    final list = <FruitTypeModel>[];
    if (weightItem != null) list.add(weightItem!);
    if (cartonItem != null) list.add(cartonItem!);
    list.addAll(otherItems);
    return list;
  }

  /// Calculates total stock value across both modes.
  double get combinedStockValue {
    double total = 0.0;
    if (weightItem != null) {
      final wVal = weightItem!.totalStockValue;
      if (wVal != null && wVal > 0) {
        total += wVal;
      } else {
        final qty = weightItem!.totalStockQuantity ?? weightItem!.totalQuantity ?? 0.0;
        final price = weightItem!.averagePurchasePrice ?? weightItem!.latestPurchasePrice ?? 0.0;
        total += (qty * price);
      }
    }
    if (cartonItem != null) {
      final cVal = cartonItem!.totalStockValue;
      if (cVal != null && cVal > 0) {
        total += cVal;
      } else {
        final qty = cartonItem!.totalStockQuantity ?? cartonItem!.totalQuantity ?? 0.0;
        final price = cartonItem!.averagePurchasePrice ?? cartonItem!.latestPurchasePrice ?? 0.0;
        total += (qty * price);
      }
    }
    for (final o in otherItems) {
      total += o.totalStockValue ?? 0.0;
    }
    return total;
  }

  /// Utility to strip suffixes like ' - وزن', ' - كراتين', ' (وزن)', etc.
  static String extractBaseName(String fullName) {
    String s = fullName.trim();
    // Strip trailing suffixes
    s = s.replaceAll(RegExp(r'\s*[-–]\s*وزن$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\(\s*وزن\s*\)$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*[-–]\s*كراتين$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\(\s*كراتين\s*\)$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*[-–]\s*كرتونة$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\(\s*كرتونة\s*\)$', caseSensitive: false), '');
    return s.trim();
  }

  /// Groups a list of [FruitTypeModel] rows into unified [FruitTypeGroupModel] instances.
  static List<FruitTypeGroupModel> groupFromItems(List<FruitTypeModel> items) {
    final Map<String, FruitTypeGroupModel> groups = {};

    for (final item in items) {
      final base = extractBaseName(item.name);
      final key = base.toLowerCase();

      final group = groups.putIfAbsent(
        key,
        () => FruitTypeGroupModel(baseName: base),
      );

      final mode = item.purchaseMode ?? item.latestPurchaseMode ?? '';
      final isCartonByName = item.name.contains('كراتين') || item.name.contains('كرتونة');
      final isWeightByName = item.name.contains('وزن');

      if (mode == 'carton' || isCartonByName) {
        if (group.cartonItem == null) {
          group.cartonItem = item;
        } else {
          group.otherItems.add(item);
        }
      } else if (mode == 'weight' || isWeightByName) {
        if (group.weightItem == null) {
          group.weightItem = item;
        } else {
          group.otherItems.add(item);
        }
      } else {
        // Unspecified mode: assign to whichever slot is free
        if (group.weightItem == null) {
          group.weightItem = item;
        } else if (group.cartonItem == null) {
          group.cartonItem = item;
        } else {
          group.otherItems.add(item);
        }
      }
    }

    return groups.values.toList();
  }
}
