import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/data/services/chart_of_accounts_service.dart';
import 'package:accounting_system/accounting/fiscal_year/models/closing_entry.dart';
import 'package:accounting_system/accounting/fiscal_year/services/closing_validation_service.dart';
import 'package:accounting_system/accounting/fiscal_year/dao/fiscal_year_dao.dart';

class MockFiscalYearDao extends Fake implements FiscalYearDao {
  final Map<String, Map<String, double>> accountTotals;
  final List<Map<String, dynamic>> permanentAccounts;

  MockFiscalYearDao({
    required this.accountTotals,
    required this.permanentAccounts,
  });

  @override
  Future<List<Map<String, dynamic>>> getExpenseAccounts() async => [];

  @override
  Future<List<Map<String, dynamic>>> getRevenueAccounts() async => [];

  @override
  Future<List<Map<String, dynamic>>> getPermanentAccounts() async => permanentAccounts;

  @override
  Future<Map<String, double>> getAccountTotals(String accountCode, int fiscalYearId) async {
    return accountTotals[accountCode] ?? {'debit': 0.0, 'credit': 0.0};
  }
}

void main() {
  group('Opening Balance Suspense Account (2342 / 23421) Tests', () {
    test('1. Hierarchy & AccountModel evaluation for 2342 (L4) and 23421 (L5)', () {
      final acc234 = AccountModel(
        code: '234',
        name: 'Retained Earnings Group',
        accountName: 'أرباح \\ خسائر مرحله',
        type: 'equity',
        parentId: 'id_23',
      );
      final acc2342 = AccountModel(
        code: '2342',
        name: 'Opening Balance Suspense Control',
        accountName: 'فروق أرصدة افتتاحية',
        type: 'equity',
        parentId: 'id_234',
      );
      final acc23421 = AccountModel(
        code: '23421',
        name: 'Opening Balance Suspense Account',
        accountName: 'رصيد افتتاحي',
        type: 'equity',
        parentId: 'id_2342',
      );

      // Level 3
      expect(acc234.evaluatedLevel, equals(3));
      expect(acc234.levelLabel, equals('مستوى 3 - فرعي'));

      // Level 4 (Control - non-postable)
      expect(acc2342.evaluatedLevel, equals(4));
      expect(acc2342.levelLabel, equals('مستوى 4 - تحليلي'));

      // Level 5 (Posting - postable)
      expect(acc23421.evaluatedLevel, equals(5));
      expect(acc23421.levelLabel, equals('مستوى 5 - حساب ترحيل'));
      expect(acc23421.type, equals('equity'));

      // Standard Arabic Names
      expect(AccountModel.getStandardArabicName('234'), equals('أرباح / خسائر مرحلة'));
      expect(AccountModel.getStandardArabicName('2341'), equals('أرباح / خسائر مرحلة'));
      expect(AccountModel.getStandardArabicName('23411'), equals('أرباح / خسائر مرحلة'));
      expect(AccountModel.getStandardArabicName('2342'), equals('فروق أرصدة افتتاحية'));
      expect(AccountModel.getStandardArabicName('23421'), equals('رصيد افتتاحي'));
    });

    test('2. ChartOfAccountsService default tree contains 2342 and 23421', () {
      final coa = ChartOfAccountsService.defaultAccounts;
      final acc2342 = coa.firstWhere((a) => a['account_code'] == '2342', orElse: () => {});
      final acc23421 = coa.firstWhere((a) => a['account_code'] == '23421', orElse: () => {});

      expect(acc2342.isNotEmpty, isTrue);
      expect(acc2342['account_name'], equals('فروق أرصدة افتتاحية'));
      expect(acc2342['account_type'], equals('equity'));

      expect(acc23421.isNotEmpty, isTrue);
      expect(acc23421['account_name'], equals('رصيد افتتاحي'));
      expect(acc23421['account_type'], equals('equity'));
    });

    test('3. Year-End Closing: 23421 balance is closed into 23411 (Retained Earnings)', () async {
      // Scenario: During the year, net opening balance differences in 23421 is 50,000 Credit
      final mockDao = MockFiscalYearDao(
        accountTotals: {
          '23421': {'debit': 0.0, 'credit': 50000.0},
          '23411': {'debit': 0.0, 'credit': 100000.0},
        },
        permanentAccounts: [
          {'account_code': '11111', 'name': 'Treasury', 'account_type': 'asset'},
          {'account_code': '23411', 'name': 'Retained Earnings', 'account_type': 'equity'},
          {'account_code': '23421', 'name': 'Opening Suspense', 'account_type': 'equity'},
        ],
      );

      final dummyClient = SupabaseClient('https://mock.supabase.co', 'mock-anon-key');
      final closingService = ClosingValidationService(client: dummyClient, dao: mockDao);
      final closingEntries = await closingService.generateClosingEntries(1);

      // Verify that 23421 is zeroed out by a debit closing entry
      final suspenseClosing = closingEntries.where((e) => e.accountCode == '23421').toList();
      expect(suspenseClosing.length, equals(1));
      expect(suspenseClosing.first.debit, equals(50000.0));
      expect(suspenseClosing.first.credit, equals(0.0));
      expect(suspenseClosing.first.entryType, anyOf(equals('TRANSFER_RETAINED'), equals('CLOSE_OPENING_SUSPENSE')));

      // Verify that the balance is transferred to Retained Earnings (23411)
      final retainedTransfers = closingEntries.where((e) => e.accountCode == '23421' || (e.accountCode == '23411' && (e.description?.contains('ترحيل فروق') == true))).toList();
      expect(retainedTransfers.length, equals(2));
      final retainedTransfer = closingEntries.firstWhere((e) => e.accountCode == '23411' && (e.description?.contains('ترحيل فروق') == true));
      expect(retainedTransfer.credit, equals(50000.0));
      expect(retainedTransfer.debit, equals(0.0));
    });

    test('4. Year-End Opening: 23421 is excluded from new fiscal year opening entries', () async {
      final mockDao = MockFiscalYearDao(
        accountTotals: {
          '11111': {'debit': 20000.0, 'credit': 0.0},
          '23411': {'debit': 0.0, 'credit': 150000.0},
          '23421': {'debit': 0.0, 'credit': 50000.0}, // Even if previous year had entries, it must not carry over
        },
        permanentAccounts: [
          {'account_code': '11111', 'name': 'Treasury', 'account_type': 'asset'},
          {'account_code': '23411', 'name': 'Retained Earnings', 'account_type': 'equity'},
          {'account_code': '23421', 'name': 'Opening Suspense', 'account_type': 'equity'},
        ],
      );

      final dummyClient = SupabaseClient('https://mock.supabase.co', 'mock-anon-key');
      final closingService = ClosingValidationService(client: dummyClient, dao: mockDao);
      final openingEntries = await closingService.generateOpeningEntries(1);

      // 23421 MUST NOT appear in opening entries for the new fiscal year
      final has23421 = openingEntries.any((e) => e.accountCode == '23421');
      expect(has23421, isFalse);

      // Normal permanent accounts do appear
      final has11111 = openingEntries.any((e) => e.accountCode == '11111');
      expect(has11111, isTrue);
    });
  });
}
