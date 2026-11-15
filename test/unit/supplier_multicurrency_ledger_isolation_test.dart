import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:accounting_system/features/suppliers/supplier_account_statement_state.dart';

void main() {
  group('Supplier Multi-Currency Ledger Isolation & Formatting Tests', () {
    test('SupplierModel.formattedCurrentBalance formats separate currencies cleanly', () {
      final supplier = SupplierModel(
        supplierCode: '50000',
        name: 'وليد',
        isMultiCurrency: true,
        currency: 'MULTI',
        supportedCurrencies: const ['EGP', 'USD'],
        initialBalancesByCurrency: const {
          'EGP': SupplierCurrencyBalance(currency: 'EGP', amount: 100.0, direction: 'CREDIT'),
          'USD': SupplierCurrencyBalance(currency: 'USD', amount: 100.0, direction: 'CREDIT', exchangeRate: 50.0),
        },
        currentBalancesByCurrency: const {
          'EGP': 100.0,
          'USD': 100.0,
        },
        outstandingBalance: 5100.0,
      );

      // Verify native breakdown displays independently without string-concatenating raw sums
      expect(supplier.formattedCurrentBalance, contains('100 ج.م'));
      expect(supplier.formattedCurrentBalance, contains('100 \$'));
      expect(supplier.formattedCurrentBalance, '100 ج.م + 100 \$');
    });

    test('SupplierModel.formattedCurrentBalance reflects changes after isolated currency purchase', () {
      final supplier = SupplierModel(
        supplierCode: '50000',
        name: 'وليد',
        isMultiCurrency: true,
        currency: 'MULTI',
        supportedCurrencies: const ['EGP', 'USD'],
        currentBalancesByCurrency: const {
          'EGP': 100.0,
          'USD': 600.0, // After $500 USD purchase
        },
        outstandingBalance: 30100.0,
      );

      expect(supplier.formattedCurrentBalance, '100 ج.م + 600 \$');
    });

    test('StatementRow tracks running balance strictly per currency stream', () {
      // Simulate statement stream with segregated currency running balances:
      // Opening: 100 EGP, 100 USD
      final openingEgp = StatementRow(
        transactionNumber: '-',
        date: '2026-09-01',
        accountName: 'رصيد سابق',
        description: 'رصيد سابق (EGP)',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 0,
        credit: 100.0,
        balance: 100.0,
        type: 'opening',
        createdAt: '2026-09-01T00:00:00Z',
        currency: 'EGP',
      );

      final openingUsd = StatementRow(
        transactionNumber: '-',
        date: '2026-09-01',
        accountName: 'رصيد سابق',
        description: 'رصيد سابق (USD)',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 0,
        credit: 100.0,
        balance: 100.0,
        type: 'opening',
        createdAt: '2026-09-01T00:00:00Z',
        currency: 'USD',
      );

      // Transaction 1: USD purchase invoice of $500
      // Transaction 2: EGP cash payment of 50 EGP
      final runningByCur = <String, double>{
        'EGP': 100.0,
        'USD': 100.0,
      };

      final tx1 = StatementRow(
        transactionNumber: 'INV-101',
        date: '2026-09-02',
        accountName: 'مشتريات',
        description: 'فاتورة مشتريات بالدولار',
        piecesCount: 1,
        quantity: 10,
        unitPrice: 50,
        debit: 0,
        credit: 500.0,
        balance: 0,
        type: 'purchase',
        createdAt: '2026-09-02T10:00:00Z',
        currency: 'USD',
      );

      final cur1 = tx1.currency!;
      runningByCur[cur1] = (runningByCur[cur1] ?? 0) + (tx1.credit - tx1.debit);
      final tx1WithBal = tx1.copyWith(balance: runningByCur[cur1]);

      expect(tx1WithBal.balance, 600.0);
      expect(tx1WithBal.currency, 'USD');
      // EGP balance remains untouched at 100.0
      expect(runningByCur['EGP'], 100.0);

      final tx2 = StatementRow(
        transactionNumber: 'PAY-201',
        date: '2026-09-03',
        accountName: 'سداد نقدي',
        description: 'سداد نقدي من الخزينة بالجنيه',
        piecesCount: 0,
        quantity: 0,
        unitPrice: 0,
        debit: 50.0,
        credit: 0,
        balance: 0,
        type: 'treasury',
        createdAt: '2026-09-03T11:00:00Z',
        currency: 'EGP',
      );

      final cur2 = tx2.currency!;
      runningByCur[cur2] = (runningByCur[cur2] ?? 0) + (tx2.credit - tx2.debit);
      final tx2WithBal = tx2.copyWith(balance: runningByCur[cur2]);

      expect(tx2WithBal.balance, 50.0);
      expect(tx2WithBal.currency, 'EGP');
      // USD balance remains untouched at 600.0
      expect(runningByCur['USD'], 600.0);
    });

    test('SupplierAccountStatementLoaded exposes native badges and unified totals', () {
      const state = SupplierAccountStatementLoaded(
        totalDebit: 50.0,
        totalCredit: 25000.0, // $500 * 50
        finalBalance: 30050.0, // 50 EGP + 600 USD (30,000 EGP)
        finalBalancesByCurrency: {
          'EGP': 50.0,
          'USD': 600.0,
        },
        openingBalancesByCurrency: {
          'EGP': 100.0,
          'USD': 100.0,
        },
      );

      expect(state.formattedFinalBalances, '50 ج.م + 600 \$');
      expect(state.formattedOpeningBalances, '100 ج.م + 100 \$');
      expect(state.finalBalance, 30050.0);
    });

    test('SupplierAccountStatementLoaded with selectedCurrency formats isolated currency stream', () {
      const state = SupplierAccountStatementLoaded(
        selectedCurrency: 'USD',
        availableCurrencies: ['ALL', 'EGP', 'USD'],
        totalDebit: 0.0,
        totalCredit: 25000.0,
        finalBalance: 30000.0,
        finalBalancesByCurrency: {
          'USD': 600.0,
        },
        openingBalancesByCurrency: {
          'USD': 100.0,
        },
      );

      // When filtered to USD, formatted badges highlight the specific native currency stream
      expect(state.formattedFinalBalances, '600 \$');
      expect(state.formattedOpeningBalances, '100 \$');
      expect(state.selectedCurrency, 'USD');
      expect(state.availableCurrencies, containsAll(['ALL', 'EGP', 'USD']));
    });

    test('Filtering ledger rows by selected currency computes isolated running balance correctly', () {
      final rows = [
        StatementRow(
          transactionNumber: '-',
          date: '2026-09-01',
          accountName: 'رصيد سابق',
          description: 'رصيد سابق (USD)',
          piecesCount: 0, quantity: 0, unitPrice: 0, debit: 0, credit: 100.0,
          balance: 100.0, type: 'opening', createdAt: '', currency: 'USD',
        ),
        StatementRow(
          transactionNumber: '-',
          date: '2026-09-01',
          accountName: 'رصيد سابق',
          description: 'رصيد سابق (EGP)',
          piecesCount: 0, quantity: 0, unitPrice: 0, debit: 0, credit: 50.0,
          balance: 50.0, type: 'opening', createdAt: '', currency: 'EGP',
        ),
        StatementRow(
          transactionNumber: 'INV-1',
          date: '2026-09-02',
          accountName: 'مشتريات',
          description: 'فاتورة بالدولار',
          piecesCount: 1, quantity: 5, unitPrice: 100, debit: 0, credit: 500.0,
          balance: 0, type: 'purchase', createdAt: '2026-09-02T10:00:00Z', currency: 'USD',
        ),
        StatementRow(
          transactionNumber: 'PAY-1',
          date: '2026-09-03',
          accountName: 'سداد نقدي',
          description: 'سداد بالجنيه',
          piecesCount: 0, quantity: 0, unitPrice: 0, debit: 20.0, credit: 0,
          balance: 0, type: 'treasury', createdAt: '2026-09-03T11:00:00Z', currency: 'EGP',
        ),
      ];

      // Simulate filtering for 'USD'
      const curFilter = 'USD';
      final filtered = <StatementRow>[];
      double running = 100.0; // opening for USD

      for (final row in rows) {
        if (row.currency != curFilter) continue;
        if (row.type == 'opening' || row.type == 'initial') {
          running = row.balance;
          filtered.add(row);
          continue;
        }
        running += (row.credit - row.debit);
        filtered.add(row.copyWith(balance: running));
      }

      expect(filtered.length, 2);
      expect(filtered.every((r) => r.currency == 'USD'), isTrue);
      expect(filtered.first.balance, 100.0);
      expect(filtered.last.balance, 600.0);
      expect(filtered.last.transactionNumber, 'INV-1');
    });
  });
}
