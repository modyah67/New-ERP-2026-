import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/batch_dao.dart';
import '../dao/lot_dao.dart';
import '../dao/packing_order_dao.dart';
import '../dao/stock_movement_dao.dart';
import '../dao/shipment_cost_item_dao.dart';
import '../dao/shipment_cost_allocation_dao.dart';
import '../dao/export_shipment_dao.dart';
import '../models/batch_model.dart';
import '../models/packing_order_model.dart';
import '../models/stock_movement_model.dart';
import 'currency_conversion_service.dart';

class CostAllocationService {
  final _client = Supabase.instance.client;
  final _batchDao = BatchDao();
  final _lotDao = LotDao();
  final _packingOrderDao = PackingOrderDao();
  final _stockMovementDao = StockMovementDao();
  final _shipmentCostItemDao = ShipmentCostItemDao();
  final _shipmentCostAllocationDao = ShipmentCostAllocationDao();
  final _exportShipmentDao = ExportShipmentDao();

  /// Runs all lot-receipt side effects atomically (supplier balance, ledger,
  /// stock batches, station inventory, product qty/price).
  Future<Map<String, dynamic>> processLotReceipt(
    String lotId, {
    double? unitCostKg,
    String? oldStationId,
    String? oldFruitTypeId,
    String? oldSupplierId,
  }) async {
    debugPrint(
        'CostAllocationService.processLotReceipt START lotId=$lotId unitCostKg=$unitCostKg oldStationId=$oldStationId oldFruitTypeId=$oldFruitTypeId oldSupplierId=$oldSupplierId');
    try {
      final result = await _lotDao.processReceiptSideEffects(
        lotId,
        unitCostKg: unitCostKg,
        oldStationId: oldStationId,
        oldFruitTypeId: oldFruitTypeId,
        oldSupplierId: oldSupplierId,
      );
      debugPrint('CostAllocationService.processLotReceipt SUCCESS: $result');
      return result;
    } catch (e, st) {
      debugPrint('CostAllocationService.processLotReceipt FAILED: $e\n$st');
      rethrow;
    }
  }

