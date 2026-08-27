import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/currency_conversion_service.dart';

class CashPaymentDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> getAll({
    int limit = 50,
    int offset = 0,
    String? fromDate,
    String? toDate,
  }) async {
    var query = _client
        .from('cash_payments')
        .select('*, suppliers(name, code)');

    if (fromDate != null) {
      query = query.gte('payment_date', fromDate);
    }
    if (toDate != null) {
      query = query.lte('payment_date', toDate);
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final data = await _client
        .from('cash_payments')
        .select('*, suppliers(name, code, phone)')
        .eq('id', id.toString())
        .maybeSingle();
    return data;
  }

  Future<int> insert({
    required String paymentDate,
    int? supplierId,
    int? accountId,
    required double amount,
    String description = '',
  }) async {
    final data = await _client
        .from('cash_payments')
        .insert({
          'payment_date': paymentDate,
          'supplier_id': supplierId,
          'amount': amount,
          'notes': description,
          'created_by': _userId,
          'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
            currency: 'EGP',
            amount: amount,
            exchangeRate: 1.0,
          ).toJson(),
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client
        .from('cash_payments')
        .select('*, suppliers(name, code)')
        .or('payment_number.ilike.%$query%,suppliers.name.ilike.%$query%')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> delete(int id) async {
    await _client.from('cash_payments').delete().eq('id', id.toString());
  }

  Future<String> getNextNumber() async {
    final data = await _client
        .from('cash_payments')
        .select('payment_number')
        .order('payment_number', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return 'PAY-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-0001';
    final numStr = (data['payment_number'] as String?) ?? '';
    final match = RegExp(r'-(\d+)$').firstMatch(numStr);
    final nextNum = match != null ? int.parse(match.group(1)!) + 1 : 1;
    return 'PAY-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${nextNum.toString().padLeft(4, '0')}';
  }
}
