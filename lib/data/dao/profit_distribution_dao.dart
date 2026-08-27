import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfitDistributionDao {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      // مفيش فلترة على user_id، بنجيب الصف المشترك الوحيد للشركة
      final data = await _client
          .from('profit_distribution_settings')
          .select()
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return data;
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getSettings): ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error (getSettings): $e');
    }
  }

  Future<void> saveSettings({
    required String? person1Id,
    required String person1Name,
    required String? person2Id,
    required String person2Name,
    required String? person3Id,
    required String person3Name,
    required Map<String, List<double>> percentages,
    required Map<String, String> person4ForShipment,
    required Map<String, Map<String, dynamic>> currencyConversions,
  }) async {
    try {
      final pctJson = percentages.map((k, v) => MapEntry(k, v));
      try {
        await _client.rpc('rpc_save_profit_distribution_settings', params: {
          'p_person1_id': person1Id,
          'p_person1_name': person1Name,
          'p_person2_id': person2Id,
          'p_person2_name': person2Name,
          'p_person3_id': person3Id,
          'p_person3_name': person3Name,
          'p_percentages': pctJson,
          'p_person4_for_shipment': person4ForShipment,
          'p_currency_conversions': currencyConversions,
        });
        return;
      } catch (rpcErr) {
        // Fallback to direct table write if RPC not available
        final payload = {
          'user_id': _userId,
          'person1_id': person1Id,
          'person1_name': person1Name,
          'person2_id': person2Id,
          'person2_name': person2Name,
          'person3_id': person3Id,
          'person3_name': person3Name,
          'percentages': pctJson,
          'person4_for_shipment': person4ForShipment,
          'currency_conversions': currencyConversions,
          'updated_at': DateTime.now().toIso8601String(),
        };

        final existing = await _client
            .from('profit_distribution_settings')
            .select('id')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (existing != null) {
          await _client
              .from('profit_distribution_settings')
              .update(payload)
              .eq('id', existing['id']);
        } else {
          await _client.from('profit_distribution_settings').insert(payload);
        }
      }
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (saveSettings): ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error (saveSettings): $e');
    }
  }
}