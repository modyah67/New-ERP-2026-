/// ReportCalculationService — Core business logic for all financial reports
///
/// Computes Trial Balance, General Ledger, Balance Sheet, Income Statement,
/// Cash Flow Statement, and Account Statement from raw transaction data.
///
/// NEVER modifies data — only reads and computes.
library;

import '../dao/report_dao.dart';
import '../models/report_models.dart';
import '../utils/account_classifier.dart';
import '../utils/balance_calculator.dart';

class ReportCalculationService {
  final ReportDao _dao;

  ReportCalculationService(this._dao);

  /// Pre-compiled regex for extracting currency from JSON strings
  static final _currencyPattern = RegExp(r'"original_currency"\s*:\s*"(\w+)"');

  static const _excludedFromCoreFinancialStatements = {
    '2101',
    '2102',
    '2105',
    '5210',
    '9000',
    '9101',
    '9102',
    '9105',
    '9210',
    '9121',
    '9122',
    '9123',
    '9124',
  };

  static bool _isExcludedFromStatements(String code) {
    // Operational waste / loss / spoilage intermediary accounts participate in valuation entries
    // and belong to Expenses & Costs / Cost of Activity (المصروفات والتكاليف).
    // They must NEVER be excluded from financial statements or trial balance.
    if (AccountClassifier.isOperationalLossOrCostAccount(code)) {
      return false;
    }
    return _excludedFromCoreFinancialStatements.contains(code) ||
        code == '9000' ||
        (code.startsWith('9') && !AccountClassifier.isOperationalLossOrCostAccount(code));
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  /// Build a map of account_id → {debit, credit} from raw totals list
  static Map<String, Map<String, double>> _buildTotalsMap(
    List<Map<String, dynamic>> totals,
  ) {
    final map = <String, Map<String, double>>{};
    for (final t in totals) {
      map[t['account_id'].toString()] = {
        'debit': (t['debit'] as num?)?.toDouble() ?? 0.0,
        'credit': (t['credit'] as num?)?.toDouble() ?? 0.0,
      };
    }
    return map;
  }

  /// Compute opening balance from pre-aggregated debit/credit sums
  ///
  /// Uses account classification to determine sign:
  /// - Debit-normal accounts (assets, expenses): balance = debit - credit
  /// - Credit-normal accounts (liabilities, equity, revenue): balance = credit - debit
  static double _computeOpeningBalance({
    required double debit,
    required double credit,
    required AccountClassification classification,
  }) {
    if (classification.isDebitNormal) {
      return debit - credit;
    } else {
      return credit - debit;
    }
  }

  // ─────────────────────────────────────────────
  // TRIAL BALANCE
  // ─────────────────────────────────────────────

  /// Calculate Trial Balance as of a specific date
  ///
  /// If [fromDate] is provided, only transactions from that date are included
  /// (period-based TB). If omitted, all transactions up to [asOfDate] are
  /// included (cumulative TB).
  /// If [currency] is provided, only entries in that currency are summed.
  Future<TrialBalanceReport> calculateTrialBalance({
    DateTime? fromDate,
    required DateTime asOfDate,
    AccountClassification? accountType,
    String? currency,
  }) async {
    final accounts = await _dao.getAllAccounts();
    final totals = await _dao.getAccountTotals(
      fromDate: fromDate,
      toDate: asOfDate,
      currency: currency,
    );
    final totalsMap = _buildTotalsMap(totals);

    final rows = <TrialBalanceRow>[];
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final account in accounts) {
      if (accountType != null && account.classification != accountType) {
        continue;
      }

      // Operational loss/spoilage intermediary accounts (e.g. 9112 وسيط هالك وفاقد المحاصيل)
      // participate in actual valuation and cost entries that affect asset or inventory ledgers.
      // They must be included in the trial balance summation so debits and credits balance out cleanly.
      // Exclude only true off-balance non-transactional memorandum accounts that do not have active double-entry movements.
      if (!AccountClassifier.isOperationalLossOrCostAccount(account.code) &&
          _isExcludedFromStatements(account.code)) {
        continue;
      }

      final accountTotals = totalsMap[account.id];
      final debit = accountTotals?['debit'] ?? 0.0;
      final credit = accountTotals?['credit'] ?? 0.0;

      if ((debit - credit).abs() < 0.01) continue;

      final net = debit - credit;
      final displayDebit = net >= 0 ? net : 0.0;
      final displayCredit = net < 0 ? -net : 0.0;

      rows.add(TrialBalanceRow(
        accountCode: account.code,
        accountName: account.name,
        accountNameAr: account.nameAr,
        classification: account.classification,
        debit: displayDebit,
        credit: displayCredit,
      ));

      totalDebit += displayDebit;
      totalCredit += displayCredit;
    }

    rows.sort((a, b) => a.accountCode.compareTo(b.accountCode));

    return TrialBalanceReport(
      asOfDate: asOfDate,
      rows: rows,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      generatedAt: DateTime.now(),
      currencyFilter: currency,
    );
  }

