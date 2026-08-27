import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Comprehensive shipment deletion with defensive checks, verification, and
/// detailed logging.  Handles every known table that references a shipment.
///
/// Does NOT touch the `transactions` table because the production schema does
/// not expose a compatible `reference_type` / `reference_id` interface from
/// client-side code.
class ShipmentDeletionService {
  final _client = Supabase.instance.client;

  // ── Known child tables (shipment_id FK) ──
  static const _childTables = <_ChildTable>[
    _ChildTable('export_shipment_items', 'shipment_id'),
    _ChildTable('shipment_cost_breakdown', 'shipment_id'),
    _ChildTable('shipment_cost_allocations', 'shipment_id'),
    _ChildTable('shipment_recipe_snapshots', 'shipment_id'),
    _ChildTable('supplier_settlements', 'shipment_id'),
    _ChildTable('prep_center_cost_items', 'shipment_id'),
  ];

  /// Performs the complete, permanent deletion of shipment [shipmentId].
  ///
  /// Steps (all idempotent and independently caught):
  ///   1. SET NULL export_shipment_id on packing_orders
  ///   2. DELETE child rows from every known FK table
  ///   3. DELETE the export_shipment row itself
  ///   4. Verify zero remaining references
  ///
  /// Throws if the final shipment-level delete fails.
  Future<ShipmentDeletionReport> delete(int shipmentId) async {
    final steps = <StepResult>[];
    final errors = <String>[];

    debugPrint('══════════════════════════════════════════════');
    debugPrint('ShipmentDeletionService.delete: shipment_id=$shipmentId');

    // ── Step 0: Clear packing_orders ref (SET NULL) ──
    try {
      final countBefore =
          await _countWhere('packing_orders', 'export_shipment_id', shipmentId);
      if (countBefore > 0) {
        await _client
            .from('packing_orders')
            .update({'export_shipment_id': null})
            .eq('export_shipment_id', shipmentId);
        debugPrint('  packing_orders unlinked: $countBefore');
      }
      steps.add(StepResult('packing_orders', countBefore, countBefore));
    } catch (e) {
      debugPrint('  packing_orders unlink failed: $e');
      errors.add('packing_orders: $e');
    }

    // ── Step 2: Delete child rows from every FK table ──
    for (final child in _childTables) {
      try {
        final before = await _countWhere(child.table, child.fk, shipmentId);
        int deleted = 0;
        if (before > 0) {
          final result = await _client
              .from(child.table)
              .delete()
              .eq(child.fk, shipmentId)
              .select();
          deleted = (result as List).length;
        }
        debugPrint('  ${child.table}: $deleted / $before rows deleted');
        steps.add(StepResult(child.table, before, deleted));
      } catch (e) {
        debugPrint('  ${child.table} delete failed: $e');
        steps.add(StepResult(child.table, -1, -1));
        errors.add('${child.table}: $e');
      }
    }

    // ── Step 3: Delete the shipment row itself ──
    bool shipmentDeleted = false;
    try {
      final result = await _client
          .from('export_shipments')
          .delete()
          .eq('id', shipmentId)
          .select();
      shipmentDeleted = (result as List).isNotEmpty;
      debugPrint('  export_shipments deleted: $shipmentDeleted');
      steps.add(StepResult(
          'export_shipments', shipmentDeleted ? 1 : 0, shipmentDeleted ? 1 : 0));
    } catch (e) {
      debugPrint('  export_shipments delete failed: $e');
      errors.add('export_shipments: $e');
      steps.add(StepResult('export_shipments', -1, -1));
    }

    // ── Step 4: Verify zero remaining references ──
    final remaining = <String, int>{};
    for (final child in _childTables) {
      try {
        final n = await _countWhere(child.table, child.fk, shipmentId);
        if (n > 0) remaining[child.table] = n;
      } catch (_) {}
    }
    try {
      final n = await _countWhere(
          'packing_orders', 'export_shipment_id', shipmentId);
      if (n > 0) remaining['packing_orders'] = n;
    } catch (_) {}

    final report = ShipmentDeletionReport(
      shipmentId: shipmentId,
      steps: steps,
      errors: errors,
      remainingRefs: remaining,
      success: errors.isEmpty && shipmentDeleted,
    );

    debugPrint('── Verdict ──────────────────────────────────');
    debugPrint('  success: ${report.success}');
    for (final s in steps) {
      if (s.rowsDeleted >= 0) {
        debugPrint('  ${s.table}: ${s.rowsDeleted} / ${s.rowsBefore}');
      } else {
        debugPrint('  ${s.table}: ERROR');
      }
    }
    if (remaining.isNotEmpty) {
      debugPrint('  REMAINING REFERENCES: $remaining');
    }
    if (errors.isNotEmpty) {
      debugPrint('  ERRORS: $errors');
    }
    debugPrint('══════════════════════════════════════════════');

    if (!report.success && errors.isNotEmpty) {
      throw Exception(
          'Shipment deletion failed. Errors: ${errors.join('; ')}');
    }
    return report;
  }

  Future<int> _countWhere(
      String table, String column, int value) async {
    try {
      final data = await _client
          .from(table)
          .select('id')
          .eq(column, value);
      return (data as List).length;
    } catch (e) {
      debugPrint('  COUNT $table.$column=$value failed: $e');
      return 0;
    }
  }
}

/// Result of a single deletion step.
class StepResult {
  final String table;
  final int rowsBefore;
  final int rowsDeleted;
  const StepResult(this.table, this.rowsBefore, this.rowsDeleted);
}

/// Report of a complete shipment deletion.
class ShipmentDeletionReport {
  final int shipmentId;
  final List<StepResult> steps;
  final List<String> errors;
  final Map<String, int> remainingRefs;
  final bool success;

  const ShipmentDeletionReport({
    required this.shipmentId,
    required this.steps,
    required this.errors,
    required this.remainingRefs,
    required this.success,
  });
}

class _ChildTable {
  final String table;
  final String fk;
  const _ChildTable(this.table, this.fk);
}
