import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/utils.dart';

void main() {
  group('AppUtils', () {
    group('formatDate', () {
      test('formats date correctly', () {
        expect(AppUtils.formatDate(DateTime(2025, 1, 15)), '15/01/2025');
      });

      test('pads single digit day and month', () {
        expect(AppUtils.formatDate(DateTime(2025, 3, 5)), '05/03/2025');
      });

      test('handles December 31', () {
        expect(AppUtils.formatDate(DateTime(2025, 12, 31)), '31/12/2025');
      });
    });

    group('formatDateForDb', () {
      test('formats date for database', () {
        expect(AppUtils.formatDateForDb(DateTime(2025, 1, 15)), '2025-01-15');
      });

      test('pads single digit values', () {
        expect(AppUtils.formatDateForDb(DateTime(2025, 3, 5)), '2025-03-05');
      });
    });

    group('parseDate', () {
      test('parses valid date string', () {
        final date = AppUtils.parseDate('2025-01-15');
        expect(date.year, 2025);
        expect(date.month, 1);
        expect(date.day, 15);
      });

      test('roundtrips with formatDateForDb', () {
        final original = DateTime(2025, 6, 15);
        final formatted = AppUtils.formatDateForDb(original);
        final parsed = AppUtils.parseDate(formatted);
        expect(parsed, original);
      });
    });

    group('roundDouble', () {
      test('rounds to 2 decimal places by default', () {
        expect(AppUtils.roundDouble(1.23456), 1.23);
      });

      test('rounds to specified decimal places', () {
        expect(AppUtils.roundDouble(1.23456, places: 3), 1.235);
      });

      test('rounds to 0 decimal places', () {
        expect(AppUtils.roundDouble(1.6, places: 0), 2.0);
      });
    });

    group('formatCurrency', () {
      test('formats EGP currency', () {
        final result = AppUtils.formatCurrency(1234567.5);
        expect(result, contains('ج.م'));
      });

      test('formats USD currency', () {
        final result = AppUtils.formatCurrency(1234567.5, 'USD');
        expect(result, contains('\$'));
      });

      test('formats EUR currency', () {
        final result = AppUtils.formatCurrency(100, 'EUR');
        expect(result, contains('\u20AC'));
      });

      test('formats GBP currency', () {
        final result = AppUtils.formatCurrency(100, 'GBP');
        expect(result, contains('\u00A3'));
      });
    });

    group('currencySymbol', () {
      test('returns correct symbols', () {
        expect(AppUtils.currencySymbol('USD'), '\$');
        expect(AppUtils.currencySymbol('EUR'), '\u20AC');
        expect(AppUtils.currencySymbol('GBP'), '\u00A3');
        expect(AppUtils.currencySymbol('EGP'), 'ج.م');
      });

      test('handles lowercase input', () {
        expect(AppUtils.currencySymbol('usd'), '\$');
      });

      test('returns code for unknown currency', () {
        expect(AppUtils.currencySymbol('JPY'), 'JPY');
      });
    });

    group('currencyName', () {
      test('returns correct Arabic names', () {
        expect(AppUtils.currencyName('EGP'), 'مصري');
        expect(AppUtils.currencyName('USD'), 'دولار');
        expect(AppUtils.currencyName('EUR'), 'يورو');
        expect(AppUtils.currencyName('GBP'), 'استرليني');
      });

      test('handles lowercase input', () {
        expect(AppUtils.currencyName('usd'), 'دولار');
      });

      test('returns code for unknown currency', () {
        expect(AppUtils.currencyName('JPY'), 'JPY');
      });
    });

    group('formatNumber', () {
      test('formats with comma separators', () {
        expect(AppUtils.formatNumber(1234567.50), '1,234,567.50');
      });

      test('formats small number', () {
        expect(AppUtils.formatNumber(999.99), '999.99');
      });

      test('formats zero', () {
        expect(AppUtils.formatNumber(0), '0.00');
      });

      test('formats negative number', () {
        expect(AppUtils.formatNumber(-1234567.50), '-1,234,567.50');
      });

      test('formats exact thousands', () {
        expect(AppUtils.formatNumber(1000), '1,000.00');
      });

      test('formats millions', () {
        expect(AppUtils.formatNumber(1000000), '1,000,000.00');
      });
    });

    group('numberToArabicWords', () {
      test('converts zero', () {
        expect(AppUtils.numberToArabicWords(0), 'صفر جنيهاً');
      });

      test('converts simple number', () {
        final result = AppUtils.numberToArabicWords(1);
        expect(result, contains('واحد'));
        expect(result, contains('جنيهاً'));
      });

      test('converts number with piasters', () {
        final result = AppUtils.numberToArabicWords(1.50);
        expect(result, contains('جنيهاً'));
        expect(result, contains('قرشاً'));
      });

      test('converts negative number', () {
        final result = AppUtils.numberToArabicWords(-100);
        expect(result, contains('سالب'));
      });
    });

    group('isNullOrEmpty', () {
      test('returns true for null', () {
        expect(AppUtils.isNullOrEmpty(null), isTrue);
      });

      test('returns true for empty string', () {
        expect(AppUtils.isNullOrEmpty(''), isTrue);
      });

      test('returns true for whitespace-only string', () {
        expect(AppUtils.isNullOrEmpty('   '), isTrue);
      });

      test('returns false for non-empty string', () {
        expect(AppUtils.isNullOrEmpty('hello'), isFalse);
      });
    });

    group('generateCode', () {
      test('generates code with prefix and padded id', () {
        expect(AppUtils.generateCode('INV', 1), 'INV000001');
      });

      test('handles large id', () {
        expect(AppUtils.generateCode('INV', 999999), 'INV999999');
      });
    });

    group('asMap', () {
      test('returns map from Map<String, dynamic>', () {
        final input = {'key': 'value'};
        expect(AppUtils.asMap(input), input);
      });

      test('returns map from generic Map', () {
        final input = <String, dynamic>{'key': 'value'};
        expect(AppUtils.asMap(input), input);
      });

      test('returns first item from List<Map>', () {
        final input = [{'key': 'value1'}, {'key': 'value2'}];
        expect(AppUtils.asMap(input), {'key': 'value1'});
      });

      test('returns null for null', () {
        expect(AppUtils.asMap(null), isNull);
      });

      test('returns null for empty list', () {
        expect(AppUtils.asMap([]), isNull);
      });

      test('returns null for non-map/non-list', () {
        expect(AppUtils.asMap('string'), isNull);
      });
    });

    group('embeddedString', () {
      test('extracts string from map', () {
        final input = {'name': 'Test'};
        expect(AppUtils.embeddedString(input, 'name'), 'Test');
      });

      test('returns null for missing key', () {
        final input = {'name': 'Test'};
        expect(AppUtils.embeddedString(input, 'missing'), isNull);
      });

      test('returns null for null input', () {
        expect(AppUtils.embeddedString(null, 'name'), isNull);
      });
    });

    group('costCategoryLabel', () {
      test('returns correct Arabic labels', () {
        expect(AppUtils.costCategoryLabel('freight'), 'شحن');
        expect(AppUtils.costCategoryLabel('clearance'), 'تخليص جمركي');
        expect(AppUtils.costCategoryLabel('admin'), 'مصاريف إدارية');
        expect(AppUtils.costCategoryLabel('packing'), 'تعبئة وتغليف');
        expect(AppUtils.costCategoryLabel('logistics'), 'لوجستيك ونقل');
      });

      test('returns input for unknown category', () {
        expect(AppUtils.costCategoryLabel('unknown_category'), 'unknown_category');
      });

      test('handles PACKAGING synonym', () {
        expect(AppUtils.costCategoryLabel('PACKAGING'), 'تعبئة وتغليف');
      });
    });
  });
}
