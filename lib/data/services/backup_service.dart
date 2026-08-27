import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BackupService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Trigger a manual backup entry.
  /// In production this would trigger Supabase Database Backup API.
  Future<bool> createBackup() async {
    try {
      await _client.from('backup_history').insert({
        'file_name': 'backup_${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.sql',
        'status': 'running',
        'type': 'manual',
        'created_by': _userId,
      });
      return true;
    } catch (e, st) {
      debugPrint('BackupService.createBackup error: $e\n$st');
      return false;
    }
  }

  /// Mark a backup as completed.
  Future<void> completeBackup(int backupId, {String? error}) async {
    try {
      await _client.from('backup_history').update({
        'status': error != null ? 'failed' : 'completed',
        if (error != null) 'error_message': error,
      }).eq('id', backupId);
    } catch (_) {}
  }

  /// Get backup history.
  Future<List<Map<String, dynamic>>> getHistory({int limit = 50}) async {
    try {
      final data = await _client
          .from('backup_history')
          .select('*, profiles(full_name)')
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).map((row) {
        final r = row as Map<String, dynamic>;
        final profiles = r['profiles'] as Map? ?? {};
        return {
          ...r,
          'created_by_name': profiles['full_name'] ?? 'نظام',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete a backup history entry.
  Future<bool> deleteEntry(int id) async {
    try {
      await _client.from('backup_history').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}
