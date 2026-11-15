import 'package:flutter/material.dart';

/// Dropdown field for cost item categories filtered by the active supplier type.
class CostItemCategoryDropdown extends StatelessWidget {
  final String keyPrefix;
  final String supplierType;
  final Map<int, String> filteredCategories;
  final int? selectedCategoryId;
  final InputDecoration decoration;
  final bool isDark;
  final ValueChanged<int?> onChanged;

  const CostItemCategoryDropdown({
    super.key,
    required this.keyPrefix,
    required this.supplierType,
    required this.filteredCategories,
    required this.selectedCategoryId,
    required this.decoration,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = filteredCategories.containsKey(selectedCategoryId)
        ? selectedCategoryId
        : null;

    return DropdownButtonFormField<int>(
      key: ValueKey('${keyPrefix}_${supplierType}_$safeValue'),
      initialValue: safeValue,
      menuMaxHeight: 350,
      decoration: decoration,
      hint: Text(
        filteredCategories.isEmpty
            ? 'لا توجد تصنيفات مسجلة لهذا النوع'
            : 'اختر تصنيف البند',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
      dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo',
        fontSize: 14,
      ),
      isExpanded: true,
      items: filteredCategories.entries.map((entry) {
        return DropdownMenuItem<int>(
          value: entry.key,
          child: Text(
            entry.value,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
      onChanged: filteredCategories.isEmpty ? null : onChanged,
    );
  }
}
