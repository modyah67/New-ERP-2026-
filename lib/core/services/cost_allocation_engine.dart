import 'package:flutter/foundation.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/shipment_profitability_snapshot_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_profitability_snapshot_model.dart';
import '../../data/services/currency_conversion_service.dart';

/// Centralized cost allocation engine for export shipments.
/// 
/// This is the SINGLE SOURCE OF TRUTH for all shipment cost and profit calculations.
/// All screens (Pricing Center, Shipment Cost Sheet, Profitability Dashboard, 
/// Preparation Center Invoice, Shipment Details, Commercial Invoice) must use this engine.
class CostAllocationEngine {
  final _exportDao = ExportShipmentDao();
  final _itemDao = ExportShipmentItemDao();
  final _packingOrderDao = PackingOrderDao();
  final _profitabilitySnapshotDao = ShipmentProfitabilitySnapshotDao();
  final _lotDao = LotDao();

  /// Complete cost breakdown for a shipment
  Future<ShipmentCostBreakdown> calculateShipmentCosts(int shipmentId) async {
    debugPrint('CostAllocationEngine: Calculating costs for shipment $shipmentId');
    
    final shipment = await _exportDao.getById(shipmentId);
    if (shipment == null) {
      throw Exception('Shipment $shipmentId not found');
    }

    final items = await _itemDao.getByShipmentId(shipmentId);
    final costItemsDao = ShipmentCostItemDao();
    final explicitCostItems = await costItemsDao.getForShipment(shipmentId);

    // Sum explicitly added costs by category from ShipmentCostingPage (Entered in EGP)
    double packingCostEgp = 0.0;
    double logisticsCostEgp = 0.0;
    double adminCostEgp = 0.0;
    double otherCostEgp = 0.0;

    for (final costItem in explicitCostItems) {
      final val = costItem.totalPrice;
      switch (costItem.category) {
        case 'packing':
          packingCostEgp += val;
          break;
        case 'logistics':
          logisticsCostEgp += val;
          break;
        case 'admin':
          adminCostEgp += val;
          break;
        default:
          otherCostEgp += val;
      }
    }

    final exchangeRate = shipment.exchangeRate > 0 ? shipment.exchangeRate : 1.0;
    
    // 1. Read production costs (fruit + packaging) from linked packing orders
    double fruitCost = 0.0;
    double autoProductionCost = 0.0;
    final cs = CurrencyConversionService.instance;
    try {
      final packingOrders = await _packingOrderDao.getByShipmentIdViaItems(shipmentId);
      for (final po in packingOrders) {
        // Total packing order cost per carton * cartons
        if (po.packingCostPerCarton > 0) {
          final cartons = po.cartonCount > 0 ? po.cartonCount : shipment.cartonsCount;
          autoProductionCost += po.packingCostPerCarton * cartons;
        } else if (po.totalPackingCost > 0) {
          autoProductionCost += po.totalPackingCost;
        }

        // Fruit component of the packing order
        if (po.fruitCostAllocated > 0) {
          fruitCost += po.fruitCostAllocated;
        } else if (po.fruitCostBase > 0) {
          fruitCost += po.fruitCostBase;
        } else if (po.lotId != null) {
          final lot = await _lotDao.getById(po.lotId);
          if (lot != null && lot.totalProductCost > 0 && lot.netWeightKg > 0) {
            final costPerKg = lot.totalProductCost / lot.netWeightKg;
            final lotCurrencyCost = po.totalNetWeight * costPerKg;
            fruitCost += cs.toBase(lotCurrencyCost, lot.currency, lot.exchangeRate);
          }
        }
      }
    } catch (e) {
      debugPrint('CostAllocationEngine: Error reading fruit and packing costs from lots/orders: $e');
    }

    // Production / Cartons cost: either from explicit saved items (category 'packing') or auto from packing orders
    final totalProductionCost = packingCostEgp > 0 ? packingCostEgp : autoProductionCost;
    final packingMaterialsCost = totalProductionCost >= fruitCost ? (totalProductionCost - fruitCost) : totalProductionCost;

    final logisticsCost = logisticsCostEgp;
    final adminCost = adminCostEgp > 0 ? adminCostEgp : shipment.allocatedAdminExpenses;
    final otherCost = otherCostEgp > 0 ? otherCostEgp : shipment.allocatedTaxes;

    // Total cost = Production (Fruit + Packaging) + Logistics + Admin + Other
    final totalShipmentCost = totalProductionCost + logisticsCost + adminCost + otherCost;

    // Revenue calculations
    final revenueForeign = _calculateRevenueForeign(shipment, items);
    final revenueLocal = cs.toBase(revenueForeign, shipment.currencyCode, exchangeRate);

    // Profit calculations
    final discount = (shipment.discountAmount) * (exchangeRate > 0 ? exchangeRate : 1.0);
    final grossProfit = revenueLocal - totalProductionCost;
    final netProfit = revenueLocal - totalShipmentCost - discount;

    // Margins
    final grossMargin = revenueLocal > 0 ? (grossProfit / revenueLocal * 100) : 0.0;
    final netMargin = revenueLocal > 0 ? (netProfit / revenueLocal * 100) : 0.0;

    // Cost distribution metrics
    final cartons = _getTotalCartons(shipment, items);
    final netWeight = _getTotalNetWeight(shipment, items);
    final pallets = _getTotalPallets(shipment, items);

    final costPerCarton = cartons > 0 ? totalShipmentCost / cartons : 0.0;
    final costPerKg = netWeight > 0 ? totalShipmentCost / netWeight : 0.0;
    final costPerPallet = pallets > 0 ? totalShipmentCost / pallets : 0.0;

    return ShipmentCostBreakdown(
      shipmentId: shipmentId,
      shipmentNo: shipment.shipmentNo,
      
      // Cost components
      fruitCost: fruitCost,
      packingCost: packingMaterialsCost,
      logisticsCost: logisticsCost,
      administrativeCost: adminCost,
      otherCost: otherCost,
      totalShipmentCost: totalShipmentCost,
      
      // Revenue
      revenueForeign: revenueForeign,
      revenueLocal: revenueLocal,
      
      // Profit
      grossProfit: grossProfit,
      netProfit: netProfit,
      grossMargin: grossMargin,
      netMargin: netMargin,
      
      // Cost distribution
      costPerCarton: costPerCarton,
      costPerKg: costPerKg,
      costPerPallet: costPerPallet,
      
      // Metrics
      cartons: cartons,
      netWeight: netWeight,
      pallets: pallets,
      exchangeRate: shipment.exchangeRate,
      currencyCode: shipment.currencyCode,
    );
  }


