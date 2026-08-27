import 'package:flutter/foundation.dart';
import '../dao/exchange_rate_dao.dart';
import '../models/currency_snapshot.dart';

/// Unified currency conversion service — single source of truth.
///
/// ALL currency conversions MUST go through this service.
/// NEVER do `amount * exchangeRate` directly in widgets/pages/DAOs.
/// Every financial transaction MUST store a CurrencySnapshot.
class CurrencyConversionService {
  CurrencyConversionService._();
  static final CurrencyConversionService instance = CurrencyConversionService._();
  factory CurrencyConversionService() => instance;

  final ExchangeRateDao _rateDao = ExchangeRateDao();

  static const baseCurrency = 'EGP';
  static const _defaultRates = {'USD': 50.0, 'EUR': 50.0, 'GBP': 60.0};

  Map<String, double> _cachedRates = {};
  DateTime? _lastFetch;
  static const _cacheTtl = Duration(minutes: 5);

  /// Convert any amount TO base currency (EGP).
  double toBase(double amount, String currency, double exchangeRate) {
    if (currency == baseCurrency) return amount;
    return amount * exchangeRate;
  }

  /// Convert FROM base currency (EGP) to target currency.
  double fromBase(double baseAmount, String targetCurrency, double exchangeRate) {
    if (targetCurrency == baseCurrency) return baseAmount;
    if (exchangeRate <= 0) return 0;
    return baseAmount / exchangeRate;
  }

  /// Convert between any two currencies via base.
  double convert(double amount, String from, String to, double rateFrom, double rateTo) {
    if (from == to) return amount;
    final base = toBase(amount, from, rateFrom);
    return fromBase(base, to, rateTo);
  }

  /// Sum a list of base amounts (already converted to EGP).
  double sumAsBase(List<double> baseAmounts) {
    double total = 0;
    for (final a in baseAmounts) {
      total += a;
    }
    return total;
  }

  // ──────────────────────────────────────────────────
  // CurrencySnapshot creation — MANDATORY for every transaction
  // ──────────────────────────────────────────────────

  /// Create a snapshot from a known exchange rate (no DB lookup).
  ///
  /// Use this when you already have the rate (e.g., from purchase form).
  CurrencySnapshot createSnapshot({
    required String currency,
    required double amount,
    required double exchangeRate,
    String source = 'system',
    String? createdBy,
  }) {
    return CurrencySnapshot.create(
      originalCurrency: currency,
      originalAmount: amount,
      exchangeRate: exchangeRate,
      rateDate: DateTime.now(),
      rateSource: source,
      createdBy: createdBy,
    );
  }

  /// Create a snapshot by fetching the current rate from the database.
  ///
  /// Use this when no rate is available from the form (e.g., treasury operations).
  Future<CurrencySnapshot> createSnapshotFromDb({
    required String currency,
    required double amount,
    String? createdBy,
  }) async {
    if (currency == baseCurrency) {
      return CurrencySnapshot.create(
        originalCurrency: currency,
        originalAmount: amount,
        exchangeRate: 1.0,
        rateDate: DateTime.now(),
        rateSource: 'default',
        createdBy: createdBy,
      );
    }
    final rate = await getRate(currency);
    return CurrencySnapshot.create(
      originalCurrency: currency,
      originalAmount: amount,
      exchangeRate: rate,
      rateDate: DateTime.now(),
      rateSource: 'database',
      createdBy: createdBy,
    );
  }

  /// Create a snapshot with a specific historical date rate.
  ///
  /// Use this for backdated transactions.
  Future<CurrencySnapshot> createSnapshotAtDate({
    required String currency,
    required double amount,
    required DateTime date,
    String? createdBy,
  }) async {
    if (currency == baseCurrency) {
      return CurrencySnapshot.create(
        originalCurrency: currency,
        originalAmount: amount,
        exchangeRate: 1.0,
        rateDate: date,
        rateSource: 'default',
        createdBy: createdBy,
      );
    }
    final rate = await _rateDao.getRateAtDate(currency, date);
    return CurrencySnapshot.create(
      originalCurrency: currency,
      originalAmount: amount,
      exchangeRate: rate,
      rateDate: date,
      rateSource: 'database_historical',
      createdBy: createdBy,
    );
  }

  /// Create a snapshot from a pre-existing stored snapshot JSON.
  ///
  /// Use this when reading historical data — DO NOT recalculate.
  CurrencySnapshot? restoreSnapshot(dynamic json) {
    return CurrencySnapshot.fromJsonNullable(json);
  }

  // ──────────────────────────────────────────────────
  // Rate fetching
  // ──────────────────────────────────────────────────

  /// Fetch the current exchange rate for a currency.
  Future<double> getRate(String currency) async {
    if (currency == baseCurrency) return 1.0;
    await _refreshIfNeeded();
    return _cachedRates[currency] ?? _defaultRates[currency] ?? 1.0;
  }

  /// Synchronous get rate — uses cache only.
  double getRateSync(String currency) {
    if (currency == baseCurrency) return 1.0;
    return _cachedRates[currency] ?? _defaultRates[currency] ?? 1.0;
  }

  Future<void> _refreshIfNeeded() async {
    if (_lastFetch != null && DateTime.now().difference(_lastFetch!) < _cacheTtl) return;
    try {
      final rates = await _rateDao.fetchRates();
      _cachedRates = {
        for (final r in rates) r['currency_code'] as String: (r['rate_to_egp'] as num).toDouble(),
      };
      _lastFetch = DateTime.now();
    } catch (e) {
      debugPrint('CurrencyConversionService._refreshIfNeeded error: $e');
    }
  }

  void invalidateCache() {
    _cachedRates.clear();
    _lastFetch = null;
  }
}
