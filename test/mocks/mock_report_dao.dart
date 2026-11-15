import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/accounting/reporting/dao/report_dao.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

bool _supabaseInitialized = false;

class MockReportDao extends ReportDao {
  List<AccountHierarchy>? accountsToReturn;
  List<Map<String, dynamic>>? transactionsToReturn;
  List<Map<String, dynamic>>? accountTotalsToReturn;
  ({double debit, double credit})? balanceBeforeDateToReturn;
  Map<String, double>? exchangeRatesToReturn;
  List<Map<String, dynamic>>? treasuryTxToReturn;
  List<Map<String, dynamic>>? bankTxToReturn;
  Map<String, double>? storedBalancesToReturn;
  List<Map<String, dynamic>>? entityLedgerToReturn;
  Exception? exceptionToThrow;

  static Future<void> ensureInitialized() async {
    if (!_supabaseInitialized) {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      try {
        await Supabase.initialize(
          url: 'https://test.supabase.co',
          anonKey: 'test-anon-key',
        );
        _supabaseInitialized = true;
      } catch (_) {
        // Supabase may already be initialized in the same isolate (e.g. by
        // another test file). Check if the instance is actually available
        // before marking as initialized.
        try {
          // ignore: unused_local_variable
          final client = Supabase.instance.client;
          _supabaseInitialized = true;
        } catch (_) {
          // If we can't access the client, rethrow the original error
          rethrow;
        }
      }
    }
  }

  void reset() {
    accountsToReturn = null;
    transactionsToReturn = null;
    accountTotalsToReturn = null;
    balanceBeforeDateToReturn = null;
    exchangeRatesToReturn = null;
    treasuryTxToReturn = null;
    bankTxToReturn = null;
    storedBalancesToReturn = null;
    entityLedgerToReturn = null;
    exceptionToThrow = null;
  }

  @override
  Future<List<AccountHierarchy>> getAllAccounts() async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return accountsToReturn ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> getAccountTotals({
    String? currency,
    DateTime? fromDate,
    DateTime? toDate,
    bool excludeClosing = false,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return accountTotalsToReturn ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> getTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? accountId,
    String? accountType,
    String? entityType,
    String? entityId,
    int? limit,
    int? offset,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    var result = transactionsToReturn ?? [];
    if (accountId != null) {
      result = result.where((r) => r['account_id'] == accountId).toList();
    }
    return result;
  }

  @override
  Future<({double debit, double credit})> getBalanceBeforeDate({
    required String accountId,
    required DateTime beforeDate,
    String? currency,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return balanceBeforeDateToReturn ?? (debit: 0.0, credit: 0.0);
  }

  @override
  Future<Map<String, double>> getExchangeRates() async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return exchangeRatesToReturn ?? {'EGP': 1.0, 'USD': 50.0};
  }

  @override
  Future<List<Map<String, dynamic>>> getTreasuryTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? currency,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return treasuryTxToReturn ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>> getBankTransactions({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return bankTxToReturn ?? [];
  }

  @override
  Future<Map<String, double>> getStoredAccountBalances() async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return storedBalancesToReturn ?? {};
  }

  @override
  Future<List<Map<String, dynamic>>> getEntityLedger({
    required String entityType,
    required String entityId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return entityLedgerToReturn ?? [];
  }
}
