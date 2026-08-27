import 'package:accounting_system/accounting/reporting/models/report_models.dart';

class TransactionFixtures {
  TransactionFixtures._();

  // ── SQL-written rows (debit/credit columns) ──

  static List<Map<String, dynamic>> get sqlDebitCreditRows => [
        {
          'id': '1',
          'account_id': '1',
          'debit': 50000.0,
          'credit': 0.0,
          'date': '2025-01-15',
          'transaction_date': '2025-01-15',
          'description': 'Opening cash balance',
          'entry_number': 1,
        },
        {
          'id': '2',
          'account_id': '1',
          'debit': 0.0,
          'credit': 10000.0,
          'date': '2025-02-10',
          'transaction_date': '2025-02-10',
          'description': 'Payment to supplier',
          'entry_number': 2,
        },
        {
          'id': '3',
          'account_id': '2',
          'debit': 25000.0,
          'credit': 0.0,
          'date': '2025-01-20',
          'transaction_date': '2025-01-20',
          'description': 'Invoice to customer',
          'entry_number': 3,
        },
        {
          'id': '4',
          'account_id': '2',
          'debit': 0.0,
          'credit': 15000.0,
          'date': '2025-03-05',
          'transaction_date': '2025-03-05',
          'description': 'Customer payment received',
          'entry_number': 4,
        },
        {
          'id': '5',
          'account_id': '4',
          'debit': 0.0,
          'credit': 8000.0,
          'date': '2025-01-25',
          'transaction_date': '2025-01-25',
          'description': 'Purchase invoice',
          'entry_number': 5,
        },
        {
          'id': '6',
          'account_id': '4',
          'debit': 3000.0,
          'credit': 0.0,
          'date': '2025-02-15',
          'transaction_date': '2025-02-15',
          'description': 'Payment to supplier',
          'entry_number': 6,
        },
        {
          'id': '7',
          'account_id': '8',
          'debit': 0.0,
          'credit': 120000.0,
          'date': '2025-01-31',
          'transaction_date': '2025-01-31',
          'description': 'Monthly sales revenue',
          'entry_number': 7,
        },
        {
          'id': '8',
          'account_id': '10',
          'debit': 75000.0,
          'credit': 0.0,
          'date': '2025-01-31',
          'transaction_date': '2025-01-31',
          'description': 'COGS for January',
          'entry_number': 8,
        },
        {
          'id': '9',
          'account_id': '11',
          'debit': 30000.0,
          'credit': 0.0,
          'date': '2025-01-31',
          'transaction_date': '2025-01-31',
          'description': 'Salaries for January',
          'entry_number': 9,
        },
        {
          'id': '10',
          'account_id': '12',
          'debit': 12000.0,
          'credit': 0.0,
          'date': '2025-01-31',
          'transaction_date': '2025-01-31',
          'description': 'Rent for January',
          'entry_number': 10,
        },
      ];

  // ── Dart-written rows (type/amount columns) ──

  static List<Map<String, dynamic>> get dartTypeAmountRows => [
        {
          'id': '101',
          'account_id': '1',
          'type': 'debit',
          'amount': 20000.0,
          'debit': 0,
          'credit': 0,
          'date': '2025-04-01',
          'transaction_date': '2025-04-01',
          'description': 'Cash deposit',
          'entry_number': 11,
        },
        {
          'id': '102',
          'account_id': '1',
          'type': 'credit',
          'amount': 5000.0,
          'debit': 0,
          'credit': 0,
          'date': '2025-04-05',
          'transaction_date': '2025-04-05',
          'description': 'Expense payment',
          'entry_number': 12,
        },
        {
          'id': '103',
          'account_id': '8',
          'type': 'credit',
          'amount': 50000.0,
          'debit': 0,
          'credit': 0,
          'date': '2025-04-10',
          'transaction_date': '2025-04-10',
          'description': 'Sales invoice',
          'entry_number': 13,
        },
      ];

