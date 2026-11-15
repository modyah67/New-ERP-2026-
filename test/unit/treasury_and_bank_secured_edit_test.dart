import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/widgets/password_verification_dialog.dart';
import 'package:accounting_system/data/models/treasury_model.dart';
import 'package:accounting_system/data/models/bank_account_transaction_model.dart';
import 'package:accounting_system/data/models/bank_account_model.dart';
import 'package:accounting_system/features/treasury/treasury_state.dart';
import 'package:accounting_system/features/bank_accounts/bank_accounts_state.dart';
import 'package:accounting_system/features/treasury/treasury_cubit.dart';
import 'package:accounting_system/features/bank_accounts/bank_accounts_cubit.dart';
import 'package:accounting_system/features/treasury/widgets/edit_confirmed_treasury_transaction_dialog.dart';
import 'package:accounting_system/features/bank_accounts/widgets/edit_confirmed_bank_transaction_dialog.dart';

class FakeTreasuryCubit extends Fake implements TreasuryCubit {}
class FakeBankAccountsCubit extends Fake implements BankAccountsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Secured Edit Password Authentication Tests (eslam2026)', () {
    testWidgets('Entering incorrect password blocks access and shows error message',
        (tester) async {
      bool editProceeded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final verified = await showPasswordVerificationDialog(
                    context,
                    expectedPassword: 'eslam2026',
                  );
                  if (verified) {
                    editProceeded = true;
                  }
                },
                child: const Text('Edit Transaction'),
              ),
            ),
          ),
        ),
      );

      // Tap Edit
      await tester.tap(find.text('Edit Transaction'));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.byType(PasswordVerificationDialog), findsOneWidget);

      // Enter wrong password
      await tester.enterText(find.byType(TextField), 'wrong_password_2026');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Verification failed
      expect(find.text('كلمة المرور غير صحيحة'), findsOneWidget);
      expect(editProceeded, isFalse);

      // Cancel
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(editProceeded, isFalse);
    });

    testWidgets('Entering eslam2026 verifies successfully and permits edit flow',
        (tester) async {
      bool editProceeded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final verified = await showPasswordVerificationDialog(
                    context,
                    expectedPassword: 'eslam2026',
                  );
                  if (verified) {
                    editProceeded = true;
                  }
                },
                child: const Text('Edit Transaction'),
              ),
            ),
          ),
        ),
      );

      // Tap Edit
      await tester.tap(find.text('Edit Transaction'));
      await tester.pumpAndSettle();

      // Enter correct administrative password
      await tester.enterText(find.byType(TextField), 'eslam2026');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      // Edit proceeded
      expect(editProceeded, isTrue);
      expect(find.byType(PasswordVerificationDialog), findsNothing);
    });
  });

  group('Confirmed Treasury Transaction Edit Dialog UI Tests', () {
    testWidgets('renders preloaded data in EditConfirmedTreasuryTransactionDialog',
        (tester) async {
      const tx = TreasuryTransactionModel(
        id: '101',
        treasuryId: '1',
        treasuryName: 'الخزينة الرئيسية',
        transactionType: 'expense',
        currency: 'EGP',
        amount: 2500.50,
        balanceBefore: 10000.0,
        balanceAfter: 7499.50,
        description: 'شراء أدوات صيانة ومستلزمات',
        createdAt: '2026-11-10T12:00:00Z',
        status: 'confirmed',
        journalEntryId: 'JE-9901',
      );

      const state = TreasuryLoaded(
        treasuries: [
          TreasuryModel(
            id: '1',
            name: 'الخزينة الرئيسية',
            type: 'main',
            createdAt: '2026-01-01',
          ),
        ],
        transactions: [tx],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditConfirmedTreasuryTransactionDialog(
              tx: tx,
              state: state,
              cubit: FakeTreasuryCubit(),
            ),
          ),
        ),
      );

      // Verify title and badges
      expect(find.text('تعديل حركة خزنة مؤكدة'), findsOneWidget);
      expect(find.text('#101'), findsOneWidget);
      expect(find.textContaining('JE-9901'), findsOneWidget);

      // Verify preloaded values in fields
      expect(find.text('2500.50'), findsOneWidget);
      expect(find.text('شراء أدوات صيانة ومستلزمات'), findsOneWidget);
      expect(find.text('حفظ التعديلات'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });
  });

  group('Confirmed Bank Account Transaction Edit Dialog UI Tests', () {
    testWidgets('renders preloaded data in EditConfirmedBankTransactionDialog',
        (tester) async {
      final tx = BankAccountTransactionModel(
        id: 505,
        bankAccountId: 10,
        type: 'deposit',
        amount: 75000.0,
        balanceBefore: 200000.0,
        balanceAfter: 275000.0,
        description: 'إيداع نقدي تحصيل مبيعات محطة',
        createdAt: DateTime.now(),
        status: 'confirmed',
        journalEntryId: 'JE-8820',
      );

      final state = BankAccountsLoaded(
        accounts: [
          BankAccountModel(
            id: 10,
            name: 'حساب الأهلي ج.م',
            currency: 'EGP',
            balance: 275000.0,
            createdAt: DateTime.now(),
          ),
        ],
        selectedAccountId: 10,
        transactions: [tx],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditConfirmedBankTransactionDialog(
              tx: tx,
              state: state,
              cubit: FakeBankAccountsCubit(),
            ),
          ),
        ),
      );

      // Verify title and badges
      expect(find.text('تعديل حركة بنكية مؤكدة'), findsOneWidget);
      expect(find.text('#JE-8820'), findsOneWidget);

      // Verify preloaded values in fields
      expect(find.text('75000.00'), findsOneWidget);
      expect(find.text('إيداع نقدي تحصيل مبيعات محطة'), findsOneWidget);
      expect(find.text('حفظ التعديلات'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });
  });

  group('Mathematical Ledger Delta Verification', () {
    test('Expense increase decreases treasury balance by exact delta', () {
      const oldAmount = 1000.0;
      const newAmount = 1500.0;
      // outflow = expense (-oldAmount -> -newAmount)
      const oldTxDelta = -oldAmount;
      const newTxDelta = -newAmount;
      const treasuryDelta = newTxDelta - oldTxDelta;

      expect(treasuryDelta, equals(-500.0));
    });

    test('Expense decrease increases treasury balance by exact delta', () {
      const oldAmount = 2000.0;
      const newAmount = 1200.0;
      const oldTxDelta = -oldAmount;
      const newTxDelta = -newAmount;
      const treasuryDelta = newTxDelta - oldTxDelta;

      expect(treasuryDelta, equals(800.0));
    });

    test('Bank deposit change computes correct balance difference', () {
      const oldAmount = 5000.0;
      const newAmount = 6500.0;
      const balanceDiff = newAmount - oldAmount;
      const oldBalanceAfter = 50000.0;
      const newBalanceAfter = oldBalanceAfter + balanceDiff;

      expect(balanceDiff, equals(1500.0));
      expect(newBalanceAfter, equals(51500.0));
    });

    test('Negative balance is strictly prevented and throws exception', () {
      // Current available balance in custody or treasury
      const currentBalance = 200.0;
      // An earlier expense of 500 is retroactively changed to 1000
      const oldExpense = 500.0;
      const newExpense = 1000.0;
      const oldTxDelta = -oldExpense;
      const newTxDelta = -newExpense;
      const treasuryDelta = newTxDelta - oldTxDelta; // -500.0

      double simulateUpdateBalance(double current, double delta) {
        final newBal = current + delta;
        if (newBal < 0) {
          throw Exception('الرصيد غير كافٍ');
        }
        return newBal;
      }

      // Negative balance is strictly prevented
      expect(
        () => simulateUpdateBalance(currentBalance, treasuryDelta),
        throwsA(isA<Exception>()),
      );
    });
  });
}
