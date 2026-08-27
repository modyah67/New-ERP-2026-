import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier_model.dart';
import '../models/stock_distribution_model.dart';
import '../../core/services/tenant_service.dart';

class SupplierRepository {
  final _client = Supabase.instance.client;

  Future<String> generateNextCode() async {
    try {
      final companyId = TenantService().tenantId;
      final data = await _client.rpc('get_next_entity_account_code', params: {
        'p_entity_type': 'supplier',
        'p_company_id': companyId,
      });
      return data?.toString() ?? '21001';
    } catch (e) {
      return '21001';
    }
  }

  SupplierModel _fromRow(Map<String, dynamic> row) {
    return SupplierModel.fromMap(row);
  }

  Future<List<SupplierModel>> getAll({int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('suppliers')
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    final balances = await _fetchSupplierBalances();
    return rows.map((row) {
      final id = row['id'];
      final invoiceTotal = id != null ? balances[id.toString()] ?? 0.0 : 0.0;
      final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
      row['computed_balance'] = initialBal + invoiceTotal;
      return _fromRow(row);
    }).toList();
  }

  Future<Map<String, double>> _fetchSupplierBalances() async {
    try {
      final Map<String, double> result = {};

      // 1. Purchase invoice remaining amounts
      final invoiceRows = await _client
          .from('purchase_invoices')
          .select('supplier_id, remaining_amount');
      for (final row in invoiceRows) {
        final sid = row['supplier_id']?.toString() ?? '';
        final amt = (row['remaining_amount'] as num?)?.toDouble() ?? 0.0;
        if (sid.isNotEmpty && amt > 0) {
          result[sid] = (result[sid] ?? 0.0) + amt;
        }
      }

      // 2. Harvest lot receipts (payable to supplier)
      final lotRows = await _client
          .from('lot_receipts')
          .select('supplier_id, total_fruit_cost')
          .gt('total_fruit_cost', 0);
      for (final row in lotRows) {
        final sid = row['supplier_id']?.toString() ?? '';
        final amt = (row['total_fruit_cost'] as num?)?.toDouble() ?? 0.0;
        if (sid.isNotEmpty && amt > 0) {
          result[sid] = (result[sid] ?? 0.0) + amt;
        }
      }

      // 3. Ledger entries for supplier (expenses/payments/reversals)
      //    lot_receipt entries already counted from lot_receipts above — skip
      final ledgerRows = await _client
          .from('ledger_entries')
          .select('entity_id, amount, reference_type')
          .eq('entity_type', 'supplier');
      for (final row in ledgerRows) {
        final sid = row['entity_id']?.toString() ?? '';
        final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        final refType = row['reference_type']?.toString() ?? '';
        if (sid.isEmpty) continue;
        if (refType == 'lot_receipt') {
          continue;
        } else if (refType == 'reversal' || refType == 'packing_cost_item') {
          result[sid] = (result[sid] ?? 0.0) + amt;
        } else {
          if (amt > 0) {
            result[sid] = (result[sid] ?? 0.0) - amt;
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('SupplierRepository._fetchSupplierBalances error: $e');
      return {};
    }
  }

  Future<List<StockDistributionEntry>> getStockDistribution(String productId) async {
    try {
      final invoiceRows = await _client
          .from('purchase_invoice_items')
          .select('''
            quantity,
            unit_cost,
            purchase_invoices!inner (
              suppliers!inner (
                supplier_code,
                name
              )
            )
          ''')
          .eq('raw_material_id', productId.toString());

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

      for (final row in invoiceRows) {
        final inv = row['purchase_invoices'] as Map<String, dynamic>?;
        final supp = inv?['suppliers'] as Map<String, dynamic>?;
        final code = supp?['supplier_code']?.toString() ?? '';
        final name = supp?['name']?.toString() ?? code;
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0.0;
        final cost = (row['unit_cost'] as num?)?.toDouble() ?? 0.0;

        grouped.putIfAbsent(code, () => _AggSupplier(name: name));
        grouped[code]!.add(qty, cost);
      }

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
      debugPrint('SupplierRepository.getStockDistribution error: $e');
      return [];
    }
  }

  Future<List<SupplierModel>> search(String query, {int limit = 50, int offset = 0}) async {
    final rows = await _client
        .from('suppliers')
        .select()
        .or('name.ilike.%$query%,supplier_code.ilike.%$query%,phone.ilike.%$query%')
        .order('name')
        .range(offset, offset + limit - 1);

    final balances = await _fetchSupplierBalances();
    return rows.map((row) {
      final id = row['id'];
      final invoiceTotal = id != null ? balances[id.toString()] ?? 0.0 : 0.0;
      final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
      row['computed_balance'] = initialBal + invoiceTotal;
      return _fromRow(row);
    }).toList();
  }

  Future<SupplierModel?> getByCode(String code) async {
    final row = await _client
        .from('suppliers')
        .select()
        .eq('supplier_code', code)
        .maybeSingle();
    if (row == null) return null;
    final balances = await _fetchSupplierBalances();
    final id = row['id'];
    final invoiceTotal = id != null ? balances[id.toString()] ?? 0.0 : 0.0;
    final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
    row['computed_balance'] = initialBal + invoiceTotal;
    return _fromRow(row);
  }

  Future<void> insert(SupplierModel supplier) async {
    await _client.from('suppliers').insert(supplier.toInsertMap());
  }

  Future<void> update(SupplierModel supplier) async {
    await _client
        .from('suppliers')
        .update(supplier.toInsertMap())
        .eq('supplier_code', supplier.supplierCode);
  }

  Future<void> delete(String supplierCode) async {
    await _client
        .from('suppliers')
        .delete()
        .eq('supplier_code', supplierCode);
  }

  Future<int> getCount() async {
    final response =
        await _client.from('suppliers').select().count(CountOption.exact);
    return response.count;
  }

  Future<List<SupplierModel>> getAllSuppliers() async {
    final data = await _client.from('suppliers').select().order('name');
    final balances = await _fetchSupplierBalances();
    return data.map((row) {
      final id = row['id'];
      final invoiceTotal = id != null ? balances[id.toString()] ?? 0.0 : 0.0;
      final initialBal = (row['initial_balance'] as num?)?.toDouble() ?? 0.0;
      row['computed_balance'] = initialBal + invoiceTotal;
      return _fromRow(row);
    }).toList();
  }
}

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
