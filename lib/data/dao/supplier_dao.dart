import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier_model.dart';
import '../models/stock_distribution_model.dart';
import '../services/currency_conversion_service.dart';
import '../../core/services/tenant_service.dart';
import '../../core/extensions/company_injection.dart';

class SupplierDao {
  final _client = Supabase.instance.client;

  // ── Code Generation ──

  Future<String> generateNextCode() async {
    try {
      final response =
          await _client.from('suppliers').select('code, supplier_code');
      int maxCode = 0;
      for (var row in response) {
        final codeStr = (row['code'] ?? row['supplier_code'])?.toString() ?? '';
        final num =
            int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxCode) maxCode = num;
      }
      return (maxCode + 1).toString().padLeft(5, '0');
    } catch (e) {
      return '00001';
    }
  }

  // ── Row mapping ──

  SupplierModel _fromRow(Map<String, dynamic> row) {
    return SupplierModel.fromMap(row);
  }

  // ── CRUD ──

  Future<List<SupplierModel>> getAll({int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('suppliers')
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    Map<String, double>? trueBalances;
    try {
      final res = await _client.rpc('get_supplier_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          trueBalances[r['supplier_id'].toString()] =
              (r['true_balance'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('get_supplier_true_balances RPC not found, falling back. $e');
    }

    final packingCosts =
        trueBalances == null ? await _fetchPackingCosts() : <String, double>{};

    return rows.map((row) {
      final id = row['id']?.toString() ?? '';
      if (trueBalances != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      } else {
        final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final outstandingBal =
            (row['outstanding_balance'] as num?)?.toDouble() ?? initialBal;
        final packingCost = packingCosts[id] ?? 0.0;
        row['computed_balance'] = outstandingBal + packingCost;
      }
      return _fromRow(row);
    }).toList();
  }

  // ── CRUD ──

  Future<List<StockDistributionEntry>> getStockDistribution(
      String productId) async {
    try {
      // 1. Fetch from purchase_invoice_items (standard purchases)
      final invoiceRows =
          await _client.from('purchase_invoice_items').select('''
            quantity,
            remaining_quantity,
            unit_cost,
            purchase_invoices!inner (
              suppliers!inner (
                supplier_code,
                name
              )
            )
          ''').eq('raw_material_id', productId.toString());

      // 2. Fetch from stock_batches (crop purchases)
      final batchRows = await _client
          .from('stock_batches')
          .select('''
            quantity,
            remaining_quantity,
            purchase_cost,
            suppliers!inner (
              supplier_code,
              name
            )
          ''')
          .eq('product_id', productId.toString())
          .like('batch_number', 'G-%');

      final Map<String, _AggSupplier> grouped = {};

      // Process invoice items
      for (final row in invoiceRows) {
        final inv = row['purchase_invoices'] as Map<String, dynamic>?;
        final supp = inv?['suppliers'] as Map<String, dynamic>?;
        final code = supp?['supplier_code']?.toString() ?? '';
        final name = supp?['name']?.toString() ?? code;
        final qty = (row['remaining_quantity'] as num?)?.toDouble() ??
            (row['quantity'] as num?)?.toDouble() ??
            0.0;
        final cost = (row['unit_cost'] as num?)?.toDouble() ?? 0.0;

        grouped.putIfAbsent(code, () => _AggSupplier(name: name));
        grouped[code]!.add(qty, cost);
      }

      // Process crop purchase batches (starting with G-)
      for (final row in batchRows) {
        final supp = row['suppliers'] as Map<String, dynamic>?;
        final code = supp?['supplier_code']?.toString() ?? '';
        final name = supp?['name']?.toString() ?? code;
        final qty = (row['remaining_quantity'] as num?)?.toDouble() ??
            (row['quantity'] as num?)?.toDouble() ??
            0.0;
        final originalQty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
        final totalCost = (row['purchase_cost'] as num?)?.toDouble() ?? 0.0;
        final unitCost = originalQty > 0 ? totalCost / originalQty : 0.0;

        grouped.putIfAbsent(code, () => _AggSupplier(name: name));
        grouped[code]!.add(qty, unitCost);
      }

      return grouped.entries.map((e) {
        final agg = e.value;
        return StockDistributionEntry(
          supplierName: agg.name,
          supplierCode: e.key,
          totalQuantity: agg.totalQty,
          totalCost: agg.totalCost,
          unitCost: agg.totalQty > 0 ? agg.totalCost / agg.totalQty : 0.0,
        );
      }).toList();
    } catch (e) {
      debugPrint('SupplierDao.getStockDistribution error: $e');
      return [];
    }
  }

  Future<List<SupplierModel>> search(String query,
      {int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('suppliers')
        .select()
        .or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%')
        .order('name')
        .range(offset, offset + limit - 1);

    Map<String, double>? trueBalances;
    try {
      final res = await _client.rpc('get_supplier_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          trueBalances[r['supplier_id'].toString()] =
              (r['true_balance'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('get_supplier_true_balances RPC not found, falling back. $e');
    }

    final packingCosts =
        trueBalances == null ? await _fetchPackingCosts() : <String, double>{};

    return rows.map((row) {
      final id = row['id']?.toString() ?? '';
      if (trueBalances != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      } else {
        final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final outstandingBal =
            (row['outstanding_balance'] as num?)?.toDouble() ?? initialBal;
        final packingCost = packingCosts[id] ?? 0.0;
        row['computed_balance'] = outstandingBal + packingCost;
      }
      return _fromRow(row);
    }).toList();
  }

  Future<SupplierModel?> getByCode(String code) async {
    final row =
        await _client.from('suppliers').select().eq('code', code).maybeSingle();
    if (row == null) return null;

    final id = row['id']?.toString() ?? '';

    try {
      final res = await _client.rpc('get_supplier_true_balances');
      if (res is List) {
        for (final r in res) {
          if (r['supplier_id'].toString() == id) {
            row['computed_balance'] = (r['true_balance'] as num).toDouble();
            return _fromRow(row);
          }
        }
      }
    } catch (e) {
      debugPrint('get_supplier_true_balances RPC not found, falling back. $e');
    }

    final packingCosts = await _fetchPackingCosts();
    final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
    final outstandingBal =
        (row['outstanding_balance'] as num?)?.toDouble() ?? initialBal;
    final packingCost = packingCosts[id] ?? 0.0;
    row['computed_balance'] = outstandingBal + packingCost;
    return _fromRow(row);
  }

  Future<void> insert(SupplierModel supplier) async {
    final data = supplier.toInsertMap();

    data['initial_balance_snapshot'] =
        (await CurrencyConversionService.instance.createSnapshotFromDb(
      currency: supplier.currency,
      amount: supplier.initialBalance,
    ))
            .toJson();
    await _client.from('suppliers').insert(data.withCompanyId());
  }

  Future<void> update(SupplierModel supplier) async {
    final data = supplier.toInsertMap();

    data['initial_balance_snapshot'] =
        (await CurrencyConversionService.instance.createSnapshotFromDb(
      currency: supplier.currency,
      amount: supplier.outstandingBalance,
    ))
            .toJson();
    await _client
        .from('suppliers')
        .update(data)
        .eq('id', supplier.id!)
        .eq('company_id', TenantService().tenantId!);
  }

  Future<void> delete(String supplierCode) async {
    await _client
        .from('suppliers')
        .delete()
        .eq('code', supplierCode); // ✅ FIX: was 'supplier_code'
  }

  Future<int> getCount() async {
    final response =
        await _client.from('suppliers').select().count(CountOption.exact);
    return response.count;
  }

  /// Fetch packing cost items from ledger_entries grouped by supplier_id.
  /// These are costs from packing order cost items that increase what we owe the supplier.
  Future<Map<String, double>> _fetchPackingCosts() async {
    try {
      final rows = await _client
          .from('ledger_entries')
          .select('entity_id, amount')
          .eq('entity_type', 'supplier')
          .eq('reference_type', 'packing_cost_item')
          .limit(5000);

      final map = <String, double>{};
      for (final row in rows) {
        final sid = row['entity_id']?.toString() ?? '';
        final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        if (sid.isNotEmpty && amt > 0) {
          map[sid] = (map[sid] ?? 0.0) + amt;
        }
      }
      return map;
    } catch (e) {
      debugPrint('SupplierDao._fetchPackingCosts error: $e');
      return {};
    }
  }

  Future<List<SupplierModel>> getAllSuppliers() async {
    final data =
        await _client.from('suppliers').select().order('name').limit(500);

    Map<String, double>? trueBalances;
    try {
      final res = await _client.rpc('get_supplier_true_balances');
      if (res is List) {
        trueBalances = {};
        for (final r in res) {
          trueBalances[r['supplier_id'].toString()] =
              (r['true_balance'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('get_supplier_true_balances RPC not found, falling back. $e');
    }

    if (trueBalances != null) {
      for (final row in data) {
        final id = row['id']?.toString() ?? '';
        if (trueBalances.containsKey(id)) {
          row['computed_balance'] = trueBalances[id];
        }
      }
    }

    return data.map(_fromRow).toList();
  }

  Future<Map<String, dynamic>> multiInvoicePayment({
    required String sourceType,
    required int sourceId,
    required double amount,
    required String currency,
    required String supplierId,
    required String description,
    required String notes,
    int? expenseAccountId,
  }) async {
    try {
      final response = await _client.rpc('rpc_supplier_multi_payment', params: {
        'p_source_type': sourceType,
        'p_source_id': sourceId,
        'p_currency': currency,
        'p_amount': amount,
        'p_supplier_id': supplierId,
        'p_description': description,
        'p_notes': notes,
        'p_expense_account_id': expenseAccountId,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('Error in multiInvoicePayment: $e');
      rethrow;
    }
  }
}

/// Helper for in-memory supplier aggregation in getStockDistribution.
class _AggSupplier {
  final String name;
  double totalQty = 0.0;
  double totalCost = 0.0;
  _AggSupplier({required this.name});
  void add(double qty, double cost) {
    totalQty += qty;
    totalCost += qty * cost;
  }
}
