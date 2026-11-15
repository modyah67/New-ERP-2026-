import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';
import '../models/closing_entry.dart';
import '../models/fiscal_year_status.dart';

class ClosingValidationService {
  final SupabaseClient _client;
  final FiscalYearDao _dao;

  ClosingValidationService({SupabaseClient? client, FiscalYearDao? dao})
      : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao();

  Future<List<String>> validatePreClosing(int fiscalYearId) async {
    final errors = <String>[];

    final fy = await _dao.getById(fiscalYearId);
    if (fy == null) {
      errors.add('السنة المالية غير موجودة');
      return errors;
    }
    if (fy.isClosed) {
      errors.add('السنة المالية مغلقة مسبقاً');
    }
    if (!fy.status.canTransitionToClosing) {
      errors.add('حالة السنة المالية الحالية (${fy.status.displayNameAr}) لا تسمح بالإغلاق');
    }

    // Trial balance check
    final tbBalanced = await _dao.validateTrialBalance(fiscalYearId);
    if (!tbBalanced) {
      errors.add('ميزان المراجعة غير متوازن - إجمالي المدين لا يساوي إجمالي الدائن');
    }

    // Orphan entries check
    final orphans = await _dao.findOrphanEntries(fiscalYearId);
    if (orphans > 0) {
      errors.add('يوجد $orphans قيد يتيم (مرتبط بحساب غير موجود)');
    }

    // Duplicate entries check
    final duplicates = await _dao.findDuplicateEntries(fiscalYearId);
    if (duplicates > 0) {
      errors.add('يوجد $duplicates قيد مكرر');
    }

    // Draft transactions check
    final draftCount = await _dao.countDraftTransactions(fiscalYearId);
    if (draftCount > 0) {
      errors.add('يوجد $draftCount معاملة مسودة يجب إكمالها أولاً');
    }

    // Negative stock check
    final negativeStock = await _dao.countNegativeStock();
    if (negativeStock > 0) {
      errors.add('يوجد $negativeStock صنف بمخزون سالب');
    }

    // Broken FIFO layers check
    final brokenFifo = await _dao.countBrokenFifoLayers();
    if (brokenFifo > 0) {
      errors.add('يوجد $brokenFifo طبقة FIFO مكسورة');
    }

    return errors;
  }

  Future<bool> validateInventoryConsistency() async {
    final negativeStock = await _dao.countNegativeStock();
    return negativeStock == 0;
  }

  Future<bool> validateGlIntegrity(int fiscalYearId) async {
    return await _dao.validateTrialBalance(fiscalYearId);
  }

  Future<bool> validateArApIntegrity(int fiscalYearId) async {
    final orphans = await _dao.findOrphanEntries(fiscalYearId);
    return orphans == 0;
  }

