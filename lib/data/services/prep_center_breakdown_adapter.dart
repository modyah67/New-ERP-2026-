import '../dao/shipment_cost_breakdown_dao.dart';

class PrepCenterBreakdownItem {
  final String description;
  final String categoryLabel;
  final String costCategory;
  final double quantity;
  final String unitLabel;
  final double unitCost;
  final double totalCost;
  final String? supplier;
  final String? notes;

  const PrepCenterBreakdownItem({
    required this.description,
    required this.categoryLabel,
    this.costCategory = '',
    required this.quantity,
    required this.unitLabel,
    required this.unitCost,
    required this.totalCost,
    this.supplier,
    this.notes,
  });
}

class PrepCenterBreakdownResult {
  final double totalSupplierAmount;
  final double totalPackingCost;
  final double totalLogisticsCost;
  final double totalAdminCost;
  final double grandTotalCost;
  final List<PrepCenterBreakdownItem> supplierItems;
  final List<PrepCenterBreakdownItem> packingItems;
  final List<PrepCenterBreakdownItem> logisticsItems;
  final List<PrepCenterBreakdownItem> adminItems;
  final bool hasData;

  const PrepCenterBreakdownResult({
    this.totalSupplierAmount = 0,
    this.totalPackingCost = 0,
    this.totalLogisticsCost = 0,
    this.totalAdminCost = 0,
    this.grandTotalCost = 0,
    this.supplierItems = const [],
    this.packingItems = const [],
    this.logisticsItems = const [],
    this.adminItems = const [],
    this.hasData = false,
  });

  List<PrepCenterBreakdownItem> get allItems =>
      [...supplierItems, ...packingItems, ...logisticsItems, ...adminItems];

  double get totalOtherCost => totalLogisticsCost + totalAdminCost;
  double get totalCostItems => totalPackingCost + totalOtherCost;
}

class PrepCenterBreakdownAdapter {
  final _dao = ShipmentCostBreakdownDao();

  PrepCenterBreakdownResult empty() => const PrepCenterBreakdownResult();

  Future<PrepCenterBreakdownResult> getForShipment(String shipmentId) async {
    final rows = await _dao.getForShipment(shipmentId);
    if (rows.isEmpty) return empty();

    final supplierItems = <PrepCenterBreakdownItem>[];
    final packingItems = <PrepCenterBreakdownItem>[];
    final logisticsItems = <PrepCenterBreakdownItem>[];
    final adminItems = <PrepCenterBreakdownItem>[];

    for (final row in rows) {
      final item = PrepCenterBreakdownItem(
        description: row.itemName,
        categoryLabel: row.costTypeLabel,
        costCategory: row.costCategory ?? '',
        quantity: row.quantity,
        unitLabel: _unitForType(row.costType),
        unitCost: row.unitCost,
        totalCost: row.totalCost,
        supplier: row.supplier,
        notes: row.notes,
      );

      switch (row.costType) {
        case 'fruit':
          supplierItems.add(item);
        case 'packing_material':
          packingItems.add(item);
        case 'logistics':
          logisticsItems.add(item);
        default:
          adminItems.add(item);
      }
    }

    final totalSupplier =
        supplierItems.fold(0.0, (s, i) => s + i.totalCost);
    final totalPacking =
        packingItems.fold(0.0, (s, i) => s + i.totalCost);
    final totalLogistics =
        logisticsItems.fold(0.0, (s, i) => s + i.totalCost);
    final totalAdmin =
        adminItems.fold(0.0, (s, i) => s + i.totalCost);

    return PrepCenterBreakdownResult(
      totalSupplierAmount: totalSupplier,
      totalPackingCost: totalPacking,
      totalLogisticsCost: totalLogistics,
      totalAdminCost: totalAdmin,
      grandTotalCost: totalSupplier + totalPacking + totalLogistics + totalAdmin,
      supplierItems: supplierItems,
      packingItems: packingItems,
      logisticsItems: logisticsItems,
      adminItems: adminItems,
      hasData: true,
    );
  }

  String _unitForType(String costType) {
    switch (costType) {
      case 'fruit':
        return 'كجم';
      case 'packing_material':
        return 'وحدة';
      default:
        return '';
    }
  }
}
