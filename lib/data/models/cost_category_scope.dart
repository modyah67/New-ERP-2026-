import 'package:flutter/material.dart';

/// Enterprise application scope for cost categories in "Fruity Farms".
/// The General Add/Edit Cost Category management screen is dedicated exclusively
/// to General & Administrative Expenses (المصروفات العمومية والإدارية),
/// while specialized operational/packaging rules are governed by their respective modules.
enum CostCategoryScope {
  generalAdmin(
    code: 'general_admin',
    labelAr: 'المصروفات العمومية والإدارية',
    labelEn: 'General & Administrative Expenses',
    parentAccountCode: '321',
    defaultCostCenterCode: 'CC-ADMIN',
    icon: Icons.business_center_rounded,
    color: Color(0xFF06B6D4), // Cyan
  ),
  packing(
    code: 'packing',
    labelAr: 'تكاليف تشغيل ومحطة تعبئة',
    labelEn: 'Packing Station Operations',
    parentAccountCode: '312',
    defaultCostCenterCode: 'packing_station',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF10B981), // Emerald
  ),
  shipment(
    code: 'shipment',
    labelAr: 'بنود شحن وتصدير ولوجستيات',
    labelEn: 'Freight & Logistics',
    parentAccountCode: '322',
    defaultCostCenterCode: 'freight_logistics',
    icon: Icons.local_shipping_rounded,
    color: Color(0xFF3B82F6), // Blue
  ),
  packingWaste(
    code: 'packing_waste',
    labelAr: 'هالك وفاقد التعبئة',
    labelEn: 'Packing Waste',
    parentAccountCode: '313',
    defaultCostCenterCode: 'packing_station',
    icon: Icons.delete_outline_rounded,
    color: Color(0xFFEC4899), // Pink
  ),
  all(
    code: 'all',
    labelAr: 'شامل لكل العمليات',
    labelEn: 'All Operations',
    parentAccountCode: '321',
    defaultCostCenterCode: 'CC-ADMIN',
    icon: Icons.all_inclusive_rounded,
    color: Color(0xFFF59E0B), // Amber
  );

  final String code;
  final String labelAr;
  final String labelEn;
  final String parentAccountCode;
  final String defaultCostCenterCode;
  final IconData icon;
  final Color color;

  const CostCategoryScope({
    required this.code,
    required this.labelAr,
    required this.labelEn,
    required this.parentAccountCode,
    required this.defaultCostCenterCode,
    required this.icon,
    required this.color,
  });

  /// Scopes exclusively featured in the general Add Cost Category screen.
  /// Dedicated exclusively to General & Administrative Expenses.
  static List<CostCategoryScope> get generalExpenseCreationScopes => const [
    CostCategoryScope.generalAdmin,
  ];

  /// Resolves an enum instance from raw database scope string
  static CostCategoryScope fromCode(String? rawCode) {
    if (rawCode == null || rawCode.trim().isEmpty) {
      return CostCategoryScope.generalAdmin;
    }
    final clean = rawCode.trim().toLowerCase();
    switch (clean) {
      case 'general_admin':
      case 'admin':
        return CostCategoryScope.generalAdmin;
      case 'packing':
        return CostCategoryScope.packing;
      case 'shipment':
        return CostCategoryScope.shipment;
      case 'packing_waste':
        return CostCategoryScope.packingWaste;
      case 'all':
      case 'both':
        return CostCategoryScope.all;
      default:
        return CostCategoryScope.generalAdmin;
    }
  }
}
