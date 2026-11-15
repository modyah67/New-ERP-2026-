import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transport_supplier_model.dart';
import '../models/transport_transaction_model.dart';
import '../models/transport_batch_model.dart';


class TransportSupplierDao {
  final _client = Supabase.instance.client;
  static const _table = 'transport_suppliers';
  static const _transactionsTable = 'transport_transactions';

  Future<String> generateNextCode() async {
    try {
      const minRange = 60000;
      const maxRange = 70000; // 60000 to 69999
      final response = await _client.from(_table).select('code');
      int maxCode = minRange - 1;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num =
            int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num >= minRange && num < maxRange && num > maxCode) maxCode = num;
      }
      if (maxCode < minRange) {
        return minRange.toString();
      }
      return (maxCode + 1).toString();
    } catch (e) {
      return '60000';
    }
  }

  /// Check if a transport supplier code already exists in the database to prevent collisions
  Future<bool> checkCodeExists(String code, {int? excludeId}) async {
    try {
      final clean = code.trim();
      var query = _client.from(_table).select('id').eq('code', clean);
      if (excludeId != null) {
        query = query.neq('id', excludeId);
      }
      final res = await query.limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  TransportSupplierModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    double dbl(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

    return TransportSupplierModel(
      id: intVal(row['id']),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      phone: str(row['phone']) ?? '',
      email: str(row['email']) ?? '',
      accountId: intVal(row['account_id']),
      balance: dbl(row['computed_balance'] ?? row['balance']),
      truckBalance: dbl(row['computed_truck_balance'] ?? row['truck_balance']),
      initialBalance: dbl(row['initial_balance']),
      initialTruckBalance: dbl(row['initial_truck_balance']),
      initialBalanceDirection: str(row['initial_balance_direction']) ?? 'CREDIT',
      notes: str(row['notes']),
      companyId: str(row['company_id']),
      createdAt: str(row['created_at']) ?? '',
      updatedAt: str(row['updated_at']),
    );
  }

  Future<List<TransportSupplierModel>> getAll(
      {int limit = 100, int offset = 0}) async {
    final rows = await _client
        .from(_table)
        .select()
        .order('name')
        .range(offset, offset + limit - 1);

    Map<int, double>? trueBalances;
    Map<int, double>? truckBalances;
    try {
      final res = await _client.rpc('get_transport_supplier_true_balances');
      if (res is List) {
        trueBalances = {};
        truckBalances = {};
        for (final r in res) {
          final id = (r['supplier_id'] as num?)?.toInt();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
            truckBalances[id] = (r['truck_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('get_transport_supplier_true_balances RPC error: $e');
    }

    return rows.map((row) {
      final id = (row['id'] as num?)?.toInt();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      if (truckBalances != null && id != null && truckBalances.containsKey(id)) {
        row['computed_truck_balance'] = truckBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  Future<TransportSupplierModel?> getById(int id) async {
    final data =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (data == null) return null;

    try {
      final res = await _client.rpc('get_transport_supplier_true_balances');
      if (res is List) {
        for (final r in res) {
          if ((r['supplier_id'] as num?)?.toInt() == id) {
            data['computed_balance'] =
                (r['true_balance'] as num?)?.toDouble() ?? 0.0;
            data['computed_truck_balance'] =
                (r['truck_balance'] as num?)?.toDouble() ?? 0.0;
            break;
          }
        }
      }
    } catch (_) {}

    return _fromRow(data);
  }

  Future<List<TransportSupplierModel>> search(String query,
      {int limit = 50, int offset = 0}) async {
    var builder = _client.from(_table).select();

    if (query.isNotEmpty) {
      final asInt = int.tryParse(query.trim());
      if (asInt != null) {
        builder = builder.or(
            'id.eq.$asInt,name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');
      } else {
        builder = builder.or(
            'name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');
      }
    }

    final rows = await builder.order('name').range(offset, offset + limit - 1);

    Map<int, double>? trueBalances;
    Map<int, double>? truckBalances;
    try {
      final res = await _client.rpc('get_transport_supplier_true_balances');
      if (res is List) {
        trueBalances = {};
        truckBalances = {};
        for (final r in res) {
          final id = (r['supplier_id'] as num?)?.toInt();
          if (id != null) {
            trueBalances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
            truckBalances[id] = (r['truck_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('get_transport_supplier_true_balances search error: $e');
    }

    return rows.map((row) {
      final id = (row['id'] as num?)?.toInt();
      if (trueBalances != null && id != null && trueBalances.containsKey(id)) {
        row['computed_balance'] = trueBalances[id];
      }
      if (truckBalances != null && id != null && truckBalances.containsKey(id)) {
        row['computed_truck_balance'] = truckBalances[id];
      }
      return _fromRow(row);
    }).toList();
  }

  /// Resolves the master Level-5 summary account ID directly (21111: موردي النقل والسيارات)
  Future<int?> resolveMasterAccountId() async {
    try {
      final res = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '21111')
          .limit(1)
          .maybeSingle();
      return (res?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<TransportSupplierModel> create(TransportSupplierModel model) async {
    String code = model.code;
    if (code.isEmpty) {
      code = await generateNextCode();
    }

    final masterAccountId = model.accountId ?? await resolveMasterAccountId();

    final data = {
      'code': code,
      'name': model.name,
      'phone': model.phone,
      'email': model.email,
      'initial_balance': model.initialBalance,
      'initial_balance_direction': model.initialBalanceDirection,
      'initial_truck_balance': model.initialTruckBalance,
      'balance': model.initialBalanceDirection == 'CREDIT'
          ? model.initialBalance
          : -model.initialBalance,
      'truck_balance': model.initialTruckBalance,
      'notes': model.notes,
      if (masterAccountId != null) 'account_id': masterAccountId,
    };

    final inserted =
        await _client.from(_table).insert(data).select().single();
    return _fromRow(inserted);
  }

  Future<TransportSupplierModel> update(TransportSupplierModel model) async {
    if (model.id == null) {
      throw Exception('Cannot update transport supplier without ID');
    }

    final data = {
      'code': model.code,
      'name': model.name,
      'phone': model.phone,
      'email': model.email,
      'initial_balance': model.initialBalance,
      'initial_balance_direction': model.initialBalanceDirection,
      'initial_truck_balance': model.initialTruckBalance,
      'notes': model.notes,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final updated = await _client
        .from(_table)
        .update(data)
        .eq('id', model.id!)
        .select()
        .single();
    return _fromRow(updated);
  }

  Future<void> delete(int id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  Future<List<TransportTransactionModel>> getTransactions(
    int supplierId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var builder = _client
        .from(_transactionsTable)
        .select()
        .eq('supplier_id', supplierId);

    if (fromDate != null) {
      builder = builder.gte(
          'date', fromDate.toIso8601String().substring(0, 10));
    }
    if (toDate != null) {
      builder =
          builder.lte('date', toDate.toIso8601String().substring(0, 10));
    }

    final rows = await builder
        .order('date', ascending: true)
        .order('id', ascending: true);

    return rows.map((r) => TransportTransactionModel.fromMap(r)).toList();
  }

  Future<Map<String, dynamic>> recordPayment({
    required int supplierId,
    required String sourceType, // 'treasury' or 'bank'
    required int sourceId,
    required double amount,
    DateTime? date,
    String? description,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'rpc_pay_transport_supplier',
      params: {
        'p_supplier_id': supplierId,
        'p_source_type': sourceType,
        'p_source_id': sourceId,
        'p_amount': amount,
        'p_date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
        'p_description': description,
        'p_notes': notes,
      },
    );

    if (response is Map<String, dynamic>) {
      return response;
    }
    return {'success': true, 'data': response};
  }

  Future<Map<String, dynamic>> recordInvoice({
    required int supplierId,
    required double amount,
    num numberOfTrucks = 1,
    String? routeFrom,
    String? routeTo,
    DateTime? date,
    String? description,
    int? expenseAccountId,
    String? referenceNumber,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'rpc_add_transport_invoice',
      params: {
        'p_supplier_id': supplierId,
        'p_amount': amount,
        'p_number_of_trucks': numberOfTrucks,
        'p_truck_count': numberOfTrucks,
        if (routeFrom != null && routeFrom.isNotEmpty) 'p_route_from': routeFrom,
        if (routeTo != null && routeTo.isNotEmpty) 'p_route_to': routeTo,
        'p_date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
        'p_description': description,
        if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
        if (referenceNumber != null) 'p_reference_number': referenceNumber,
        if (notes != null) 'p_notes': notes,
      },
    );

    if (response is Map<String, dynamic>) {
      return response;
    }
    return {'success': true, 'data': response};
  }

  /// Fetch distinct transport entitlement batches (دفعات استحقاقات النقل) for a supplier.
  /// Calculates total trucks, consumed trucks, and remaining available trucks for each batch.
  Future<List<TransportBatchModel>> getEntitlementBatches(
    int supplierId, {
    int? excludePackingOrderId,
    bool onlyAvailable = false,
  }) async {
    try {
      // 1. Fetch supplier for initial truck balance
      final suppRes = await _client
          .from(_table)
          .select('id, name, initial_balance, initial_truck_balance, created_at')
          .eq('id', supplierId)
          .maybeSingle();

      // 2. Fetch invoice and opening_balance transactions
      final invoiceRows = await _client
          .from(_transactionsTable)
          .select()
          .eq('supplier_id', supplierId)
          .inFilter('type', ['invoice', 'opening_balance'])
          .order('date', ascending: true)
          .order('id', ascending: true);

      // 3. Fetch consumptions for this supplier
      final consumptionRows = await _client
          .from(_transactionsTable)
          .select()
          .eq('supplier_id', supplierId)
          .inFilter('type', ['packing_consumption', 'packing_order_consumption']);

      final Map<int, double> batchConsumptions = {};
      double unallocatedConsumptions = 0.0;

      for (final c in consumptionRows) {
        if (excludePackingOrderId != null &&
            c['reference_id']?.toString() == excludePackingOrderId.toString()) {
          continue;
        }

        final truckCount = (c['truck_count'] as num?)?.toDouble() ?? 0.0;
        if (truckCount <= 0) continue;

        final notesStr = c['notes']?.toString() ?? '';
        final descStr = c['description']?.toString() ?? '';
        int? linkedBatchId;

        // Try extracting batch_id from notes JSON
        try {
          if (notesStr.contains('"batch_id"')) {
            final match =
                RegExp(r'"batch_id"\s*:\s*(-?\d+)').firstMatch(notesStr);
            if (match != null) {
              linkedBatchId = int.tryParse(match.group(1)!);
            }
          }
        } catch (_) {}

        // Try extracting batch_id from text (e.g. "دفعة #1" or "batch_id: 1")
        if (linkedBatchId == null) {
          final match = RegExp(r'(?:دفعة\s*#|batch_id\s*:\s*)(-?\d+)')
              .firstMatch('$notesStr $descStr');
          if (match != null) {
            linkedBatchId = int.tryParse(match.group(1)!);
          }
        }

        if (linkedBatchId != null) {
          batchConsumptions[linkedBatchId] =
              (batchConsumptions[linkedBatchId] ?? 0.0) + truckCount;
        } else {
          unallocatedConsumptions += truckCount;
        }
      }

      final List<TransportBatchModel> batches = [];

      // Check if synthetic initial balance batch should be created
      final initialTrucks =
          (suppRes?['initial_truck_balance'] as num?)?.toDouble() ?? 0.0;
      final initialBal =
          (suppRes?['initial_balance'] as num?)?.toDouble() ?? 0.0;
      final hasOpeningTx = invoiceRows.any((r) => r['type'] == 'opening_balance');

      if (initialTrucks > 0 && !hasOpeningTx) {
        double consumed = batchConsumptions[-1] ?? 0.0;
        if (unallocatedConsumptions > 0) {
          final deduct = unallocatedConsumptions.clamp(
              0.0, (initialTrucks - consumed).clamp(0.0, double.infinity));
          consumed += deduct;
          unallocatedConsumptions -= deduct;
        }
        final available =
            (initialTrucks - consumed).clamp(0.0, double.infinity);
        final costPerTruck =
            initialTrucks > 0 ? (initialBal / initialTrucks) : 0.0;

        batches.add(TransportBatchModel(
          id: -1,
          supplierId: supplierId,
          date: suppRes?['created_at']?.toString().substring(0, 10) ?? '',
          description: 'رصيد افتتاحي (أول المدة)',
          referenceId: 'رصيد أول المدة',
          totalAmount: initialBal,
          totalTrucks: initialTrucks,
          consumedTrucks: consumed,
          availableTrucks: available,
          costPerTruck: costPerTruck,
          isOpeningBalance: true,
        ));
      }

      // Add regular invoice / opening_balance batches
      for (final r in invoiceRows) {
        final bId = (r['id'] as num).toInt();
        final totalTrucks = (r['truck_count'] as num?)?.toDouble() ?? 1.0;
        final totalAmount = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final costPerTruck =
            totalTrucks > 0 ? (totalAmount / totalTrucks) : 0.0;

        double consumed = batchConsumptions[bId] ?? 0.0;
        if (unallocatedConsumptions > 0) {
          final deduct = unallocatedConsumptions.clamp(
              0.0, (totalTrucks - consumed).clamp(0.0, double.infinity));
          consumed += deduct;
          unallocatedConsumptions -= deduct;
        }
        final available = (totalTrucks - consumed).clamp(0.0, double.infinity);

        batches.add(TransportBatchModel(
          id: bId,
          supplierId: supplierId,
          date: r['date']?.toString() ?? '',
          description: r['description']?.toString() ?? 'استحقاق نقل',
          referenceId: r['reference_id']?.toString(),
          routeFrom: r['route_from']?.toString(),
          routeTo: r['route_to']?.toString(),
          totalAmount: totalAmount,
          totalTrucks: totalTrucks,
          consumedTrucks: consumed,
          availableTrucks: available,
          costPerTruck: costPerTruck,
          isOpeningBalance: r['type'] == 'opening_balance',
        ));
      }

      if (onlyAvailable) {
        return batches.where((b) => b.availableTrucks > 0.0001).toList();
      }
      return batches;
    } catch (e) {
      debugPrint('Error fetching transport entitlement batches: $e');
      return [];
    }
  }
}
