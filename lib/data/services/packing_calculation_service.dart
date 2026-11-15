import 'dart:convert';
import 'packing_cost_allocation_engine.dart';
import '../models/packing_order_line_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Centralized calculation service for the Packing Order system.
///
/// All formulas live here. UI must NEVER compute costs directly — always call
/// this service and use the returned [PackingCalcResult].
///
/// Equations (invariant):
///   rawCost         = productCostPerKg × effectiveWeight
///   fruitCostAfterSort = rawCost − sortingCost
///   sortingCost     = sortedWeight × productCostPerKg
///   materialTotal   = Σ(used_qty × unit_cost)
///   materialWaste   = materialTotal × wastePercent / 100
///   costItemsTotal  = Σ(total_egp)
///   totalCost       = fruitCostAfterSort + cropWasteCost + materialTotal + materialWaste + costItemsTotal
///   costPerCarton   = totalCost / totalCartons
///   costPerKg       = totalCost / totalNetWeight
/// ═══════════════════════════════════════════════════════════════════════════

/// Per-crop line input data for calculations.
class PackingLineInput {
  final String productName;
  final int cartonCount;
  final double netWeightPerCarton;
  final double grossWeightPerCarton;
  final double effectiveWeight;
  final double sortedWeight;
  final double productCostPerKg;
  final double wasteWeight;
  final double totalPurchaseCost;

  final double? precomputedSortingCost;
  final double? precomputedWasteCost;

  const PackingLineInput({
    required this.productName,
    required this.cartonCount,
    required this.netWeightPerCarton,
    required this.grossWeightPerCarton,
    required this.effectiveWeight,
    required this.sortedWeight,
    required this.productCostPerKg,
    required this.wasteWeight,
    this.totalPurchaseCost = 0,
    this.precomputedSortingCost,
    this.precomputedWasteCost,
  });

  // ── Derived per-line values ──

  /// وزن صافي للكراتين = عدد الكراتين × الوزن الصافي للكرتونة
  double get totalNetWeight => cartonCount * netWeightPerCarton;

  /// وزن إجمالي للكراتين = عدد الكراتين × الوزن الإجمالي للكرتونة
  double get totalGrossWeight => cartonCount * grossWeightPerCarton;

  /// تكلفة الشراء الأولية = سعر الشراء × الكمية الفعلية
  /// This is the cost of ALL input fruit.
  double get rawCost => totalPurchaseCost > 0
      ? totalPurchaseCost
      : productCostPerKg * effectiveWeight;

  /// تكلفة الفرز = وزن الفرز × سعر الشراء
  double get sortingCost =>
      precomputedSortingCost ?? (sortedWeight * productCostPerKg);

  /// تكلفة الهالك = وزن الهالك × سعر الشراء
  double get wasteCost =>
      precomputedWasteCost ?? (wasteWeight * productCostPerKg);

  /// وزن صافي بعد الهالك = الكمية الفعلية − الهالك
  double get netWeightAfterWaste => effectiveWeight - wasteWeight;

  /// وزن متاح للتعبئة = وزن صافي بعد الهالك − الفرز
  double get availableWeight =>
      (netWeightAfterWaste - sortedWeight).clamp(0.0, double.infinity);

  /// تكلفة الخام بعد الفرز = تكلفة الشراء − تكلفة الفرز
  /// NOTE: waste cost is NOT added — it's already embedded in rawCost.
  double get fruitCostAfterSort => rawCost - sortingCost;
}

/// Per-crop line computed output.
class PackingLineResult {
  final PackingLineInput input;
  final double fruitCost;
  final double adjustedCostPerKg;
  final double sortingCost;
  final double rawCost;

  const PackingLineResult({
    required this.input,
    required this.fruitCost,
    required this.adjustedCostPerKg,
    required this.sortingCost,
    required this.rawCost,
  });
}

/// Summary of all weight/carton totals.
class WeightSummary {
  final int totalCrops;
  final int totalCartons;
  final double totalEffectiveWeight;
  final double totalSortedWeight;
  final double totalWasteWeight;
  final double totalNetWeight;
  final double totalSortingCost;

  const WeightSummary({
    required this.totalCrops,
    required this.totalCartons,
    required this.totalEffectiveWeight,
    required this.totalSortedWeight,
    required this.totalWasteWeight,
    required this.totalNetWeight,
    required this.totalSortingCost,
  });
}

/// Packaging material cost summary.
class MaterialCostSummary {
  final double materialCost;
  final double wastePercent;
  final double wasteCost;
  final double totalMaterialsWithWaste;
  final double settledWasteCost;
  final double unsettledWasteCost;
  final String wasteSettlementStatus;