  // ─────────────────────────────────────────────
  // GENERAL LEDGER
  // ─────────────────────────────────────────────

  /// Calculate General Ledger for a date range
  Future<LedgerReport> calculateGeneralLedger({
    required DateTime fromDate,
    required DateTime toDate,
    String? accountId,
    AccountClassification? accountType,
    String? currency,
  }) async {
    // Fetch accounts and opening balance in parallel (independent queries)
    final accountsFuture = _dao.getAllAccounts();
    final openingBalanceFuture = accountId != null
        ? _dao.getBalanceBeforeDate(
            accountId: accountId,
            beforeDate: fromDate,
          )
        : Future<({double debit, double credit})>.value((debit: 0.0, credit: 0.0));

    final results = await Future.wait([accountsFuture, openingBalanceFuture]);
    final accounts = results[0] as List<AccountHierarchy>;
    final openingSums = results[1] as ({double debit, double credit});

    final accountMap = <String, AccountHierarchy>{};
    for (final a in accounts) {
      accountMap[a.id] = a;
    }

    double openingBalance = 0.0;
    if (accountId != null) {
      final account = accountMap[accountId];
      if (account != null) {
        openingBalance = _computeOpeningBalance(
          debit: openingSums.debit,
          credit: openingSums.credit,
          classification: account.classification,
        );
      }
    }

    final rawTransactions = await _dao.getTransactions(
      fromDate: fromDate,
      toDate: toDate,
      accountId: accountId,
    );

    final rows = <LedgerRow>[];
    for (final row in rawTransactions) {
      final account = accountMap[row['account_id']?.toString() ?? ''];
      if (account == null) continue;

      if (accountType != null && account.classification != accountType) {
        continue;
      }

      final (debit, credit) = BalanceCalculator.normalizeRow(row);
      final dateStr = row['transaction_date']?.toString() ??
          row['date']?.toString() ??
          row['entry_date']?.toString() ??
          '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();

      rows.add(LedgerRow(
        id: row['id']?.toString(),
        date: date,
        entryNumber: row['entry_number']?.toString(),
        accountCode: account.code,
        accountName: account.name,
        description: row['description']?.toString(),
        debit: debit,
        credit: credit,
        entityType: row['customer_id'] != null
            ? 'customer'
            : (row['supplier_code'] != null ? 'supplier' : null),
        entityId: row['customer_id']?.toString() ??
            row['supplier_code']?.toString(),
        referenceType: row['reference_type']?.toString(),
        referenceId: row['reference_id']?.toString(),
        currency: _extractCurrency(row['currency_snapshot']),
      ));
    }

    rows.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return (a.entryNumber ?? '').compareTo(b.entryNumber ?? '');
    });

    final account = accountId != null ? accountMap[accountId] : null;
    final classification = account?.classification ?? AccountClassification.asset;
    final withBalance = BalanceCalculator.applyRunningBalance(
      rows: rows,
      openingBalance: openingBalance,
      accountType: classification,
    );

    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final row in withBalance) {
      totalDebit += row.debit;
      totalCredit += row.credit;
    }

    final closingBalance =
        withBalance.isNotEmpty ? withBalance.last.balance : openingBalance;

    return LedgerReport(
      fromDate: fromDate,
      toDate: toDate,
      accountId: accountId,
      rows: withBalance,
      openingBalance: openingBalance,
      closingBalance: closingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      transactionCount: withBalance.length,
      generatedAt: DateTime.now(),
      currencyFilter: currency,
    );
  }

  // ─────────────────────────────────────────────
  // BALANCE SHEET
  // ─────────────────────────────────────────────

  /// Calculate Balance Sheet as of a specific date
  /// If [currency] is provided, only entries in that currency are summed.
  Future<BalanceSheetReport> calculateBalanceSheet({
    required DateTime asOfDate,
    String? currency,
  }) async {
    final accounts = await _dao.getAllAccounts();
    final totals = await _dao.getAccountTotals(
      toDate: asOfDate,
      currency: currency,
      excludeClosing: true,
    );
    final totalsMap = _buildTotalsMap(totals);

    final assetLines = <BalanceSheetLine>[];
    final liabilityLines = <BalanceSheetLine>[];
    final equityLines = <BalanceSheetLine>[];

    double totalAssets = 0.0;
    double totalLiabilities = 0.0;
    double totalEquity = 0.0;

    for (final account in accounts) {
      // Exclude 2100 branch, sub-accounts (2101, 2102, 2105, 2106, 2107) and 5210
      if (_isExcludedFromStatements(account.code)) {
        continue;
      }

      final accountTotals = totalsMap[account.id];
      final debit = accountTotals?['debit'] ?? 0.0;
      final credit = accountTotals?['credit'] ?? 0.0;

      if ((debit - credit).abs() < 0.01) continue;

      switch (account.classification) {
        case AccountClassification.asset:
          final net = debit - credit;
          assetLines.add(BalanceSheetLine(
            accountCode: account.code,
            accountName: account.name,
            accountNameAr: account.nameAr,
            amount: net,
          ));
          totalAssets += net;
          break;
        case AccountClassification.liability:
          final net = credit - debit;
          liabilityLines.add(BalanceSheetLine(
            accountCode: account.code,
            accountName: account.name,
            accountNameAr: account.nameAr,
            amount: net,
          ));
          totalLiabilities += net;
          break;
        case AccountClassification.equity:
          final net = credit - debit;
          equityLines.add(BalanceSheetLine(
            accountCode: account.code,
            accountName: account.name,
            accountNameAr: account.nameAr,
            amount: net,
          ));
          totalEquity += net;
          break;
        default:
          break;
      }
    }

    // Also calculate current period net income to incorporate into Equity
    try {
      final yearStart = DateTime(asOfDate.year, 1, 1);
      final incomeStatement = await calculateIncomeStatement(
        fromDate: yearStart,
        toDate: asOfDate,
        currency: currency,
      );
      final netIncome = incomeStatement.netIncome;
      if (netIncome.abs() >= 0.01) {
        equityLines.add(BalanceSheetLine(
          accountCode: '39999',
          accountName: 'Current Period Net Income',
          accountNameAr: 'أرباح / (خسائر) الفترة الحالية',
          amount: netIncome,
        ));
        totalEquity += netIncome;
      }
    } catch (_) {}

    assetLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));
    liabilityLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));
    equityLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));

    return BalanceSheetReport(
      asOfDate: asOfDate,
      assets: BalanceSheetSection(
        title: 'Assets',
        titleAr: 'الأصول',
        lines: assetLines,
        total: totalAssets,
      ),
      liabilities: BalanceSheetSection(
        title: 'Liabilities',
        titleAr: 'الخصوم',
        lines: liabilityLines,
        total: totalLiabilities,
      ),
      equity: BalanceSheetSection(
        title: 'Equity',
        titleAr: 'حقوق الملكية',
        lines: equityLines,
        total: totalEquity,
      ),
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLiabilities + totalEquity,
      generatedAt: DateTime.now(),
      currencyFilter: currency,
    );
  }

  // ─────────────────────────────────────────────
  // INCOME STATEMENT
  // ─────────────────────────────────────────────

  /// Calculate Income Statement for a date range
  /// If [currency] is provided, only entries in that currency are summed.
  Future<IncomeStatementReport> calculateIncomeStatement({
    required DateTime fromDate,
    required DateTime toDate,
    String? currency,
  }) async {
    final accounts = await _dao.getAllAccounts();
    final totals = await _dao.getAccountTotals(
      fromDate: fromDate,
      toDate: toDate,
      currency: currency,
      excludeClosing: true,
    );
    final totalsMap = _buildTotalsMap(totals);

    final revenueLines = <IncomeStatementLine>[];
    final cogsLines = <IncomeStatementLine>[];
    final expenseLines = <IncomeStatementLine>[];

    double totalRevenue = 0.0;
    double totalCogs = 0.0;
    double totalExpenses = 0.0;

    for (final account in accounts) {
      if (account.classification != AccountClassification.revenue &&
          account.classification != AccountClassification.expense) {
        continue;
      }

      // Exclude 2100 branch, sub-accounts (2101, 2102, 2105, 2106, 2107) and 5210
      if (_isExcludedFromStatements(account.code)) {
        continue;
      }

      final accountTotals = totalsMap[account.id];
      final debit = accountTotals?['debit'] ?? 0.0;
      final credit = accountTotals?['credit'] ?? 0.0;

      double amount;
      if (account.classification == AccountClassification.revenue) {
        amount = credit - debit;
      } else {
        amount = debit - credit;
      }

      if (amount.abs() < 0.01) continue;

      final line = IncomeStatementLine(
        accountCode: account.code,
        accountName: account.name,
        accountNameAr: account.nameAr,
        amount: amount,
      );

      if (account.classification == AccountClassification.revenue) {
        revenueLines.add(line);
        totalRevenue += amount;
      } else {
        // COGS accounts: starting with 5
        if (account.code.startsWith('5')) {
          cogsLines.add(line);
          totalCogs += amount;
        } else {
          expenseLines.add(line);
          totalExpenses += amount;
        }
      }
    }

    revenueLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));
    cogsLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));
    expenseLines.sort((a, b) => a.accountCode.compareTo(b.accountCode));

    final grossProfit = totalRevenue - totalCogs;
    final netIncome = grossProfit - totalExpenses;

    return IncomeStatementReport(
      fromDate: fromDate,
      toDate: toDate,
      revenue: IncomeStatementSection(
        title: 'Revenue',
        titleAr: 'الإيرادات',
        lines: revenueLines,
        total: totalRevenue,
      ),
      costOfGoodsSold: IncomeStatementSection(
        title: 'Cost of Goods Sold',
        titleAr: 'تكلفة البضاعة المباعة',
        lines: cogsLines,
        total: totalCogs,
      ),
      operatingExpenses: IncomeStatementSection(
        title: 'Operating Expenses',
        titleAr: 'المصروفات التشغيلية',
        lines: expenseLines,
        total: totalExpenses,
      ),
      grossProfit: grossProfit,
      operatingIncome: grossProfit,
      netIncome: netIncome,
      generatedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────
  // ACCOUNT STATEMENT
  // ─────────────────────────────────────────────

  /// Calculate Account Statement for a specific account
  Future<AccountStatementReport> calculateAccountStatement({
    required String accountId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final accounts = await _dao.getAllAccounts();
    final account = accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => throw ArgumentError('Account not found: $accountId'),
    );

    // Use server-side RPC for opening balance (replaces raw row download)
    final openingSums = await _dao.getBalanceBeforeDate(
      accountId: accountId,
      beforeDate: fromDate,
    );
    final openingBalance = _computeOpeningBalance(
      debit: openingSums.debit,
      credit: openingSums.credit,
      classification: account.classification,
    );

    final rawTransactions = await _dao.getTransactions(
      fromDate: fromDate,
      toDate: toDate,
      accountId: accountId,
    );

    final rows = <AccountStatementRow>[];
    double runningBalance = openingBalance;
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final row in rawTransactions) {
      final (debit, credit) = BalanceCalculator.normalizeRow(row);
      final amount = debit > 0 ? debit : credit;
      final type = debit > 0 ? 'debit' : 'credit';

      final normalized = AccountClassifier.normalizeAmount(
        amount: amount,
        transactionType: type,
        accountType: account.classification,
      );

      runningBalance += normalized;

      final dateStr = row['transaction_date']?.toString() ??
          row['transaction_date']?.toString() ??
          '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();

      rows.add(AccountStatementRow(
        date: date,
        description: row['description']?.toString(),
        debit: debit > 0 ? amount : 0.0,
        credit: credit > 0 ? amount : 0.0,
        runningBalance: runningBalance,
        referenceType: row['reference_type']?.toString(),
        referenceId: row['reference_id']?.toString(),
        entityType: row['customer_id'] != null
            ? 'customer'
            : (row['supplier_code'] != null ? 'supplier' : null),
        entityId: row['customer_id']?.toString() ??
            row['supplier_code']?.toString(),
      ));

      totalDebit += debit;
      totalCredit += credit;
    }

    return AccountStatementReport(
      accountId: accountId,
      accountCode: account.code,
      accountName: account.name,
      fromDate: fromDate,
      toDate: toDate,
      openingBalance: openingBalance,
      rows: rows,
      closingBalance: runningBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      generatedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────
  // SUBSIDIARY LEDGER (per-customer/supplier)
  // ─────────────────────────────────────────────

  /// Calculate Subsidiary Ledger for a specific entity (customer/supplier)
  Future<LedgerReport> calculateSubsidiaryLedger({
    required String entityType,
    required String entityId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final ledgerRows = await _dao.getEntityLedger(
      entityType: entityType,
      entityId: entityId,
      fromDate: fromDate,
      toDate: toDate,
    );

    final rows = <LedgerRow>[];
    for (final row in ledgerRows) {
      final entryType = row['entry_type']?.toString() ?? '';
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final dateStr = row['created_at']?.toString() ?? '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();

      // In ledger_entries: entry_type='credit' means entity owes us (debit side)
      // entry_type='debit' means we owe entity (credit side)
      final debit = entryType == 'credit' ? amount : 0.0;
      final credit = entryType == 'debit' ? amount : 0.0;

      rows.add(LedgerRow(
        id: row['id']?.toString(),
        date: date,
        accountCode: entityType,
        accountName: entityType == 'customer' ? 'عميل' : 'مورد',
        description: row['description']?.toString(),
        debit: debit,
        credit: credit,
        entityType: entityType,
        entityId: entityId,
        referenceType: row['reference_type']?.toString(),
        referenceId: row['reference_id']?.toString(),
        currency: row['currency']?.toString(),
      ));
    }

    rows.sort((a, b) => a.date.compareTo(b.date));

    // Apply running balance
    double running = 0.0;
    final withBalance = <LedgerRow>[];
    for (final row in rows) {
      running += row.debit - row.credit;
      withBalance.add(LedgerRow(
        id: row.id,
        date: row.date,
        entryNumber: row.entryNumber,
        accountCode: row.accountCode,
        accountName: row.accountName,
        description: row.description,
        debit: row.debit,
        credit: row.credit,
        balance: running,
        entityType: row.entityType,
        entityId: row.entityId,
        entityName: row.entityName,
        referenceType: row.referenceType,
        referenceId: row.referenceId,
        currency: row.currency,
        exchangeRate: row.exchangeRate,
      ));
    }

    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final row in withBalance) {
      totalDebit += row.debit;
      totalCredit += row.credit;
    }

    return LedgerReport(
      fromDate: fromDate,
      toDate: toDate,
      rows: withBalance,
      openingBalance: 0.0,
      closingBalance: running,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      transactionCount: withBalance.length,
      generatedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────
  // CASH FLOW STATEMENT
  // ─────────────────────────────────────────────

  /// Calculate Cash Flow Statement for a date range
  ///
  /// Uses treasury_transactions and bank_account_transactions as the
  /// source of truth for cash movements.
  /// If [currency] is provided, only transactions in that currency are included.
  Future<CashFlowReport> calculateCashFlowStatement({
    required DateTime fromDate,
    required DateTime toDate,
    String? currency,
  }) async {
    final treasuryTx = await _dao.getTreasuryTransactions(
      fromDate: fromDate,
      toDate: toDate,
    );
    final bankTx = await _dao.getBankTransactions(
      fromDate: fromDate,
      toDate: toDate,
    );

    // Classify treasury transactions into operating/investing/financing
    final operatingLines = <CashFlowLine>[];
    final investingLines = <CashFlowLine>[];
    final financingLines = <CashFlowLine>[];

    double totalOperating = 0.0;
    double totalInvesting = 0.0;
    double totalFinancing = 0.0;

    // Treasury transactions → Operating activities
    for (final tx in treasuryTx) {
      final type = tx['type']?.toString() ?? '';
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      final description = tx['description']?.toString() ?? type;
      final txCurrency = tx['currency']?.toString() ?? 'EGP';

      if (currency != null && txCurrency != currency) continue;

      // Determine if cash inflow or outflow
      double cashFlow;
      switch (type) {
        case 'deposit':
        case 'deposit_in':
        case 'customer_payment':
        case 'income':
        case 'shareholder_deposit':
          cashFlow = amount;
          break;
        case 'withdrawal':
        case 'expense':
        case 'supplier_payment':
        case 'multi_payment':
        case 'shareholder_withdrawal':
          cashFlow = -amount;
          break;
        case 'disbursement':
        case 'disbursement_out':
        case 'disbursement_in':
        case 'transfer_out':
        case 'transfer_in':
        case 'return_out':
        case 'return_in':
        case 'exchange':
        case 'currency_exchange':
        default:
          cashFlow = 0;
      }

      if (cashFlow == 0) continue;

      final line = CashFlowLine(
        description: '$description ($txCurrency)',
        descriptionAr: '$description ($txCurrency)',
        amount: cashFlow,
      );

      final refType = tx['reference_type']?.toString();
      if (refType == 'bank' || refType == 'bank_account') continue;

      final shareholderId = tx['shareholder_id'];
      if (shareholderId != null || type == 'shareholder_deposit' || type == 'shareholder_withdrawal') {
        financingLines.add(line);
        totalFinancing += cashFlow;
      } else {
        operatingLines.add(line);
        totalOperating += cashFlow;
      }
    }

    // Bank transactions → classified by type
    for (final tx in bankTx) {
      final type = tx['type']?.toString() ?? '';
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      final description = tx['description']?.toString() ?? type;
      final bankCurrency = tx['bank_currency']?.toString() ?? 'EGP';

      if (currency != null && bankCurrency != currency) continue;

      final entityType = tx['entity_type']?.toString();
      if (entityType == 'treasury') continue; // Internal transfer to treasury

      double cashFlow;
      if (type == 'deposit') {
        cashFlow = amount;
      } else if (type == 'withdraw' || type == 'withdrawal') {
        cashFlow = -amount;
      } else {
        cashFlow = 0;
      }

      if (cashFlow == 0) continue;

      final line = CashFlowLine(
        description: '$description ($bankCurrency)',
        descriptionAr: '$description ($bankCurrency)',
        amount: cashFlow,
      );

      if (entityType == 'shareholder') {
        financingLines.add(line);
        totalFinancing += cashFlow;
      } else {
        operatingLines.add(line);
        totalOperating += cashFlow;
      }
    }

    final netChange = totalOperating + totalInvesting + totalFinancing;

    return CashFlowReport(
      fromDate: fromDate,
      toDate: toDate,
      operating: CashFlowSection(
        title: 'Operating Activities',
        titleAr: 'الأنشطة التشغيلية',
        lines: operatingLines,
        total: totalOperating,
      ),
      investing: CashFlowSection(
        title: 'Investing Activities',
        titleAr: 'الأنشطة الاستثمارية',
        lines: investingLines,
        total: totalInvesting,
      ),
      financing: CashFlowSection(
        title: 'Financing Activities',
        titleAr: 'الأنشطة التمويلية',
        lines: financingLines,
        total: totalFinancing,
      ),
      netCashFromOperating: totalOperating,
      netCashFromInvesting: totalInvesting,
      netCashFromFinancing: totalFinancing,
      netChangeInCash: netChange,
      generatedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  String? _extractCurrency(dynamic snapshot) {
    if (snapshot == null) return null;
    if (snapshot is Map) {
      return snapshot['original_currency']?.toString();
    }
    if (snapshot is String) {
      try {
        final match = _currencyPattern.firstMatch(snapshot);
        return match?.group(1);
      } catch (_) {}
    }
    return null;
  }
}
