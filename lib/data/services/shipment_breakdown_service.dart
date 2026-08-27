import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/shipment_cost_breakdown_dao.dart';
import '../dao/packing_order_dao.dart';
import '../dao/export_shipment_dao.dart';
import '../dao/shipment_cost_item_dao.dart';
import '../dao/lot_dao.dart';
import '../models/shipment_cost_breakdown_model.dart';
import '../models/export_shipment_model.dart';
import 'currency_conversion_service.dart';

class ShipmentBreakdownService {
  final _client = Supabase.instance.client;
  final _breakdownDao = ShipmentCostBreakdownDao();
  final _packingOrderDao = PackingOrderDao();
  final _exportShipmentDao = ExportShipmentDao();
  final _costItemDao = ShipmentCostItemDao();
  final _lotDao = LotDao();

  Future<void> generateBreakdown(String shipmentId) async {
    try {
      await _breakdownDao.deleteForShipment(shipmentId);

      final rows = <ShipmentCostBreakdownModel>[];

      final shipment = await _exportShipmentDao.getById(shipmentId);
      if (shipment == null) return;

      final currency = shipment.currencyCode.isNotEmpty ? shipment.currencyCode : 'EGP';

      rows.addAll(await _buildFruitRows(shipmentId));
      rows.addAll(await _buildPackingMaterialRows(shipmentId));
      rows.addAll(await _buildLogisticsRows(shipmentId, currency: currency));
      rows.addAll(await _buildExportCostRows(shipment));
      rows.addAll(await _buildAdminRows(shipmentId, currency: currency));
      rows.addAll(await _buildOtherRows(shipmentId, currency: currency));

      await _breakdownDao.insertAll(int.parse(shipmentId), rows);
    } catch (e, st) {
      debugPrint('❌ ShipmentBreakdownService.generateBreakdown error: $e\n$st');
      rethrow;
    }
  }

  Future<List<ShipmentCostBreakdownModel>> _buildFruitRows(
      String shipmentId) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final orders = await _packingOrderDao.getByShipmentIdViaItems(int.parse(shipmentId));
    final cs = CurrencyConversionService.instance;

    final gradeWeights = <String, double>{};
    final gradeCosts = <String, double>{};
    final gradeSupplier = <String, String>{};
    for (final o in orders) {
      gradeWeights.update(o.grade, (v) => v + o.totalNetWeight,
          ifAbsent: () => o.totalNetWeight);
          
      double fruitCost = o.fruitCostBase > 0 ? o.fruitCostBase : o.fruitCostAllocated;
      if (o.lotId != null) {
        try {
          final lot = await _lotDao.getById(o.lotId);
          if (lot != null && lot.totalProductCost > 0 && lot.netWeightKg > 0) {
            final costPerKg = lot.totalProductCost / lot.netWeightKg;
            final lotCurrencyCost = o.totalNetWeight * costPerKg;
            fruitCost = cs.toBase(lotCurrencyCost, lot.currency, lot.exchangeRate);
          }
        } catch (_) {}
      }
      
      gradeCosts.update(o.grade, (v) => v + fruitCost,
          ifAbsent: () => fruitCost);
          
      if (o.supplierName != null && o.supplierName!.trim().isNotEmpty) {
        gradeSupplier.putIfAbsent(o.grade, () => o.supplierName!);
      }
    }

