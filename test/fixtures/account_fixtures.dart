import 'package:accounting_system/accounting/reporting/models/report_models.dart';

class AccountFixtures {
  AccountFixtures._();

  // ── Account Hierarchies ──────────────────────

  static List<AccountHierarchy> get flatAccounts => [
        const AccountHierarchy(
          id: '1',
          code: '1000',
          name: 'Cash',
          nameAr: 'النقدية',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: '2',
          code: '1100',
          name: 'Accounts Receivable',
          nameAr: 'المدينون',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: '3',
          code: '1200',
          name: 'Inventory',
          nameAr: 'المخزون',
          classification: AccountClassification.asset,
        ),
        const AccountHierarchy(
          id: '4',
          code: '2000',
          name: 'Accounts Payable',
          nameAr: 'الدائنون',
          classification: AccountClassification.liability,
        ),
        const AccountHierarchy(
          id: '5',
          code: '2100',
          name: 'Loans',
          nameAr: 'القروض',
          classification: AccountClassification.liability,
        ),
        const AccountHierarchy(
          id: '6',
          code: '3000',
          name: 'Owner Equity',
          nameAr: 'حقوق الملكية',
          classification: AccountClassification.equity,
        ),
        const AccountHierarchy(
          id: '7',
          code: '3100',
          name: 'Retained Earnings',
          nameAr: 'أرباح محتجزة',
          classification: AccountClassification.equity,
        ),
        const AccountHierarchy(
          id: '8',
          code: '4000',
          name: 'Sales Revenue',
          nameAr: 'إيرادات المبيعات',
          classification: AccountClassification.revenue,
        ),
        const AccountHierarchy(
          id: '9',
          code: '4100',
          name: 'Service Revenue',
          nameAr: 'إيرادات الخدمات',
          classification: AccountClassification.revenue,
        ),
        const AccountHierarchy(
          id: '10',
          code: '5000',
          name: 'Cost of Goods Sold',
          nameAr: 'تكلفة البضاعة المباعة',
          classification: AccountClassification.expense,
        ),
        const AccountHierarchy(
          id: '11',
          code: '6000',
          name: 'Salaries',
          nameAr: 'الرواتب',
          classification: AccountClassification.expense,
        ),
        const AccountHierarchy(
          id: '12',
          code: '6100',
          name: 'Rent',
          nameAr: 'الإيجار',
          classification: AccountClassification.expense,
        ),
      ];

  static List<AccountHierarchy> get hierarchicalAccounts => [
        AccountHierarchy(
          id: '100',
          code: '1',
          name: 'Assets',
          nameAr: 'الأصول',
          classification: AccountClassification.asset,
          children: [
            const AccountHierarchy(
              id: '1',
              code: '1000',
              name: 'Cash',
              nameAr: 'النقدية',
              classification: AccountClassification.asset,
              parentId: '100',
              depth: 1,
            ),
            const AccountHierarchy(
              id: '2',
              code: '1100',
              name: 'Accounts Receivable',
              nameAr: 'المدينون',
              classification: AccountClassification.asset,
              parentId: '100',
              depth: 1,
            ),
          ],
        ),
        AccountHierarchy(
          id: '200',
          code: '2',
          name: 'Liabilities',
          nameAr: 'الخصوم',
          classification: AccountClassification.liability,
          children: [
            const AccountHierarchy(
              id: '4',
              code: '2000',
              name: 'Accounts Payable',
              nameAr: 'الدائنون',
              classification: AccountClassification.liability,
              parentId: '200',
              depth: 1,
            ),
          ],
        ),
        AccountHierarchy(
          id: '300',
          code: '3',
          name: 'Equity',
          nameAr: 'حقوق الملكية',
          classification: AccountClassification.equity,
          children: [
            const AccountHierarchy(
              id: '6',
              code: '3000',
              name: 'Owner Equity',
              nameAr: 'حقوق الملكية',
              classification: AccountClassification.equity,
              parentId: '300',
              depth: 1,
            ),
          ],
        ),
      ];

  // ── Asset-only accounts ──────────────────────

  static List<AccountHierarchy> get assetAccounts =>
      flatAccounts
          .where((a) => a.classification == AccountClassification.asset)
          .toList();

  static List<AccountHierarchy> get liabilityAccounts =>
      flatAccounts
          .where((a) => a.classification == AccountClassification.liability)
          .toList();

  static List<AccountHierarchy> get revenueAccounts =>
      flatAccounts
          .where((a) => a.classification == AccountClassification.revenue)
          .toList();

  static List<AccountHierarchy> get expenseAccounts =>
      flatAccounts
          .where((a) => a.classification == AccountClassification.expense)
          .toList();
}