  // ── Multi-currency rows ──────────────────────

  static List<Map<String, dynamic>> get multiCurrencyRows => [
        {
          'id': '201',
          'account_id': '1',
          'debit': 5000.0,
          'credit': 0.0,
          'date': '2025-01-15',
          'transaction_date': '2025-01-15',
          'description': 'USD deposit',
          'currency_snapshot': '{"currency": "USD", "rate": 50.0}',
          'entry_number': 21,
        },
        {
          'id': '202',
          'account_id': '1',
          'debit': 0.0,
          'credit': 2000.0,
          'date': '2025-02-10',
          'transaction_date': '2025-02-10',
          'description': 'EUR payment',
          'currency_snapshot': '{"currency": "EUR", "rate": 55.0}',
          'entry_number': 22,
        },
        {
          'id': '203',
          'account_id': '1',
          'debit': 3000.0,
          'credit': 0.0,
          'date': '2025-03-15',
          'transaction_date': '2025-03-15',
          'description': 'GBP deposit',
          'currency_snapshot': '{"currency": "GBP", "rate": 63.0}',
          'entry_number': 23,
        },
      ];

  // ── Balanced dataset for Trial Balance ───────

  static List<Map<String, dynamic>> get balancedTrialBalanceDataset => [
        // Cash: debit 50,000
        {
          'account_id': '1',
          'debit': 50000.0,
          'credit': 0.0,
        },
        // AR: debit 25,000
        {
          'account_id': '2',
          'debit': 25000.0,
          'credit': 0.0,
        },
        // AP: credit 8,000
        {
          'account_id': '4',
          'debit': 0.0,
          'credit': 8000.0,
        },
        // Loans: credit 20,000
        {
          'account_id': '5',
          'debit': 0.0,
          'credit': 20000.0,
        },
        // Equity: credit 47,000
        {
          'account_id': '6',
          'debit': 0.0,
          'credit': 47000.0,
        },
      ];

  // ── Unbalanced dataset ───────────────────────

  static List<Map<String, dynamic>> get unbalancedTrialBalanceDataset => [
        {
          'account_id': '1',
          'debit': 50000.0,
          'credit': 0.0,
        },
        {
          'account_id': '4',
          'debit': 0.0,
          'credit': 30000.0,
        },
        // Missing equity to balance
      ];

  // ── Large dataset for performance tests ──────

  static List<Map<String, dynamic>> generateLargeDataset(int count) {
    final rows = <Map<String, dynamic>>[];
    final accountIds = ['1', '2', '4', '5', '6', '8', '10', '11', '12'];

    for (var i = 0; i < count; i++) {
      final isDebit = i % 2 == 0;
      final accountId = accountIds[i % accountIds.length];
      final amount = (i * 100.0) + 1.0;

      rows.add({
        'id': '$i',
        'account_id': accountId,
        'debit': isDebit ? amount : 0.0,
        'credit': isDebit ? 0.0 : amount,
        'date': '2025-${(i % 12 + 1).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
        'transaction_date':
            '2025-${(i % 12 + 1).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
        'description': 'Transaction $i',
        'entry_number': i + 1,
      });
    }
    return rows;
  }

  // ── Currency exchange rates ──────────────────

  static Map<String, double> get exchangeRates => {
        'EGP': 1.0,
        'USD': 50.0,
        'EUR': 55.0,
        'GBP': 63.0,
      };

  // ── Treasury transactions ────────────────────

