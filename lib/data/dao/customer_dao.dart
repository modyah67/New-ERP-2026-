import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_model.dart';
import '../services/currency_conversion_service.dart';
import '../services/opening_balance_gl_sync_service.dart';
import '../../core/extensions/company_injection.dart';
import '../../core/services/tenant_service.dart';

class CustomerDao {
  final _client = Supabase.instance.client;

  // ── Code Generation ──

  Future<String> generateNextCode() async {
    try {
      const minRange = 12000;
      const maxRange = 20000; // 12000 to 19999
      final response = await _client.from('customers').select('code');
      int maxCode = minRange - 1;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num >= minRange && num < maxRange && num > maxCode) {
          maxCode = num;
        }
      }
      if (maxCode < minRange) {
        return minRange.toString();
      }
      return (maxCode + 1).toString();
    } catch (e) {
      return '12000';
    }
  }

  /// Check if a customer code already exists in the database to prevent collisions
  Future<bool> checkCodeExists(String code, {String? excludeId}) async {
    try {
      final clean = code.trim();
      var query = _client.from('customers').select('id').eq('code', clean);
      if (excludeId != null && excludeId.isNotEmpty) {
        query = query.neq('id', excludeId);
      }
      final res = await query.limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Helper ──

  List<Map<String, dynamic>> _parseAddresses(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((a) {
      if (a is! Map) return <String, dynamic>{};
      final map = Map<String, dynamic>.from(a);
      if (map.containsKey('address') && !map.containsKey('address_line_1')) {
        map['address_line_1'] = map['address'];
      }
      if (map.containsKey('label') && !map.containsKey('type')) {
        map['type'] = map['label'].toString().contains('مختصر') ? 'quick' : 'full';
      }
      return map;
    }).toList();
  }

  // ── Row mapping ──

  CustomerModel _fromRow(Map<String, dynamic> row) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return CustomerModel(
      id: str(row['id']),
      code: str(row['code']) ?? '',
      name: str(row['name']) ?? '',
      customerType: str(row['company_type']) ?? str(row['customer_type']) ?? 'export',
      accountId: intVal(row['account_id']),
      phone: str(row['phone']) ?? '',
      city: str(row['city']) ?? '',
      country: str(row['country']) ?? '',
      gmail: str(row['gmail']) ?? '',
      vatNumber: str(row['vat_no']) ?? '',
      eoriNo: str(row['eori_no']) ?? '',
      contactPersonName: str(row['contact_person_name']) ?? '',
      contactPersonPhone: str(row['contact_person_phone']) ?? '',
      contactPersonEmail: str(row['contact_person_email']) ?? '',
      addresses: _parseAddresses(row['addresses']),
      balance: numVal(row['balance'])?.toDouble() ?? 0.0,
      initialBalance: numVal(row['initial_balance'])?.toDouble() ?? 0.0,
      currency: str(row['currency']) ?? 'EGP',
      createdAt: str(row['created_at']) ?? '',
    );
  }

  // ── True Balances ──

  Future<Map<String, double>> fetchCustomerTrueBalances() async {
    // 1. Try RPC get_customer_true_balances
    try {
      final res = await _client.rpc('get_customer_true_balances');
      if (res is List) {
        final balances = <String, double>{};
        for (final r in res) {
          final id = r['customer_id']?.toString();
          if (id != null) {
            balances[id] = (r['true_balance'] as num?)?.toDouble() ?? 0.0;
          }
        }
        return balances;
      }
    } catch (e) {
      // Fall through to subledger calculation
    }

    // 2. Fallback in Dart: Calculate from subledger transactions
    try {
      final balances = <String, double>{};

      // A. Initial balances from customers
      final custRows = await _client
          .from('customers')
          .select('id, initial_balance, initial_balance_direction, currency');
      for (final c in custRows) {
        final id = c['id']?.toString();
        if (id == null) continue;
        final initBal = (c['initial_balance'] as num?)?.toDouble() ?? 0.0;
        final dir = (c['initial_balance_direction'] ?? 'DEBIT').toString().toUpperCase();
        balances[id] = (dir == 'CREDIT') ? -initBal : initBal;
      }

      // B. Export Shipments (Debits)
      try {
        final shipments = await _client
            .from('export_shipments')
            .select('customer_id, total_revenue_egp, total_revenue_foreign, discount_amount')
            .eq('is_confirmed', true)
            .neq('status', 'cancelled');
        for (final s in shipments) {
          final id = s['customer_id']?.toString();
          if (id != null) {
            final cust = custRows.firstWhere((c) => c['id']?.toString() == id, orElse: () => <String, dynamic>{});
            final custCur = cust['currency']?.toString() ?? 'EGP';
            final rev = custCur.toUpperCase() == 'EGP'
                ? (s['total_revenue_egp'] as num?)?.toDouble() ?? 0.0
                : (s['total_revenue_foreign'] ?? s['total_revenue_egp'] as num?)?.toDouble() ?? 0.0;
            final disc = (s['discount_amount'] as num?)?.toDouble() ?? 0.0;
            balances[id] = (balances[id] ?? 0.0) + (rev - disc);
          }
        }
      } catch (_) {}

      // C. Local Invoices (Debits)
      try {
        final invoices = await _client
            .from('invoices')
            .select('customer_id, total_amount')
            .inFilter('status', ['confirmed', 'paid']);
        for (final inv in invoices) {
          final id = inv['customer_id']?.toString();
          if (id != null) {
            final amt = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
            balances[id] = (balances[id] ?? 0.0) + amt;
          }
        }
      } catch (_) {}

      // D. Cheques (Incoming = Credit, Outgoing = Debit)
      try {
        final cheques = await _client
            .from('cheques')
            .select('counterparty_id, type, amount, status')
            .eq('counterparty_type', 'customer')
            .inFilter('status', ['pending', 'cleared', 'collected']);
        for (final ch in cheques) {
          final id = ch['counterparty_id']?.toString();
          if (id != null) {
            final amt = (ch['amount'] as num?)?.toDouble() ?? 0.0;
            final type = ch['type']?.toString();
            if (type == 'incoming') {
              balances[id] = (balances[id] ?? 0.0) - amt;
            } else if (type == 'outgoing') {
              balances[id] = (balances[id] ?? 0.0) + amt;
            }
          }
        }
      } catch (_) {}

      // E. Treasury Transactions (Incoming/Receive = Credit, Expense/Refund = Debit)
      try {
        final treasuryTxs = await _client
            .from('treasury_transactions')
            .select('customer_id, type, amount')
            .not('customer_id', 'is', null)
            .neq('status', 'draft');
        for (final tx in treasuryTxs) {
          final id = tx['customer_id']?.toString();
          if (id != null) {
            final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
            final type = tx['type']?.toString();
            final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
            balances[id] = (balances[id] ?? 0.0) + (isCredit ? -amt : amt);
          }
        }
      } catch (_) {}

      // F. Bank Transactions (Deposit = Credit, Withdraw = Debit)
      try {
        final bankTxs = await _client
            .from('bank_account_transactions')
            .select('entity_id, type, amount')
            .eq('entity_type', 'customer')
            .neq('status', 'draft');
        for (final tx in bankTxs) {
          final id = tx['entity_id']?.toString();
          if (id != null) {
            final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
            final type = tx['type']?.toString();
            final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
            balances[id] = (balances[id] ?? 0.0) + (isCredit ? -amt : amt);
          }
        }
      } catch (_) {}

      return balances;
    } catch (e) {
      return {};
    }
  }

  // ── CRUD ──

  Future<List<CustomerModel>> getAll({
    int limit = 50,
    int offset = 0,
    String? customerType,
  }) async {
    var query = _client.from('customers').select();
    if (customerType != null && customerType.isNotEmpty) {
      if (customerType == 'export') {
        query = query.neq('company_type', 'local');
      } else if (customerType == 'local') {
        query = query.eq('company_type', 'local');
      }
    }

    final data = await query
        .order('name')
        .range(offset, offset + limit - 1);

    final balances = await fetchCustomerTrueBalances();

    final list = data.map((row) {
      final id = row['id']?.toString();
      if (id != null && balances.containsKey(id)) {
        row['balance'] = balances[id];
      }
      return _fromRow(row);
    }).toList();

    if (customerType != null && customerType.isNotEmpty) {
      if (customerType == 'export') {
        return list.where((c) => c.customerType != 'local').toList();
      } else if (customerType == 'local') {
        return list.where((c) => c.customerType == 'local').toList();
      }
    }
    return list;
  }

  Future<List<CustomerModel>> search(
    String query, {
    int limit = 50,
    int offset = 0,
    String? customerType,
  }) async {
    var dbQuery = _client
        .from('customers')
        .select()
        .or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%');

    if (customerType != null && customerType.isNotEmpty) {
      if (customerType == 'export') {
        dbQuery = dbQuery.neq('company_type', 'local');
      } else if (customerType == 'local') {
        dbQuery = dbQuery.eq('company_type', 'local');
      }
    }

    final data = await dbQuery
        .order('name')
        .range(offset, offset + limit - 1);

    final balances = await fetchCustomerTrueBalances();

    final list = data.map((row) {
      final id = row['id']?.toString();
      if (id != null && balances.containsKey(id)) {
        row['balance'] = balances[id];
      }
      return _fromRow(row);
    }).toList();

    if (customerType != null && customerType.isNotEmpty) {
      if (customerType == 'export') {
        return list.where((c) => c.customerType != 'local').toList();
      } else if (customerType == 'local') {
        return list.where((c) => c.customerType == 'local').toList();
      }
    }
    return list;
  }

  Future<List<CustomerModel>> getExportCustomers({int limit = 100, int offset = 0}) async {
    return getAll(limit: limit, offset: offset, customerType: 'export');
  }

  Future<CustomerModel?> getById(String id) async {
    final data = await _client
        .from('customers')
        .select()
        .eq('id', int.tryParse(id) ?? id)
        .maybeSingle();
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data);
    final balances = await fetchCustomerTrueBalances();
    final rowId = map['id']?.toString();
    if (rowId != null && balances.containsKey(rowId)) {
      map['balance'] = balances[rowId];
    }
    return _fromRow(map);
  }

  /// Resolves the master Level-5 summary account ID directly:
  /// - Export -> 12511 ("عملاء تصدير")
  /// - Local  -> 12512 ("عملاء محلي")
  Future<int?> resolveMasterAccountId(String customerType) async {
    final cleanType = customerType.trim().toLowerCase();
    final targetCode = (cleanType == 'local' || cleanType == 'محلي') ? '12512' : '12511';
    final tenantId = TenantService().tenantId;

    try {
      var query = _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetCode);

      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.or('company_id.eq.$tenantId,company_id.is.null,company_id.eq.a0000000-0000-0000-0000-000000000001');
      }

      final res = await query.limit(1).maybeSingle();
      if (res != null && res['id'] != null) {
        return (res['id'] as num).toInt();
      }

      final fallback = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', targetCode)
          .limit(1)
          .maybeSingle();
      return (fallback?['id'] as num?)?.toInt();
    } catch (e) {
      return null;
    }
  }

  Future<String> insert(CustomerModel customer) async {
    final customerData = customer.toInsertMap();
    if (customer.addresses.isNotEmpty) {
      customerData['addresses'] = customer.addresses;
    }

    // Direct Master Account Binding (12511 for Export, 12512 for Local)
    if (customerData['account_id'] == null) {
      final masterId = await resolveMasterAccountId(customer.customerType);
      if (masterId != null) {
        customerData['account_id'] = masterId;
      }
    }

    customerData['initial_balance_snapshot'] = await CurrencyConversionService.instance.createSnapshotFromDb(
      currency: customer.currency,
      amount: customer.initialBalance,
    ).then((s) => s.toJson());

    final data = await _client
        .from('customers')
        .insert(customerData.withCompanyId())
        .select()
        .single();

    final newId = data['id'].toString();

    // Mirror opening balance to General Ledger (COA and Statements)
    try {
      await OpeningBalanceGlSyncService.instance.syncCustomerOpeningBalance(
        customerId: newId,
        customerName: customer.name,
        initialBalance: customer.initialBalance,
        currency: customer.currency,
        direction: customer.initialBalanceDirection,
        accountId: customerData['account_id'] as int?,
        companyId: customerData['company_id']?.toString(),
        customerType: customer.customerType,
      );
    } catch (e) {
      // Non-blocking: background trigger will also handle this if active
    }

    return newId;
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    final updateData = {
      'code': customer.code,
      'name': customer.name,
      'phone': customer.phone,
      'city': customer.city,
      'country': customer.country,
      'gmail': customer.gmail,
      'vat_no': customer.vatNumber,
      'eori_no': customer.eoriNo,
      'contact_person_name': customer.contactPersonName,
      'contact_person_phone': customer.contactPersonPhone,
      'contact_person_email': customer.contactPersonEmail,
      'balance': customer.balance,
      'initial_balance': customer.initialBalance,
      'initial_balance_direction': customer.initialBalanceDirection,
      'currency': customer.currency,
      'addresses': customer.addresses,
      'initial_balance_snapshot': (await CurrencyConversionService.instance.createSnapshotFromDb(
        currency: customer.currency,
        amount: customer.balance,
      )).toJson(),
    };

    await _client
        .from('customers')
        .update(updateData)
        .eq('id', int.tryParse(customer.id!) ?? customer.id!)
        .eq('company_id', TenantService().tenantId!);

    // Mirror opening balance to General Ledger (COA and Statements)
    try {
      await OpeningBalanceGlSyncService.instance.syncCustomerOpeningBalance(
        customerId: customer.id!,
        customerName: customer.name,
        initialBalance: customer.initialBalance,
        currency: customer.currency,
        direction: customer.initialBalanceDirection,
        accountId: customer.accountId,
        companyId: TenantService().tenantId,
        customerType: customer.customerType,
      );
    } catch (e) {
      // Non-blocking: background trigger will also handle this if active
    }
  }

  Future<void> updateBalance(String customerId, double newBalance) async {
    final row = await _client
        .from('customers')
        .select('currency')
        .eq('id', int.tryParse(customerId) ?? customerId)
        .maybeSingle();
    final currency = row?['currency'] as String? ?? 'EGP';
    await _client
        .from('customers')
        .update({
          'balance': newBalance,
          'initial_balance_snapshot': (await CurrencyConversionService.instance.createSnapshotFromDb(
            currency: currency,
            amount: newBalance,
          )).toJson(),
        })
        .eq('id', int.tryParse(customerId) ?? customerId)
        .eq('company_id', TenantService().tenantId!);
  }

  Future<void> adjustBalance(String customerId, double delta) async {
    final row = await _client
        .from('customers')
        .select('balance, currency')
        .eq('id', int.tryParse(customerId) ?? customerId)
        .single();
    final current = (row['balance'] as num?)?.toDouble() ?? 0.0;
    final currency = row['currency'] as String? ?? 'EGP';
    await _client
        .from('customers')
        .update({
          'balance': current + delta,
          'initial_balance_snapshot': (await CurrencyConversionService.instance.createSnapshotFromDb(
            currency: currency,
            amount: current + delta,
          )).toJson(),
        })
        .eq('id', int.tryParse(customerId) ?? customerId)
        .eq('company_id', TenantService().tenantId!);
  }

  Future<void> delete(String id) async {
    await _client.from('customers').delete().eq('id', int.tryParse(id) ?? id);
  }

  /// Deletes a customer AFTER server-side admin + dependency checks.
  /// Returns the JSONB result from the RPC: {"success": true} or {"error": "..."}.
  Future<Map<String, dynamic>> deleteSafe(String id) async {
    final result = await _client.rpc('delete_customer_safe', params: {
      'p_customer_id': id,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<int> getCount() async {
    final response = await _client.from('customers').select().count(CountOption.exact);
    return response.count;
  }

  Future<double> getTotalDebts() async {
    final data = await _client
        .from('customers')
        .select('balance')
        .gt('balance', 0);
    double total = 0;
    for (final row in data) {
      total += ((row['balance'] as num?)?.toDouble() ?? 0.0);
    }
    return total;
  }

  Future<List<CustomerModel>> getAllCustomers() async {
    final data = await _client
        .from('customers')
        .select()
        .order('name')
        .limit(500);
    return data.map(_fromRow).toList();
  }
}
