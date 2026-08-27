import 'package:flutter/foundation.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/shipment_cost_breakdown_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/models/export_shipment_model.dart';
import 'cost_allocation_engine.dart';

/// Service for calculating shipment profitability metrics.
/// 
/// This is the SINGLE SOURCE OF TRUTH for all shipment profitability calculations.
/// All screens and PDFs must consume ONLY this service for:
/// - Revenue EUR
/// - Revenue EGP
/// - Fruit Cost
/// - Packing Cost
/// - Logistics Cost
/// - Administrative Cost
/// - Other Cost
/// - Total Cost
/// - Net Profit
/// - Net Margin
/// - Cost Per Carton
/// - Profit Per Carton
/// - Cost Per Kg
/// - Profit Per Kg
/// - Cost Per Pallet
/// - Profit Per Pallet
class ShipmentProfitabilityService {
  final _costEngine = CostAllocationEngine();
  final _exportDao = ExportShipmentDao();
  final _itemDao = ExportShipmentItemDao();
  final _breakdownDao = ShipmentCostBreakdownDao();
  final _packingOrderDao = PackingOrderDao();

  /// Calculate complete profitability for a shipment.
  /// 
  /// This method:
  /// 1. Loads shipment
  /// 2. Loads commercial invoice (via items)
  /// 3. Loads exchange rate (from shipment)
  /// 4. Loads lot allocations (via cost engine)
  /// 5. Loads packing allocations (via cost engine)
  /// 6. Loads shipment_cost_breakdown
  /// 
  /// Returns [ShipmentProfitabilityResult] with all metrics.
  /// 
  /// Throws [Exception] if shipment not found.
  Future<ShipmentProfitabilityResult> calculateShipment(String shipmentId) async {
    debugPrint('ShipmentProfitabilityService: Calculating profitability for shipment $shipmentId');
    
    // Load shipment
    final shipment = await _exportDao.getById(shipmentId);
    if (shipment == null) {
      throw Exception('Shipment $shipmentId not found');
    }

    // Load items (commercial invoice data)
    final items = await _itemDao.getByShipmentId(shipmentId);

    // Load cost breakdown
    final breakdown = await _breakdownDao.getForShipment(shipmentId);

    // Load packing orders
    final packingOrders = await _packingOrderDao.getByShipmentIdViaItems(int.parse(shipmentId));

    // Use CostAllocationEngine for core calculations
    final costBreakdown = await _costEngine.calculateShipmentCosts(int.parse(shipmentId));

    // Validate data
    final warnings = <String>[];
    
    if (costBreakdown.fruitCost == 0) {
      warnings.add('⚠️ Fruit cost is missing or zero. Profitability may be inaccurate.');
    }
    
    if (costBreakdown.packingCost == 0) {
      warnings.add('⚠️ Packing cost is missing or zero. Profitability may be inaccurate.');
    }
    
    if (costBreakdown.revenueLocal == 0) {
      warnings.add('⚠️ Revenue is missing or zero. Profitability cannot be calculated.');
    }

    if (breakdown.isEmpty) {
      warnings.add('⚠️ Cost breakdown is missing. Profitability may be incomplete.');
    }

    // Check revenue mismatch between calculated and stored shipment value
    if ((costBreakdown.revenueLocal - shipment.totalRevenueEgp).abs() > 1.0) {
      warnings.add('⚠️ Revenue mismatch detected between calculated and expected values.');
    }

    // Calculate additional metrics
    final profitPerCarton = costBreakdown.cartons > 0 
        ? costBreakdown.netProfit / costBreakdown.cartons 
        : 0.0;
    
    final profitPerKg = costBreakdown.netWeight > 0 
        ? costBreakdown.netProfit / costBreakdown.netWeight 
        : 0.0;
    
    final profitPerPallet = costBreakdown.pallets > 0 
        ? costBreakdown.netProfit / costBreakdown.pallets 
        : 0.0;

    debugPrint('ShipmentProfitabilityService: Calculation complete for shipment $shipmentId');
    debugPrint('  Revenue EUR: ${costBreakdown.revenueForeign.toStringAsFixed(2)}');
    debugPrint('  Revenue EGP: ${costBreakdown.revenueLocal.toStringAsFixed(2)}');
    debugPrint('  Fruit Cost: ${costBreakdown.fruitCost.toStringAsFixed(2)}');
    debugPrint('  Packing Cost: ${costBreakdown.packingCost.toStringAsFixed(2)}');
    debugPrint('  Logistics Cost: ${costBreakdown.logisticsCost.toStringAsFixed(2)}');
    debugPrint('  Administrative Cost: ${costBreakdown.administrativeCost.toStringAsFixed(2)}');
    debugPrint('  Other Cost: ${costBreakdown.otherCost.toStringAsFixed(2)}');
    debugPrint('  Total Cost: ${costBreakdown.totalShipmentCost.toStringAsFixed(2)}');
    debugPrint('  Net Profit: ${costBreakdown.netProfit.toStringAsFixed(2)}');
    debugPrint('  Net Margin: ${costBreakdown.netMargin.toStringAsFixed(2)}%');
    debugPrint('  Cost Per Carton: ${costBreakdown.costPerCarton.toStringAsFixed(2)}');
    debugPrint('  Profit Per Carton: ${profitPerCarton.toStringAsFixed(2)}');
    debugPrint('  Cost Per Kg: ${costBreakdown.costPerKg.toStringAsFixed(2)}');
    debugPrint('  Profit Per Kg: ${profitPerKg.toStringAsFixed(2)}');
    debugPrint('  Cost Per Pallet: ${costBreakdown.costPerPallet.toStringAsFixed(2)}');
    debugPrint('  Profit Per Pallet: ${profitPerPallet.toStringAsFixed(2)}');

    return ShipmentProfitabilityResult(
      shipmentId: int.parse(shipmentId),
      shipmentNo: shipment.shipmentNo,
      
      // Revenue
      revenueEur: costBreakdown.revenueForeign,
      revenueEgp: costBreakdown.revenueLocal,
      
      // Costs
      fruitCost: costBreakdown.fruitCost,
      packingCost: costBreakdown.packingCost,
      logisticsCost: costBreakdown.logisticsCost,
      administrativeCost: costBreakdown.administrativeCost,
      otherCost: costBreakdown.otherCost,
      totalCost: costBreakdown.totalShipmentCost,
      
      // Profit
      netProfit: costBreakdown.netProfit,
      netMargin: costBreakdown.netMargin,
      
      // Per-unit metrics
      costPerCarton: costBreakdown.costPerCarton,
      profitPerCarton: profitPerCarton,
      costPerKg: costBreakdown.costPerKg,
      profitPerKg: profitPerKg,
      costPerPallet: costBreakdown.costPerPallet,
      profitPerPallet: profitPerPallet,
      
      // Additional metrics
      grossProfit: costBreakdown.grossProfit,
      grossMargin: costBreakdown.grossMargin,
      
      // Metrics
      cartons: costBreakdown.cartons,
      netWeight: costBreakdown.netWeight,
      pallets: costBreakdown.pallets,
      exchangeRate: costBreakdown.exchangeRate,
      currencyCode: costBreakdown.currencyCode,
      
      // Validation
      warnings: warnings,
      
      // Raw data for reference
      shipment: shipment,
      items: items,
      breakdown: breakdown,
      packingOrders: packingOrders,
    );
  }
}