  static List<Map<String, dynamic>> get treasuryTransactions => [
        {
          'id': 't1',
          'type': 'deposit',
          'amount': 100000.0,
          'currency': 'EGP',
          'description': 'Customer payment',
          'created_at': '2025-01-15T10:00:00Z',
        },
        {
          'id': 't2',
          'type': 'withdrawal',
          'amount': 30000.0,
          'currency': 'EGP',
          'description': 'Supplier payment',
          'created_at': '2025-01-20T14:00:00Z',
        },
        {
          'id': 't3',
          'type': 'expense',
          'amount': 12000.0,
          'currency': 'EGP',
          'description': 'Rent payment',
          'created_at': '2025-01-31T09:00:00Z',
        },
        {
          'id': 't4',
          'type': 'deposit',
          'amount': 5000.0,
          'currency': 'USD',
          'description': 'USD deposit',
          'created_at': '2025-02-10T11:00:00Z',
        },
        {
          'id': 't5',
          'type': 'transfer_out',
          'amount': 20000.0,
          'currency': 'EGP',
          'description': 'Transfer to bank',
          'created_at': '2025-02-15T16:00:00Z',
        },
      ];

  // ── Bank transactions ────────────────────────

  static List<Map<String, dynamic>> get bankTransactions => [
        {
          'id': 'b1',
          'type': 'deposit',
          'amount': 50000.0,
          'bank_currency': 'EGP',
          'description': 'Bank deposit',
          'created_at': '2025-01-20T12:00:00Z',
        },
        {
          'id': 'b2',
          'type': 'withdrawal',
          'amount': 15000.0,
          'bank_currency': 'EGP',
          'description': 'ATM withdrawal',
          'created_at': '2025-02-05T10:00:00Z',
        },
        {
          'id': 'b3',
          'type': 'deposit',
          'amount': 3000.0,
          'bank_currency': 'USD',
          'description': 'USD wire transfer',
          'created_at': '2025-03-01T09:00:00Z',
        },
      ];

  // ── Validation hierarchy ─────────────────────

  static List<AccountHierarchy> get validHierarchy => [
        const AccountHierarchy(
          id: 'a1',
          code: '1000',
          name: 'Assets',
          nameAr: 'الأصول',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: 'a2',
          code: '1100',
          name: 'Cash',
          nameAr: 'النقدية',
          classification: AccountClassification.asset,
          parentId: 'a1',
        ),
        const AccountHierarchy(
          id: 'a3',
          code: '2000',
          name: 'Liabilities',
          nameAr: 'الخصوم',
          classification: AccountClassification.liability,
        ),
      ];

  static List<AccountHierarchy> get hierarchyWithMissingParent => [
        const AccountHierarchy(
          id: 'b1',
          code: '1000',
          name: 'Assets',
          nameAr: 'الأصول',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: 'b2',
          code: '1100',
          name: 'Cash',
          nameAr: 'النقدية',
          classification: AccountClassification.asset,
          parentId: 'NONEXISTENT',
        ),
      ];

  static List<AccountHierarchy> get hierarchyWithDuplicates => [
        const AccountHierarchy(
          id: 'c1',
          code: '1000',
          name: 'Assets',
          nameAr: 'الأصول',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: 'c1',
          code: '1001',
          name: 'Assets Duplicate',
          nameAr: 'الأصول مكرر',
          classification: AccountClassification.asset,
        ),
      ];

  // ── Account totals for calculation service ───

  static List<Map<String, dynamic>> get accountTotalsForCalculation => [
        {
          'account_id': '1',
          'debit': 50000.0,
          'credit': 10000.0,
        },
        {
          'account_id': '2',
          'debit': 25000.0,
          'credit': 15000.0,
        },
        {
          'account_id': '4',
          'debit': 3000.0,
          'credit': 8000.0,
        },
        {
          'account_id': '5',
          'debit': 0.0,
          'credit': 20000.0,
        },
        {
          'account_id': '6',
          'debit': 0.0,
          'credit': 47000.0,
        },
        {
          'account_id': '8',
          'debit': 0.0,
          'credit': 95000.0,
        },
        {
          'account_id': '10',
          'debit': 75000.0,
          'credit': 0.0,
        },
        {
          'account_id': '11',
          'debit': 30000.0,
          'credit': 0.0,
        },
        {
          'account_id': '12',
          'debit': 12000.0,
          'credit': 0.0,
        },
      ];
}
