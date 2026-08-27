import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApprovalService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Supported entity types
  static const entities = {
    'purchase_invoice': 'purchase_invoices',
    'export_shipment': 'export_shipments',
    'treasury': 'treasuries',
  };

  /// Submit an entity for approval (draft → pending).
  Future<bool> submit({
    required String entityType,
    required dynamic entityId,
    String? comment,
  }) async {
    try {
      final table = entities[entityType];
      if (table == null) return false;

      await _client.from(table).update({'approval_status': 'pending'}).eq('id', entityId);
      await _logHistory(entityType, '$entityId', 'submitted', 'draft', 'pending', comment);
      await _createNotification(
        type: 'approval_request',
        title: 'طلب اعتماد',
        body: 'طلب اعتماد جديد في $entityType #$entityId',
        entityType: entityType,
        entityId: '$entityId',
        severity: 'warning',
      );
      return true;
    } catch (e, st) {
      debugPrint('ApprovalService.submit error: $e\n$st');
      return false;
    }
  }

  /// Approve a pending entity (pending → approved).
  Future<bool> approve({
    required String entityType,
    required dynamic entityId,
    String? comment,
  }) async {
    try {
      final table = entities[entityType];
      if (table == null) return false;

      await _client.from(table).update({'approval_status': 'approved'}).eq('id', entityId);
      await _logHistory(entityType, '$entityId', 'approved', 'pending', 'approved', comment);
      return true;
    } catch (e, st) {
      debugPrint('ApprovalService.approve error: $e\n$st');
      return false;
    }
  }

  /// Reject a pending entity (pending → rejected).
  Future<bool> reject({
    required String entityType,
    required dynamic entityId,
    String? comment,
  }) async {
    try {
      final table = entities[entityType];
      if (table == null) return false;

      await _client.from(table).update({'approval_status': 'rejected'}).eq('id', entityId);
      await _logHistory(entityType, '$entityId', 'rejected', 'pending', 'rejected', comment);
      return true;
    } catch (e, st) {
      debugPrint('ApprovalService.reject error: $e\n$st');
      return false;
    }
  }

  /// Get approval history for an entity.
  Future<List<Map<String, dynamic>>> getHistory({
    required String entityType,
    required dynamic entityId,
  }) async {
    try {
      final data = await _client
          .from('approval_history')
          .select('*, profiles(full_name)')
          .eq('entity_type', entityType)
          .eq('entity_id', '$entityId')
          .order('created_at', ascending: false);
      return (data as List).map((row) {
        final r = row as Map<String, dynamic>;
        final profiles = r['profiles'] as Map? ?? {};
        r['user_name'] = profiles['full_name'] ?? '';
        return r;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get all pending entities across all supported types.
  Future<List<Map<String, dynamic>>> getPendingApprovals() async {
    final results = <Map<String, dynamic>>[];
    for (final entry in entities.entries) {
      try {
        final data = await _client
            .from(entry.value)
            .select('id, approval_status')
            .eq('approval_status', 'pending');
        for (final row in data) {
          results.add({
            'entity_type': entry.key,
            'entity_id': '${row['id']}',
            'approval_status': row['approval_status'],
          });
        }
      } catch (_) {}
    }
    return results;
  }

  Future<void> _logHistory(
    String entityType,
    String entityId,
    String action,
    String? fromStatus,
    String toStatus,
    String? comment,
  ) async {
    await _client.from('approval_history').insert({
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action,
      'from_status': fromStatus,
      'to_status': toStatus,
      'comment': comment,
      'user_id': _userId,
    });
  }

  Future<void> _createNotification({
    required String type,
    required String title,
    required String body,
    required String entityType,
    required String entityId,
    required String severity,
  }) async {
    // Notify all admin users
    try {
      final admins = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'admin');
      for (final a in admins) {
        await _client.from('notifications').insert({
          'type': type,
          'title': title,
          'body': body,
          'entity_type': entityType,
          'entity_id': entityId,
          'severity': severity,
          'user_id': a['user_id'],
        });
      }
    } catch (_) {}
  }
}
