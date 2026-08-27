import 'dart:convert';
import '../models/packing_order_line_model.dart';

/// Detailed trace entry for a single allocation line item.
class AllocationTraceEntry {
  final int lineIndex;
  final String productName;
  final String methodName;
  final double basisValue;
  final double basisPercent;
  final double allocatedAmount;

  const AllocationTraceEntry({
    required this.lineIndex,
    required this.productName,
    required this.methodName,
    required this.basisValue,
    required this.basisPercent,
    required this.allocatedAmount,
  });

  Map<String, dynamic> toJson() => {
        'line_index': lineIndex,
        'product_name': productName,
        'method': methodName,
        'basis_value': basisValue,
        'basis_percent': basisPercent,
        'allocated_amount': allocatedAmount,
      };
}

/// Trace for a single material or cost item allocation.
class AllocationItemTrace {
  final String itemName;
  final String itemType; // 'material' or 'cost_item'
  final String applyTo; // 'all', 'line:N', etc.
  final String allocationMethod;
  final double totalAmount;
  final List<AllocationTraceEntry> entries;

  const AllocationItemTrace({
    required this.itemName,
    required this.itemType,
    required this.applyTo,
    required this.allocationMethod,
    required this.totalAmount,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'item_type': itemType,
        'apply_to': applyTo,
        'allocation_method': allocationMethod,
        'total_amount': totalAmount,
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

/// Full allocation trace for the order.
class AllocationTrace {
  final List<AllocationItemTrace> itemTraces;
  final double totalMaterials;
  final double totalCostItems;
  final Map<int, double> lineTotals; // lineIndex → total allocated

  const AllocationTrace({
    required this.itemTraces,
    required this.totalMaterials,
    required this.totalCostItems,
    required this.lineTotals,
  });

  String toJsonString() => jsonEncode({
        'item_traces': itemTraces.map((t) => t.toJson()).toList(),
        'total_materials': totalMaterials,
        'total_cost_items': totalCostItems,
        'line_totals': lineTotals.map((k, v) => MapEntry(k.toString(), v)),
      });
}

/// Result of allocating shared packaging + overhead across packing order lines.
class PackingLineAllocationResult {
  final List<PackingOrderLineModel> lines;
  final double totalSpecificPackaging;
  final double totalSharedPackaging;
  final double totalAllocatedCostItems;
  final double totalFinalCost;
  final AllocationTrace? trace;

  const PackingLineAllocationResult({
    required this.lines,
    required this.totalSpecificPackaging,
    required this.totalSharedPackaging,
    required this.totalAllocatedCostItems,
    required this.totalFinalCost,
    this.trace,
  });
}

/// Cost snapshot stored per packing order on confirm for historical immutability.
class CostSnapshot {
  final List<CostSnapshotLine> lines;
  final double totalRawCost;
  final double totalSpecificPackaging;
  final double totalSharedPackaging;
  final double totalAllocatedCostItems;
  final double totalFinalCost;
  final String allocationMethod;
  final DateTime calculatedAt;

  const CostSnapshot({
    required this.lines,
    required this.totalRawCost,
    required this.totalSpecificPackaging,
    required this.totalSharedPackaging,
    required this.totalAllocatedCostItems,
    required this.totalFinalCost,
    required this.allocationMethod,
    required this.calculatedAt,
  });

  Map<String, dynamic> toJson() => {
        'lines': lines.map((l) => l.toJson()).toList(),
        'total_raw_cost': totalRawCost,
        'total_specific_packaging': totalSpecificPackaging,
        'total_shared_packaging': totalSharedPackaging,
        'total_allocated_cost_items': totalAllocatedCostItems,
        'total_final_cost': totalFinalCost,
        'allocation_method': allocationMethod,
        'calculated_at': calculatedAt.toIso8601String(),
      };

  static CostSnapshot fromAllocationResult(PackingLineAllocationResult result) {
    return CostSnapshot(
      lines: result.lines.map((l) => CostSnapshotLine(
        productName: l.productName,
        grade: l.grade,
        rawMaterialCost: l.rawMaterialCost,
        specificPackagingCost: l.specificPackagingCost,
        allocatedSharedPackaging: l.allocatedSharedPackaging,
        allocatedCostItems: l.allocatedCostItems,
        finalCost: l.finalCost,
        finalUnitCost: l.finalUnitCost,
        cartonCount: l.cartonCount,
        totalNetWeight: l.totalNetWeight,
      )).toList(),
      totalRawCost: result.lines.fold(0.0, (s, l) => s + l.rawMaterialCost),
      totalSpecificPackaging: result.totalSpecificPackaging,
      totalSharedPackaging: result.totalSharedPackaging,
      totalAllocatedCostItems: result.totalAllocatedCostItems,
      totalFinalCost: result.totalFinalCost,
      allocationMethod: 'MULTI_PRODUCT',
      calculatedAt: DateTime.now(),
    );
  }
}

class CostSnapshotLine {
  final String productName;
  final String grade;
  final double rawMaterialCost;
  final double specificPackagingCost;
  final double allocatedSharedPackaging;
  final double allocatedCostItems;
  final double finalCost;
  final double finalUnitCost;
  final int cartonCount;
  final double totalNetWeight;

  const CostSnapshotLine({
    required this.productName,
    required this.grade,
    required this.rawMaterialCost,
    required this.specificPackagingCost,
    required this.allocatedSharedPackaging,
    required this.allocatedCostItems,
    required this.finalCost,
    required this.finalUnitCost,
    required this.cartonCount,
    required this.totalNetWeight,
  });

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'grade': grade,
        'raw_material_cost': rawMaterialCost,
        'specific_packaging_cost': specificPackagingCost,
        'allocated_shared_packaging': allocatedSharedPackaging,
        'allocated_cost_items': allocatedCostItems,
        'final_cost': finalCost,
        'final_unit_cost': finalUnitCost,
        'carton_count': cartonCount,
        'total_net_weight': totalNetWeight,
      };
}

/// Multi-product packing cost allocation engine.
///
/// Allocates:
/// - Specific packaging materials (`apply_to` = line index) → that line only
/// - Shared packaging materials (`apply_to` = all) → by material's allocation_method
/// - Cost items → by each item's [CostAllocationMethod]
///
/// Supports 8 allocation methods with precise decimal math and full traceability.
class PackingCostAllocationEngine {
  PackingCostAllocationEngine._();
  static final PackingCostAllocationEngine instance =
      PackingCostAllocationEngine._();
  factory PackingCostAllocationEngine() => instance;

  /// [materials] maps must include:
  /// - `used_qty`, `unit_cost` (EGP), or `total` (pre-computed)
  /// - `apply_to`: `'all'` (default) or `'line:<index>'`
  /// - `allocation_method`: optional, defaults to BY_NET_WEIGHT for shared
  /// - `name`: display name for trace
  ///
  /// [costItems] maps must include:
  /// - `total_egp` (preferred) or `total`
  /// - `allocation_method` (default BY_NET_WEIGHT)
  /// - for MANUAL: `target_line_index` or `manual_amounts` (map index→amount)
  /// - `name`: display name for trace
  PackingLineAllocationResult allocate({
    required List<PackingOrderLineModel> lines,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> costItems,
    bool includeTrace = true,
  }) {
    if (lines.isEmpty) {
      return const PackingLineAllocationResult(
        lines: [],
        totalSpecificPackaging: 0,
        totalSharedPackaging: 0,
        totalAllocatedCostItems: 0,
        totalFinalCost: 0,
      );
    }

    final n = lines.length;
    final specific = List<double>.filled(n, 0);
    final shared = List<double>.filled(n, 0);
    final overhead = List<double>.filled(n, 0);

    final traces = <AllocationItemTrace>[];

    // ── Packaging materials ──
    final sharedMats = <Map<String, dynamic>>[];
    for (final m in materials) {
      final cost = _materialCost(m);
      if (cost <= 0) continue;
      final applyTo = (m['apply_to'] as String?)?.trim() ?? 'all';
      final matName = (m['product_name'] as String?)?.replaceAll(' (مادة تعبئة)', '') ??
          (m['name'] as String?)?.replaceAll(' (مادة تعبئة)', '') ??
          (m['item_name'] as String?) ??
          (m['material_name'] as String?) ??
          'مادة تعبئة';
      if (applyTo.startsWith('line:')) {
        final idx = int.tryParse(applyTo.substring(5));
        if (idx != null && idx >= 0 && idx < n) {
          specific[idx] += cost;
          if (includeTrace) {
            traces.add(AllocationItemTrace(
              itemName: matName,
              itemType: 'material',
              applyTo: applyTo,
              allocationMethod: 'SPECIFIC',
              totalAmount: _round2(cost),
              entries: [AllocationTraceEntry(
                lineIndex: idx,
                productName: lines[idx].productName,
                methodName: 'محدد لمنتج',
                basisValue: cost,
                basisPercent: 100.0,
                allocatedAmount: _round2(cost),
              )],
            ));
          }
        } else {
          sharedMats.add(m);
        }
      } else {
        sharedMats.add(m);
      }
    }

    final sharedPkgTotal =
        sharedMats.fold<double>(0, (s, m) => s + _materialCost(m));
    if (sharedPkgTotal > 0) {
      // Each shared material can have its own allocation method
      for (final m in sharedMats) {
        final matCost = _materialCost(m);
        if (matCost <= 0) continue;
        final matMethod = CostAllocationMethod.fromCode(
          m['allocation_method'] as String?,
        );
        final matName = (m['product_name'] as String?)?.replaceAll(' (مادة تعبئة)', '') ??
            (m['name'] as String?)?.replaceAll(' (مادة تعبئة)', '') ??
            (m['item_name'] as String?) ??
            (m['material_name'] as String?) ??
            'مادة تعبئة';
        final shares = _computeShares(lines, matMethod);
        final entryAmounts = <AllocationTraceEntry>[];
        var assigned = 0.0;
        for (var i = 0; i < n; i++) {
          final part = (i == n - 1)
              ? _round2(matCost - assigned)
              : _round2(matCost * shares[i]);
          shared[i] += part;
          assigned += part;
          if (includeTrace) {
            entryAmounts.add(AllocationTraceEntry(
              lineIndex: i,
              productName: lines[i].productName,
              methodName: matMethod.label,
              basisValue: _getBasisValue(lines[i], matMethod),
              basisPercent: _round2(shares[i] * 100),
              allocatedAmount: part,
            ));
          }
        }
        if (includeTrace) {
          traces.add(AllocationItemTrace(
            itemName: matName,
            itemType: 'material',
            applyTo: 'all',
            allocationMethod: matMethod.code,
            totalAmount: _round2(matCost),
            entries: entryAmounts,
          ));
        }
      }
    }

    // ── Cost items ──
    for (final item in costItems) {
      final amount = _costItemAmount(item);
      if (amount <= 0) continue;
      final method = CostAllocationMethod.fromCode(
        item['allocation_method'] as String?,
      );
      final itemName = (item['name'] as String?) ?? 'بند تكلفة';

      if (method == CostAllocationMethod.manual) {
        final targetIdx = (item['target_line_index'] as num?)?.toInt();
        if (targetIdx != null && targetIdx >= 0 && targetIdx < n) {
          overhead[targetIdx] += amount;
          if (includeTrace) {
            traces.add(AllocationItemTrace(
              itemName: itemName,
              itemType: 'cost_item',
              applyTo: 'line:$targetIdx',
              allocationMethod: 'MANUAL',
              totalAmount: _round2(amount),
              entries: [AllocationTraceEntry(
                lineIndex: targetIdx,
                productName: lines[targetIdx].productName,
                methodName: 'يدوي (محدد)',
                basisValue: amount,
                basisPercent: 100.0,
                allocatedAmount: _round2(amount),
              )],
            ));
          }
          continue;
        }
        final manual = item['manual_amounts'];
        if (manual is Map) {
          var assigned = 0.0;
          final entryAmounts = <AllocationTraceEntry>[];
          for (final e in manual.entries) {
            final idx = int.tryParse(e.key.toString()) ??
                (e.key is num ? (e.key as num).toInt() : null);
            final amt = (e.value as num?)?.toDouble() ?? 0;
            if (idx != null && idx >= 0 && idx < n && amt > 0) {
              overhead[idx] += amt;
              assigned += amt;
              if (includeTrace) {
                entryAmounts.add(AllocationTraceEntry(
                  lineIndex: idx,
                  productName: lines[idx].productName,
                  methodName: 'يدوي',
                  basisValue: amt,
                  basisPercent: _round2(amt / amount * 100),
                  allocatedAmount: _round2(amt),
                ));
              }
            }
          }
          final residual = _round2(amount - assigned);
          if (residual.abs() >= 0.01) {
            final maxIdx = _maxIndex(overhead);
            overhead[maxIdx] += residual;
            if (includeTrace) {
              entryAmounts.add(AllocationTraceEntry(
                lineIndex: maxIdx,
                productName: lines[maxIdx].productName,
                methodName: 'يدوي (باقي)',
                basisValue: residual,
                basisPercent: _round2(residual / amount * 100),
                allocatedAmount: residual,
              ));
            }
          }
          if (includeTrace) {
            traces.add(AllocationItemTrace(
              itemName: itemName,
              itemType: 'cost_item',
              applyTo: 'manual',
              allocationMethod: 'MANUAL',
              totalAmount: _round2(amount),
              entries: entryAmounts,
            ));
          }
          continue;
        }
        // Fallback: equal if MANUAL without target
        final shares = _computeShares(lines, CostAllocationMethod.equal);
        final entryAmounts = <AllocationTraceEntry>[];
        var assigned = 0.0;
        for (var i = 0; i < n; i++) {
          final part = (i == n - 1)
              ? _round2(amount - assigned)
              : _round2(amount * shares[i]);
          overhead[i] += part;
          assigned += part;
          if (includeTrace) {
            entryAmounts.add(AllocationTraceEntry(
              lineIndex: i,
              productName: lines[i].productName,
              methodName: 'بالتساوي (احتياطي)',
              basisValue: 1.0,
              basisPercent: _round2(shares[i] * 100),
              allocatedAmount: part,
            ));
          }
        }
        if (includeTrace) {
          traces.add(AllocationItemTrace(
            itemName: itemName,
            itemType: 'cost_item',
            applyTo: 'all',
            allocationMethod: 'EQUAL',
            totalAmount: _round2(amount),
            entries: entryAmounts,
          ));
        }
      } else {
        final shares = _computeShares(lines, method);
        final entryAmounts = <AllocationTraceEntry>[];
        var assigned = 0.0;
        for (var i = 0; i < n; i++) {
          final part = (i == n - 1)
              ? _round2(amount - assigned)
              : _round2(amount * shares[i]);
          overhead[i] += part;
          assigned += part;
          if (includeTrace) {
            entryAmounts.add(AllocationTraceEntry(
              lineIndex: i,
              productName: lines[i].productName,
              methodName: method.label,
              basisValue: _getBasisValue(lines[i], method),
              basisPercent: _round2(shares[i] * 100),
              allocatedAmount: part,
            ));
          }
        }
        if (includeTrace) {
          traces.add(AllocationItemTrace(
            itemName: itemName,
            itemType: 'cost_item',
            applyTo: 'all',
            allocationMethod: method.code,
            totalAmount: _round2(amount),
            entries: entryAmounts,
          ));
        }
      }
    }

    // ── Build result lines ──
    final result = <PackingOrderLineModel>[];
    var totSpec = 0.0;
    var totShared = 0.0;
    var totOh = 0.0;
    var totFinal = 0.0;
    final lineTotals = <int, double>{};

    for (var i = 0; i < n; i++) {
      final line = lines[i];
      final raw = _round2(line.rawMaterialCost);
      final spec = _round2(specific[i]);
      final sh = _round2(shared[i]);
      final oh = _round2(overhead[i]);
      final finalCost = _round2(raw + spec + sh + oh);
      final unit = line.totalNetWeight > 0
          ? _round4(finalCost / line.totalNetWeight)
          : (line.cartonCount > 0
              ? _round4(finalCost / line.cartonCount)
              : 0.0);

      totSpec += spec;
      totShared += sh;
      totOh += oh;
      totFinal += finalCost;
      lineTotals[i] = finalCost;

      result.add(line.copyWith(
        specificPackagingCost: spec,
        allocatedSharedPackaging: sh,
        allocatedCostItems: oh,
        finalCost: finalCost,
        finalUnitCost: unit,
      ));
    }

    final trace = includeTrace
        ? AllocationTrace(
            itemTraces: traces,
            totalMaterials: _round2(totSpec + totShared),
            totalCostItems: _round2(totOh),
            lineTotals: lineTotals,
          )
        : null;

    return PackingLineAllocationResult(
      lines: result,
      totalSpecificPackaging: _round2(totSpec),
      totalSharedPackaging: _round2(totShared),
      totalAllocatedCostItems: _round2(totOh),
      totalFinalCost: _round2(totFinal),
      trace: trace,
    );
  }

  /// Compute the raw basis value for a line under a given method.
  double _getBasisValue(PackingOrderLineModel l, CostAllocationMethod method) {
    switch (method) {
      case CostAllocationMethod.byWeight:
        return l.totalGrossWeight > 0 ? l.totalGrossWeight : l.totalNetWeight;
      case CostAllocationMethod.byNetWeight:
        return l.totalNetWeight > 0
            ? l.totalNetWeight
            : (l.cartonCount * l.netWeightPerCarton);
      case CostAllocationMethod.byInputWeight:
        return l.quantity;
      case CostAllocationMethod.byProductValue:
        return l.rawMaterialCost;
      case CostAllocationMethod.byQuantity:
      case CostAllocationMethod.byPackages:
        return l.cartonCount.toDouble();
      case CostAllocationMethod.equal:
      case CostAllocationMethod.manual:
        return 1.0;
    }
  }

  List<double> _computeShares(
    List<PackingOrderLineModel> lines,
    CostAllocationMethod method,
  ) {
    final n = lines.length;
    final bases = List<double>.filled(n, 0);

    for (var i = 0; i < n; i++) {
      bases[i] = _getBasisValue(lines[i], method);
    }

    final total = bases.fold<double>(0, (s, v) => s + v);
    if (total <= 0) {
      return List<double>.filled(n, 1.0 / n);
    }
    return bases.map((b) => b / total).toList();
  }

  /// Validate allocation: checks for negative costs, missing methods, etc.
  static List<String> validateAllocation({
    required List<PackingOrderLineModel> lines,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> costItems,
  }) {
    final errors = <String>[];

    if (lines.isEmpty) {
      errors.add('لا توجد منتجات في أمر التعبئة');
      return errors;
    }

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.rawMaterialCost < 0) {
        errors.add('تكلفة الخام سالبة للمنتج ${i + 1}: ${l.productName}');
      }
      if (l.cartonCount <= 0) {
        errors.add('عدد الكراتين يجب أن يكون أكبر من صفر: ${l.productName}');
      }
      if (l.totalNetWeight <= 0) {
        errors.add('الوزن الصافي يجب أن يكون أكبر من صفر: ${l.productName}');
      }
    }

    for (final m in materials) {
      final cost = (m['total'] as num?)?.toDouble();
      if (cost != null && cost < 0) {
        errors.add('تكلفة مادة سالبة: ${m['name'] ?? 'مادة'}');
      }
      final applyTo = (m['apply_to'] as String?) ?? 'all';
      if (applyTo.startsWith('line:')) {
        final idx = int.tryParse(applyTo.substring(5));
        if (idx == null || idx < 0 || idx >= lines.length) {
          errors.add('خط غير صالح للمادة: ${m['name'] ?? 'مادة'} → $applyTo');
        }
      }
    }

    for (final item in costItems) {
      final amount = (item['total_egp'] as num?)?.toDouble() ??
          (item['total'] as num?)?.toDouble() ??
          0;
      if (amount < 0) {
        errors.add('بند تكلفة سالب: ${item['name'] ?? 'بند'}');
      }
      final method = item['allocation_method'] as String?;
      if (method == null || method.isEmpty) {
        errors.add('طريقة التخصيص غير محددة: ${item['name'] ?? 'بند'}');
      }
    }

    return errors;
  }

  double _materialCost(Map<String, dynamic> m) {
    final qty = (m['used_qty'] as num?)?.toDouble() ?? 0;
    final unit = (m['unit_cost'] as num?)?.toDouble() ?? 0;
    final computed = qty * unit;
    if (computed > 0) return computed;
    return (m['total'] as num?)?.toDouble() ?? 0;
  }

  double _costItemAmount(Map<String, dynamic> item) {
    return (item['total_egp'] as num?)?.toDouble() ??
        (item['total'] as num?)?.toDouble() ??
        0;
  }

  int _maxIndex(List<double> values) {
    var maxI = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[maxI]) maxI = i;
    }
    return maxI;
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;
  double _round4(double v) => (v * 10000).roundToDouble() / 10000;
}
