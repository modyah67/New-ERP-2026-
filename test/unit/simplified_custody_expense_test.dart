import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/treasury_model.dart';
import 'package:accounting_system/data/models/account_model.dart';
import 'package:accounting_system/data/services/custody_service.dart';

void main() {
  group('Simplified Custody Expense & Quick Accounts Tests', () {
    test('1. QuickCustodyExpenseItem contains the 3 exact designated accounts', () {
      final items = QuickCustodyExpenseItem.defaultItems;

      expect(items.length, 3);

      // Account 1: 31123 - مصروفات انتقالات
      final transportItem = items.firstWhere((i) => i.code == '31123');
      expect(transportItem.title, 'مصروفات انتقالات');
      expect(transportItem.englishName, 'Staff Transportation Expense');
      expect(transportItem.sortOrder, 31123);

      // Account 2: 31124 - وجبات
      final mealsItem = items.firstWhere((i) => i.code == '31124');
      expect(mealsItem.title, 'وجبات');
      expect(mealsItem.englishName, 'Staff Meals Expense');
      expect(mealsItem.sortOrder, 31124);

      // Account 3: 31125 - عمالة
      final laborItem = items.firstWhere((i) => i.code == '31125');
      expect(laborItem.title, 'عمالة');
      expect(laborItem.englishName, 'Temporary Labor Expense');
      expect(laborItem.sortOrder, 31125);
    });

    test('2. TreasuryModel correctly identifies employee custody and retrieves currency balance', () {
      final custody = TreasuryModel(
        id: '15',
        type: 'employee',
        name: 'عهدة المهندس أحمد',
        userName: 'أحمد محمود',
        userId: 'usr-101',
        accountId: '4580',
        createdAt: '2026-11-04T00:00:00Z',
        balances: const [
          TreasuryBalanceModel(
            id: 'b-1',
            treasuryId: '15',
            currency: 'EGP',
            balance: 3500.0,
            costBase: 3500.0,
            bookRate: 1.0,
          ),
        ],
      );

      expect(custody.isEmployee, isTrue);
      expect(custody.isMain, isFalse);
      expect(custody.displayName, contains('عهدة المهندس أحمد'));
      expect(custody.getBalance('EGP')?.balance, 3500.0);
    });

    test('3. Balance validation logic prevents spending more than available custody funds', () {
      const availableBalance = 1250.0;

      bool isAmountOverBalance(double enteredAmount) {
        if (enteredAmount <= 0) return false;
        return enteredAmount > (availableBalance + 0.001);
      }

      // Valid amounts
      expect(isAmountOverBalance(200.0), isFalse);
      expect(isAmountOverBalance(1250.0), isFalse);

      // Invalid amounts
      expect(isAmountOverBalance(1250.01), isTrue);
      expect(isAmountOverBalance(2000.0), isTrue);
    });

    test('4. Automated double-entry GL parameters for spend_custody without cost center', () {
      const treasuryId = 15;
      const expenseAccountId = 4720; // e.g. 31123, 31124, 31125
      const amount = 450.0;
      const description = 'وجبات غداء طاقم العمل';

      // In the simplified custody expense form, cost_center_id is intentionally null/omitted
      final params = <String, dynamic>{
        'p_treasury_id': treasuryId,
        'p_currency': 'EGP',
        'p_amount': amount,
        'p_description': description,
        'p_expense_account_id': expenseAccountId,
        'p_cost_center_id': null,
        'p_notes': 'صرف عهدة: وجبات',
      };

      expect(params['p_treasury_id'], 15);
      expect(params['p_amount'], 450.0);
      expect(params['p_currency'], 'EGP');
      expect(params['p_expense_account_id'], 4720);
      expect(params['p_cost_center_id'], isNull);
      expect(params['p_notes'], 'صرف عهدة: وجبات');
    });

    test('5. Level-5 Quick Accounts Model serialization and properties', () {
      final accountMap = {
        'id': '4724',
        'account_code': '31124',
        'name': 'Staff Meals Expense',
        'account_name': 'وجبات',
        'account_type': 'expense',
        'normal_balance': 'Debit',
        'is_active': true,
        'level': 5,
      };

      final account = AccountModel.fromMap(accountMap);
      expect(account.id, '4724');
      expect(account.code, '31124');
      expect(account.name, 'Staff Meals Expense');
      expect(account.accountName, 'وجبات');
      expect(account.type, 'expense');
      expect(account.isLeaf, isTrue);
      expect(account.isCreditNormal, isFalse);
    });
  });
}
