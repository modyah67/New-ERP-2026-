import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Immutable audit log entry for financial transactions.
///
/// Records every insert/update/delete on financial tables.
/// NEVER modifies existing entries — append-only.
class AuditLogEntry {
  final int? id;
  final String tableName;
  final String recordId;
  final String action;
  final Map<String, dynamic>? oldSnapshot;
  final Map<String, dynamic>? newSnapshot;
  final String? changedBy;
  final DateTime changedAt;
  final String? reason;
  final String? ipAddress;

  const AuditLogEntry({
    this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.oldSnapshot,
    this.newSnapshot,
    this.changedBy,
    required this.changedAt,
    this.reason,
    this.ipAddress,
  });

  Map<String, dynamic> toMap() => {
        'table_name': tableName,
        'record_id': recordId,
        'action': action,
        if (oldSnapshot != null) 'old_snapshot': oldSnapshot,
        if (newSnapshot != null) 'new_snapshot': newSnapshot,
        if (changedBy != null) 'changed_by': changedBy,
        'changed_at': changedAt.toIso8601String(),
        if (reason != null) 'reason': reason,
        if (ipAddress != null) 'ip_address': ipAddress,
      };
}

/// Service for recording financial audit trail.
///
/// Append-only: entries are NEVER modified or deleted.
class FinancialAuditLogDao {
  final _client = Supabase.instance.client;
  static const _table = 'financial_audit_log';

  /// Log an insert operation.
  Future<void> logInsert({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> snapshot,
    String? changedBy,
    String? reason,
  }) async {
    try {
      await _client.from(_table).insert(AuditLogEntry(
        tableName: tableName,
        recordId: recordId,
        action: 'insert',
        newSnapshot: snapshot,
        changedBy: changedBy,
        changedAt: DateTime.now(),
        reason: reason,
      ).toMap());
    } catch (e) {
      debugPrint('⚠️ FinancialAuditLogDao.logInsert error: $e');
    }
  }

  /// Log an update operation — stores both old and new snapshots.
  Future<void> logUpdate({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> oldSnapshot,
    required Map<String, dynamic> newSnapshot,
    String? changedBy,
    String? reason,
  }) async {
    try {
      await _client.from(_table).insert(AuditLogEntry(
        tableName: tableName,
        recordId: recordId,
        action: 'update',
        oldSnapshot: oldSnapshot,
        newSnapshot: newSnapshot,
        changedBy: changedBy,
        changedAt: DateTime.now(),
        reason: reason,
      ).toMap());
    } catch (e) {
      debugPrint('⚠️ FinancialAuditLogDao.logUpdate error: $e');
    }
  }

  /// Log a delete operation — stores the deleted snapshot.
  Future<void> logDelete({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> snapshot,
    String? changedBy,
    String? reason,
  }) async {
    try {
      await _client.from(_table).insert(AuditLogEntry(
        tableName: tableName,
        recordId: recordId,
        action: 'delete',
        oldSnapshot: snapshot,
        changedBy: changedBy,
        changedAt: DateTime.now(),
        reason: reason,
      ).toMap());
    } catch (e) {
      debugPrint('⚠️ FinancialAuditLogDao.logDelete error: $e');
    }
  }

  /// Get audit log for a specific record.
  Future<List<AuditLogEntry>> getForRecord({
    required String tableName,
    required String recordId,
  }) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('table_name', tableName)
          .eq('record_id', recordId)
          .order('changed_at', ascending: false);
      return data.map((row) => AuditLogEntry(
        id: row['id'] as int?,
        tableName: row['table_name'] as String,
        recordId: row['record_id'] as String,
        action: row['action'] as String,
        oldSnapshot: row['old_snapshot'] as Map<String, dynamic>?,
        newSnapshot: row['new_snapshot'] as Map<String, dynamic>?,
        changedBy: row['changed_by'] as String?,
        changedAt: DateTime.parse(row['changed_at'] as String),
        reason: row['reason'] as String?,
        ipAddress: row['ip_address'] as String?,
      )).toList();
    } catch (e) {
      debugPrint('❌ FinancialAuditLogDao.getForRecord error: $e');
      return [];
    }
  }

  /// Get recent audit entries across all tables.
  Future<List<AuditLogEntry>> getRecent({int limit = 50}) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .order('changed_at', ascending: false)
          .limit(limit);
      return data.map((row) => AuditLogEntry(
        id: row['id'] as int?,
        tableName: row['table_name'] as String,
        recordId: row['record_id'] as String,
        action: row['action'] as String,
        oldSnapshot: row['old_snapshot'] as Map<String, dynamic>?,
        newSnapshot: row['new_snapshot'] as Map<String, dynamic>?,
        changedBy: row['changed_by'] as String?,
        changedAt: DateTime.parse(row['changed_at'] as String),
        reason: row['reason'] as String?,
        ipAddress: row['ip_address'] as String?,
      )).toList();
    } catch (e) {
      debugPrint('❌ FinancialAuditLogDao.getRecent error: $e');
      return [];
    }
  }
}