  /// Calculate foreign revenue from shipment and items
  double _calculateRevenueForeign(ExportShipmentModel shipment, List<Map<String, dynamic>> items) {
    // Prefer item-level calculation
    if (items.isNotEmpty) {
      return items.fold<double>(
        0.0,
        (sum, item) => sum + (_parseInt(item['quantity']) ?? 0) * (_parseDouble(item['export_price_per_carton']) ?? 0.0)
      );
    }
    
    // Fallback to shipment-level
    return shipment.totalRevenueForeign > 0
        ? shipment.totalRevenueForeign
        : (shipment.exportPricePerCarton * shipment.cartonsCount);
  }

  /// Get total cartons (prefer items, fallback to shipment)
  int _getTotalCartons(ExportShipmentModel shipment, List<Map<String, dynamic>> items) {
    if (items.isNotEmpty) {
      return items.fold<int>(0, (sum, item) => sum + (_parseInt(item['quantity']) ?? 0));
    }
    return shipment.cartonsCount;
  }

  /// Get total net weight (prefer items, fallback to shipment)
  double _getTotalNetWeight(ExportShipmentModel shipment, List<Map<String, dynamic>> items) {
    if (items.isNotEmpty) {
      return items.fold<double>(0.0, (sum, item) => sum + (_parseDouble(item['net_weight']) ?? 0.0));
    }
    return shipment.netWeight;
  }

  /// Get total pallets (prefer items, fallback to shipment)
  int _getTotalPallets(ExportShipmentModel shipment, List<Map<String, dynamic>> items) {
    if (items.isNotEmpty) {
      return items.fold<int>(0, (sum, item) => sum + (_parseInt(item['pallets']) ?? 0));
    }
    return shipment.palletsCount;
  }

  /// Helper: parse int
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Helper: parse double
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Create profitability snapshot for a shipment
  /// Call this when shipment status changes to 'closed'
  Future<void> createProfitabilitySnapshot(int shipmentId) async {
    debugPrint('CostAllocationEngine: Creating profitability snapshot for shipment $shipmentId');
    
    try {
      final breakdown = await calculateShipmentCosts(shipmentId);
      
      final snapshot = ShipmentProfitabilitySnapshotModel(
        shipmentId: shipmentId,
        shipmentNo: breakdown.shipmentNo,
        revenueForeign: breakdown.revenueForeign,
        revenueLocal: breakdown.revenueLocal,
        fruitCost: breakdown.fruitCost,
        packingCost: breakdown.packingCost,
        logisticsCost: breakdown.logisticsCost,
        administrativeCost: breakdown.administrativeCost,
        otherCost: breakdown.otherCost,
        totalCost: breakdown.totalShipmentCost,
        grossProfit: breakdown.grossProfit,
        netProfit: breakdown.netProfit,
        grossMargin: breakdown.grossMargin,
        netMargin: breakdown.netMargin,
        costPerCarton: breakdown.costPerCarton,
        costPerKg: breakdown.costPerKg,
        costPerPallet: breakdown.costPerPallet,
        cartons: breakdown.cartons,
        netWeight: breakdown.netWeight,
        pallets: breakdown.pallets,
        exchangeRate: breakdown.exchangeRate,
        currencyCode: breakdown.currencyCode,
      );
      
      await _profitabilitySnapshotDao.create(snapshot);
      debugPrint('CostAllocationEngine: Profitability snapshot created successfully');
    } catch (e, st) {
      debugPrint('CostAllocationEngine: Error creating profitability snapshot: $e\n$st');
      rethrow;
    }
  }

