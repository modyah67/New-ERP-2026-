import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:accounting_system/data/models/treasury_model.dart';
import 'package:accounting_system/data/models/bank_account_transaction_model.dart';
import 'package:accounting_system/data/models/bank_account_model.dart';
import 'package:accounting_system/features/treasury/treasury_state.dart';
import 'package:accounting_system/features/bank_accounts/bank_accounts_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Date Range Filtering Tests (Treasury, Custody & Bank Accounts)', () {
    test('TreasuryLoaded filters transactions strictly by date range', () {
      final t1 = TreasuryTransactionModel(
        id: '1',
        treasuryId: '10',
        amount: 500,
        currency: 'EGP',
        transactionType: 'deposit',
        createdAt: '2026-05-10T10:00:00Z',
        balanceAfter: 500,
      );
      final t2 = TreasuryTransactionModel(
        id: '2',
        treasuryId: '10',
        amount: 300,
        currency: 'EGP',
        transactionType: 'expense',
        createdAt: '2026-05-20T10:00:00Z',
        balanceAfter: 200,
      );
      final t3 = TreasuryTransactionModel(
        id: '3',
        treasuryId: '10',
        amount: 100,
        currency: 'EGP',
        transactionType: 'deposit',
        createdAt: '2026-06-01T10:00:00Z',
        balanceAfter: 300,
      );

      final stateAll = TreasuryLoaded(
        treasuries: [
          const TreasuryModel(
            id: '10',
            name: 'الخزينة الرئيسية',
            type: 'main',
            createdAt: '2026-01-01',
          ),
        ],
        transactions: [t1, t2, t3],
      );

      // No date filter => all 3 transactions
      expect(stateAll.filteredTransactions.length, 3);

      // Filter: May 15 to May 25 => only t2
      final stateFiltered = stateAll.copyWith(
        startDate: DateTime(2026, 5, 15),
        endDate: DateTime(2026, 5, 25),
      );
      expect(stateFiltered.filteredTransactions.length, 1);
      expect(stateFiltered.filteredTransactions.first.id, '2');

      // Filter: May 01 to May 25 => t1 and t2
      final stateMay = stateAll.copyWith(
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 25),
      );
      expect(stateMay.filteredTransactions.length, 2);
    });

    test('Custody TreasuryLoaded correctly identifies custody and filters by date', () {
      final c1 = TreasuryTransactionModel(
        id: '101',
        treasuryId: '20',
        amount: 250,
        currency: 'EGP',
        transactionType: 'custody_expense',
        createdAt: '2026-04-10T10:00:00Z',
        balanceAfter: 750,
      );
      final c2 = TreasuryTransactionModel(
        id: '102',
        treasuryId: '20',
        amount: 150,
        currency: 'EGP',
        transactionType: 'custody_expense',
        createdAt: '2026-04-22T10:00:00Z',
        balanceAfter: 600,
      );

      const custodyTreasury = TreasuryModel(
        id: '20',
        name: 'عهدة محمد أحمد',
        type: 'employee',
        createdAt: '2026-01-01',
      );

      final state = TreasuryLoaded(
        treasuries: [custodyTreasury],
        selectedTreasury: custodyTreasury,
        transactions: [c1, c2],
        startDate: DateTime(2026, 4, 20),
        endDate: DateTime(2026, 4, 30),
      );

      expect(state.selectedTreasury?.isEmployee, isTrue);
      expect(state.filteredTransactions.length, 1);
      expect(state.filteredTransactions.first.id, '102');
    });

    test('BankAccountsLoaded filters transactions strictly by date range', () {
      final b1 = BankAccountTransactionModel(
        id: 1,
        bankAccountId: 5,
        type: 'deposit',
        amount: 10000,
        balanceBefore: 0,
        balanceAfter: 10000,
        createdAt: DateTime(2026, 3, 5, 10, 0),
      );
      final b2 = BankAccountTransactionModel(
        id: 2,
        bankAccountId: 5,
        type: 'withdrawal',
        amount: 4000,
        balanceBefore: 10000,
        balanceAfter: 6000,
        createdAt: DateTime(2026, 3, 15, 14, 0),
      );
      final b3 = BankAccountTransactionModel(
        id: 3,
        bankAccountId: 5,
        type: 'withdrawal',
        amount: 1000,
        balanceBefore: 6000,
        balanceAfter: 5000,
        createdAt: DateTime(2026, 3, 28, 12, 0),
      );

      final account = BankAccountModel(
        id: 5,
        name: 'بنك مصر - حساب جاري',
        currency: 'EGP',
        balance: 5000,
      );

      final stateAll = BankAccountsLoaded(
        accounts: [account],
        transactions: [b1, b2, b3],
        selectedAccountId: 5,
      );

      expect(stateAll.filteredTransactions.length, 3);

      // Filter: March 10 to March 20 => only b2
      final stateFiltered = stateAll.copyWith(
        startDate: DateTime(2026, 3, 10),
        endDate: DateTime(2026, 3, 20),
      );
      expect(stateFiltered.filteredTransactions.length, 1);
      expect(stateFiltered.filteredTransactions.first.id, 2);

      // Filter: March 20 to March 31 => only b3
      final stateEnd = stateAll.copyWith(
        startDate: DateTime(2026, 3, 20),
        endDate: DateTime(2026, 3, 31),
      );
      expect(stateEnd.filteredTransactions.length, 1);
      expect(stateEnd.filteredTransactions.first.id, 3);
    });
  });

  group('PDF Landscape Page Setup & Margins Tests', () {
    test('A4 Landscape dimensions have width greater than height for expansive tables', () {
      const format = PdfPageFormat.a4;
      final landscape = format.landscape;

      expect(landscape.width, greaterThan(landscape.height));
      expect(landscape.width, closeTo(841.89, 0.1));
      expect(landscape.height, closeTo(595.28, 0.1));
    });
  });
}