/// Result of shipment profitability calculation.
class ShipmentProfitabilityResult {
  final int shipmentId;
  final String shipmentNo;

  // Revenue
  final double revenueEur;
  final double revenueEgp;

  // Costs
  final double fruitCost;
  final double packingCost;
  final double logisticsCost;
  final double administrativeCost;
  final double otherCost;
  final double totalCost;

  // Profit
  final double netProfit;
  final double netMargin;

  // Per-unit metrics
  final double costPerCarton;
  final double profitPerCarton;
  final double costPerKg;
  final double profitPerKg;
  final double costPerPallet;
  final double profitPerPallet;

  // Additional metrics
  final double grossProfit;
  final double grossMargin;

  // Metrics
  final int cartons;
  final double netWeight;
  final int pallets;
  final double exchangeRate;
  final String currencyCode;

  // Validation
  final List<String> warnings;

  // Raw data for reference
  final ExportShipmentModel shipment;
  final List<Map<String, dynamic>> items;
  final List<dynamic> breakdown;
  final List<dynamic> packingOrders;

  const ShipmentProfitabilityResult({
    required this.shipmentId,
    required this.shipmentNo,
    required this.revenueEur,
    required this.revenueEgp,
    required this.fruitCost,
    required this.packingCost,
    required this.logisticsCost,
    required this.administrativeCost,
    required this.otherCost,
    required this.totalCost,
    required this.netProfit,
    required this.netMargin,
    required this.costPerCarton,
    required this.profitPerCarton,
    required this.costPerKg,
    required this.profitPerKg,
    required this.costPerPallet,
    required this.profitPerPallet,
    required this.grossProfit,
    required this.grossMargin,
    required this.cartons,
    required this.netWeight,
    required this.pallets,
    required this.exchangeRate,
    required this.currencyCode,
    required this.warnings,
    required this.shipment,
    required this.items,
    required this.breakdown,
    required this.packingOrders,
  });

  /// Whether the result has any warnings.
  bool get hasWarnings => warnings.isNotEmpty;

  /// Whether revenue is missing.
  bool get revenueMissing => revenueEgp == 0;

  /// Whether fruit cost is missing.
  bool get fruitCostMissing => fruitCost == 0;

  /// Whether packing cost is missing.
  bool get packingCostMissing => packingCost == 0;

  /// Whether breakdown rows are empty.
  bool get breakdownMissing => breakdown.isEmpty;

  /// Whether revenue from items differs from shipment stored revenue.
  bool get revenueMismatch => (revenueEgp - shipment.totalRevenueEgp).abs() > 1.0;

  /// Revenue per carton.
  double get revenuePerCarton => cartons > 0 ? revenueEgp / cartons : 0.0;

  /// Revenue per kg.
  double get revenuePerKg => netWeight > 0 ? revenueEgp / netWeight : 0.0;
}
