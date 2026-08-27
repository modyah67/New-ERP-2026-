/// Currency Converter — Multi-currency display and conversion utilities
///
/// Uses exchange rates from the database to convert amounts
/// between EGP, USD, EUR, and GBP for display purposes.
///
/// Create an instance with exchange rates, then call conversion methods.
/// Example:
/// ```dart
/// final converter = CurrencyConverter(exchangeRates);
/// final usdInEgp = converter.toEgp(amount: 100, currency: 'USD');
/// ```
library;

import '../models/report_models.dart';

/// Thrown when a currency is not in the supported list or exchange rates map.
class CurrencyNotSupportedException implements Exception {
  final String currency;
  const CurrencyNotSupportedException(this.currency);
  @override
  String toString() => 'CurrencyNotSupportedException: $currency is not supported';
}

class CurrencyConverter {
  final Map<String, double> _rates;

  static const supportedCurrencies = ['EGP', 'USD', 'EUR', 'GBP'];

  /// Create a converter with the given exchange rates (currency → EGP rate).
  ///
  /// EGP rate is always normalized to 1.0 regardless of what is passed.
  CurrencyConverter(Map<String, double> exchangeRates)
      : _rates = Map.unmodifiable({
          ...exchangeRates,
          'EGP': 1.0, // EGP is always 1.0
        });

  /// Convert an amount from one currency to another
  double convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) {
    if (fromCurrency == toCurrency) return amount;

    final fromRate = _rates[fromCurrency];
    if (fromRate == null) {
      throw CurrencyNotSupportedException(fromCurrency);
    }

    final toRate = _rates[toCurrency];
    if (toRate == null) {
      throw CurrencyNotSupportedException(toCurrency);
    }
    if (toRate == 0) {
      throw ArgumentError('Exchange rate for $toCurrency is zero — cannot convert');
    }

    final amountInEgp = amount * fromRate;
    return amountInEgp / toRate;
  }

  /// Convert an amount to EGP
  double toEgp({
    required double amount,
    required String currency,
  }) {
    final rate = _rates[currency];
    if (rate == null) {
      throw CurrencyNotSupportedException(currency);
    }
    return amount * rate;
  }

  /// Create a [CurrencyDisplay] from raw data
  CurrencyDisplay createDisplay({
    required double amount,
    required String currency,
  }) {
    final rate = _rates[currency];
    if (rate == null) {
      throw CurrencyNotSupportedException(currency);
    }
    final amountInEgp = amount * rate;

    return CurrencyDisplay(
      currency: currency,
      amount: amount,
      exchangeRate: rate,
      amountInEgp: amountInEgp,
    );
  }

  /// Create a multi-currency summary from a map of currency → amount
  MultiCurrencySummary createSummary({
    required Map<String, double> amountsByCurrency,
  }) {
    final displays = <CurrencyDisplay>[];
    double totalInEgp = 0.0;

    for (final entry in amountsByCurrency.entries) {
      if (entry.value == 0.0) continue;
      final display = createDisplay(
        amount: entry.value,
        currency: entry.key,
      );
      displays.add(display);
      totalInEgp += display.amountInEgp;
    }

    return MultiCurrencySummary(
      currencies: displays,
      totalInEgp: totalInEgp,
    );
  }

  /// Format a currency amount for display
  static String formatAmount({
    required double amount,
    required String currency,
    int decimals = 2,
  }) {
    final formatted = amount.toStringAsFixed(decimals);
    return '$currency $formatted';
  }

  /// Format a currency amount with comma separators
  static String formatAmountAr({
    required double amount,
    required String currency,
    int decimals = 2,
  }) {
    final formatted = _formatWithCommas(amount, decimals);
    return '$currency $formatted';
  }

  /// Format number with comma separators
  static String _formatWithCommas(double value, int decimals) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '';

    final buffer = StringBuffer();
    final digits = intPart.split('');
    final isNegative = digits.isNotEmpty && digits[0] == '-';
    final actualDigits = isNegative ? digits.sublist(1) : digits;

    for (var i = 0; i < actualDigits.length; i++) {
      if (i > 0 && (actualDigits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(actualDigits[i]);
    }

    if (isNegative) {
      buffer.write('-');
    }
    final result = buffer.toString();
    if (decPart.isNotEmpty) {
      return '$result.$decPart';
    }
    return result;
  }
}
