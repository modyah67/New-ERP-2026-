import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cheque_model.dart';
import '../services/currency_conversion_service.dart';

class ChequeDao {
  final _client = Supabase.instance.client;

  void _log(String msg) => debugPrint('🧾 ChequeDao: $msg');

  Future<List<ChequeModel>> getAll({
    int limit = 100,
    int offset = 0,
    String? typeFilter,
    String? statusFilter,
    String? searchQuery,
  }) async {
    _log('getAll(offset=$offset, limit=$limit, type=$typeFilter, status=$statusFilter, q=$searchQuery)');
    var query = _client
        .from('cheques')
        .select('*, suppliers(name, code), shareholders(name), clearing_agents(name), shipping_companies(name)');

    if (typeFilter != null && typeFilter.isNotEmpty) {
      query = query.eq('type', typeFilter);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.eq('status', statusFilter);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
          'cheque_number.ilike.%$searchQuery%');
    }

    try {
      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      _log('getAll: ${data.length} row(s) returned');
      
      // Manual join for customer names (counterparty_id is polymorphic BIGINT without FK)
      final customerIds = data
          .where((e) => (e as Map)['counterparty_type'] == 'customer' && (e as Map)['counterparty_id'] != null)
          .map((e) => ((e as Map)['counterparty_id'] as num).toInt())
          .toSet()
          .toList();
      
      Map<int, Map<String, dynamic>> customerMap = {};
      if (customerIds.isNotEmpty) {
        final customers = await _client
            .from('customers')
            .select('id, name, code')
            .inFilter('id', customerIds);
        customerMap = {for (var c in customers) (c['id'] as num).toInt(): Map<String, dynamic>.from(c as Map)};
      }
      
      return data.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        // Inject customer data if needed
        if (map['counterparty_type'] == 'customer' && map['counterparty_id'] != null) {
          final cid = (map['counterparty_id'] as num).toInt();
          if (customerMap.containsKey(cid)) {
            map['customers'] = customerMap[cid];
          }
        }
        return ChequeModel.fromMap(map);
      }).toList();
    } catch (e, st) {
      _log('getAll ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<ChequeModel?> getById(int id) async {
    _log('getById($id)');
    try {
      final data = await _client
          .from('cheques')
          .select('*, suppliers(name, code), shareholders(name), clearing_agents(name), shipping_companies(name)')
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      
      final map = Map<String, dynamic>.from(data as Map);
      // Manual join for customer if needed
      if (map['counterparty_type'] == 'customer' && map['counterparty_id'] != null) {
        final cid = (map['counterparty_id'] as num).toInt();
        final customer = await _client
            .from('customers')
            .select('id, name, code')
            .eq('id', cid)
            .maybeSingle();
        if (customer != null) {
          map['customers'] = Map<String, dynamic>.from(customer as Map);
        }
      }
      
      return ChequeModel.fromMap(map);
    } catch (e, st) {
      _log('getById ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<int> create({
    required String chequeNumber,
    required String type,
    required double amount,
    required String currency,
    required String issueDate,
    required String dueDate,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? notes,
    int? categoryId,
    int? expenseAccountId,
    int? treasuryId,
    bool postLedger = true,
    double? exchangeRate,
  }) async {
    final result = await _client.rpc('create_cheque', params: {
      'p_cheque_number': chequeNumber,
      'p_type': type,
      'p_amount': amount,
      'p_currency': currency,
      'p_issue_date': issueDate,
      'p_due_date': dueDate,
      if (counterpartyType != null) 'p_counterparty_type': counterpartyType,
      if (counterpartyId != null) 'p_counterparty_id': counterpartyId,
      if (supplierId != null && supplierId.isNotEmpty) 'p_supplier_id': supplierId,
      if (shareholderId != null && shareholderId.isNotEmpty) 'p_shareholder_id': shareholderId,
      if (clearingAgentId != null) 'p_clearing_agent_id': clearingAgentId,
      if (shippingCompanyId != null) 'p_shipping_company_id': shippingCompanyId,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
      if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
      'p_post_ledger': postLedger,
    });
    final map = Map<String, dynamic>.from(result as Map);
    final id = (map['id'] as num).toInt();

    final rate = (exchangeRate != null && exchangeRate > 0)
        ? exchangeRate
        : await CurrencyConversionService.instance.getRate(currency);

    final snapshot = CurrencyConversionService.instance.createSnapshot(
      currency: currency,
      amount: amount,
      exchangeRate: rate,
    );

    final updateData = <String, dynamic>{
      'currency_snapshot': snapshot.toJson(),
      'exchange_rate': rate,
      'amount_in_base_currency': amount * rate,
    };
    if (categoryId != null) updateData['category_id'] = categoryId;
    if (treasuryId != null) updateData['treasury_id'] = treasuryId;

    await _client.from('cheques').update(updateData).eq('id', id);

    return id;
  }

  Future<Map<String, dynamic>> clearCheque(int id) async {
    final result = await _client.rpc('clear_cheque', params: {'p_cheque_id': id});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> cancelCheque(int id) async {
    final result = await _client.rpc('cancel_cheque', params: {'p_cheque_id': id});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> receivePayment({
    required String receiptType,
    required double amount,
    required String currency,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? description,
    String? notes,
    int? treasuryId,
  }) async {
    await _client.rpc('receive_payment', params: {
      'p_receipt_type': receiptType,
      'p_amount': amount,
      'p_currency': currency,
      if (counterpartyType != null) 'p_counterparty_type': counterpartyType,
      if (counterpartyId != null) 'p_counterparty_id': counterpartyId,
      if (supplierId != null && supplierId.isNotEmpty) 'p_supplier_id': supplierId,
      if (shareholderId != null && shareholderId.isNotEmpty) 'p_shareholder_id': shareholderId,
      if (description != null && description.isNotEmpty) 'p_description': description,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
      if (treasuryId != null) 'p_treasury_id': treasuryId,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingForNotification(int daysAhead) async {
    final data = await _client.rpc('get_pending_cheques_for_notification', params: {
      'p_days_ahead': daysAhead,
    });
    return (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<int> getPendingCount() async {
    final data = await _client
        .from('cheques')
        .select('id')
        .eq('status', 'pending');
    return (data as List).length;
  }

  Future<bool> chequeNumberExists(String number) async {
    final data = await _client
        .from('cheques')
        .select('id')
        .eq('cheque_number', number)
        .limit(1);
    return (data as List).isNotEmpty;
  }
}