  /// Get profitability snapshot for a shipment
  /// Returns snapshot if shipment is closed, otherwise calculates live costs
  Future<ShipmentCostBreakdown> getShipmentCosts(int shipmentId) async {
    final shipment = await _exportDao.getById(shipmentId);
    if (shipment == null) {
      throw Exception('Shipment $shipmentId not found');
    }

    // If shipment is closed, use snapshot
    if (shipment.status == 'closed') {
      final snapshot = await _profitabilitySnapshotDao.getByShipmentId(shipmentId);
      if (snapshot != null) {
        debugPrint('CostAllocationEngine: Using profitability snapshot for closed shipment $shipmentId');
        return ShipmentCostBreakdown(
          shipmentId: snapshot.shipmentId,
          shipmentNo: snapshot.shipmentNo,
          fruitCost: snapshot.fruitCost,
          packingCost: snapshot.packingCost,
          logisticsCost: snapshot.logisticsCost,
          administrativeCost: snapshot.administrativeCost,
          otherCost: snapshot.otherCost,
          totalShipmentCost: snapshot.totalCost,
          revenueForeign: snapshot.revenueForeign,
          revenueLocal: snapshot.revenueLocal,
          grossProfit: snapshot.grossProfit,
          netProfit: snapshot.netProfit,
          grossMargin: snapshot.grossMargin,
          netMargin: snapshot.netMargin,
          costPerCarton: snapshot.costPerCarton,
          costPerKg: snapshot.costPerKg,
          costPerPallet: snapshot.costPerPallet,
          cartons: snapshot.cartons,
          netWeight: snapshot.netWeight,
          pallets: snapshot.pallets,
          exchangeRate: snapshot.exchangeRate,
          currencyCode: snapshot.currencyCode,
        );
      }
    }

    // Otherwise calculate live costs
    return calculateShipmentCosts(shipmentId);
  }
}

/// Data class for shipment cost breakdown
class ShipmentCostBreakdown {
  final int shipmentId;
  final String shipmentNo;
  
  // Cost components
  final double fruitCost;
  final double packingCost;
  final double logisticsCost;
  final double administrativeCost;
  final double otherCost;
  final double totalShipmentCost;
  
  // Revenue
  final double revenueForeign;
  final double revenueLocal;
  
  // Profit
  final double grossProfit;
  final double netProfit;
  final double grossMargin;
  final double netMargin;
  
  // Cost distribution
  final double costPerCarton;
  final double costPerKg;
  final double costPerPallet;
  
  // Metrics
  final int cartons;
  final double netWeight;
  final int pallets;
  final double exchangeRate;
  final String currencyCode;

  const ShipmentCostBreakdown({
    required this.shipmentId,
    required this.shipmentNo,
    required this.fruitCost,
    required this.packingCost,
    required this.logisticsCost,
    required this.administrativeCost,
    required this.otherCost,
    required this.totalShipmentCost,
    required this.revenueForeign,
    required this.revenueLocal,
    required this.grossProfit,
    required this.netProfit,
    required this.grossMargin,
    required this.netMargin,
    required this.costPerCarton,
    required this.costPerKg,
    required this.costPerPallet,
    required this.cartons,
    required this.netWeight,
    required this.pallets,
    required this.exchangeRate,
    required this.currencyCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'shipment_id': shipmentId,
      'shipment_no': shipmentNo,
      'fruit_cost': fruitCost,
      'packing_cost': packingCost,
      'logistics_cost': logisticsCost,
      'administrative_cost': administrativeCost,
      'other_cost': otherCost,
      'total_shipment_cost': totalShipmentCost,
      'revenue_foreign': revenueForeign,
      'revenue_local': revenueLocal,
      'gross_profit': grossProfit,
      'net_profit': netProfit,
      'gross_margin': grossMargin,
      'net_margin': netMargin,
      'cost_per_carton': costPerCarton,
      'cost_per_kg': costPerKg,
      'cost_per_pallet': costPerPallet,
      'cartons': cartons,
      'net_weight': netWeight,
      'pallets': pallets,
      'exchange_rate': exchangeRate,
      'currency_code': currencyCode,
    };
  }

  @override
  String toString() {
    return 'ShipmentCostBreakdown(shipmentNo: $shipmentNo, '
        'totalCost: $totalShipmentCost, revenueLocal: $revenueLocal, '
        'netProfit: $netProfit, netMargin: $netMargin%)';
  }
}
