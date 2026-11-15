import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/unpaid_liability_model.dart';
import '../../core/utils.dart';

class PaymentDao {
  final _supabase = Supabase.instance.client;

  Future<List<UnpaidLiabilityModel>> getUnpaidLiabilities(String entityType, String entityId) async {
    try {
      final response = await _supabase
          .from('vw_unpaid_liabilities')
          .select()
          .eq('entity_type', entityType.toLowerCase())
          .eq('entity_id', entityId)
          .order('liability_date', ascending: true);
          
      return (response as List)
          .map((json) => UnpaidLiabilityModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching unpaid liabilities: $e');
      rethrow;
    }
  }

  /// Fetches total paid opening balances grouped by currency from supplier_payment_allocations
  Future<Map<String, double>> getOpeningBalancePaid(String entityType, String entityId) async {
    try {
      final isSupplier = entityType.toLowerCase() == 'supplier';
      var query = _supabase
          .from('supplier_payment_allocations')
          .select('currency, amount')
          .eq('allocation_type', 'opening_balance');

      if (isSupplier) {
        query = query.or('supplier_id.eq.$entityId,entity_id.eq.$entityId');
      } else {
        query = query.eq('entity_id', entityId).eq('entity_type', entityType.toLowerCase());
      }

      final response = await query;
      final map = <String, double>{};
      for (final row in response as List) {
        final cur = (row['currency']?.toString() ?? 'EGP').toUpperCase();
        final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        map[cur] = (map[cur] ?? 0.0) + amt;
      }
      return map;
    } catch (e) {
      print('Error fetching opening balance paid: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> entityMultiPayment({
    required String sourceType,
    required int sourceId,
    required double amount,
    required String currency,
    required String entityType,
    required String entityId,
    required String description,
    required String notes,
    int? expenseAccountId,
  }) async {
    try {
      final response = await _supabase.rpc('rpc_entity_multi_payment', params: {
        'p_source_type': sourceType,
        'p_source_id': sourceId,
        'p_currency': currency,
        'p_amount': amount,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_description': description,
        'p_notes': notes,
        'p_expense_account_id': expenseAccountId,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('Error in entityMultiPayment: $e');
      rethrow;
    }
  }
}
