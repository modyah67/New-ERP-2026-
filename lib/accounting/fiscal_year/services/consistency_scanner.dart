import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/fiscal_year_dao.dart';

enum IssueSeverity { info, warning, error }

class ConsistencyIssue {
  final String category;
  final String categoryAr;
  final String description;
  final String descriptionAr;
  final IssueSeverity severity;
  final int? count;
  final Map<String, dynamic>? details;

  const ConsistencyIssue({
    required this.category,
    required this.categoryAr,
    required this.description,
    required this.descriptionAr,
    required this.severity,
    this.count,
    this.details,
  });
}

class ConsistencyScanner {
  final SupabaseClient _client;
  final FiscalYearDao _dao;

  ConsistencyScanner({SupabaseClient? client, FiscalYearDao? dao})
      : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao();

  Future<List<ConsistencyIssue>> scanAll(int fiscalYearId) async {
    final results = await Future.wait([
      _scanBrokenReferences(fiscalYearId),
      _scanInvalidBalances(fiscalYearId),
      _scanMissingCurrencySnapshots(fiscalYearId),
      _scanNegativeInventory(),
      _scanBrokenFifo(),
      _scanMissingAuditRecords(fiscalYearId),
      _scanDuplicateVouchers(fiscalYearId),
      _scanUnbalancedJournals(fiscalYearId),
      _scanCorruptedOpeningBalances(fiscalYearId),
      _scanCorruptedClosingBalances(fiscalYearId),
    ]);
    return results.expand((list) => list).toList();
  }

  Future<List<ConsistencyIssue>> _scanBrokenReferences(int fyId) async {
    try {
      final orphans = await _dao.findOrphanEntries(fyId);
      if (orphans > 0) {
        return [ConsistencyIssue(
          category: 'References',
          categoryAr: 'المرجعيات',
          description: '$orphans orphan entries',
          descriptionAr: '$orphans قيد يتيم بمرجع غير صحيح',
          severity: IssueSeverity.error,
          count: orphans,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanInvalidBalances(int fyId) async {
    try {
      final balanced = await _dao.validateTrialBalance(fyId);
      if (!balanced) {
        return [ConsistencyIssue(
          category: 'Balances',
          categoryAr: 'الأرصدة',
          description: 'Trial balance is not balanced',
          descriptionAr: 'ميزان المراجعة غير متوازن',
          severity: IssueSeverity.error,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanMissingCurrencySnapshots(int fyId) async {
    try {
      final fy = await _dao.getById(fyId);
      if (fy == null) return [];
      final response = await _client.from('transactions')
          .select('id')
          .gte('transaction_date', fy.startDate.toIso8601String())
          .lte('transaction_date', fy.endDate.toIso8601String());
      final count = (response as List).length;
      if (count > 0) {
        return [ConsistencyIssue(
          category: 'Currency',
          categoryAr: 'العملة',
          description: '$count transactions missing currency snapshots',
          descriptionAr: '$count معاملة بدون لقطة عملة',
          severity: IssueSeverity.warning,
          count: count,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanNegativeInventory() async {
    try {
      final negative = await _dao.countNegativeStock();
      if (negative > 0) {
        return [ConsistencyIssue(
          category: 'Inventory',
          categoryAr: 'المخزون',
          description: '$negative items with negative stock',
          descriptionAr: '$negative أصناف بمخزون سالب',
          severity: IssueSeverity.error,
          count: negative,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanBrokenFifo() async {
    try {
      final broken = await _dao.countBrokenFifoLayers();
      if (broken > 0) {
        return [ConsistencyIssue(
          category: 'FIFO',
          categoryAr: 'FIFO',
          description: '$broken broken FIFO layers',
          descriptionAr: '$broken طبقة FIFO مكسورة',
          severity: IssueSeverity.error,
          count: broken,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanMissingAuditRecords(int fyId) async {
    try {
      final fy = await _dao.getById(fyId);
      if (fy == null) return [];
      if (fy.isClosed) {
        final log = await _dao.getAuditLogForFiscalYear(fyId, limit: 1);
        final hasLog = log != null && (log['entries'] as List?)?.isNotEmpty == true;
        if (!hasLog) {
          return [ConsistencyIssue(
            category: 'Audit',
            categoryAr: 'التدقيق',
            description: 'Closed FY missing audit records',
            descriptionAr: 'سنة مالية مغلقة بدون سجل تدقيق',
            severity: IssueSeverity.error,
          )];
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanDuplicateVouchers(int fyId) async {
    try {
      final duplicates = await _dao.findDuplicateEntries(fyId);
      if (duplicates > 0) {
        return [ConsistencyIssue(
          category: 'Duplicates',
          categoryAr: 'التكرارات',
          description: '$duplicates duplicate voucher entries',
          descriptionAr: '$duplicates قيد سند مكرر',
          severity: IssueSeverity.error,
          count: duplicates,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanUnbalancedJournals(int fyId) async {
    try {
      final fy = await _dao.getById(fyId);
      if (fy == null) return [];
      final response = await _client.rpc('validate_trial_balance', params: {
        'p_fiscal_year_id': fyId,
      });
      if (response != true) {
        return [ConsistencyIssue(
          category: 'Journals',
          categoryAr: 'القيود اليومية',
          description: 'Unbalanced journal entries found',
          descriptionAr: 'تم العثور على قيود يومية غير متوازنة',
          severity: IssueSeverity.error,
        )];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanCorruptedOpeningBalances(int fyId) async {
    try {
      final entries = await _dao.getClosingEntries(fyId, entryType: 'OPENING_BALANCE');
      if (entries.isNotEmpty) {
        double totalDebit = 0;
        double totalCredit = 0;
        for (final e in entries) {
          totalDebit += (e['debit'] as num?)?.toDouble() ?? 0;
          totalCredit += (e['credit'] as num?)?.toDouble() ?? 0;
        }
        if ((totalDebit - totalCredit).abs() > 0.01) {
          return [ConsistencyIssue(
            category: 'Opening',
            categoryAr: 'الافتتاحية',
            description: 'Opening balances not balanced: D=$totalDebit C=$totalCredit',
            descriptionAr: 'القيود الافتتاحية غير متوازنة',
            severity: IssueSeverity.error,
          )];
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<ConsistencyIssue>> _scanCorruptedClosingBalances(int fyId) async {
    try {
      final entries = await _dao.getClosingEntries(fyId, entryType: 'CLOSE_REVENUE');
      if (entries.isEmpty) {
        final fy = await _dao.getById(fyId);
        if (fy != null && fy.isClosed) {
          return [ConsistencyIssue(
            category: 'Closing',
            categoryAr: 'الإغلاق',
            description: 'Closed FY has no closing entries',
            descriptionAr: 'سنة مالية مغلقة بدون قيود إغلاق',
            severity: IssueSeverity.warning,
          )];
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
