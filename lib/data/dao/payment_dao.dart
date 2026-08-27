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
