import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/utils/currency_converter.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

import '../../fixtures/transaction_fixtures.dart';

void main() {
  group('CurrencyConverter', () {
    late CurrencyConverter converter;

    setUp(() {
      converter = CurrencyConverter(TransactionFixtures.exchangeRates);
    });

    group('constructor', () {
      test('normalizes EGP rate to 1.0', () {
        final conv = CurrencyConverter({'EGP': 5.0, 'USD': 50.0});
        final result = conv.toEgp(amount: 100, currency: 'EGP');
        expect(result, 100.0);
      });

      test('preserves non-EGP rates', () {
        final conv = CurrencyConverter({'USD': 50.0});
        final result = conv.toEgp(amount: 100, currency: 'USD');
        expect(result, 5000.0);
      });
    });

    group('convert', () {
      test('same currency returns same amount', () {
        final result = converter.convert(
          amount: 1000.0,
          fromCurrency: 'USD',
          toCurrency: 'USD',
        );
        expect(result, 1000.0);
      });

      test('converts USD to EGP', () {
        final result = converter.convert(
          amount: 100.0,
          fromCurrency: 'USD',
          toCurrency: 'EGP',
        );
        // 100 * 50 / 1 = 5000
        expect(result, 5000.0);
      });

      test('converts EGP to USD', () {
        final result = converter.convert(
          amount: 5000.0,
          fromCurrency: 'EGP',
          toCurrency: 'USD',
        );
        // 5000 * 1 / 50 = 100
        expect(result, 100.0);
      });

      test('converts USD to EUR', () {
        final result = converter.convert(
          amount: 100.0,
          fromCurrency: 'USD',
          toCurrency: 'EUR',
        );
        // 100 * 50 / 55 = 90.909...
        expect(result, closeTo(90.909, 0.001));
      });

      test('converts EUR to GBP', () {
        final result = converter.convert(
          amount: 100.0,
          fromCurrency: 'EUR',
          toCurrency: 'GBP',
        );
        // 100 * 55 / 63 = 87.301...
        expect(result, closeTo(87.301, 0.001));
      });

      test('handles zero amount', () {
        final result = converter.convert(
          amount: 0.0,
          fromCurrency: 'USD',
          toCurrency: 'EGP',
        );
        expect(result, 0.0);
      });

      test('handles negative amount', () {
        final result = converter.convert(
          amount: -100.0,
          fromCurrency: 'USD',
          toCurrency: 'EGP',
        );
        expect(result, -5000.0);
      });

      test('throws for unsupported from currency', () {
        expect(
          () => converter.convert(
            amount: 100.0,
            fromCurrency: 'JPY',
            toCurrency: 'EGP',
          ),
          throwsA(isA<CurrencyNotSupportedException>()),
        );
      });

      test('throws for unsupported to currency', () {
        expect(
          () => converter.convert(
            amount: 100.0,
            fromCurrency: 'USD',
            toCurrency: 'JPY',
          ),
          throwsA(isA<CurrencyNotSupportedException>()),
        );
      });
    });

    group('toEgp', () {
      test('converts USD to EGP', () {
        expect(converter.toEgp(amount: 100, currency: 'USD'), 5000.0);
      });

      test('converts EUR to EGP', () {
        expect(converter.toEgp(amount: 100, currency: 'EUR'), 5500.0);
      });

      test('converts GBP to EGP', () {
        expect(converter.toEgp(amount: 100, currency: 'GBP'), 6300.0);
      });

      test('EGP returns same amount', () {
        expect(converter.toEgp(amount: 100, currency: 'EGP'), 100.0);
      });

      test('throws for unsupported currency', () {
        expect(
          () => converter.toEgp(amount: 100, currency: 'JPY'),
          throwsA(isA<CurrencyNotSupportedException>()),
        );
      });

      test('handles zero', () {
        expect(converter.toEgp(amount: 0, currency: 'USD'), 0.0);
      });
    });

    group('createDisplay', () {
      test('creates display for USD', () {
        final display = converter.createDisplay(amount: 100, currency: 'USD');
        expect(display.currency, 'USD');
        expect(display.amount, 100.0);
        expect(display.exchangeRate, 50.0);
        expect(display.amountInEgp, 5000.0);
      });

      test('creates display for EGP', () {
        final display = converter.createDisplay(amount: 100, currency: 'EGP');
        expect(display.currency, 'EGP');
        expect(display.amount, 100.0);
        expect(display.exchangeRate, 1.0);
        expect(display.amountInEgp, 100.0);
      });

      test('throws for unsupported currency', () {
        expect(
          () => converter.createDisplay(amount: 100, currency: 'JPY'),
          throwsA(isA<CurrencyNotSupportedException>()),
        );
      });
    });

    group('createSummary', () {
      test('creates summary with multiple currencies', () {
        final summary = converter.createSummary(amountsByCurrency: {
          'USD': 100.0,
          'EUR': 200.0,
          'GBP': 50.0,
        });
        expect(summary.currencies.length, 3);
        expect(summary.totalInEgp, closeTo(100 * 50 + 200 * 55 + 50 * 63, 0.01));
      });

      test('skips zero amounts', () {
        final summary = converter.createSummary(amountsByCurrency: {
          'USD': 100.0,
          'EUR': 0.0,
          'GBP': 50.0,
        });
        expect(summary.currencies.length, 2);
      });

      test('handles empty map', () {
        final summary = converter.createSummary(amountsByCurrency: {});
        expect(summary.currencies, isEmpty);
        expect(summary.totalInEgp, 0.0);
      });

      test('handles single currency', () {
        final summary = converter.createSummary(amountsByCurrency: {
          'USD': 200.0,
        });
        expect(summary.currencies.length, 1);
        expect(summary.totalInEgp, 10000.0);
      });
    });

    group('formatAmount', () {
      test('formats with 2 decimals', () {
        expect(CurrencyConverter.formatAmount(amount: 1234.5, currency: 'USD'), 'USD 1234.50');
      });

      test('formats with 0 decimals', () {
        expect(CurrencyConverter.formatAmount(amount: 1234.5, currency: 'EGP', decimals: 0), 'EGP 1235');
      });

      test('formats negative amount', () {
        expect(CurrencyConverter.formatAmount(amount: -500.0, currency: 'USD'), 'USD -500.00');
      });
    });

    group('formatAmountAr', () {
      test('formats with comma separators', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: 1234567.5, currency: 'EGP'),
          'EGP 1,234,567.50',
        );
      });

      test('formats small number without commas', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: 999.99, currency: 'USD'),
          'USD 999.99',
        );
      });

      test('formats zero', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: 0.0, currency: 'EGP'),
          'EGP 0.00',
        );
      });

      test('formats negative with commas', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: -1234567.5, currency: 'EUR'),
          'EUR 1,234,567-.50',
        );
      });

      test('formats exact thousands', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: 1000.0, currency: 'USD'),
          'USD 1,000.00',
        );
      });

      test('formats millions', () {
        expect(
          CurrencyConverter.formatAmountAr(amount: 1000000.0, currency: 'EGP'),
          'EGP 1,000,000.00',
        );
      });
    });

    group('CurrencyNotSupportedException', () {
      test('has correct message', () {
        final exception = CurrencyNotSupportedException('JPY');
        expect(exception.toString(), 'CurrencyNotSupportedException: JPY is not supported');
      });
    });

    group('CurrencyDisplay model', () {
      test('displayLabel formats correctly', () {
        const display = CurrencyDisplay(
          currency: 'USD',
          amount: 100.0,
          exchangeRate: 50.0,
          amountInEgp: 5000.0,
        );
        expect(display.displayLabel, 'USD 100.00');
      });

      test('displayLabelEgp formats correctly', () {
        const display = CurrencyDisplay(
          currency: 'USD',
          amount: 100.0,
          exchangeRate: 50.0,
          amountInEgp: 5000.0,
        );
        expect(display.displayLabelEgp, 'EGP 5000.00');
      });
    });
  });
}
