import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents an exchange rate record from the database.
class ExchangeRateModel {
  final int? id;
  final String currencyCode;
  final String currencyName;
  final String? nameAr;
  final double rateToEgp;
  final DateTime? updatedAt;
  final int sortOrder;

  const ExchangeRateModel({
    this.id,
    required this.currencyCode,
    required this.currencyName,
    this.nameAr,
    required this.rateToEgp,
    this.updatedAt,
    this.sortOrder = 0,
  });

  String get displayName => nameAr != null && nameAr!.isNotEmpty
      ? '$nameAr ($currencyCode)'
      : '$currencyName ($currencyCode)';

  factory ExchangeRateModel.fromMap(Map<String, dynamic> map) {
    return ExchangeRateModel(
      id: map['id'] as int?,
      currencyCode: (map['currency_code'] as String?)?.toUpperCase() ?? '',
      currencyName: (map['currency_name'] as String?) ?? '',
      nameAr: map['name_ar'] as String?,
      rateToEgp: (map['rate_to_egp'] as num?)?.toDouble() ?? 1.0,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'currency_code': currencyCode.toUpperCase(),
        'currency_name': currencyName,
        if (nameAr != null) 'name_ar': nameAr,
        'rate_to_egp': rateToEgp,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

typedef ExchangeRateRecord = ExchangeRateModel;

class ExchangeRateDao {
  final _client = Supabase.instance.client;

  /// Fetch all exchange rates from the database.
  Future<List<ExchangeRateModel>> fetchAllRates() async {
    try {
      final data = await _client
          .from('exchange_rates')
          .select()
          .order('sort_order', ascending: true)
          .order('currency_code', ascending: true);

      return (data as List<dynamic>)
          .map((item) => ExchangeRateModel.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ExchangeRateDao.fetchAllRates error: $e');
      rethrow;
    }
  }

  /// Backward compatibility map fetching.
  Future<List<Map<String, dynamic>>> fetchRates() async {
    try {
      final data = await _client
          .from('exchange_rates')
          .select()
          .order('currency_code');
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('ExchangeRateDao.fetchRates error: $e');
      rethrow;
    }
  }

  /// Get rate for a single currency code (returns 1.0 for EGP).
  Future<double> getRate(String currencyCode) async {
    final code = currencyCode.toUpperCase().trim();
    if (code == 'EGP' || code.isEmpty) return 1.0;

    try {
      final data = await _client
          .from('exchange_rates')
          .select('rate_to_egp')
          .eq('currency_code', code)
          .maybeSingle();

      if (data == null) return 1.0;
      return (data['rate_to_egp'] as num?)?.toDouble() ?? 1.0;
    } catch (e) {
      debugPrint('ExchangeRateDao.getRate($code) error: $e');
      return 1.0;
    }
  }

  /// Get rate for a specific date (returns current unified rate).
  Future<double> getRateAtDate(String currencyCode, DateTime date) async {
    return getRate(currencyCode);
  }

  /// Get active exchange rate model for a currency.
  Future<ExchangeRateModel?> getActiveRate(String currencyCode) async {
    final code = currencyCode.toUpperCase().trim();
    if (code == 'EGP') return null;
    try {
      final data = await _client
          .from('exchange_rates')
          .select()
          .eq('currency_code', code)
          .maybeSingle();
      if (data == null) return null;
      return ExchangeRateModel.fromMap(data);
    } catch (e) {
      debugPrint('ExchangeRateDao.getActiveRate error: $e');
      return null;
    }
  }

  /// Update the exchange rate for a currency code.
  Future<void> updateRate(String currencyCode, double newRate, {String? updatedBy}) async {
    final code = currencyCode.toUpperCase().trim();
    if (code == 'EGP') return;

    try {
      await _client.from('exchange_rates').update({
        'rate_to_egp': newRate,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (updatedBy != null) 'updated_by': updatedBy,
      }).eq('currency_code', code);
    } catch (e) {
      debugPrint('ExchangeRateDao.updateRate error: $e');
      rethrow;
    }
  }

  /// Add a new currency exchange rate.
  Future<void> addCurrency({
    required String currencyCode,
    required String currencyName,
    String? nameAr,
    required double rateToEgp,
  }) async {
    final code = currencyCode.toUpperCase().trim();
    if (code == 'EGP') return;

    try {
      await _client.from('exchange_rates').upsert({
        'currency_code': code,
        'currency_name': currencyName.trim(),
        'name_ar': (nameAr != null && nameAr.trim().isNotEmpty) ? nameAr.trim() : currencyName.trim(),
        'rate_to_egp': rateToEgp,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sort_order': 10,
      }, onConflict: 'currency_code');
    } catch (e) {
      debugPrint('ExchangeRateDao.addCurrency error: $e');
      rethrow;
    }
  }
}
