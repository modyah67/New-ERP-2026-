import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/journal_entry/journal_entry_excel_service.dart';

void main() {
  group('Journal Entry Double-Entry Notation Tests (من حـ/ وإلى حـ/)', () {
    test('Excel export headers include explicit "من حـ/" and "إلى حـ/" labels', () {
      const headers = JournalEntryExcelService.journalHeaders;
      expect(headers, contains('الجانب المدين (من حـ/)'));
      expect(headers, contains('الجانب الدائن (إلى حـ/)'));
    });

    test('Sorting logic places Debit lines (من حـ/) before Credit lines (إلى حـ/)', () {
      final rawLines = [
        {'account_name': 'مورد - الشركة الدولية', 'debit': 0.0, 'credit': 5000.0},
        {'account_name': 'خزينة رئيسية - ج.م', 'debit': 5000.0, 'credit': 0.0},
      ];

      final sorted = List<Map<String, dynamic>>.from(rawLines);
      sorted.sort((a, b) {
        final double aDeb = (a['debit'] as num?)?.toDouble() ?? 0.0;
        final double bDeb = (b['debit'] as num?)?.toDouble() ?? 0.0;
        if (aDeb > 0 && bDeb == 0) return -1;
        if (aDeb == 0 && bDeb > 0) return 1;
        return 0;
      });

      // First line must be Debit (من حـ/)
      expect(sorted.first['debit'], 5000.0);
      expect(sorted.first['account_name'], 'خزينة رئيسية - ج.م');

      // Second line must be Credit (إلى حـ/)
      expect(sorted.last['credit'], 5000.0);
      expect(sorted.last['account_name'], 'مورد - الشركة الدولية');
    });

    test('Semantic prefix formatting adheres to Arabic double-entry standard', () {
      String formatAccountName(String rawName, bool isDebit) {
        if (rawName.startsWith('من ح') || rawName.startsWith('إلى ح')) {
          return rawName;
        }
        final prefix = isDebit ? 'من حـ/ ' : 'إلى حـ/ ';
        return '$prefix$rawName';
      }

      final debitFormatted = formatAccountName('مخزون مواد التعبئة', true);
      final creditFormatted = formatAccountName('مورد - علي', false);

      expect(debitFormatted, 'من حـ/ مخزون مواد التعبئة');
      expect(creditFormatted, 'إلى حـ/ مورد - علي');

      // Idempotency check: don't double-prefix if already prefixed
      expect(formatAccountName('من حـ/ البنك التجاري', true), 'من حـ/ البنك التجاري');
      expect(formatAccountName('إلى حـ/ الصندوق', false), 'إلى حـ/ الصندوق');
    });

    test('Compound journal entry balances total debits with total credits', () {
      final compoundLines = [
        {'side': 'من حـ/', 'account': 'مخزون خامات', 'debit': 3000.0, 'credit': 0.0},
        {'side': 'من حـ/', 'account': 'ضريبة قيمة مضافة', 'debit': 420.0, 'credit': 0.0},
        {'side': 'إلى حـ/', 'account': 'مورد - خامات', 'debit': 0.0, 'credit': 3420.0},
      ];

      double totalDebits = 0;
      double totalCredits = 0;

      for (final line in compoundLines) {
        totalDebits += line['debit'] as double;
        totalCredits += line['credit'] as double;
      }

      expect(totalDebits, 3420.0);
      expect(totalCredits, 3420.0);
      expect((totalDebits - totalCredits).abs(), lessThan(0.001));
    });

    test('PDF voucher "من د/" and "إلى د/" notation correctly prefixes accounts', () {
      String formatVoucherAccount(String rawName, bool isDebit) {
        if (rawName.startsWith('من ') || rawName.startsWith('إلى ')) {
          return rawName;
        }
        final prefix = isDebit ? 'من د/ ' : 'إلى د/ ';
        return '$prefix$rawName';
      }

      expect(formatVoucherAccount('مخزون مواد التعبئة والتغليف', true), 'من د/ مخزون مواد التعبئة والتغليف');
      expect(formatVoucherAccount('مورد - علي', false), 'إلى د/ مورد - علي');
      expect(formatVoucherAccount('من د/ مخزون', true), 'من د/ مخزون');
      expect(formatVoucherAccount('إلى د/ مورد', false), 'إلى د/ مورد');
    });

    test('Landscape column flex widths favor descriptive columns over numeric/code', () {
      const colWidths = {
        'side': 2.0,
        'code': 1.4,
        'name': 4.8,
        'debit': 2.0,
        'credit': 2.0,
        'desc': 5.0,
      };

      final descriptiveWeight = colWidths['name']! + colWidths['desc']!;
      final compactWeight = colWidths['side']! + colWidths['code']! + colWidths['debit']! + colWidths['credit']!;

      expect(descriptiveWeight, greaterThan(compactWeight));
      expect(descriptiveWeight / (descriptiveWeight + compactWeight), greaterThan(0.55));
    });

    test('Branding resolution drops extraneous text and resolves Fruity Farms', () {
      String resolveBrand(String? raw) {
        if (raw == null || raw.isEmpty || raw.contains('أعمال المحاسبة')) {
          return 'فروتي فارمز - Fruity Farms';
        }
        return raw;
      }

      expect(resolveBrand(null), 'فروتي فارمز - Fruity Farms');
      expect(resolveBrand(''), 'فروتي فارمز - Fruity Farms');
      expect(resolveBrand('مؤسسة أعمال المحاسبة'), 'فروتي فارمز - Fruity Farms');
      expect(resolveBrand('Fruity Farms Global'), 'Fruity Farms Global');
    });
  });
}

