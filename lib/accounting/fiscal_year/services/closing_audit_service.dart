import 'dart:io';
import '../models/fiscal_year.dart';
import '../dao/fiscal_year_dao.dart';

class ClosingAuditService {
  final FiscalYearDao _dao;

  ClosingAuditService({FiscalYearDao? dao}) : _dao = dao ?? FiscalYearDao();

  String _getMachineInfo() {
    try {
      final hostname = Platform.localHostname;
      final os = Platform.operatingSystem;
      final version = Platform.operatingSystemVersion;
      return '$hostname ($os $version)';
    } catch (e) {
      return 'unknown';
    }
  }

  Future<void> logClose({
    required FiscalYear fy,
    required String userId,
    required Map<String, dynamic> oldStatus,
    required Map<String, dynamic> newStatus,
    String? reason,
    Map<String, dynamic>? details,
    int? durationMs,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'CLOSE',
      performedBy: userId,
      oldStatus: oldStatus,
      newStatus: newStatus,
      reason: reason,
      machineInfo: _getMachineInfo(),
      details: details,
      durationMs: durationMs,
    );
  }

  Future<void> logReopen({
    required FiscalYear fy,
    required String userId,
    required Map<String, dynamic> oldStatus,
    required Map<String, dynamic> newStatus,
    String? reason,
    Map<String, dynamic>? details,
    int? durationMs,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'REOPEN',
      performedBy: userId,
      oldStatus: oldStatus,
      newStatus: newStatus,
      reason: reason,
      machineInfo: _getMachineInfo(),
      details: details,
      durationMs: durationMs,
    );
  }

  Future<void> logValidate({
    required FiscalYear fy,
    required String userId,
    required Map<String, dynamic> details,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'VALIDATE',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
      details: details,
    );
  }

  Future<void> logOpeningEntries({
    required FiscalYear fy,
    required String userId,
    required Map<String, dynamic> details,
    int? durationMs,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'OPENING_ENTRIES',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
      details: details,
      durationMs: durationMs,
    );
  }

  Future<void> logReverseClosing({
    required FiscalYear fy,
    required String userId,
    String? reason,
    Map<String, dynamic>? details,
    int? durationMs,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'REVERSE_CLOSING',
      performedBy: userId,
      reason: reason,
      machineInfo: _getMachineInfo(),
      details: details,
      durationMs: durationMs,
    );
  }

  Future<void> logLockAcquired({
    required FiscalYear fy,
    required String userId,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'LOCK_ACQUIRED',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
    );
  }

  Future<void> logLockReleased({
    required FiscalYear fy,
    required String userId,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'LOCK_RELEASED',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
    );
  }

  Future<void> logBackupCreated({
    required FiscalYear fy,
    required String userId,
    required String backupId,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'BACKUP_CREATED',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
      details: {'backup_identifier': backupId},
    );
  }

  Future<void> logProgressUpdate({
    required FiscalYear fy,
    required String userId,
    required String step,
    required int progressPct,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'PROGRESS_UPDATE',
      performedBy: userId,
      machineInfo: _getMachineInfo(),
      details: {'step': step, 'progress_pct': progressPct},
    );
  }

  Future<void> logClosingFailed({
    required FiscalYear fy,
    required String userId,
    required String error,
    Map<String, dynamic>? details,
  }) async {
    await _dao.audit(
      fiscalYearId: fy.id,
      action: 'CLOSING_FAILED',
      performedBy: userId,
      reason: error,
      machineInfo: _getMachineInfo(),
      details: details,
    );
  }
}