  /// ---------------------------------------------------------------
  /// PHASE 2A: Allocate purchase cost to a lot
  /// ---------------------------------------------------------------
  /// @deprecated Prefer [processLotReceipt] which runs atomically via RPC.
  /// Either reads the linked purchase invoice item's unit_cost OR
  /// uses the provided unitCostKg to compute fruit_cost_per_kg /
  /// total_fruit_cost for the lot, then creates the supplier transaction.
  Future<void> allocateLotCost(dynamic lotId, dynamic purchaseInvoiceItemId,
      {double? unitCostKg}) async {
    debugPrint(
        'allocateLotCost START: lotId=$lotId, purchaseInvoiceItemId=$purchaseInvoiceItemId, unitCostKg=$unitCostKg');
    try {
      double costPerKg = 0.0;

      if (unitCostKg != null && unitCostKg > 0) {
        costPerKg = unitCostKg;
        debugPrint('allocateLotCost: using direct unitCostKg=$costPerKg');
      } else if (purchaseInvoiceItemId != null) {
        final item = await _client
            .from('purchase_invoice_items')
            .select('unit_cost')
            .eq('id', purchaseInvoiceItemId.toString())
            .maybeSingle();
        if (item == null) {
          debugPrint(
              'allocateLotCost: SKIP - purchase_invoice_items id=$purchaseInvoiceItemId not found');
          return;
        }
        costPerKg = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
        debugPrint(
            'allocateLotCost: unitCost from purchaseInvoiceItem=$costPerKg');
      } else {
        debugPrint(
            'allocateLotCost: SKIP - no unitCostKg and no purchaseInvoiceItemId');
        return;
      }

      final lot = await _lotDao.getById(lotId);
      if (lot == null) {
        debugPrint('allocateLotCost: SKIP - lot id=$lotId not found');
        return;
      }

      final totalCost = lot.netWeightKg * costPerKg;
      debugPrint('allocateLotCost: costPerKg=$costPerKg, totalCost=$totalCost');

      await _client.from('lot_receipts').update({
        'fruit_cost_per_kg': costPerKg,
        'total_fruit_cost': totalCost,
        'updated_at': DateTime.now().toIso8601String(),
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: lot.currency,
          amount: totalCost,
          exchangeRate: lot.exchangeRate,
        ).toJson(),
      }).eq('id', lotId);
      debugPrint('allocateLotCost: DONE - lot_receipts id=$lotId updated');

      // Create supplier transaction for the lot receipt
      if (lot.supplierId != null && totalCost > 0) {
        await _client.rpc('rpc_build_cost_allocation_journal', params: {
          'payload': {
            'date': lot.receiptDate.toIso8601String().substring(0, 10),
            'amount': totalCost,
            'supplier_id': lot.supplierId,
            'lot_number': lot.lotNumber,
            'product_name': lot.productName,
            'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
              currency: lot.currency,
              amount: totalCost,
              exchangeRate: lot.exchangeRate,
            ).toJson(),
          }
        });
        debugPrint(
            'allocateLotCost: supplier cost allocation journal created for ${lot.supplierId}');

        // Update supplier outstanding balance
        try {
          final row = await _client.from('suppliers').select('outstanding_balance').eq('id', lot.supplierId!).maybeSingle();
          final cur = (row?['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
          await _client.from('suppliers').update({
            'outstanding_balance': cur + lot.totalFruitCost,
            'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
              currency: lot.currency,
              amount: lot.totalFruitCost,
              exchangeRate: lot.exchangeRate,
            ).toJson(),
          }).eq('id', lot.supplierId!);
        } catch (e) {
          debugPrint('⚠️ Supplier outstanding_balance update failed: $e');
        }
        debugPrint('allocateLotCost: supplier balance updated');
      }
    } catch (e, st) {
      debugPrint('❌ CostAllocationService.allocateLotCost error: $e\n$st');
      rethrow;
    }
  }

  /// ---------------------------------------------------------------
  /// PHASE 2B: Create stock batches from grading results
  /// ---------------------------------------------------------------
  /// After grading is saved, creates stock_batches for A/B/C grades.
  /// Waste is excluded (it increases cost of remaining fruit).
  /// Cost allocation formula:
  ///   effectiveCostPerKg = lot.totalProductCost / (A + B + C weight)
  ///   Each batch cost = weight * effectiveCostPerKg
  Future<void> createBatchesFromGrading(String lotId, {String? warehouseId}) async {
    debugPrint(
        'createBatchesFromGrading START: lotId=$lotId, warehouseId=$warehouseId');
    try {
      final lot = await _lotDao.getById(lotId);
      if (lot == null) {
        debugPrint('createBatchesFromGrading: SKIP - lot id=$lotId not found');
        return;
      }
      debugPrint(
          'createBatchesFromGrading: lot=${lot.lotNumber}, gradingResults=${lot.gradingResults.length}');

      // ── Cleanup orphaned batches from previous grading ──────────────
      final pattern = 'G-${lot.lotNumber}-%';
      final oldBatches = await _client
          .from('stock_batches')
          .select('id, batch_number, quantity, remaining_quantity')
          .like('batch_number', pattern);
      debugPrint(
          'createBatchesFromGrading: found ${oldBatches.length} old batches to clean');
      for (final ob in oldBatches) {
        final qty = (ob['quantity'] as num?)?.toDouble() ?? 0;
        final remQty = (ob['remaining_quantity'] as num?)?.toDouble() ?? 0;
        if (remQty >= qty) {
          await _client.from('stock_batches').delete().eq('id', ob['id']);
          debugPrint(
              'createBatchesFromGrading: deleted orphaned batch id=${ob['id']}');
        } else {
          await _client.from('stock_batches').update({
            'remaining_quantity': 0,
            'status': 'depleted',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', ob['id']);
          debugPrint(
              'createBatchesFromGrading: marked depleted batch id=${ob['id']}');
        }
      }
      // ─────────────────────────────────────────────────────────────────

      final nonWaste = lot.gradingResults
          .where((r) => r.grade != 'waste' && r.weightKg > 0)
          .toList();
      if (nonWaste.isEmpty) {
        debugPrint(
            'createBatchesFromGrading: SKIP - no non-waste grading results');
        return;
      }

      final totalGradedWeight =
          nonWaste.fold<double>(0.0, (s, r) => s + r.weightKg);
      if (totalGradedWeight <= 0) {
        debugPrint(
            'createBatchesFromGrading: SKIP - totalGradedWeight=$totalGradedWeight <= 0');
        return;
      }

      final effectiveCostPerKg =
          totalGradedWeight > 0 ? lot.totalProductCost / totalGradedWeight : 0.0;
      debugPrint(
          'createBatchesFromGrading: totalGradedWeight=$totalGradedWeight, effectiveCostPerKg=$effectiveCostPerKg');

      int batchCount = 0;
      for (final result in nonWaste) {
        final batchCost = result.weightKg * effectiveCostPerKg;

        final batch = BatchModel(
          batchNumber: 'G-${lot.lotNumber}-${result.grade}',
          productId: lot.fruitTypeId ?? '',
          supplierId: lot.supplierId,
          supplierName: lot.supplierName,
          quantity: result.weightKg,
          remainingQuantity: result.weightKg,
          purchaseCost: batchCost,
          qualityGrade: result.grade,
          category: lot.productName,
          notes: 'من فرز ${lot.lotNumber} - درجة ${result.grade}',
          status: 'active',
          warehouseId: warehouseId,
        );

        final batchId = await _batchDao.insert(batch);
        debugPrint(
            'createBatchesFromGrading: created stock_batch id=$batchId for grade ${result.grade}');

        await _client
            .from('lot_grading_results')
            .update({'stock_batch_id': batchId}).eq('id', result.id!);
        debugPrint(
            'createBatchesFromGrading: linked stock_batch_id=$batchId to lot_grading_result id=${result.id}');

        await _stockMovementDao.insert(StockMovementModel(
          movementType: 'adjustment',
          productId: lot.fruitTypeId ?? '',
          quantity: result.weightKg,
          unitCost: effectiveCostPerKg,
          totalCost: batchCost,
          description:
              'إضافة مخزون من فرز ${lot.lotNumber} درجة ${result.grade}',
          referenceType: 'lot_grading',
          referenceId: lotId.toString(),
        ));
        debugPrint(
            'createBatchesFromGrading: created stock_movement for batch $batchId');
        batchCount++;
      }
      debugPrint(
          'createBatchesFromGrading: created $batchCount stock batches total');

      await _lotDao.updateStatus(lotId, 'sorting');
      debugPrint('createBatchesFromGrading: DONE - status updated to sorting');
    } catch (e, st) {
      debugPrint(
          '❌ CostAllocationService.createBatchesFromGrading error: $e\n$st');
      rethrow;
    }
  }

  /// ---------------------------------------------------------------
  /// PHASE 2C: Consume fruit inventory for a packing order
  /// ---------------------------------------------------------------
  /// Deducts the required fruit weight from the matching grade stock_batch.
  /// Stores fruit_cost_allocated on the packing order.
  Future<double> consumeFruitForPacking(String packingOrderId) async {
    try {
      final order = await _packingOrderDao.getById(int.parse(packingOrderId));
      if (order == null) return 0.0;

      final requiredWeight = order.cartonCount * order.netWeightPerCarton;
      if (requiredWeight <= 0) return 0.0;
      if (order.fruitTypeId == null) return 0.0;

      final batches = await _batchDao.getActiveBatches(order.fruitTypeId!);
      final gradeBatches =
          batches.where((b) => b.qualityGrade == order.grade).toList();
      if (gradeBatches.isEmpty) return 0.0;

      double remainingQty = requiredWeight;
      double totalAllocatedCost = 0.0;

      for (final batch in gradeBatches) {
        if (remainingQty <= 0) break;

        final deductQty = remainingQty > batch.remainingQuantity
            ? batch.remainingQuantity
            : remainingQty;

        await _batchDao.deductStock(batch.id!, deductQty);

        final batchCost = batch.purchaseCost > 0 && batch.quantity > 0
            ? (deductQty / batch.quantity) * batch.purchaseCost
            : 0.0;
        totalAllocatedCost += batchCost;

        await _stockMovementDao.insert(StockMovementModel(
          movementType: 'packaging_usage',
          productId: order.fruitTypeId!,
          quantity: -deductQty,
          unitCost:
              batch.quantity > 0 ? batch.purchaseCost / batch.quantity : 0.0,
          totalCost: batchCost,
          description:
              'صرف فاكهة لأمر تعبئة ${order.orderNumber} من ${batch.batchNumber}',
          referenceType: 'packing_order',
          referenceId: packingOrderId.toString(),
        ));

        remainingQty -= deductQty;
      }

      if (remainingQty > 0) {
        throw Exception(
            'المخزون غير كافٍ. المتبقي: $remainingQty كجم من أصل $requiredWeight كجم');
      }

      await _packingOrderDao.updateFruitCost(
          int.parse(packingOrderId), totalAllocatedCost);

      return totalAllocatedCost;
    } catch (e, st) {
      debugPrint(
          '❌ CostAllocationService.consumeFruitForPacking error: $e\n$st');
      rethrow;
    }
  }

  /// ---------------------------------------------------------------
  /// PHASE 2D: Calculate material cost using FIFO from purchase invoice items
  /// ---------------------------------------------------------------
  /// For each raw material in the recipe:
  ///   1. Calculates required quantity: recipeQtyPerCarton × cartonCount
  ///   2. Checks available stock (products.quantity)
  ///   3. Consumes from oldest purchase_invoice_items first (FIFO)
  ///   4. Calculates actual cost from consumed batches
  ///   5. Decreases products.quantity for each material
  Future<void> calculateMaterialCost(String packingOrderId) async {
    try {
      final order = await _packingOrderDao.getById(int.parse(packingOrderId));
      if (order == null) return;

      if (order.recipeName == null || order.recipeName!.isEmpty) return;

      final recipes = await _client
          .from('packing_recipes')
          .select('*, raw_materials!packing_recipes_raw_material_id_fkey(default_purchase_price)')
          .eq('name', order.recipeName!)
          .eq('grade', order.grade ?? '')
          .eq('is_active', true);

      double estimatedCost = 0.0;
      double actualCost = 0.0;

      for (final r in recipes) {
        final qtyPerCarton =
            (r['quantity_per_carton'] as num?)?.toDouble() ?? 0.0;
        final totalQty = qtyPerCarton * order.cartonCount;
        final rawMaterialId = r['raw_material_id']?.toString();

        final material = r['raw_materials'] as Map<String, dynamic>?;
        final estUnitCost =
            (material?['default_purchase_price'] as num?)?.toDouble() ?? 0.0;
        estimatedCost += totalQty * estUnitCost;

        if (rawMaterialId != null && totalQty > 0) {
          final fifoCost =
              await _consumeMaterialFifo(rawMaterialId, totalQty, order);
          actualCost += fifoCost;
        }
      }

      if (actualCost == 0.0) actualCost = estimatedCost;
      if (estimatedCost == 0.0) estimatedCost = actualCost;

      await _packingOrderDao.updateMaterialCost(
          int.parse(packingOrderId), actualCost, estimatedCost);
    } catch (e, st) {
      debugPrint(
          '❌ CostAllocationService.calculateMaterialCost error: $e\n$st');
      rethrow;
    }
  }

  /// Consumes material from purchase_invoice_items using FIFO (oldest first).
  /// Deducts remaining_quantity from oldest batches, decreases products.quantity,
  /// and records stock movements.
  Future<double> _consumeMaterialFifo(String materialProductId, double requiredQty,
      PackingOrderModel order) async {
    if (requiredQty <= 0) return 0.0;

    final items = await _client
        .from('purchase_invoice_items')
        .select('id, unit_cost, remaining_quantity')
        .eq('raw_material_id', materialProductId.toString())
        .gt('remaining_quantity', 0)
        .order('created_at');

    double remainingToConsume = requiredQty;
    double totalCost = 0.0;

    for (final item in items) {
      if (remainingToConsume <= 0) break;

      final id = item['id'];
      final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
      final availableQty =
          (item['remaining_quantity'] as num?)?.toDouble() ?? 0.0;

      if (availableQty <= 0) continue;

      final deductQty =
          remainingToConsume > availableQty ? availableQty : remainingToConsume;

      await _client.from('purchase_invoice_items').update({
        'remaining_quantity': availableQty - deductQty,
      }).eq('id', id);

      final cost = deductQty * unitCost;
      totalCost += cost;
      remainingToConsume -= deductQty;

      await _stockMovementDao.insert(StockMovementModel(
        movementType: 'packaging_usage',
        productId: materialProductId.toString(),
        quantity: -deductQty,
        unitCost: unitCost,
        totalCost: cost,
        description: 'صرف مواد تعبئة لأمر ${order.orderNumber} - تكلفة FIFO',
        referenceType: 'packing_order',
        referenceId: '${order.id}',
      ));
    }

    // Decrease total raw material stock (optional — table may not exist)
    try {
      final materialRow = await _client
          .from('raw_materials')
          .select('quantity')
          .eq('id', materialProductId)
          .single();
      final currentStock = (materialRow['quantity'] as num?)?.toDouble() ?? 0.0;
      await _client.from('raw_materials').update({
        'quantity':
            (currentStock - requiredQty).clamp(0, double.infinity),
      }).eq('id', materialProductId);
    } catch (e) {
      debugPrint('⚠️ cost_allocation_service: Failed to deduct raw material stock: $e');
    }

    return totalCost;
  }

  /// ---------------------------------------------------------------
  /// PHASE 2E: Accumulate costs onto export shipment
  /// ---------------------------------------------------------------
  /// Reads all packing orders linked to a shipment and sums their
  /// fruit_cost_allocated + actual_material_cost, then updates the
  /// shipment's total_fruit_cost / total_packing_material_cost.
  Future<void> accumulateShipmentCosts(String shipmentId) async {
    try {
      final orders = await _packingOrderDao.getByShipmentIdViaItems(int.parse(shipmentId));
      final cs = CurrencyConversionService.instance;

      double totalFruitCost = 0.0;
      double totalPackingMatCost = 0.0;

      for (final o in orders) {
        if (o.lotId != null) {
          try {
            final lot = await _lotDao.getById(o.lotId);
            if (lot != null && lot.totalProductCost > 0 && lot.netWeightKg > 0) {
              final costPerKg = lot.totalProductCost / lot.netWeightKg;
              final lotCurrencyCost = o.totalNetWeight * costPerKg;
              totalFruitCost += cs.toBase(lotCurrencyCost, lot.currency, lot.exchangeRate);
            } else if (o.fruitCostBase > 0) {
              totalFruitCost += o.fruitCostBase;
            } else {
              totalFruitCost += o.fruitCostAllocated;
            }
          } catch (_) {
            totalFruitCost += o.fruitCostBase > 0 ? o.fruitCostBase : o.fruitCostAllocated;
          }
        } else {
          totalFruitCost += o.fruitCostBase > 0 ? o.fruitCostBase : o.fruitCostAllocated;
        }
        totalPackingMatCost += o.materialCostBase > 0 ? o.materialCostBase : o.actualMaterialCost;
      }

      final shipment = await _exportShipmentDao.getById(shipmentId);
      if (shipment == null) return;

      // Read shipment cost items to separate packing costs from non-packing
      final allCostItems =
          await _shipmentCostItemDao.getForShipment(int.parse(shipmentId));
      final packingCostSum = allCostItems
          .where((i) => i.category == 'packing')
          .fold<double>(0.0, (s, i) => s + i.totalPrice);
      final nonPackingLandedCost = shipment.totalLandedCost - packingCostSum;

      await _exportShipmentDao.updateCosting(
        shipmentId: int.parse(shipmentId),
        totalLandedCost: shipment.totalLandedCost,
        cartonCount: shipment.cartonsCount,
        exportPricePerCarton: shipment.exportPricePerCarton,
        currencyCode: shipment.currencyCode,
        exchangeRate: shipment.exchangeRate,
        totalFruitCost: totalFruitCost,
        totalPackingMaterialCost: totalPackingMatCost,
        nonPackingLandedCost: nonPackingLandedCost,
      );
    } catch (e, st) {
      debugPrint(
          '❌ CostAllocationService.accumulateShipmentCosts error: $e\n$st');
      rethrow;
    }
  }

  /// ---------------------------------------------------------------
  /// PHASE 2F: Allocate shared shipment costs to individual products
  /// ---------------------------------------------------------------
  /// Distributes non-packing cost items (logistics, admin, other)
  /// across products based on weight or carton proportion.
  Future<void> allocateSharedCostsForShipment(String shipmentId,
      {String basis = 'weight_based'}) async {
    debugPrint(
        'allocateSharedCostsForShipment START: shipmentId=$shipmentId, basis=$basis');
    try {
      final costItems = await _shipmentCostItemDao.getForShipment(int.parse(shipmentId));
      final sharedItems = costItems
          .where((i) => i.category != 'packing' && i.totalPrice > 0)
          .toList();
      if (sharedItems.isEmpty) {
        debugPrint(
            'allocateSharedCostsForShipment: no shared cost items found');
        return;
      }
      debugPrint(
          'allocateSharedCostsForShipment: ${sharedItems.length} shared items, total=${sharedItems.fold(0.0, (s, i) => s + i.totalPrice)}');

      final orders = await _packingOrderDao.getByShipmentIdViaItems(int.parse(shipmentId));
      if (orders.isEmpty) {
        debugPrint(
            'allocateSharedCostsForShipment: no packing orders found for shipment');
        return;
      }

      final Map<String, Map<String, double>> productTotals = {};
      for (final o in orders) {
        if (o.fruitTypeId == null) continue;
        productTotals.putIfAbsent(
            o.fruitTypeId!, () => {'cartons': 0, 'weight': 0.0});
        productTotals[o.fruitTypeId!]!['cartons'] =
            (productTotals[o.fruitTypeId!]!['cartons'] ?? 0) + o.cartonCount;
        productTotals[o.fruitTypeId!]!['weight'] =
            (productTotals[o.fruitTypeId!]!['weight'] ?? 0) + o.totalNetWeight;
      }

      final double totalCartons = productTotals.values
          .fold(0, (s, v) => s + (v['cartons'] ?? 0).toInt())
          .toDouble();
      final double totalWeight =
          productTotals.values.fold(0.0, (s, v) => s + (v['weight'] ?? 0));
      debugPrint(
          'allocateSharedCostsForShipment: totalCartons=$totalCartons, totalWeight=$totalWeight, products=${productTotals.length}');

      if (totalCartons <= 0 && totalWeight <= 0) {
        debugPrint('allocateSharedCostsForShipment: no allocation basis data');
        return;
      }

      // Delete old allocations then re-insert
      await _shipmentCostAllocationDao.deleteForShipment(int.parse(shipmentId));
      debugPrint('allocateSharedCostsForShipment: deleted old allocations');

      final double basisTotal =
          basis == 'weight_based' ? totalWeight : totalCartons;
      if (basisTotal <= 0) {
        debugPrint(
            'allocateSharedCostsForShipment: basisTotal=$basisTotal <= 0, cannot allocate');
        return;
      }

      for (final costItem in sharedItems) {
        for (final entry in productTotals.entries) {
          final productId = entry.key;
          final pCartons = entry.value['cartons'] ?? 0;
          final pWeight = entry.value['weight'] ?? 0.0;
          final pBasis =
              basis == 'weight_based' ? pWeight : pCartons.toDouble();
          final pct = pBasis / basisTotal;

          final allocatedAmt = costItem.totalPrice * pct;

          await _client.from('shipment_cost_allocations').insert({
            'shipment_id': shipmentId,
            'source_cost_item_id': costItem.id,
            'finished_product_id': productId,
            'allocation_basis': basis,
            'allocated_amount': allocatedAmt,
            'allocation_percentage': pct,
            'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
              currency: 'EGP',
              amount: allocatedAmt,
              exchangeRate: 1.0,
            ).toJson(),
          });
          debugPrint(
              'allocateSharedCostsForShipment: productId=$productId, item=${costItem.description}, pct=${(pct * 100).toStringAsFixed(1)}%, amt=$allocatedAmt');
        }
      }
      debugPrint('allocateSharedCostsForShipment: DONE');
    } catch (e, st) {
      debugPrint(
          '❌ CostAllocationService.allocateSharedCostsForShipment error: $e\n$st');
      rethrow;
    }
  }
}
