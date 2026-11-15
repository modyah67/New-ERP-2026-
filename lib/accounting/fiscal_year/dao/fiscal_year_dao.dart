import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';

class FiscalYearDao {
  final SupabaseClient _client;

  FiscalYearDao({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  Future<List<FiscalYear>> getAll() async {
    final response = await _client.from('fiscal_years').select().order('start_date', ascending: true);
    return (response as List).map((e) => FiscalYear.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FiscalYear?> getCurrent() async {
    final response = await _client
        .from('fiscal_years')
        .select()
        .eq('is_current', true)
        .order('start_date', ascending: false)
        .limit(1);
    final list = response as List;
    if (list.isEmpty) return null;
    return FiscalYear.fromJson(list.first as Map<String, dynamic>);
  }

  Future<FiscalYear?> getById(int id) async {
    final response = await _client.from('fiscal_years').select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return FiscalYear.fromJson(response as Map<String, dynamic>);
  }

  Future<bool> exists(int year) async {
    final response = await _client.from('fiscal_years').select('id').eq('year', year).maybeSingle();
    return response != null;
  }

  Future<FiscalYear?> getByYear(int year) async {
    final response = await _client.from('fiscal_years').select().eq('year', year).maybeSingle();
    if (response == null) return null;
    return FiscalYear.fromJson(response as Map<String, dynamic>);
  }

  Future<FiscalYear> create(FiscalYear fy) async {
    final payload = fy.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    final response = await _client.from('fiscal_years').insert(payload).select().single();
    return FiscalYear.fromJson(response as Map<String, dynamic>);
  }

  Future<FiscalYear> update(FiscalYear fy) async {
    final payload = fy.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    final response = await _client.from('fiscal_years').update(payload).eq('id', fy.id).select().single();
    return FiscalYear.fromJson(response as Map<String, dynamic>);
  }

  Future<void> setCurrent(int id, {String? performedBy, String? reason}) async {
    // 1. Unset all other years first so trigger checks pass safely
    await _client.from('fiscal_years').update({'is_current': false}).neq('id', id);
    // 2. Set the target year as current
    await _client.from('fiscal_years').update({'is_current': true}).eq('id', id);
    final fy = await getById(id);
    if (fy != null) {
      await audit(
        fiscalYearId: fy.id,
        action: 'SET_CURRENT',
        performedBy: performedBy,
        oldStatus: {'is_current': false},
        newStatus: {'is_current': true},
        reason: reason,
      );
    }
  }

  Future<void> updateStatus(int id, {required FiscalYearStatus status, String? performedBy, String? reason}) async {
    final updates = <String, dynamic>{
      'status': status.value,
      'is_closed': status == FiscalYearStatus.closed || status == FiscalYearStatus.archived,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status == FiscalYearStatus.closed) {
      updates['closed_by'] = performedBy;
      updates['closed_at'] = DateTime.now().toUtc().toIso8601String();
      updates['is_current'] = false;
    } else if (status == FiscalYearStatus.archived) {
      updates['is_current'] = false;
    } else if (status == FiscalYearStatus.active && performedBy != null) {
      updates['opened_by'] = performedBy;
      updates['opened_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _client.from('fiscal_years').update(updates).eq('id', id);
  }

  Future<void> closeStatus(int id, {String? performedBy, String? reason}) async {
    await updateStatus(id, status: FiscalYearStatus.closed, performedBy: performedBy, reason: reason);
    final fy = await getById(id);
    if (fy != null) {
      await audit(
        fiscalYearId: fy.id,
        action: 'CLOSE',
        performedBy: performedBy,
        oldStatus: {'status': fy.status.value, 'is_closed': fy.isClosed},
        newStatus: {'status': 'CLOSED', 'is_closed': true},
        reason: reason,
      );
    }
  }

  Future<void> reopenStatus(int id, {String? performedBy, String? reason}) async {
    await updateStatus(id, status: FiscalYearStatus.active, performedBy: performedBy, reason: reason);
    final fy = await getById(id);
    if (fy != null) {
      await audit(
        fiscalYearId: fy.id,
        action: 'REOPEN',
        performedBy: performedBy,
        oldStatus: {'status': fy.status.value, 'is_closed': fy.isClosed},
        newStatus: {'status': 'ACTIVE', 'is_closed': false},
        reason: reason,
      );
    }
  }

  Future<bool> overlaps(DateTime start, DateTime end, {int? excludeId}) async {
    var query = _client.from('fiscal_years')
        .select('id')
        .lte('start_date', end.toIso8601String())
        .gte('end_date', start.toIso8601String());
    if (excludeId != null) {
      query = query.neq('id', excludeId);
    }
    final response = await query;
    return (response as List).isNotEmpty;
  }

  Future<bool> isDateInClosedFiscalYear(DateTime date) async {
    try {
      final dateStr = date.toIso8601String().substring(0, 10);
      final response = await _client
          .from('fiscal_years')
          .select('is_closed, status')
          .lte('start_date', dateStr)
          .gte('end_date', dateStr)
          .maybeSingle();

      if (response == null) return false;
      final isClosed = response['is_closed'] == true ||
          (response['status'] as String?)?.toUpperCase() == 'CLOSED';
      return isClosed;
    } catch (_) {
      try {
        final fyId = await _getFiscalYearIdForDate(date);
        if (fyId == null) return false;
        final response = await _client.rpc('is_fiscal_year_closed', params: {
          'p_fiscal_year_id': fyId,
        });
        return response as bool? ?? false;
      } catch (_) {
        return false;
      }
    }
  }

  Future<int?> _getFiscalYearIdForDate(DateTime date) async {
    final response = await _client.rpc('get_fiscal_year_for_date', params: {
      'p_date': date.toIso8601String(),
    });
    return response as int?;
  }

  Future<List<FiscalYear>> getClosedYears() async {
    final response = await _client.from('fiscal_years')
        .select()
        .eq('is_closed', true)
        .order('year', ascending: false);
    return (response as List).map((e) => FiscalYear.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<FiscalYear>> getActiveYears() async {
    final response = await _client.from('fiscal_years')
        .select()
        .eq('status', 'ACTIVE')
        .order('year', ascending: false);
    return (response as List).map((e) => FiscalYear.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> archive(int id, {String? performedBy}) async {
    await updateStatus(id, status: FiscalYearStatus.archived, performedBy: performedBy);
    final fy = await getById(id);
    if (fy != null) {
      await audit(
        fiscalYearId: fy.id,
        action: 'ARCHIVE',
        performedBy: performedBy,
        oldStatus: {'status': fy.status.value},
        newStatus: {'status': 'ARCHIVED'},
      );
    }
  }

  Future<void> audit({
    required int fiscalYearId,
    required String action,
    String? performedBy,
    Map<String, dynamic>? oldStatus,
    Map<String, dynamic>? newStatus,
    String? reason,
    String? machineInfo,
    Map<String, dynamic>? details,
    int? durationMs,
  }) async {
    final payload = {
      'fiscal_year_id': fiscalYearId,
      'action': action,
      if (performedBy != null) 'performed_by': performedBy,
      'performed_at': DateTime.now().toUtc().toIso8601String(),
      if (oldStatus != null) 'old_status': oldStatus,
      if (newStatus != null) 'new_status': newStatus,
      if (reason != null) 'reason': reason,
      if (machineInfo != null) 'machine_info': machineInfo,
      if (details != null) 'details': details,
      if (durationMs != null) 'duration_ms': durationMs,
    };
    await _client.from('fiscal_year_audit_log').insert(payload);
  }

  Future<Map<String, dynamic>?> getAuditLogForFiscalYear(int fiscalYearId, {int limit = 50}) async {
    final response = await _client.from('fiscal_year_audit_log')
        .select()
        .eq('fiscal_year_id', fiscalYearId)
        .order('performed_at', ascending: false)
        .limit(limit);
    return {'entries': response};
  }

  Future<List<Map<String, dynamic>>> getAccountBalances(int fiscalYearId) async {
    final response = await _client.rpc('get_account_balances_for_fy', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    if (response == null) return [];
    
    Map<String, dynamic> map = {};
    if (response is List) {
      if (response.isEmpty) return [];
      map = Map<String, dynamic>.from(response.first as Map);
    } else {
      map = Map<String, dynamic>.from(response as Map);
    }

    return map.entries.map((e) => {
      'account_code': e.key,
      ...Map<String, dynamic>.from(e.value as Map),
    }).toList();
  }

  Future<Map<String, dynamic>> getAccountBalancesWithCurrency(int fiscalYearId) async {
    final response = await _client.rpc('get_account_balances_with_currency', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    if (response == null) return {};
    if (response is List) {
      if (response.isEmpty) return {};
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> getRevenueAccounts() async {
    final response = await _client
        .from('accounts')
        .select('account_code, name, account_type')
        .eq('account_type', 'revenue')
        .eq('is_active', true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getExpenseAccounts() async {
    final response = await _client
        .from('accounts')
        .select('account_code, name, account_type')
        .eq('account_type', 'expense')
        .eq('is_active', true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, double>> getAccountTotals(String accountCode, int fiscalYearId) async {
    final response = await _client.rpc('get_account_totals', params: {
      'p_account_code': accountCode,
      'p_fiscal_year_id': fiscalYearId,
    });
    if (response == null) return {'debit': 0.0, 'credit': 0.0};
    
    Map<String, dynamic> data = {};
    if (response is List) {
      if (response.isEmpty) return {'debit': 0.0, 'credit': 0.0};
      data = Map<String, dynamic>.from(response.first as Map);
    } else {
      data = Map<String, dynamic>.from(response as Map);
    }

    return {
      'debit': (data['total_debit'] as num?)?.toDouble() ?? 0.0,
      'credit': (data['total_credit'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> getPermanentAccounts() async {
    final response = await _client
        .from('accounts')
        .select('account_code, name, account_type')
        .inFilter('account_type', ['asset', 'liability', 'equity'])
        .eq('is_active', true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<bool> validateTrialBalance(int fiscalYearId) async {
    final response = await _client.rpc('validate_trial_balance', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    return response as bool? ?? false;
  }

  Future<int> countDraftTransactions(int fiscalYearId) async {
    final response = await _client.rpc('count_draft_transactions', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    return (response as int?) ?? 0;
  }

  Future<int> countNegativeStock() async {
    final response = await _client.rpc('count_negative_stock');
    return (response as int?) ?? 0;
  }

  Future<int> countBrokenFifoLayers() async {
    final response = await _client.rpc('count_broken_fifo_layers');
    return (response as int?) ?? 0;
  }

  Future<int> findOrphanEntries(int fiscalYearId) async {
    final response = await _client.rpc('find_orphan_entries', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    return (response as int?) ?? 0;
  }

  Future<int> findDuplicateEntries(int fiscalYearId) async {
    final response = await _client.rpc('find_duplicate_entries', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    return (response as int?) ?? 0;
  }

  Future<bool> acquireClosingLock(String userId, int fiscalYearId) async {
    try {
      final response = await _client.rpc('acquire_closing_lock', params: {
        'p_user_id': userId,
        'p_fiscal_year_id': fiscalYearId,
      });
      return response as bool? ?? false;
    } catch (e) {
      // Fallback: If RPC throws (e.g. legacy type mismatch in PostgreSQL),
      // verify lock availability directly from table
      try {
        final lockData = await _client
            .from('fiscal_year_closing_lock')
            .select('status, locked_by, fiscal_year_id')
            .eq('id', 1)
            .maybeSingle();
        if (lockData == null ||
            lockData['status'] == 'FREE' ||
            lockData['status'] == null ||
            lockData['locked_by'] == userId ||
            lockData['fiscal_year_id'] == fiscalYearId) {
          await _client.from('fiscal_year_closing_lock').upsert({
            'id': 1,
            'status': 'LOCKED',
            'locked_by': userId,
            'fiscal_year_id': fiscalYearId,
            'locked_at': DateTime.now().toUtc().toIso8601String(),
          });
          return true;
        }
      } catch (_) {}
      return false;
    }
  }

  Future<void> releaseClosingLock() async {
    try {
      await _client.rpc('release_closing_lock');
    } catch (_) {}
    try {
      await _client.from('fiscal_year_closing_lock').update({
        'status': 'FREE',
        'locked_by': null,
        'fiscal_year_id': null,
        'released_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 1);
    } catch (_) {}
  }

  Future<bool> forceReleaseStaleLock() async {
    try {
      final response = await _client.rpc('force_release_stale_lock');
      return response as bool? ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> updateClosingProgress(int fiscalYearId, String status, int progressPct, String currentStep, {String? errorMessage}) async {
    await _client.rpc('update_closing_progress', params: {
      'p_fiscal_year_id': fiscalYearId,
      'p_status': status,
      'p_progress_pct': progressPct,
      'p_current_step': currentStep,
      'p_error_message': errorMessage,
    });
  }

  Future<Map<String, dynamic>?> getClosingProgress(int fiscalYearId) async {
    final response = await _client.rpc('get_closing_progress', params: {
      'p_fiscal_year_id': fiscalYearId,
    });
    if (response == null) return null;
    
    if (response is List) {
      if (response.isEmpty) return null;
      return Map<String, dynamic>.from(response.first as Map);
    }
    
    final map = response as Map;
    if (map.isEmpty) return null;
    return Map<String, dynamic>.from(map);
  }

  Future<void> insertClosingEntry(Map<String, dynamic> entry) async {
    await _client.from('fiscal_year_closing_entries').insert(entry);
  }

  Future<List<Map<String, dynamic>>> getClosingEntries(int fiscalYearId, {String? entryType}) async {
    var query = _client.from('fiscal_year_closing_entries')
        .select()
        .eq('fiscal_year_id', fiscalYearId);
    if (entryType != null) {
      query = query.eq('entry_type', entryType);
    }
    final response = await query.order('id', ascending: true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertInventorySnapshot(Map<String, dynamic> snapshot) async {
    await _client.from('fiscal_year_inventory_snapshot').insert(snapshot);
  }

  Future<List<Map<String, dynamic>>> getInventorySnapshots(int fiscalYearId, {String? snapshotType}) async {
    var query = _client.from('fiscal_year_inventory_snapshot')
        .select()
        .eq('fiscal_year_id', fiscalYearId);
    if (snapshotType != null) {
      query = query.eq('snapshot_type', snapshotType);
    }
    final response = await query.order('id', ascending: true);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<void> insertBackupMetadata(Map<String, dynamic> metadata) async {
    await _client.from('fiscal_year_backup_metadata').insert(metadata);
  }

  Future<List<Map<String, dynamic>>> getBackupMetadata(int fiscalYearId) async {
    final response = await _client.from('fiscal_year_backup_metadata')
        .select()
        .eq('fiscal_year_id', fiscalYearId)
        .order('backup_time', ascending: false);
    return (response as List).cast<Map<String, dynamic>>();
  }
}
