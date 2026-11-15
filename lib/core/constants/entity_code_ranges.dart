/// Architectural definition and metadata for scalable 5-digit ERP entity code ranges.
/// Guarantees strict segregation, zero collisions, and massive capacity.
class EntityCategoryRange {
  final String categoryKey;
  final String label;
  final int minCode;
  final int maxCode;
  final int capacity;
  final String hint;

  const EntityCategoryRange({
    required this.categoryKey,
    required this.label,
    required this.minCode,
    required this.maxCode,
    required this.capacity,
    required this.hint,
  });

  /// Check if an integer code is within the designated range
  bool contains(int code) => code >= minCode && code <= maxCode;

  /// Check if two ranges overlap
  bool overlapsWith(EntityCategoryRange other) =>
      minCode <= other.maxCode && maxCode >= other.minCode;

  /// Strict validation for form controllers and viewmodels
  String? validate(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'كود $label مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final numVal = int.tryParse(cleanCode);
    if (numVal == null) {
      return 'يجب أن يحتوي كود $label على أرقام فقط';
    }
    if (!contains(numVal)) {
      return 'كود $label يجب أن يكون بين $minCode و $maxCode (السعة: $capacity سجل)';
    }
    return null;
  }

  String formatHint() => 'مثال: $minCode (نطاق $minCode - $maxCode)';
}

/// Central catalog of all scalable 5-digit entity code ranges
class AppEntityCodeRanges {
  AppEntityCodeRanges._();

  // 1. العملاء (Customers): Range 12000 to 19999 (Capacity: 8,000 records)
  static const customerRange = EntityCategoryRange(
    categoryKey: 'customer',
    label: 'العملاء',
    minCode: 12000,
    maxCode: 19999,
    capacity: 8000,
    hint: 'مثال: 12000 (نطاق 12000 - 19999)',
  );

  // 2. المخلصين البحريين (Maritime Customs Clearance): Range 20000 to 24999 (Capacity: 5,000 records)
  static const maritimeClearingRange = EntityCategoryRange(
    categoryKey: 'maritime_clearing',
    label: 'المخلصين الجمركيين (بحري)',
    minCode: 20000,
    maxCode: 24999,
    capacity: 5000,
    hint: 'مثال: 20000 (نطاق 20000 - 24999)',
  );

  // 3. المخلصين الجويين (Air Customs Clearance): Range 25000 to 29999 (Capacity: 5,000 records)
  static const airClearingRange = EntityCategoryRange(
    categoryKey: 'air_clearing',
    label: 'المخلصين الجمركيين (جوي)',
    minCode: 25000,
    maxCode: 29999,
    capacity: 5000,
    hint: 'مثال: 25000 (نطاق 25000 - 29999)',
  );

  // 4. المساهمين (Shareholders): Range 30000 to 39999 (Capacity: 10,000 records)
  static const shareholderRange = EntityCategoryRange(
    categoryKey: 'shareholder',
    label: 'المساهمين',
    minCode: 30000,
    maxCode: 39999,
    capacity: 10000,
    hint: 'مثال: 30000 (نطاق 30000 - 39999)',
  );

  // 5. موردين التخصيمات (Deductions Suppliers): Range 40000 to 49999 (Capacity: 10,000 records)
  static const deductionsSupplierRange = EntityCategoryRange(
    categoryKey: 'deduction',
    label: 'موردين التخصيمات',
    minCode: 40000,
    maxCode: 49999,
    capacity: 10000,
    hint: 'مثال: 40000 (نطاق 40000 - 49999)',
  );

  // 6. موردين المحاصيل (Crop Suppliers): Range 50000 to 59999 (Capacity: 10,000 records)
  static const cropSupplierRange = EntityCategoryRange(
    categoryKey: 'crop',
    label: 'موردين المحاصيل',
    minCode: 50000,
    maxCode: 59999,
    capacity: 10000,
    hint: 'مثال: 50000 (نطاق 50000 - 59999)',
  );

  // 7. موردين النقل (Transport Suppliers): Range 60000 to 69999 (Capacity: 10,000 records)
  static const transportSupplierRange = EntityCategoryRange(
    categoryKey: 'transport',
    label: 'موردين النقل',
    minCode: 60000,
    maxCode: 69999,
    capacity: 10000,
    hint: 'مثال: 60000 (نطاق 60000 - 69999)',
  );

  // 8. موردين مواد التعبئة والتغليف (Packaging Suppliers): Range 70000 to 74999 (Capacity: 5,000 records)
  static const packagingSupplierRange = EntityCategoryRange(
    categoryKey: 'packaging',
    label: 'موردين مواد التعبئة والتغليف',
    minCode: 70000,
    maxCode: 74999,
    capacity: 5000,
    hint: 'مثال: 70000 (نطاق 70000 - 74999)',
  );

  // 9. الموردين المشتركين (Shared Suppliers - Crops & Packaging): Range 75000 to 79999 (Capacity: 5,000 records)
  static const sharedSupplierRange = EntityCategoryRange(
    categoryKey: 'shared',
    label: 'الموردين المشتركين (محاصيل وتعبئة)',
    minCode: 75000,
    maxCode: 79999,
    capacity: 5000,
    hint: 'مثال: 75000 (نطاق 75000 - 79999)',
  );

  // 10. المخازن الفرعية / محطات التعبئة (Sub-warehouses / Stations): Range 80000 to 84999 (Capacity: 5,000 records)
  static const warehouseStationRange = EntityCategoryRange(
    categoryKey: 'sub_warehouse',
    label: 'المخازن الفرعية (المحطات)',
    minCode: 80000,
    maxCode: 84999,
    capacity: 5000,
    hint: 'مثال: 80000 (نطاق 80000 - 84999)',
  );

  // 11. موردين المحطات (Station Suppliers): Range 85000 to 89999 (Capacity: 5,000 records)
  static const stationRange = EntityCategoryRange(
    categoryKey: 'station',
    label: 'موردين المحطات',
    minCode: 85000,
    maxCode: 89999,
    capacity: 5000,
    hint: 'مثال: 85000 (نطاق 85000 - 89999)',
  );

  // 11. شركات الشحن (Shipping Companies): Range 90000 to 99999 (Capacity: 10,000 records)
  static const shippingCompanyRange = EntityCategoryRange(
    categoryKey: 'shipping',
    label: 'شركات الشحن',
    minCode: 90000,
    maxCode: 99999,
    capacity: 10000,
    hint: 'مثال: 90000 (نطاق 90000 - 99999)',
  );

  /// All category ranges for iteration and collision verification
  static const List<EntityCategoryRange> allRanges = [
    customerRange,
    maritimeClearingRange,
    airClearingRange,
    shareholderRange,
    deductionsSupplierRange,
    cropSupplierRange,
    transportSupplierRange,
    packagingSupplierRange,
    sharedSupplierRange,
    warehouseStationRange,
    stationRange,
    shippingCompanyRange,
  ];

  /// Find which category range contains a given numeric code
  static EntityCategoryRange? findRangeForCode(int code) {
    for (final range in allRanges) {
      if (range.contains(code)) return range;
    }
    return null;
  }
}
