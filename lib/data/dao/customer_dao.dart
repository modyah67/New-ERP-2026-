import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_model.dart';
import '../services/currency_conversion_service.dart';
import '../../core/extensions/company_injection.dart';
import '../../core/services/tenant_service.dart';

class CustomerDao {
  final _client = Supabase.instance.client;

  // ── Code Generation ──

  Future<String> generateNextCode() async {
    try {
      final response = await _client.from('customers').select('code');
      int maxCode = 0;
      for (var row in response) {
        final codeStr = row['code']?.toString() ?? '';
        final num = int.tryParse(codeStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxCode) maxCode = num;
      }
      return (maxCode + 1).toString().padLeft(5, '0');
    } catch (e) {
      return '00001';
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

  // ── CRUD ──

  Future<List<CustomerModel>> getAll({int limit = 50, int offset = 0}) async {
    final data = await _client
        .from('customers')
        .select()
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<List<CustomerModel>> search(String query, {int limit = 50, int offset = 0}) async {
    final data = await _client
        .from('customers')
        .select()
        .or('name.ilike.%$query%,code.ilike.%$query%,phone.ilike.%$query%')
        .order('name')
        .range(offset, offset + limit - 1);
    return data.map(_fromRow).toList();
  }

  Future<CustomerModel?> getById(String id) async {
    final data = await _client
        .from('customers')
        .select()
        .eq('id', int.tryParse(id) ?? id)
        .maybeSingle();
    if (data == null) return null;
    return _fromRow(data);
  }

  Future<String> insert(CustomerModel customer) async {
    final customerData = customer.toInsertMap();
    if (customer.addresses.isNotEmpty) {
      customerData['addresses'] = customer.addresses;
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
