import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/shipment_profitability_snapshot_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/packing_order_model.dart';
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
    
    // 1. Real-time cost mapping from linked packing orders & lines
    double fruitCost = 0.0;
    double autoProductionCost = 0.0;
    double liveProductionCost = 0.0;
    bool hasLiveProductionCost = false;
    final cs = CurrencyConversionService.instance;
    try {
      final packingOrders = await _packingOrderDao.getByShipmentIdViaItems(shipmentId);
      final poMap = <int, PackingOrderModel>{};
      for (final po in packingOrders) {
        final pid = int.tryParse(po.id ?? '');
        if (pid != null) poMap[pid] = po;
      }

      // Collect line IDs if any
      final lineIds = items
          .map((i) => _parseInt(i['packing_order_line_id']))
          .where((id) => id != null)
          .cast<int>()
          .toList();

      final Map<int, Map<String, dynamic>> linesMap = {};
      if (lineIds.isNotEmpty) {
        try {
          final linesData = await Supabase.instance.client
              .from('packing_order_lines')
              .select('id, final_unit_cost, final_cost, carton_count')
              .inFilter('id', lineIds);
          for (final l in linesData) {
            linesMap[l['id'] as int] = Map<String, dynamic>.from(l as Map);
          }
        } catch (e) {
          debugPrint('CostAllocationEngine: Error reading packing_order_lines: $e');
        }
      }

      // Item-level real-time cost mapping
      for (final item in items) {
        final itemQty = (_parseInt(item['quantity']) ?? 0).toDouble();
        final poId = _parseInt(item['packing_order_id']);
        final lineId = _parseInt(item['packing_order_line_id']);

        double liveUnitCost = 0.0;
        PackingOrderModel? po = poId != null ? poMap[poId] : null;

        // Check line final unit cost first
        if (lineId != null && linesMap.containsKey(lineId)) {
          final l = linesMap[lineId]!;
          final uCost = (l['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
          if (uCost > 0) {
            liveUnitCost = uCost;
          } else {
            final fCost = (l['final_cost'] as num?)?.toDouble() ?? 0.0;
            final fCtns = (l['carton_count'] as num?)?.toInt() ?? 0;
            if (fCost > 0 && fCtns > 0) {
              liveUnitCost = fCost / fCtns;
            }
          }
        }

        // Fallback to packing order's authoritative packing_cost_per_carton
        if (liveUnitCost <= 0 && po != null && po.packingCostPerCarton > 0) {
          liveUnitCost = po.packingCostPerCarton;
        }

        // If not mapped by ID but exactly one PO is linked to the shipment
        if (liveUnitCost <= 0 && packingOrders.length == 1 && packingOrders.first.packingCostPerCarton > 0) {
          po = packingOrders.first;
          liveUnitCost = po.packingCostPerCarton;
        }

        if (liveUnitCost > 0 && itemQty > 0) {
          hasLiveProductionCost = true;
          // In-memory update: ensure downstream UI components and tables get the live cost
          item['price'] = liveUnitCost;
          item['amount'] = liveUnitCost * itemQty;
          liveProductionCost += liveUnitCost * itemQty;

          // Proportional fruit cost
          if (po != null) {
            final totalPoCartons = po.cartonCount > 0 ? po.cartonCount : itemQty.toInt();
            final poFruitCost = po.fruitCostAllocated > 0 ? po.fruitCostAllocated : po.fruitCostBase;
            if (poFruitCost > 0 && totalPoCartons > 0) {
              fruitCost += (poFruitCost / totalPoCartons) * itemQty;
            } else if (po.lotId.isNotEmpty) {
              try {
                final lot = await _lotDao.getById(po.lotId);
                if (lot != null && lot.totalProductCost > 0 && lot.netWeightKg > 0) {
                  final costPerKg = lot.totalProductCost / lot.netWeightKg;
                  final itemNetWeight = (_parseDouble(item['net_weight']) ?? 0.0);
                  final lotCurrencyCost = itemNetWeight * costPerKg;
                  fruitCost += cs.toBase(lotCurrencyCost, lot.currency, lot.exchangeRate);
                }
              } catch (_) {}
            }
          }
        }
      }

      // If items didn't have poId links directly, but POs exist for the shipment
      if (!hasLiveProductionCost && packingOrders.isNotEmpty) {
        double totalPoCost = 0.0;
        int totalPoCartons = 0;
        for (final po in packingOrders) {
          if (po.packingCostPerCarton > 0) {
            final cartons = po.cartonCount > 0 ? po.cartonCount : shipment.cartonsCount;
            totalPoCost += po.packingCostPerCarton * cartons;
            totalPoCartons += cartons;
          } else if (po.totalPackingCost > 0) {
            totalPoCost += po.totalPackingCost;
            totalPoCartons += po.cartonCount > 0 ? po.cartonCount : shipment.cartonsCount;
          }
        }
        final avgCost = totalPoCartons > 0 ? totalPoCost / totalPoCartons : packingOrders.first.packingCostPerCarton;
        if (avgCost > 0) {
          hasLiveProductionCost = true;
          final totalCartons = _getTotalCartons(shipment, items);
          liveProductionCost = avgCost * totalCartons;
          for (final item in items) {
            item['price'] = avgCost;
            final q = (_parseInt(item['quantity']) ?? 0).toDouble();
            item['amount'] = avgCost * q;
          }
        }
      }

      // Fallback calculation from packing orders if not already computed
      if (!hasLiveProductionCost) {
        for (final po in packingOrders) {
          if (po.packingCostPerCarton > 0) {
            final cartons = po.cartonCount > 0 ? po.cartonCount : shipment.cartonsCount;
            autoProductionCost += po.packingCostPerCarton * cartons;
          } else if (po.totalPackingCost > 0) {
            autoProductionCost += po.totalPackingCost;
          }

          if (po.fruitCostAllocated > 0) {
            fruitCost += po.fruitCostAllocated;
          } else if (po.fruitCostBase > 0) {
            fruitCost += po.fruitCostBase;
          } else if (po.lotId.isNotEmpty) {
            final lot = await _lotDao.getById(po.lotId);
            if (lot != null && lot.totalProductCost > 0 && lot.netWeightKg > 0) {
              final costPerKg = lot.totalProductCost / lot.netWeightKg;
              final lotCurrencyCost = po.totalNetWeight * costPerKg;
              fruitCost += cs.toBase(lotCurrencyCost, lot.currency, lot.exchangeRate);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CostAllocationEngine: Error reading fruit and packing costs from lots/orders: $e');
    }

    // Authoritative production cost:
    // If real-time live cost from packing orders is available, it ALWAYS takes precedence over old static packing costs!
    final totalProductionCost = hasLiveProductionCost
        ? liveProductionCost
        : (packingCostEgp > 0 ? packingCostEgp : autoProductionCost);
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
    if (hasLiveProductionCost) {
      _asyncSyncLiveCosts(
        shipmentId: shipmentId,
        items: items,
        liveProductionCost: liveProductionCost,
        totalShipmentCost: totalShipmentCost,
        costPerCarton: costPerCarton,
        totalFruitCost: fruitCost,
        totalPackingMaterialCost: packingMaterialsCost,
        grossProfit: grossProfit,
        netProfit: netProfit,
      );
    }

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

  void _asyncSyncLiveCosts({
    required int shipmentId,
    required List<Map<String, dynamic>> items,
    required double liveProductionCost,
    required double totalShipmentCost,
    required double costPerCarton,
    required double totalFruitCost,
    required double totalPackingMaterialCost,
    required double grossProfit,
    required double netProfit,
  }) {
    Future.microtask(() async {
      try {
        final client = Supabase.instance.client;
        // 1. Sync export_shipment_items
        for (final item in items) {
          final itemId = item['id'];
          final price = item['price'];
          final amount = item['amount'];
          if (itemId != null && price != null) {
            await client.from('export_shipment_items').update({
              'price': price,
              'amount': amount,
            }).eq('id', itemId);
          }
        }

        // 2. Sync read-only packing items in shipment_cost_items
        final costItems = await ShipmentCostItemDao().getForShipment(shipmentId);
        final readOnlyPackingItems = costItems
            .where((c) => c.category == 'packing' && (c.isReadOnly || c.reportCategoryName == 'تكلفة الكراتين'))
            .toList();
        if (readOnlyPackingItems.isNotEmpty) {
          for (final cItem in readOnlyPackingItems) {
            if (cItem.id != null) {
              final uPrice = cItem.quantity > 0 ? liveProductionCost / cItem.quantity : liveProductionCost;
              await client.from('shipment_cost_items').update({
                'unit_price': uPrice,
              }).eq('id', cItem.id!);
            }
          }
        }

        // 3. Sync export_shipments record
        await client.from('export_shipments').update({
          'cost_per_carton': costPerCarton,
          'total_landed_cost': totalShipmentCost,
          'total_fruit_cost': totalFruitCost,
          'total_packing_material_cost': totalPackingMaterialCost,
          'gross_profit': grossProfit,
          'net_profit': netProfit,
          'net_profit_egp': netProfit,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', shipmentId);
      } catch (e) {
        debugPrint('CostAllocationEngine: Background cost sync error (non-fatal): $e');
      }
    });
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
