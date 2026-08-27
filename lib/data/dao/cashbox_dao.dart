import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cashbox_model.dart';
import '../services/currency_conversion_service.dart';

class CashboxDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<CashboxModel>> getAll({
    String? fromDate,
    String? toDate,
    int limit = 1000,
  }) async {
    var query = _client
        .from('cashbox_transactions')
        .select('id, transaction_type, amount, description, reference_id, reference_type, created_at');

    if (fromDate != null) {
      query = query.gte('created_at', fromDate);
    }
    if (toDate != null) {
      query = query.lte('created_at', toDate);
    }

    final data = await query.order('created_at', ascending: false).limit(limit);
    return (data as List).map((e) {
      final map = Map<String, dynamic>.from(e);
      return CashboxModel.fromMap({
        'id': map['id'],
        'transaction_date': map['created_at'],
        'type': map['transaction_type'],
        'amount': map['amount'],
        'balance_after': 0,
        'description': map['description'] ?? '',
        'related_transaction_id': map['reference_id'],
        'created_at': map['created_at'],
      });
    }).toList();
  }

  Future<int> insert(CashboxModel entry) async {
    final data = await _client
        .from('cashbox_transactions')
        .insert({
          'transaction_type': entry.type,
          'amount': entry.amount,
          'description': entry.description,
          'reference_id': entry.relatedTransactionId?.toString(),
          'user_id': _userId,
          'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
            currency: 'EGP',
            amount: entry.amount,
            exchangeRate: 1.0,
          ).toJson(),
        })
        .select('id')
        .single();
    return data['id'] as int;
  }

  Future<double> getCurrentBalance() async {
    try {
      final result = await _client.rpc('get_cashbox_balance');
      return (result as num).toDouble();
    } catch (e) {
      print('CashboxDao error: $e');
      final data = await _client
          .from('cashbox_transactions')
          .select('amount, transaction_type');
      double balance = 0.0;
      for (final row in data as List) {
        final amount = (row['amount'] as num).toDouble();
        final type = row['transaction_type'] as String;
        balance += type == 'income' ? amount : -amount;
      }
      return balance;
    }
  }

  Future<double> getTotalIn({String? fromDate, String? toDate}) async {
    try {
      final result = await _client.rpc('get_cashbox_total_in');
      return (result as num).toDouble();
    } catch (e) {
      print('CashboxDao error: $e');
      var query = _client
          .from('cashbox_transactions')
          .select('amount')
          .eq('transaction_type', 'income');

      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', toDate);
      }

      final data = await query;
      double total = 0.0;
      for (final row in data as List) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    }
  }

  Future<double> getTotalOut({String? fromDate, String? toDate}) async {
    try {
      final result = await _client.rpc('get_cashbox_total_out');
      return (result as num).toDouble();
    } catch (e) {
      print('CashboxDao error: $e');
      var query = _client
          .from('cashbox_transactions')
          .select('amount')
          .eq('transaction_type', 'expense');

      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', toDate);
      }

      final data = await query;
      double total = 0.0;
      for (final row in data as List) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    }
  }
}
