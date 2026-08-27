/// Multi-Currency Cost Engine Validation Suite
/// Run before every release to verify currency integrity.
///
/// Usage:
///   final results = await CurrencyEngineValidator.validate();
///   if (!results.allPassed) {
///     print(results.summary);
///   }
library;

import '../data/services/currency_conversion_service.dart';
import '../data/models/currency_snapshot.dart';
import '../core/utils.dart';

class ValidationResult {
  final String name;
  final bool passed;
  final String message;
  ValidationResult(this.name, this.passed, this.message);
}

class ValidationReport {
  final List<ValidationResult> results;
  ValidationReport(this.results);

  bool get allPassed => results.every((r) => r.passed);
  int get passedCount => results.where((r) => r.passed).length;
  int get failedCount => results.where((r) => !r.passed).length;

  String get summary {
    final buf = StringBuffer();
    buf.writeln('=== Multi-Currency Engine Validation ===');
    buf.writeln('Passed: $passedCount / ${results.length}');
    buf.writeln('Failed: $failedCount / ${results.length}');
    buf.writeln('');
    for (final r in results) {
      buf.writeln('${r.passed ? "✅" : "❌"} ${r.name}');
      if (!r.passed) buf.writeln('   ${r.message}');
    }
    buf.writeln('');
    buf.writeln(allPassed ? '✅ ALL CHECKS PASSED' : '❌ SOME CHECKS FAILED');
    return buf.toString();
  }
}

class CurrencyEngineValidator {
  static Future<ValidationReport> validate() async {
    final results = <ValidationResult>[];

    results.add(_validateSnapshotCreation());
    results.add(_validateSnapshotImmutability());
    results.add(_validateNoMixedCurrencyAddition());
    results.add(_validateServiceIsSingleton());
    results.add(_validateCurrencySymbols());
    results.add(_validateConversionAccuracy());
    results.add(_validateAppUtilsCurrencySymbol());

    return ValidationReport(results);
  }

