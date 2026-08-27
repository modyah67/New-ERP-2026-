import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/currency_conversion_service.dart';

class GeneralCostItemDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> add({
    required String name,
    required double amount,
    required DateTime date,
    int? reportCategoryId,
  }) async {
    await _client.from('general_cost_items').insert({
      'name': name,
      'amount': amount,
      'cost_date': date.toIso8601String().substring(0, 10),
      if (reportCategoryId != null) 'report_category_id': reportCategoryId,
      'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
        currency: 'EGP',
        amount: amount,
        exchangeRate: 1.0,
      ).toJson(),
    });
  }
}