  const MaterialCostSummary({
    required this.materialCost,
    required this.wastePercent,
    required this.wasteCost,
    required this.totalMaterialsWithWaste,
    this.settledWasteCost = 0.0,
    this.unsettledWasteCost = 0.0,
    this.wasteSettlementStatus = 'no_waste',
  });
}

/// Cost items summary.
class CostItemsSummary {
  final double totalCostItems;
  final int itemCount;

  const CostItemsSummary({
    required this.totalCostItems,
    required this.itemCount,
  });
}

/// Final cost totals.
class FinalCostSummary {
  final double totalRawCost;
  final double cropWasteCost;
  final double fruitCost;
  final double materialCost;
  final double materialWasteCost;
  final double costItemsTotal;
  final double totalCost;
  final double costPerCarton;
  final double costPerKg;

  const FinalCostSummary({
    required this.totalRawCost,
    required this.cropWasteCost,
    required this.fruitCost,
    required this.materialCost,
    required this.materialWasteCost,
    required this.costItemsTotal,
    required this.totalCost,
    required this.costPerCarton,
    required this.costPerKg,
  });
}

/// Per-product cost breakdown for the product cost table.
class ProductCostLine {
  final String productName;
  final int cartonCount;
  final double totalNetWeight;
  final double rawCost;
  final double wasteCost;
  final double sortingContribution;
  final double fruitCostAfterSort;
  final double specificPackagingCost;
  final double allocatedSharedPackaging;
  final double allocatedMaterialWaste;
  final double allocatedCostItems;
  final double finalCost;
  final double finalUnitCost;

  const ProductCostLine({
    required this.productName,
    required this.cartonCount,
    required this.totalNetWeight,
    required this.rawCost,
    required this.wasteCost,
    required this.sortingContribution,
    required this.fruitCostAfterSort,
    required this.specificPackagingCost,
    required this.allocatedSharedPackaging,
    required this.allocatedMaterialWaste,
    required this.allocatedCostItems,
    required this.finalCost,
    required this.finalUnitCost,
  });

  /// تكلفة المواد = تكلفة المواد المخصصة + تكلفة المواد المشتركة (بدون فاقد)
  double get packagingCost => specificPackagingCost + allocatedSharedPackaging;

  /// فاقد المواد = تكلفة الفاقد المخصصة
  double get packagingLoss => allocatedMaterialWaste;

  /// بنود التكلفة الإضافية
  double get extraCosts => allocatedCostItems;
}

/// Allocation trace entry for one product.
class AllocationTraceRow {
  final int lineIndex;
  final String productName;
  final double basisPercent;
  final double allocatedAmount;

  const AllocationTraceRow({
    required this.lineIndex,
    required this.productName,
    required this.basisPercent,
    required this.allocatedAmount,
  });
}

/// Allocation trace for one material or cost item.
class AllocationTraceGroup {
  final String itemName;
  final String itemType;
  final String allocationMethod;
  final double totalAmount;
  final List<AllocationTraceRow> rows;

  const AllocationTraceGroup({
    required this.itemName,
    required this.itemType,
    required this.allocationMethod,
    required this.totalAmount,
    required this.rows,
  });
}

/// Complete calculation result — the single source of truth.
class PackingCalcResult {
  final WeightSummary weights;
  final MaterialCostSummary materials;
  final CostItemsSummary costItems;
  final FinalCostSummary finalCost;
  final List<ProductCostLine> productLines;
  final List<PackingOrderLineModel> packingLines;
  final List<AllocationTraceGroup> allocationTraces;

  const PackingCalcResult({
    required this.weights,
    required this.materials,
    required this.costItems,
    required this.finalCost,
    required this.productLines,
    required this.packingLines,
    required this.allocationTraces,
  });
}

/// Validation error for pre-save checks.
class ValidationIssue {
  final String field;
  final String message;

  const ValidationIssue({required this.field, required this.message});
}

/// ═══════════════════════════════════════════════════════════════════════════
/// The Calculation Service
/// ═══════════════════════════════════════════════════════════════════════════
class PackingCalculationService {
  const PackingCalculationService._();

  // ── Number Formatting ──

  /// Money: 2 decimal places with thousand separators
  static String fmtMoney(double v) {
    if (v == v.roundToDouble() && v.abs() < 1000000)
      return v.toStringAsFixed(0);
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    if (decPart == '00') return buf.toString();
    return '${buf.toString()}.$decPart';
  }

  /// Weight: 2 decimal places
  static String fmtWeight(double v) => v.toStringAsFixed(2);