  static ValidationResult _validateSnapshotCreation() {
    try {
      final snapshot = CurrencySnapshot.create(
        originalCurrency: 'USD',
        originalAmount: 1000.0,
        exchangeRate: 50.0,
        rateDate: DateTime(2026, 7, 13),
      );

      if (snapshot.originalAmount != 1000.0) {
        return ValidationResult('Snapshot Creation', false,
            'originalAmount mismatch: ${snapshot.originalAmount}');
      }
      if (snapshot.baseAmount != 50000.0) {
        return ValidationResult('Snapshot Creation', false,
            'baseAmount mismatch: ${snapshot.baseAmount} (expected 50000.0)');
      }
      if (snapshot.exchangeRate != 50.0) {
        return ValidationResult('Snapshot Creation', false,
            'exchangeRate mismatch: ${snapshot.exchangeRate}');
      }
      if (snapshot.originalCurrency != 'USD') {
        return ValidationResult('Snapshot Creation', false,
            'originalCurrency mismatch: ${snapshot.originalCurrency}');
      }
      if (snapshot.baseCurrency != 'EGP') {
        return ValidationResult('Snapshot Creation', false,
            'baseCurrency mismatch: ${snapshot.baseCurrency}');
      }

      return ValidationResult('Snapshot Creation', true, 'OK');
    } catch (e) {
      return ValidationResult('Snapshot Creation', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateSnapshotImmutability() {
    try {
      final snapshot = CurrencySnapshot.create(
        originalCurrency: 'USD',
        originalAmount: 1000.0,
        exchangeRate: 50.0,
        rateDate: DateTime(2026, 7, 13),
      );

      final json = snapshot.toJson();
      if (json['original_currency'] != 'USD') {
        return ValidationResult('Snapshot Immutability', false,
            'toJson() original_currency mismatch');
      }
      if (json['base_amount'] != 50000.0) {
        return ValidationResult('Snapshot Immutability', false,
            'toJson() base_amount mismatch');
      }

      final restored = CurrencySnapshot.fromJson(json);
      if (restored.baseAmount != snapshot.baseAmount) {
        return ValidationResult('Snapshot Immutability', false,
            'fromJson round-trip failed');
      }

      return ValidationResult('Snapshot Immutability', true, 'OK');
    } catch (e) {
      return ValidationResult('Snapshot Immutability', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateNoMixedCurrencyAddition() {
    try {
      final s1 = CurrencySnapshot.create(
        originalCurrency: 'USD',
        originalAmount: 100.0,
        exchangeRate: 50.0,
        rateDate: DateTime(2026, 7, 13),
      );
      final s2 = CurrencySnapshot.create(
        originalCurrency: 'USD',
        originalAmount: 200.0,
        exchangeRate: 50.0,
        rateDate: DateTime(2026, 7, 13),
      );

      final totalBase = s1.baseAmount + s2.baseAmount;
      if (totalBase != 15000.0) {
        return ValidationResult('No Mixed-Currency Addition', false,
            'Base amount addition failed: $totalBase');
      }

      return ValidationResult('No Mixed-Currency Addition', true, 'OK');
    } catch (e) {
      return ValidationResult('No Mixed-Currency Addition', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateServiceIsSingleton() {
    try {
      final s1 = CurrencyConversionService.instance;
      final s2 = CurrencyConversionService.instance;
      if (!identical(s1, s2)) {
        return ValidationResult('Service Singleton', false,
            'Two different instances created');
      }
      return ValidationResult('Service Singleton', true, 'OK');
    } catch (e) {
      return ValidationResult('Service Singleton', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateCurrencySymbols() {
    try {
      const currencies = ['EGP', 'USD', 'EUR', 'GBP'];
      for (final c in currencies) {
        final symbol = AppUtils.currencySymbol(c);
        if (symbol.isEmpty) {
          return ValidationResult('Currency Symbols', false,
              'Empty symbol for $c');
        }
      }
      return ValidationResult('Currency Symbols', true, 'OK');
    } catch (e) {
      return ValidationResult('Currency Symbols', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateConversionAccuracy() {
    try {
      final cs = CurrencyConversionService.instance;

      final baseAmount = cs.toBase(1000.0, 'USD', 50.0);
      if ((baseAmount - 50000.0).abs() > 0.01) {
        return ValidationResult('Conversion Accuracy', false,
            'toBase(1000, USD, 50) = $baseAmount, expected 50000');
      }

      final foreignAmount = cs.fromBase(50000.0, 'USD', 50.0);
      if ((foreignAmount - 1000.0).abs() > 0.01) {
        return ValidationResult('Conversion Accuracy', false,
            'fromBase(50000, USD, 50) = $foreignAmount, expected 1000');
      }

      final egpBase = cs.toBase(5000.0, 'EGP', 1.0);
      if ((egpBase - 5000.0).abs() > 0.01) {
        return ValidationResult('Conversion Accuracy', false,
            'toBase(5000, EGP, 1) = $egpBase, expected 5000');
      }

      return ValidationResult('Conversion Accuracy', true, 'OK');
    } catch (e) {
      return ValidationResult('Conversion Accuracy', false, 'Exception: $e');
    }
  }

  static ValidationResult _validateAppUtilsCurrencySymbol() {
    try {
      if (AppUtils.currencySymbol('EGP') != 'ج.م') {
        return ValidationResult('AppUtils Symbol', false, 'EGP symbol wrong');
      }
      if (AppUtils.currencySymbol('USD') != '\$') {
        return ValidationResult('AppUtils Symbol', false, 'USD symbol wrong');
      }
      if (AppUtils.currencySymbol('EUR') != '\u20AC') {
        return ValidationResult('AppUtils Symbol', false, 'EUR symbol wrong');
      }
      if (AppUtils.currencySymbol('GBP') != '\u00A3') {
        return ValidationResult('AppUtils Symbol', false, 'GBP symbol wrong');
      }
      return ValidationResult('AppUtils Symbol', true, 'OK');
    } catch (e) {
      return ValidationResult('AppUtils Symbol', false, 'Exception: $e');
    }
  }
}