  Future<List<ClosingEntry>> generateClosingEntries(int fiscalYearId) async {
    final entries = <ClosingEntry>[];

    final revenueAccounts = await _dao.getRevenueAccounts();
    double totalRevenue = 0;

    for (final account in revenueAccounts) {
      final totals = await _dao.getAccountTotals(
          account['account_code'] as String, fiscalYearId);
      final balance = totals['credit']! - totals['debit']!;
      if (balance.abs() > 0.01) {
        entries.add(ClosingEntry(
          id: null,
          fiscalYearId: fiscalYearId,
          entryType: 'CLOSE_REVENUE',
          accountCode: account['account_code'] as String,
          accountName: account['name'] as String,
          accountType: 'revenue',
          debit: balance > 0 ? balance : 0,
          credit: balance < 0 ? balance.abs() : 0,
          description: 'إغلاق حساب الإيرادات - السنة المالية',
          createdAt: DateTime.now(),
        ));
        totalRevenue += balance;
      }
    }

    final expenseAccounts = await _dao.getExpenseAccounts();
    double totalExpenses = 0;

    for (final account in expenseAccounts) {
      final totals = await _dao.getAccountTotals(
          account['account_code'] as String, fiscalYearId);
      final balance = totals['debit']! - totals['credit']!;
      if (balance.abs() > 0.01) {
        entries.add(ClosingEntry(
          id: null,
          fiscalYearId: fiscalYearId,
          entryType: 'CLOSE_EXPENSE',
          accountCode: account['account_code'] as String,
          accountName: account['name'] as String,
          accountType: 'expense',
          debit: balance < 0 ? balance.abs() : 0,
          credit: balance > 0 ? balance : 0,
          description: 'إغلاق حسابات المصروفات - السنة المالية',
          createdAt: DateTime.now(),
        ));
        totalExpenses += balance;
      }
    }

    final netIncome = totalRevenue - totalExpenses;
    if (netIncome.abs() > 0.01) {
      entries.add(ClosingEntry(
        id: null,
        fiscalYearId: fiscalYearId,
        entryType: 'TRANSFER_RETAINED',
        accountCode: '23411',
        accountName: 'أرباح وخسائر مرحلة',
        accountType: 'equity',
        debit: netIncome > 0 ? 0 : netIncome.abs(),
        credit: netIncome > 0 ? netIncome : 0,
        description: 'تحويل صافي الدخل إلى الأرباح المرحلة',
        createdAt: DateTime.now(),
      ));
    }

    // إقفال رصيد حساب فروق الأرصدة الافتتاحية (23421) في حساب الأرباح والخسائر المرحلة (23411)
    final suspenseTotals = await _dao.getAccountTotals('23421', fiscalYearId);
    final suspenseCredit = suspenseTotals['credit'] ?? 0.0;
    final suspenseDebit = suspenseTotals['debit'] ?? 0.0;
    final suspenseBalance = suspenseCredit - suspenseDebit;

    if (suspenseBalance.abs() > 0.01) {
      // 1. تصفير حساب فروق أرصدة افتتاحية 23421
      entries.add(ClosingEntry(
        id: null,
        fiscalYearId: fiscalYearId,
        entryType: 'TRANSFER_RETAINED',
        accountCode: '23421',
        accountName: 'رصيد افتتاحي',
        accountType: 'equity',
        debit: suspenseBalance > 0 ? suspenseBalance : 0,
        credit: suspenseBalance < 0 ? suspenseBalance.abs() : 0,
        description: 'تصفير حساب فروق الأرصدة الافتتاحية نهاية السنة المالية',
        createdAt: DateTime.now(),
      ));

      // 2. ترحيل الرصيد إلى الأرباح والخسائر المرحلة 23411
      entries.add(ClosingEntry(
        id: null,
        fiscalYearId: fiscalYearId,
        entryType: 'TRANSFER_RETAINED',
        accountCode: '23411',
        accountName: 'أرباح وخسائر مرحلة',
        accountType: 'equity',
        debit: suspenseBalance < 0 ? suspenseBalance.abs() : 0,
        credit: suspenseBalance > 0 ? suspenseBalance : 0,
        description: 'ترحيل فروق الأرصدة الافتتاحية إلى الأرباح والخسائر المرحلة',
        createdAt: DateTime.now(),
      ));
    }

    return entries;
  }

  Future<List<ClosingEntry>> generateOpeningEntries(int closingFiscalYearId) async {
    final entries = <ClosingEntry>[];

    final accounts = await _dao.getPermanentAccounts();

    for (final account in accounts) {
      final code = account['account_code'] as String;
      // عدم ترحيل حساب فروق أرصدة افتتاحية 23421 أو أرباح العام الحالي 23511 كأرصدة افتتاحية
      // لأنها أقفلت بالكامل في الأرباح المرحلة 23411 بنهاية السنة
      if (code == '23421' || code == '23511' || code == '2351' || code == '2342') {
        continue;
      }

      final totals = await _dao.getAccountTotals(code, closingFiscalYearId);
      final balance = totals['debit']! - totals['credit']!;
      if (balance.abs() > 0.01) {
        entries.add(ClosingEntry(
          id: null,
          fiscalYearId: 0,
          entryType: 'OPENING_BALANCE',
          accountCode: code,
          accountName: account['name'] as String,
          accountType: account['account_type'] as String,
          debit: balance > 0 ? balance : 0,
          credit: balance < 0 ? balance.abs() : 0,
          description: 'قيد افتتاحي - بداية السنة المالية الجديدة',
          createdAt: DateTime.now(),
        ));
      }
    }

    return entries;
  }

  Future<List<Map<String, dynamic>>> getInventorySnapshot(int fiscalYearId) async {
    try {
      final response = await _client
          .from('stock_batches')
          .select('product_id, warehouse_id, remaining_quantity, cost_per_unit, cost_method')
          .gt('remaining_quantity', 0);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }
}
