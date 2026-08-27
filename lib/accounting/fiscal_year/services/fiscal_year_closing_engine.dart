import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import '../models/closing_entry.dart';
import '../models/closing_result.dart';
import '../models/closing_progress.dart';
import '../dao/fiscal_year_dao.dart';
import 'closing_validation_service.dart';
import 'closing_audit_service.dart';

class FiscalYearClosingEngine {
  final SupabaseClient _client;
  final FiscalYearDao _dao;
  final ClosingValidationService _validationService;
  final ClosingAuditService _auditService;

  FiscalYearClosingEngine({
    SupabaseClient? client,
    FiscalYearDao? dao,
    ClosingValidationService? validationService,
    ClosingAuditService? auditService,
  })  : _client = client ?? Supabase.instance.client,
        _dao = dao ?? FiscalYearDao(),
        _validationService = validationService ?? ClosingValidationService(),
        _auditService = auditService ?? ClosingAuditService();

  Future<FiscalYear?> getCurrentFiscalYear() => _dao.getCurrent();
  Future<List<FiscalYear>> getAllFiscalYears() => _dao.getAll();
  Future<FiscalYear?> getFiscalYearById(int id) => _dao.getById(id);

  Future<List<String>> validatePreClosing(int fiscalYearId) =>
      _validationService.validatePreClosing(fiscalYearId);

  Future<ClosingProgress?> getClosingProgress(int fiscalYearId) async {
    final data = await _dao.getClosingProgress(fiscalYearId);
    if (data == null) return null;
    return ClosingProgress(
      id: data['id'] as int?,
      fiscalYearId: fiscalYearId,
      status: ClosingProgressStatusExtension.fromString(data['status'] as String? ?? 'PENDING'),
      progressPct: data['progress_pct'] as int? ?? 0,
      currentStep: data['current_step'] as String?,
      startedAt: DateTime.parse(data['started_at'] as String? ?? DateTime.now().toIso8601String()),
      completedAt: data['completed_at'] != null ? DateTime.parse(data['completed_at'] as String) : null,
      errorMessage: data['error_message'] as String?,
    );
  }