  /// Percent: 1 decimal place
  static String fmtPercent(double v) => v.toStringAsFixed(1);

  /// Compute authoritative cost per carton from raw DB map or PackingOrderModel
  /// taking into account all discounts applied to materials, fruitBase, waste, sorting, and additional costs.
  static double computeEffectiveCostPerCarton(Map<String, dynamic> row) {
    Map<String, dynamic> notes = {};
    if (row['notes'] != null) {
      if (row['notes'] is Map) {
        notes = Map<String, dynamic>.from(row['notes'] as Map);
      } else if (row['notes'] is String && (row['notes'] as String).isNotEmpty) {
        try {
          notes = Map<String, dynamic>.from(jsonDecode(row['notes'] as String) as Map);
        } catch (_) {}
      }
    }

    final cartons = (row['carton_count'] as num?)?.toInt() ?? 0;
    if (cartons <= 0) return 0.0;

    final fruitBase = (row['fruit_cost_base'] as num?)?.toDouble() ??
        (row['fruit_cost_allocated'] as num?)?.toDouble() ?? 0.0;
    final rawWeight = (notes['partial_weight_kg'] as num?)?.toDouble() ??
        (notes['total_raw_weight_kg'] as num?)?.toDouble() ??
        (row['total_gross_weight'] as num?)?.toDouble() ?? 0.0;
    final sortedWeight = (notes['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0;
    final wasteWeight = (notes['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;

    double fruitCostPerKg = rawWeight > 0 ? (fruitBase / rawWeight) : 0.0;
    double sortingCost = (notes['sorting_cost'] as num?)?.toDouble() ?? (sortedWeight * fruitCostPerKg);
    double wasteCost = (notes['waste_cost'] as num?)?.toDouble() ?? (wasteWeight * fruitCostPerKg);

    // If fruitBase was updated by debit note, recalculate sortingCost & wasteCost using new fruitCostPerKg
    if (fruitBase > 0 && rawWeight > 0) {
      sortingCost = sortedWeight * fruitCostPerKg;
      wasteCost = wasteWeight * fruitCostPerKg;
    }

    final fruitCostAfterSort = fruitBase - sortingCost;

    // Materials
    double matsCost = 0.0;
    if (notes['materials'] is List && (notes['materials'] as List).isNotEmpty) {
      for (var m in notes['materials']) {
        final q = (m['used_qty'] as num?)?.toDouble() ?? (m['quantity'] as num?)?.toDouble() ?? 0.0;
        final u = (m['unit_cost'] as num?)?.toDouble() ?? (m['cost'] as num?)?.toDouble() ?? 0.0;
        final t = (m['total'] as num?)?.toDouble() ?? (m['total_cost'] as num?)?.toDouble() ?? (q * u);
        matsCost += t;
      }
    } else {
      matsCost = (row['actual_material_cost'] as num?)?.toDouble() ??
          (row['material_cost_base'] as num?)?.toDouble() ?? 0.0;
    }
    final matWastePct = (notes['material_waste_percent'] as num?)?.toDouble() ?? 0.0;
    final matWasteCost = matsCost * (matWastePct / 100.0);

    // Cost items
    double costItemsCost = 0.0;
    if (notes['cost_items'] is List && (notes['cost_items'] as List).isNotEmpty) {
      for (var c in notes['cost_items']) {
        costItemsCost += (c['total_egp'] as num?)?.toDouble() ?? (c['total'] as num?)?.toDouble() ?? 0.0;
      }
    } else {
      costItemsCost = (row['other_cost_base'] as num?)?.toDouble() ?? 0.0;
    }

    if (matsCost > 0 || fruitBase > 0 || costItemsCost > 0) {
      final total = fruitCostAfterSort + wasteCost + matsCost + matWasteCost + costItemsCost;
      return total / cartons;
    }

    final headerCost = (row['packing_cost_per_carton'] as num?)?.toDouble() ?? 0.0;
    if (headerCost > 0) return headerCost;
    final totalPkg = (row['total_packing_cost'] as num?)?.toDouble() ?? 0.0;
    return totalPkg > 0 ? totalPkg / cartons : 0.0;
  }

  /// Computes the exact "ملخص تكلفة المنتجات" (Product Cost Summary lines)
  /// directly from packing_orders header and packing_order_lines data.
  static List<ProductCostLine> calculateProductCostLinesFromDb({
    required Map<String, dynamic> poData,
    required List<Map<String, dynamic>> dbLines,
  }) {
    Map<String, dynamic> notes = {};
    if (poData['notes'] != null) {
      if (poData['notes'] is Map) {
        notes = Map<String, dynamic>.from(poData['notes'] as Map);
      } else if (poData['notes'] is String && (poData['notes'] as String).isNotEmpty) {
        try {
          notes = Map<String, dynamic>.from(jsonDecode(poData['notes'] as String) as Map);
        } catch (_) {}
      }
    }

    final materials = notes['materials'] is List
        ? List<Map<String, dynamic>>.from(notes['materials'])
        : <Map<String, dynamic>>[];
    final costItems = notes['cost_items'] is List
        ? List<Map<String, dynamic>>.from(notes['cost_items'])
        : <Map<String, dynamic>>[];
    final matWastePct = (notes['material_waste_percent'] as num?)?.toDouble() ?? 0.0;

    final linesInput = <PackingLineInput>[];
    for (final l in dbLines) {
      final rawCost = (l['raw_material_cost'] as num?)?.toDouble() ?? 0.0;
      final qty = (l['quantity'] as num?)?.toDouble() ?? 0.0;
      final costPerKg = qty > 0 ? (rawCost / qty) : ((l['unit_cost'] as num?)?.toDouble() ?? 0.0);

      linesInput.add(PackingLineInput(
        productName: (l['product_name'] ?? '').toString(),
        cartonCount: (l['carton_count'] as num?)?.toInt() ?? 0,
        netWeightPerCarton: (l['net_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
        grossWeightPerCarton: (l['gross_weight_per_carton'] as num?)?.toDouble() ?? 0.0,
        effectiveWeight: qty,
        sortedWeight: (l['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0,
        productCostPerKg: costPerKg,
        wasteWeight: (l['waste_weight_kg'] as num?)?.toDouble() ?? 0.0,
        totalPurchaseCost: rawCost,
        precomputedWasteCost: (l['waste_cost'] as num?)?.toDouble() ?? 0.0,
        precomputedSortingCost: (l['sorting_cost'] as num?)?.toDouble() ?? 0.0,
      ));
    }

    if (linesInput.isEmpty) return const [];

    final calcResult = calculateAll(
      lines: linesInput,
      materialItems: materials,
      costItems: costItems,
      materialWastePercent: matWastePct,
    );

    return calcResult.productLines;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. calculateSummary() — weights and cartons
  // ═══════════════════════════════════════════════════════════════════════════
  static WeightSummary calculateSummary(List<PackingLineInput> lines) {
    int totalCartons = 0;
    double totalEffective = 0;
    double totalSorted = 0;
    double totalWaste = 0;
    double totalNet = 0;
    double totalSortingCost = 0;

    for (final l in lines) {
      totalCartons += l.cartonCount;
      totalEffective += l.effectiveWeight;
      totalSorted += l.sortedWeight;
      totalWaste += l.wasteWeight;
      totalNet += l.totalNetWeight;
      totalSortingCost += l.sortingCost;
    }

    return WeightSummary(
      totalCrops: lines.length,
      totalCartons: totalCartons,
      totalEffectiveWeight: totalEffective,
      totalSortedWeight: totalSorted,
      totalWasteWeight: totalWaste,
      totalNetWeight: totalNet,
      totalSortingCost: totalSortingCost,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. calculatePackaging() — material costs
  // ═══════════════════════════════════════════════════════════════════════════
  static MaterialCostSummary calculatePackaging(
    List<Map<String, dynamic>> materialItems,
    double wastePercent, {
    double settledWasteCost = 0.0,
    double? overrideWasteCost,
  }) {
    double total = 0;
    for (final m in materialItems) {
      final qty = ((m['used_qty'] ?? 0) as num).toDouble();
      final cost = ((m['unit_cost'] ?? 0) as num).toDouble();
      final computed = qty * cost;
      if (computed > 0) {
        total += computed;
      } else {
        total += ((m['total'] ?? 0) as num).toDouble();
      }
    }
    final wasteCost = (overrideWasteCost != null && overrideWasteCost > 0)
        ? overrideWasteCost
        : (total * wastePercent / 100);
    final effectivePercent = total > 0 ? (wasteCost / total) * 100 : wastePercent;
    final unsettled = (wasteCost - settledWasteCost).clamp(0.0, double.infinity);
    String status;
    if (wasteCost <= 0.001) {
      status = 'no_waste';
    } else if (settledWasteCost <= 0.001) {
      status = 'unsettled';
    } else if (unsettled <= 0.001) {
      status = 'fully_settled';
    } else {
      status = 'partially_settled';
    }

    return MaterialCostSummary(
      materialCost: total,
      wastePercent: effectivePercent,
      wasteCost: wasteCost,
      totalMaterialsWithWaste: total + wasteCost,
      settledWasteCost: settledWasteCost,
      unsettledWasteCost: unsettled,
      wasteSettlementStatus: status,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. calculateCostItems() — cost items total
  // ═══════════════════════════════════════════════════════════════════════════
  static CostItemsSummary calculateCostItems(
    List<Map<String, dynamic>> costItems,
  ) {
    double total = 0;
    for (final item in costItems) {
      final amount =
          ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();
      total += amount;
    }
    return CostItemsSummary(
      totalCostItems: total,
      itemCount: costItems.length,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. calculateDistribution() — per-line fruit costs
  // ═══════════════════════════════════════════════════════════════════════════
  static List<PackingLineResult> calculateDistribution(
      List<PackingLineInput> lines) {
    final results = <PackingLineResult>[];
    for (final l in lines) {
      final available = l.availableWeight;
      final fruitCostAfterSort = l.fruitCostAfterSort;
      final adjustedCostPerKg =
          available > 0 ? fruitCostAfterSort / available : l.productCostPerKg;
      final fruitCost = adjustedCostPerKg * available;
      results.add(PackingLineResult(
        input: l,
        fruitCost: fruitCost,
        adjustedCostPerKg: adjustedCostPerKg,
        sortingCost: l.sortingCost,
        rawCost: l.rawCost,
      ));
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. calculateFinalCost() — totals, per-carton, per-kg
  // ═══════════════════════════════════════════════════════════════════════════
  static FinalCostSummary calculateFinalCost({
    required List<PackingLineInput> lines,
    required MaterialCostSummary materials,
    required CostItemsSummary costItems,
    required int totalCartons,
    required double totalNetWeight,
  }) {
    final totalRawCost = lines.fold<double>(0, (s, l) => s + l.rawCost);
    final totalCropWasteCost = lines.fold<double>(0, (s, l) => s + l.wasteCost);
    final fruitCost = lines.fold<double>(0, (s, l) => s + l.fruitCostAfterSort);
    final totalCost = fruitCost +
        totalCropWasteCost +
        materials.materialCost +
        materials.wasteCost +
        costItems.totalCostItems;
    final costPerCarton = totalCartons > 0 ? totalCost / totalCartons : 0.0;
    final costPerKg = totalNetWeight > 0 ? totalCost / totalNetWeight : 0.0;

    return FinalCostSummary(
      totalRawCost: totalRawCost,
      cropWasteCost: totalCropWasteCost,
      fruitCost: fruitCost,
      materialCost: materials.materialCost,
      materialWasteCost: materials.wasteCost,
      costItemsTotal: costItems.totalCostItems,
      totalCost: totalCost,
      costPerCarton: costPerCarton,
      costPerKg: costPerKg,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Full calculation pipeline — single call returns everything
  static PackingCalcResult calculateAll({
    required List<PackingLineInput> lines,
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
    required double materialWastePercent,
    double? totalSortingCost,
    double settledMaterialWasteCost = 0.0,
    double? overrideWasteCost,
  }) {
    if (lines.isEmpty) {
      return const PackingCalcResult(
        weights: WeightSummary(
            totalCrops: 0,
            totalCartons: 0,
            totalEffectiveWeight: 0,
            totalSortedWeight: 0,
            totalWasteWeight: 0,
            totalNetWeight: 0,
            totalSortingCost: 0),
        materials: MaterialCostSummary(
            materialCost: 0,
            wastePercent: 0,
            wasteCost: 0,
            totalMaterialsWithWaste: 0,
            settledWasteCost: 0,
            unsettledWasteCost: 0,
            wasteSettlementStatus: 'no_waste'),
        costItems: CostItemsSummary(totalCostItems: 0, itemCount: 0),
        finalCost: FinalCostSummary(
            totalRawCost: 0,
            cropWasteCost: 0,
            fruitCost: 0,
            materialCost: 0,
            materialWasteCost: 0,
            costItemsTotal: 0,
            totalCost: 0,
            costPerCarton: 0,
            costPerKg: 0),
        productLines: [],
        packingLines: [],
        allocationTraces: [],
      );
    }

    final weights = calculateSummary(lines);
    final materials = calculatePackaging(
      materialItems,
      materialWastePercent,
      settledWasteCost: settledMaterialWasteCost,
      overrideWasteCost: overrideWasteCost,
    );
    final costItemsSummary = calculateCostItems(costItems);
    final lineResults = calculateDistribution(lines);

    final finalCost = calculateFinalCost(
      lines: lines,
      materials: materials,
      costItems: costItemsSummary,
      totalCartons: weights.totalCartons,
      totalNetWeight: weights.totalNetWeight,
    );

    final packingLinesDraft = <PackingOrderLineModel>[];
    for (final l in lines) {
      packingLinesDraft.add(PackingOrderLineModel(
        packingOrderId: 0,
        productName: l.productName,
        grade: 'A',
        quantity: l.effectiveWeight,
        cartonCount: l.cartonCount,
        netWeightPerCarton: l.netWeightPerCarton,
        grossWeightPerCarton: l.grossWeightPerCarton,
        rawMaterialCost: l.rawCost,
        wasteWeightKg: l.wasteWeight,
        wasteCost: l.wasteCost,
        sortedWeightKg: l.sortedWeight,
        sortingCost: l.sortingCost,
      ));
    }

    final allocResult = PackingCostAllocationEngine.instance.allocate(
      lines: packingLinesDraft,
      materials: materialItems,
      costItems: costItems,
      includeTrace: true,
    );

    final productLines = <ProductCostLine>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final allocLine = i < allocResult.lines.length
          ? allocResult.lines[i]
          : packingLinesDraft[i];
      final rawCost = l.rawCost;
      final sortingCost = l.sortingCost;
      final fruitCostAfterSort = rawCost - sortingCost;
      final materialCostLine =
          allocLine.specificPackagingCost + allocLine.allocatedSharedPackaging;
      final materialWasteLine = materialCostLine * materialWastePercent / 100;
      final costItemsLine = allocLine.allocatedCostItems;
      final finalCostLine = fruitCostAfterSort +
          l.wasteCost +
          materialCostLine +
          materialWasteLine +
          costItemsLine;
      final netW = l.totalNetWeight;
      final unitCost = netW > 0 ? finalCostLine / netW : 0.0;

      productLines.add(ProductCostLine(
        productName: l.productName,
        cartonCount: l.cartonCount,
        totalNetWeight: netW,
        rawCost: rawCost,
        wasteCost: l.wasteCost,
        sortingContribution: sortingCost,
        fruitCostAfterSort: fruitCostAfterSort,
        specificPackagingCost: allocLine.specificPackagingCost,
        allocatedSharedPackaging: allocLine.allocatedSharedPackaging,
        allocatedMaterialWaste: materialWasteLine,
        allocatedCostItems: costItemsLine,
        finalCost: finalCostLine,
        finalUnitCost: unitCost,
      ));
    }

    final packingLines = <PackingOrderLineModel>[];
    for (var i = 0; i < productLines.length; i++) {
      final pl = productLines[i];
      final input = lines[i];
      packingLines.add(PackingOrderLineModel(
        packingOrderId: 0,
        productName: pl.productName,
        grade: 'A',
        quantity: input.effectiveWeight,
        cartonCount: pl.cartonCount,
        netWeightPerCarton: input.netWeightPerCarton,
        grossWeightPerCarton: input.grossWeightPerCarton,
        totalNetWeight: pl.totalNetWeight,
        totalGrossWeight: pl.totalNetWeight > 0
            ? pl.cartonCount * input.grossWeightPerCarton
            : 0,
        unitCost: input.productCostPerKg,
        rawMaterialCost: pl.rawCost,
        wasteWeightKg: input.wasteWeight,
        wasteCost: input.wasteCost,
        sortedWeightKg: input.sortedWeight,
        sortingCost: pl.sortingContribution,
        specificPackagingCost: pl.specificPackagingCost,
        allocatedSharedPackaging: pl.allocatedSharedPackaging,
        allocatedCostItems: pl.allocatedCostItems,
        finalCost: pl.finalCost,
        finalUnitCost: pl.finalUnitCost,
      ));
    }

    // ═══ DEBUG: Per-line equation verification ═══
    assert(() {
      double sumFinal = 0;
      for (final pl in productLines) {
        final netProductCost = pl.rawCost - pl.sortingContribution;
        final expectedFinal = netProductCost +
            pl.wasteCost +
            pl.packagingCost +
            pl.packagingLoss +
            pl.extraCosts;
        final expectedUnitCost =
            pl.totalNetWeight > 0 ? expectedFinal / pl.totalNetWeight : 0.0;
        assert((pl.fruitCostAfterSort - netProductCost).abs() < 0.02,
            '${pl.productName}: fruitCostAfterSort(${pl.fruitCostAfterSort}) != netProductCost($netProductCost)');
        assert((pl.finalCost - expectedFinal).abs() < 0.02,
            '${pl.productName}: finalCost(${pl.finalCost}) != expected($expectedFinal)');
        assert((pl.finalUnitCost - expectedUnitCost).abs() < 0.02,
            '${pl.productName}: unitCost(${pl.finalUnitCost}) != expected($expectedUnitCost)');
        sumFinal += pl.finalCost;
      }
      assert((sumFinal - finalCost.totalCost).abs() < 0.02,
          'Sum(finalCost)($sumFinal) != totalCost(${finalCost.totalCost})');
      return true;
    }());

    return PackingCalcResult(
      weights: weights,
      materials: materials,
      costItems: costItemsSummary,
      finalCost: finalCost,
      productLines: productLines,
      packingLines: packingLines,
      allocationTraces: allocResult.trace != null
          ? allocResult.trace!.itemTraces
              .map((t) => AllocationTraceGroup(
                    itemName: t.itemName,
                    itemType: t.itemType,
                    allocationMethod: t.allocationMethod,
                    totalAmount: t.totalAmount,
                    rows: t.entries
                        .map((e) => AllocationTraceRow(
                              lineIndex: e.lineIndex,
                              productName: e.productName,
                              basisPercent: e.basisPercent,
                              allocatedAmount: e.allocatedAmount,
                            ))
                        .toList(),
                  ))
              .toList()
          : const [],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Validation — pre-save balance checks
  // ═══════════════════════════════════════════════════════════════════════════
  static List<ValidationIssue> validateAllocationBalance({
    required List<Map<String, dynamic>> materialItems,
    required List<Map<String, dynamic>> costItems,
  }) {
    final issues = <ValidationIssue>[];

    // Check each cost item: allocation total must equal item total
    for (final item in costItems) {
      final amount =
          ((item['total_egp'] ?? item['total'] ?? 0) as num).toDouble();
      if (amount <= 0) continue;
      final method = item['allocation_method'] as String?;
      if (method == null || method.isEmpty) {
        issues.add(ValidationIssue(
          field: 'cost_item',
          message: 'بند التكلفة "${item['name'] ?? ''}" بدون طريقة توزيع',
        ));
      }
    }

    // Check material items: if apply_to is specific, validate index
    for (final m in materialItems) {
      final applyTo = (m['apply_to'] as String?) ?? 'all';
      if (applyTo.startsWith('line:')) {
        final idx = int.tryParse(applyTo.substring(5));
        if (idx == null || idx < 0) {
          issues.add(ValidationIssue(
            field: 'material',
            message: 'مادة "${m['product_name'] ?? ''}" مرتبطة بخط غير صالح',
          ));
        }
      }
    }

    return issues;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Equation verification — for debugging/testing
  // ═══════════════════════════════════════════════════════════════════════════
  static bool verifyEquations({
    required WeightSummary weights,
    required MaterialCostSummary materials,
    required CostItemsSummary costItems,
    required FinalCostSummary finalCost,
  }) {
    const eps = 0.02; // tolerance for floating-point rounding

    // 1. costPerCarton = totalCost / totalCartons
    if (weights.totalCartons > 0) {
      final expected = finalCost.totalCost / weights.totalCartons;
      if ((finalCost.costPerCarton - expected).abs() > eps) return false;
    }

    // 2. costPerKg = totalCost / totalNetWeight
    if (weights.totalNetWeight > 0) {
      final expected = finalCost.totalCost / weights.totalNetWeight;
      if ((finalCost.costPerKg - expected).abs() > eps) return false;
    }

    // 3. totalCost = fruitCost + cropWasteCost + materialCost + materialWasteCost + costItemsTotal
    final expectedTotal = finalCost.fruitCost +
        finalCost.cropWasteCost +
        finalCost.materialCost +
        finalCost.materialWasteCost +
        finalCost.costItemsTotal;
    if ((finalCost.totalCost - expectedTotal).abs() > eps) return false;

    // 4. materialWasteCost = materialCost * wastePercent / 100
    final expectedWaste = materials.materialCost * materials.wastePercent / 100;
    if ((materials.wasteCost - expectedWaste).abs() > eps) return false;

    // 5. totalMaterialsWithWaste = materialCost + wasteCost
    final expectedMatTotal = materials.materialCost + materials.wasteCost;
    if ((materials.totalMaterialsWithWaste - expectedMatTotal).abs() > eps)
      return false;

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Debug: Print per-line verification
  // ═══════════════════════════════════════════════════════════════════════════
  static void printDebugVerification(PackingCalcResult result) {
    final f = result.finalCost;
    final w = result.weights;
    final m = result.materials;
    final c = result.costItems;

    print('═══════════════════════════════════════════');
    print('  PACKING ORDER CALCULATION VERIFICATION');
    print('═══════════════════════════════════════════');

    double sumRaw = 0,
        sumSort = 0,
        sumPkg = 0,
        sumLoss = 0,
        sumExtra = 0,
        sumFinal = 0,
        sumNetW = 0;
    int sumCartons = 0;

    for (var i = 0; i < result.productLines.length; i++) {
      final pl = result.productLines[i];
      final netProductCost = pl.rawCost - pl.sortingContribution;
      final expectedFinal = netProductCost +
          pl.wasteCost +
          pl.packagingCost +
          pl.packagingLoss +
          pl.extraCosts;
      final costPerCarton =
          pl.cartonCount > 0 ? pl.finalCost / pl.cartonCount : 0.0;

      print('');
      print('─ Product #${i + 1}: ${pl.productName}');
      print('  RawCost          = ${pl.rawCost.toStringAsFixed(2)}');
      print(
          '  SortingCost      = ${pl.sortingContribution.toStringAsFixed(2)}');
      print(
          '  NetProductCost   = ${netProductCost.toStringAsFixed(2)} (= Raw - Sorting)');
      print('  PackagingCost    = ${pl.packagingCost.toStringAsFixed(2)}');
      print('  PackagingLoss    = ${pl.packagingLoss.toStringAsFixed(2)}');
      print('  WasteCost        = ${pl.wasteCost.toStringAsFixed(2)}');
      print('  AllocatedExtra   = ${pl.extraCosts.toStringAsFixed(2)}');
      print(
          '  FinalProductCost = ${pl.finalCost.toStringAsFixed(2)} (= Raw + Waste - Sorting + Pkg + Loss + Extra)');
      print('  Expected         = ${expectedFinal.toStringAsFixed(2)}');
      print(
          '  Match            = ${(pl.finalCost - expectedFinal).abs() < 0.02 ? "✓" : "✗ MISMATCH"}');
      print(
          '  CostPerKg        = ${pl.finalUnitCost.toStringAsFixed(2)} (= ${pl.finalCost.toStringAsFixed(2)} / ${pl.totalNetWeight.toStringAsFixed(2)})');
      print(
          '  CostPerCarton    = ${costPerCarton.toStringAsFixed(2)} (= ${pl.finalCost.toStringAsFixed(2)} / ${pl.cartonCount})');

      sumRaw += pl.rawCost;
      sumSort += pl.sortingContribution;
      sumPkg += pl.packagingCost;
      sumLoss += pl.packagingLoss;
      sumExtra += pl.extraCosts;
      sumFinal += pl.finalCost;
      sumNetW += pl.totalNetWeight;
      sumCartons += pl.cartonCount;
    }

    print('');
    print('═══════════════════════════════════════════');
    print('  TOTALS');
    print('═══════════════════════════════════════════');
    print('  Cartons          = $sumCartons');
    print('  NetWeight        = ${sumNetW.toStringAsFixed(2)}');
    print(
        '  Sum(RawCost)     = ${sumRaw.toStringAsFixed(2)} vs TotalRawCost = ${f.totalRawCost.toStringAsFixed(2)} → ${(sumRaw - f.totalRawCost).abs() < 0.02 ? "✓" : "✗"}');
    print(
        '  Sum(Sorting)     = ${sumSort.toStringAsFixed(2)} vs TotalSorting = ${w.totalSortingCost.toStringAsFixed(2)} → ${(sumSort - w.totalSortingCost).abs() < 0.02 ? "✓" : "✗"}');
    print(
        '  Sum(Packaging)   = ${sumPkg.toStringAsFixed(2)} vs MaterialCost = ${m.materialCost.toStringAsFixed(2)} → ${(sumPkg - m.materialCost).abs() < 0.02 ? "✓" : "✗"}');
    print(
        '  Sum(Loss)        = ${sumLoss.toStringAsFixed(2)} vs WasteCost   = ${m.wasteCost.toStringAsFixed(2)} → ${(sumLoss - m.wasteCost).abs() < 0.02 ? "✓" : "✗"}');
    print(
        '  Sum(Extra)       = ${sumExtra.toStringAsFixed(2)} vs CostItems   = ${c.totalCostItems.toStringAsFixed(2)} → ${(sumExtra - c.totalCostItems).abs() < 0.02 ? "✓" : "✗"}');
    print(
        '  Sum(FinalCost)   = ${sumFinal.toStringAsFixed(2)} vs TotalCost   = ${f.totalCost.toStringAsFixed(2)} → ${(sumFinal - f.totalCost).abs() < 0.02 ? "✓" : "✗"}');
    print('  CostPerCarton    = ${f.costPerCarton.toStringAsFixed(2)}');
    print('  CostPerKg        = ${f.costPerKg.toStringAsFixed(2)}');
    print('═══════════════════════════════════════════');
  }
}
