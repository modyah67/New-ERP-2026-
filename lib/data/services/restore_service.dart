import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RestoreService {
  final _client = Supabase.instance.client;

  /// Validate that a restore can proceed.
  /// Checks critical tables for data integrity.
  Future<Map<String, dynamic>> validateRestore() async {
    try {
      final checks = <String, dynamic>{
        'accounts_ok': false,
        'products_ok': false,
        'export_shipments_ok': false,
      };

      try {
        final accts = await _client.from('accounts').select('id').limit(1);
        checks['accounts_ok'] = (accts as List).isNotEmpty;
      } catch (e) {
        debugPrint('⚠️ restore_service: accounts table check failed: $e');
      }

      try {
        final prods = await _client.from('fruit_types').select('id').limit(1);
        checks['products_ok'] = (prods as List).isNotEmpty;
      } catch (e) {
        debugPrint('⚠️ restore_service: fruit_types table check failed: $e');
      }

      try {
        final exports = await _client.from('export_shipments').select('id').limit(1);
        checks['export_shipments_ok'] = (exports as List).isNotEmpty;
      } catch (e) {
        debugPrint('⚠️ restore_service: export_shipments table check failed: $e');
      }

      return checks;
    } catch (e) {
      debugPrint('RestoreService.validateRestore error: $e');
      return {'error': '$e'};
    }
  }

  /// Log a restore attempt.
  Future<void> logRestore({
    required bool success,
    String? error,
  }) async {
    try {
      await _client.from('backup_history').insert({
        'file_name': 'restore_${DateTime.now().toIso8601String().substring(0, 10)}',
        'status': success ? 'completed' : 'failed',
        'type': 'manual',
        'error_message': error,
        'created_by': _client.auth.currentUser?.id,
      });
    } catch (e) {
      debugPrint('⚠️ restore_service: Failed to log restore attempt: $e');
    }
  }
}