    for (final grade in gradeWeights.keys) {
      final totalWt = gradeWeights[grade] ?? 0.0;
      final totalCost = gradeCosts[grade] ?? 0.0;
      final unitCost =
          totalWt > 0 ? double.parse((totalCost / totalWt).toStringAsFixed(4)) : 0.0;

      rows.add(ShipmentCostBreakdownModel(
        shipmentId: int.parse(shipmentId),
        costType: 'fruit',
        costCategory: 'fruit_${grade.toLowerCase()}',
        itemName: 'فاكهة درجة $grade',
        quantity: double.parse(totalWt.toStringAsFixed(3)),
        unitCost: unitCost,
        totalCost: double.parse(totalCost.toStringAsFixed(2)),
        currency: 'EGP',
        supplier: gradeSupplier[grade],
      ));
    }
    return rows;
  }

  Future<List<ShipmentCostBreakdownModel>> _buildPackingMaterialRows(
      String shipmentId) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final orders = await _packingOrderDao.getByShipmentIdViaItems(int.parse(shipmentId));

    // key = "materialType|materialName"
    final mq = <String, double>{};
    final mc = <String, double>{};
    final mt = <String, String>{};

    for (final o in orders) {
      if (o.recipeName == null) continue;
      final recipes = await _client
          .from('packing_recipes')
          .select(
              '*, raw_materials!packing_recipes_raw_material_id_fkey(name, default_purchase_price, unit)')
          .eq('name', o.recipeName!)
          .eq('grade', o.grade)
          .eq('is_active', true);

      for (final r in recipes) {
        final qtyPerCarton = (r['quantity_per_carton'] as num?)?.toDouble() ?? 0;
        final totalQty = qtyPerCarton * o.cartonCount;
        final rawMaterialName = _nestedString(r, 'raw_materials', 'name') ?? 'خامة';
        final estUnitCost =
            (_nestedNum(r, 'raw_materials', 'default_purchase_price') ?? 0).toDouble();
        final matType = 'other_material';

        final key = '$matType|$rawMaterialName';
        mq.update(key, (v) => v + totalQty, ifAbsent: () => totalQty);
        mc.update(key, (v) => v + (totalQty * estUnitCost),
            ifAbsent: () => totalQty * estUnitCost);
        mt.putIfAbsent(key, () => matType);
      }
    }

    for (final key in mq.keys) {
      final name = key.split('|')[1];
      final totalQty = mq[key] ?? 0.0;
      final totalCost = mc[key] ?? 0.0;
      final unitCost = totalQty > 0
          ? double.parse((totalCost / totalQty).toStringAsFixed(4))
          : 0.0;

      rows.add(ShipmentCostBreakdownModel(
        shipmentId: int.parse(shipmentId),
        costType: 'packing_material',
        costCategory: mt[key],
        itemName: name,
        quantity: double.parse(totalQty.toStringAsFixed(3)),
        unitCost: unitCost,
        totalCost: double.parse(totalCost.toStringAsFixed(2)),
        currency: 'EGP',
      ));
    }
    return rows;
  }

  Future<List<ShipmentCostBreakdownModel>> _buildLogisticsRows(
      String shipmentId, {String currency = 'EGP'}) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final costItems = await _costItemDao.getForShipment(int.parse(shipmentId));
    for (final item in costItems.where((i) => i.category == 'logistics')) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: int.parse(shipmentId),
        costType: 'logistics',
        costCategory: 'logistics',
        itemName: item.description,
        quantity: item.quantity,
        unitCost: item.unitPrice,
        totalCost: item.totalPrice,
        currency: currency,
      ));
    }
    return rows;
  }

  Future<List<ShipmentCostBreakdownModel>> _buildExportCostRows(
      ExportShipmentModel s) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final currency = s.currencyCode.isNotEmpty ? s.currencyCode : 'EGP';

    final sid = s.id is int ? s.id as int : int.tryParse('$s.id') ?? 0;

    if (s.freightCost > 0) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: sid,
        costType: 'export_cost',
        costCategory: 'freight',
        itemName: 'شحن بحري / جوي',
        quantity: 1,
        unitCost: s.freightCost,
        totalCost: s.freightCost,
        currency: currency,
      ));
    }

    if (s.insuranceCost > 0) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: sid,
        costType: 'export_cost',
        costCategory: 'insurance',
        itemName: 'تأمين',
        quantity: 1,
        unitCost: s.insuranceCost,
        totalCost: s.insuranceCost,
        currency: currency,
      ));
    }

    if (s.clearanceCost > 0) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: sid,
        costType: 'export_cost',
        costCategory: 'clearance',
        itemName: 'تكاليف التخليص',
        quantity: 1,
        unitCost: s.clearanceCost,
        totalCost: s.clearanceCost,
        currency: currency,
      ));
    }

    if (s.otherCosts > 0) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: sid,
        costType: 'export_cost',
        costCategory: 'other_export',
        itemName: 'تكاليف تصدير أخرى',
        quantity: 1,
        unitCost: s.otherCosts,
        totalCost: s.otherCosts,
        currency: currency,
      ));
    }
    return rows;
  }

  Future<List<ShipmentCostBreakdownModel>> _buildAdminRows(
      String shipmentId, {String currency = 'EGP'}) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final costItems = await _costItemDao.getForShipment(int.parse(shipmentId));
    for (final item in costItems.where((i) => i.category == 'admin')) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: int.parse(shipmentId),
        costType: 'admin',
        costCategory: 'admin',
        itemName: item.description,
        quantity: item.quantity,
        unitCost: item.unitPrice,
        totalCost: item.totalPrice,
        currency: currency,
      ));
    }
    return rows;
  }

  Future<List<ShipmentCostBreakdownModel>> _buildOtherRows(
      String shipmentId, {String currency = 'EGP'}) async {
    final rows = <ShipmentCostBreakdownModel>[];
    final costItems = await _costItemDao.getForShipment(int.parse(shipmentId));
    for (final item in costItems.where((i) => i.category == 'other')) {
      rows.add(ShipmentCostBreakdownModel(
        shipmentId: int.parse(shipmentId),
        costType: 'other',
        costCategory: 'other',
        itemName: item.description,
        quantity: item.quantity,
        unitCost: item.unitPrice,
        totalCost: item.totalPrice,
        currency: currency,
      ));
    }
    return rows;
  }

  String? _nestedString(dynamic map, String outer, String inner) {
    if (map is Map && map[outer] is Map) {
      return (map[outer] as Map)[inner]?.toString();
    }
    return null;
  }

  num? _nestedNum(dynamic map, String outer, String inner) {
    if (map is Map && map[outer] is Map) {
      final v = (map[outer] as Map)[inner];
      return v is num ? v : num.tryParse('$v');
    }
    return null;
  }

}