  Future<ClosingResult> closeFiscalYear({
    required int fiscalYearId,
    required String userId,
    String? reason,
    bool createNextYear = false,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Try atomic PostgreSQL RPC
      try {
        final rpcRes = await _client.rpc('rpc_close_fiscal_year', params: {
          'p_fiscal_year_id': fiscalYearId,
          'p_user_id': userId,
          'p_reason': reason,
          'p_create_next_year': createNextYear,
        });
        if (rpcRes != null && (rpcRes['success'] == true || rpcRes is Map)) {
          stopwatch.stop();
          return ClosingResult(
            success: true,
            message: 'تم إغلاق السنة المالية بنجاح',
            closingEntries: [],
            openingEntries: [],
            netIncome: (rpcRes['net_income'] as num?)?.toDouble() ?? 0.0,
            revenueTotals: {'total': (rpcRes['total_revenue'] as num?)?.toDouble() ?? 0.0},
            expenseTotals: {'total': (rpcRes['total_expense'] as num?)?.toDouble() ?? 0.0},
            closedAt: DateTime.now(),
            duration: stopwatch.elapsed,
          );
        }
      } catch (rpcErr) {
        // Fallback to client-side pipeline
      }

      // Step 1: Validate
      await _updateProgress(fiscalYearId, ClosingProgressStatus.validating, 'التحقق من البيانات');
      final fy = await _dao.getById(fiscalYearId);
      if (fy == null) {
        return ClosingResult.failure('السنة المالية غير موجودة');
      }
      if (fy.isClosed) {
        return ClosingResult.failure('السنة المالية مغلقة مسبقاً');
      }
      if (!fy.status.canTransitionToClosing) {
        return ClosingResult.failure('لا يمكن إغلاق السنة المالية من الحالة الحالية: ${fy.status.displayNameAr}');
      }

      final validationErrors = await validatePreClosing(fiscalYearId);
      if (validationErrors.isNotEmpty) {
        await _auditService.logValidate(fy: fy, userId: userId, details: {'errors': validationErrors});
        await _updateProgress(fiscalYearId, ClosingProgressStatus.failed, 'فشل التحقق', error: validationErrors.join(', '));
        return ClosingResult.failure('فشل التحقق: ${validationErrors.join(', ')}');
      }

      // Step 2: Acquire distributed lock
      await _updateProgress(fiscalYearId, ClosingProgressStatus.validating, '获取 قفل الإغلاق');
      final lockAcquired = await _dao.acquireClosingLock(userId, fiscalYearId);
      if (!lockAcquired) {
        final staleReleased = await _dao.forceReleaseStaleLock();
        if (staleReleased) {
          final retryLock = await _dao.acquireClosingLock(userId, fiscalYearId);
          if (!retryLock) {
            return ClosingResult.failure('يوجد عملية إغلاق أخرى جارية حالياً. حاول مرة أخرى لاحقاً');
          }
        } else {
          return ClosingResult.failure('يوجد عملية إغلاق أخرى جارية حالياً. حاول مرة أخرى لاحقاً');
        }
      }

      await _auditService.logLockAcquired(fy: fy, userId: userId);

      // Step 2.5: Verify backup exists (Part 7)
      final backupVerified = await _client.rpc('verify_fiscal_year_backup', params: {'p_fiscal_year_id': fiscalYearId});
      if (backupVerified == null || (backupVerified is Map && backupVerified['verified'] == false)) {
        await _rollback(fiscalYearId, fy, userId, 'لا توجد نسخة احتياطية موثقة');
        return ClosingResult.failure('يجب التحقق من النسخة الاحتياطية قبل الإغلاق');
      }

      // Step 3: Begin database transaction - set status to CLOSING
      await _dao.updateStatus(fiscalYearId, status: FiscalYearStatus.closing, performedBy: userId);

      // Step 4: Generate and persist closing entries (GL)
      await _updateProgress(fiscalYearId, ClosingProgressStatus.closingGl, 'إغلاق الدفتر الأستاذ العام');
      final closingEntries = await _validationService.generateClosingEntries(fiscalYearId);

      final revenueTotals = <String, double>{};
      final expenseTotals = <String, double>{};
      double netIncome = 0;

      for (final entry in closingEntries) {
        if (entry.entryType == 'TRANSFER_RETAINED') {
          netIncome = entry.credit > 0 ? entry.credit : -entry.debit;
        } else if (entry.accountType == 'revenue') {
          revenueTotals[entry.accountCode] = entry.credit - entry.debit;
        } else if (entry.accountType == 'expense') {
          expenseTotals[entry.accountCode] = entry.debit - entry.credit;
        }
      }

      final persisted = await _persistJournalEntries(
        entries: closingEntries,
        transactionDate: fy.endDate,
        referenceType: 'fiscal_year_closing',
        referenceId: fiscalYearId.toString(),
      );
      if (!persisted) {
        await _rollback(fiscalYearId, fy, userId, 'فشل حفظ قيود الإغلاق');
        return ClosingResult.failure('فشل حفظ قيود إغلاق السنة المالية');
      }

      // Persist closing entries in tracking table
      for (final entry in closingEntries) {
        await _dao.insertClosingEntry(entry.toJson()..['fiscal_year_id'] = fiscalYearId);
      }

      // Step 5: Capture inventory snapshots
      await _updateProgress(fiscalYearId, ClosingProgressStatus.closingInventory, 'إغلاق المخزون');
      await _captureInventorySnapshot(fiscalYearId, 'CLOSING');

      // Step 6: Generate and persist opening entries
      await _updateProgress(fiscalYearId, ClosingProgressStatus.generatingOpening, 'إنشاء القيود الافتتاحية');
      final openingEntries = await _validationService.generateOpeningEntries(fiscalYearId);

      // Step 7: Write audit logs
      await _updateProgress(fiscalYearId, ClosingProgressStatus.writingAudit, 'كتابة سجل التدقيق');
      final closedAt = DateTime.now();
      final oldStatus = {
        'status': fy.status.value,
        'is_closed': fy.isClosed,
        'year': fy.year,
      };

      await _auditService.logClose(
        fy: fy,
        userId: userId,
        oldStatus: oldStatus,
        newStatus: {'status': 'CLOSED', 'is_closed': true},
        reason: reason,
        details: {
          'closing_entries_count': closingEntries.length,
          'net_income': netIncome,
          'revenue_total': revenueTotals.values.fold(0.0, (sum, v) => sum + v),
          'expense_total': expenseTotals.values.fold(0.0, (sum, v) => sum + v),
          'opening_entries_count': openingEntries.length,
        },
        durationMs: stopwatch.elapsedMilliseconds,
      );

      // Step 8: Mark as CLOSED
      await _updateProgress(fiscalYearId, ClosingProgressStatus.finalizing, 'الإنهاء');
      await _dao.closeStatus(fiscalYearId, performedBy: userId, reason: reason);

      // Step 9: Create next fiscal year if requested
      int? newFiscalYearId;
      if (createNextYear) {
        final nextFy = await _createNextFiscalYear(fy, userId);
        if (nextFy != null) {
          newFiscalYearId = nextFy.id;

          // Persist opening entries for new year
          final persistedOpening = await _persistJournalEntries(
            entries: openingEntries.map((e) => e.copyWith(fiscalYearId: nextFy.id)).toList(),
            transactionDate: nextFy.startDate,
            referenceType: 'opening_balance',
            referenceId: nextFy.id.toString(),
          );

          if (persistedOpening) {
            for (final entry in openingEntries) {
              await _dao.insertClosingEntry(entry.toJson()
                ..['fiscal_year_id'] = nextFy.id
                ..['entry_type'] = 'OPENING_BALANCE');
            }
            await _captureInventorySnapshot(nextFy.id, 'OPENING');
          }

          await _auditService.logOpeningEntries(
            fy: fy,
            userId: userId,
            details: {
              'new_fiscal_year_id': nextFy.id,
              'new_fiscal_year': nextFy.year,
              'opening_entries_count': openingEntries.length,
            },
            durationMs: stopwatch.elapsedMilliseconds,
          );
        }
      }

      // Step 10: Post-closing verification (Part 8)
      await _updateProgress(fiscalYearId, ClosingProgressStatus.validating, 'التحقق ما بعد الإغلاق');
      final postCheck = await _client.rpc('verify_post_closing_integrity', params: {'p_fiscal_year_id': fiscalYearId});
      if (postCheck != null && postCheck is Map && postCheck['all_passed'] == false) {
        await _auditService.logClosingFailed(
          fy: fy,
          userId: userId,
          error: 'فشل التحقق ما بعد الإغلاق: ${postCheck['issues']}',
        );
      }

      // Release lock
      await _dao.releaseClosingLock();
      await _auditService.logLockReleased(fy: fy, userId: userId);

      stopwatch.stop();

      // Step 10: Complete
      await _updateProgress(fiscalYearId, ClosingProgressStatus.completed, 'اكتمل الإغلاق');

      return ClosingResult.success(
        closingEntries: closingEntries,
        openingEntries: openingEntries,
        revenueTotals: revenueTotals,
        expenseTotals: expenseTotals,
        netIncome: netIncome,
        closedAt: closedAt,
        newFiscalYearId: newFiscalYearId,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      final fy = await _dao.getById(fiscalYearId);
      if (fy != null) {
        await _auditService.logClosingFailed(fy: fy, userId: userId, error: e.toString());
      }
      await _dao.releaseClosingLock();
      await _updateProgress(fiscalYearId, ClosingProgressStatus.failed, 'فشل الإغلاق', error: e.toString());
      return ClosingResult.failure('خطأ في الإغلاق: $e');
    }
  }

  Future<void> _rollback(int fiscalYearId, FiscalYear fy, String userId, String error) async {
    try {
      // Revert status to ACTIVE
      await _dao.updateStatus(fiscalYearId, status: FiscalYearStatus.active, performedBy: userId);
      // Delete any persisted closing entries
      await _client.from('fiscal_year_closing_entries').delete().eq('fiscal_year_id', fiscalYearId);
      // Release lock
      await _dao.releaseClosingLock();
      await _auditService.logClosingFailed(fy: fy, userId: userId, error: error);
    } catch (rollbackError) {
      await _updateProgress(fiscalYearId, ClosingProgressStatus.failed, 'فشل التراجع', error: rollbackError.toString());
    }
  }

  Future<ClosingResult> reopenFiscalYear({
    required int fiscalYearId,
    required String userId,
    required String reason,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Try atomic PostgreSQL RPC
      try {
        final rpcRes = await _client.rpc('rpc_reopen_fiscal_year', params: {
          'p_fiscal_year_id': fiscalYearId,
          'p_user_id': userId,
          'p_reason': reason,
        });
        if (rpcRes != null && (rpcRes['success'] == true || rpcRes is Map)) {
          stopwatch.stop();
          return ClosingResult(
            success: true,
            message: 'تم إعادة فتح السنة المالية بنجاح',
            closingEntries: [],
            openingEntries: [],
            netIncome: 0,
            closedAt: DateTime.now(),
            duration: stopwatch.elapsed,
          );
        }
      } catch (rpcErr) {
        // Fallback to client-side pipeline
      }

      final fy = await _dao.getById(fiscalYearId);
      if (fy == null) {
        return ClosingResult.failure('السنة المالية غير موجودة');
      }
      if (!fy.isClosed && fy.status != FiscalYearStatus.closed) {
        return ClosingResult.failure('السنة المالية ليست مغلقة');
      }
      if (reason.trim().isEmpty) {
        return ClosingResult.failure('يجب إدخال سبب إعادة الفتح');
      }

      // Reverse closing entries
      final closingEntries = await _dao.getClosingEntries(fiscalYearId, entryType: 'CLOSE_REVENUE');
      final expenseEntries = await _dao.getClosingEntries(fiscalYearId, entryType: 'CLOSE_EXPENSE');
      final retainedEntries = await _dao.getClosingEntries(fiscalYearId, entryType: 'TRANSFER_RETAINED');

      final allClosing = [...closingEntries, ...expenseEntries, ...retainedEntries];
      if (allClosing.isNotEmpty) {
        final reversedEntries = allClosing.map((e) => ClosingEntry(
          id: null,
          fiscalYearId: fiscalYearId,
          entryType: 'REVERSE_CLOSING',
          accountCode: e['account_code'] as String,
          accountName: e['account_name'] as String?,
          accountType: e['account_type'] as String?,
          debit: (e['credit'] as num?)?.toDouble() ?? 0.0,
          credit: (e['debit'] as num?)?.toDouble() ?? 0.0,
          description: 'عكس قيود الإغلاق - إعادة فتح',
          createdAt: DateTime.now(),
        )).toList();

        await _persistJournalEntries(
          entries: reversedEntries,
          transactionDate: DateTime.now(),
          referenceType: 'fiscal_year_reopening',
          referenceId: fiscalYearId.toString(),
        );

        for (final entry in reversedEntries) {
          await _dao.insertClosingEntry(entry.toJson()..['fiscal_year_id'] = fiscalYearId);
        }
      }

      // Revert status
      final oldStatus = {
        'status': fy.status.value,
        'is_closed': fy.isClosed,
        'closed_by': fy.closedBy,
        'closed_at': fy.closedAt?.toIso8601String(),
      };

      await _dao.reopenStatus(fiscalYearId, performedBy: userId, reason: reason);

      stopwatch.stop();

      await _auditService.logReopen(
        fy: fy,
        userId: userId,
        oldStatus: oldStatus,
        newStatus: {'status': 'ACTIVE', 'is_closed': false},
        reason: reason,
        details: {'reversed_entries_count': allClosing.length},
        durationMs: stopwatch.elapsedMilliseconds,
      );

      return ClosingResult(
        success: true,
        message: 'تم إعادة فتح السنة المالية بنجاح',
        closingEntries: [],
        openingEntries: [],
        netIncome: 0,
        closedAt: DateTime.now(),
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ClosingResult.failure('خطأ في إعادة الفتح: $e');
    }
  }

  Future<ClosingResult> archiveFiscalYear({
    required int fiscalYearId,
    required String userId,
  }) async {
    try {
      final fy = await _dao.getById(fiscalYearId);
      if (fy == null) return ClosingResult.failure('السنة المالية غير موجودة');
      if (fy.status != FiscalYearStatus.closed) {
        return ClosingResult.failure('لا يمكن أرشفة سنة مالية غير مغلقة');
      }

      await _dao.archive(fiscalYearId, performedBy: userId);

      return ClosingResult(
        success: true,
        message: 'تم أرشفة السنة المالية بنجاح',
        netIncome: 0,
        closedAt: DateTime.now(),
      );
    } catch (e) {
      return ClosingResult.failure('خطأ في الأرشفة: $e');
    }
  }

  Future<FiscalYear?> _createNextFiscalYear(FiscalYear currentFy, String userId) async {
    final nextYear = currentFy.year + 1;
    final existing = await _dao.exists(nextYear);
    if (existing) return null;

    final nextStartDate = currentFy.endDate.add(const Duration(days: 1));
    final nextEndDate = DateTime(nextYear, 12, 31);

    final newFy = FiscalYear(
      id: 0,
      year: nextYear,
      name: nextYear.toString(),
      startDate: nextStartDate,
      endDate: nextEndDate,
      status: FiscalYearStatus.active,
      isCurrent: true,
      isClosed: false,
      createdBy: userId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      companyId: currentFy.companyId,
    );

    return await _dao.create(newFy);
  }

  Future<void> _captureInventorySnapshot(int fiscalYearId, String snapshotType) async {
    try {
      final batches = await _validationService.getInventorySnapshot(fiscalYearId);
      for (final batch in batches) {
        final quantity = (batch['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (batch['cost_per_unit'] as num?)?.toDouble() ?? 0.0;
        final totalCost = quantity * unitCost;

        // Fetch currency snapshot for this batch's product
        Map<String, dynamic>? currencySnapshot;
        try {
          final productResponse = await _client
              .from('products')
              .select('currency, currency_snapshot')
              .eq('id', batch['product_id'])
              .maybeSingle();
          if (productResponse != null) {
            currencySnapshot = productResponse['currency_snapshot'] as Map<String, dynamic>?;
          }
        } catch (_) {}

        await _dao.insertInventorySnapshot({
          'fiscal_year_id': fiscalYearId,
          'snapshot_type': snapshotType,
          'product_id': batch['product_id'],
          'warehouse_id': batch['warehouse_id'],
          'batch_id': batch['id'],
          'quantity': quantity,
          'unit_cost': unitCost,
          'total_cost': totalCost,
          'cost_method': batch['cost_method'],
          'currency': batch['currency'] ?? 'USD',
          'original_amount': totalCost,
          'base_amount': totalCost,
          'exchange_rate': 1.0,
          'currency_snapshot': currencySnapshot,
          'captured_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Inventory snapshot failure is non-critical, log but continue
    }
  }

  Future<bool> _persistJournalEntries({
    required List<ClosingEntry> entries,
    required DateTime transactionDate,
    required String referenceType,
    String? referenceId,
  }) async {
    if (entries.isEmpty) return true;

    final lines = <Map<String, dynamic>>[];

    try {
      for (final entry in entries) {
        final accountId = await _getAccountIdByCode(entry.accountCode);
        if (accountId == null) {
          throw Exception('حساب غير موجود: ${entry.accountCode}');
        }

        lines.add({
          'account_id': int.parse(accountId),
          'debit': entry.isDebit ? entry.debit : 0,
          'base_debit': entry.isDebit ? entry.debit : 0,
          'credit': !entry.isDebit ? entry.credit : 0,
          'base_credit': !entry.isDebit ? entry.credit : 0,
          'currency': 'EGP',
          'description': entry.description ?? 'إقفال سنة مالية',
        });
      }

      final fyId = int.tryParse(referenceId ?? '') ?? 1;
      final fy = await _dao.getById(fyId);
      final companyId = fy?.companyId ?? (await _client.from('sys_companies').select('id').maybeSingle())?['id'];

      await _client.rpc('post_journal_entry', params: {
        'p_source_type': 'fiscal_year_closing',
        'p_description': 'قيد إقفال السنة المالية ${fy?.year ?? ''}',
        'p_entry_date': transactionDate.toIso8601String().substring(0, 10),
        'p_company_id': companyId,
        'p_created_by': _client.auth.currentUser?.id,
        'p_lines': lines,
        'p_source_id': referenceId,
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error persisting closing entries: $e');
      return false;
    }
  }

  Future<String?> _getAccountIdByCode(String accountCode) async {
    final response = await _client
        .from('accounts')
        .select('id')
        .eq('account_code', accountCode)
        .maybeSingle();
    if (response == null) return null;
    return response['id']?.toString();
  }

  Future<void> _updateProgress(int fiscalYearId, ClosingProgressStatus status, String step, {String? error}) async {
    try {
      await _dao.updateClosingProgress(
        fiscalYearId,
        status.value,
        status.progressPct,
        step,
        errorMessage: error,
      );
    } catch (_) {
      // Progress update failure is non-critical
    }
  }
}
