import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _client = Supabase.instance.client;
  Timer? _pollTimer;

  String? get _userId => _client.auth.currentUser?.id;

  /// Create a notification.
  Future<void> createNotification({
    required String type,
    required String title,
    required String body,
    String? entityType,
    String? entityId,
    String severity = 'info',
    String? userId,
  }) async {
    try {
      await _client.from('notifications').insert({
        'type': type,
        'title': title,
        'body': body,
        'entity_type': entityType,
        'entity_id': entityId,
        'severity': severity,
        'user_id': userId ?? _userId,
      });
    } catch (e, st) {
      debugPrint('NotificationService.create error: $e\n$st');
    }
  }

  /// Get notifications for current user.
  Future<List<Map<String, dynamic>>> getNotifications({
    bool? unreadOnly,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('notifications')
          .select()
          .eq('user_id', _userId ?? '');
      if (unreadOnly == true) {
        query = query.eq('is_read', false);
      }
      final data = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Get unread count.
  Future<int> getUnreadCount() async {
    try {
      final resp = await _client
          .from('notifications')
          .select()
          .eq('user_id', _userId ?? '')
          .eq('is_read', false)
          .count(CountOption.exact);
      return resp.count;
    } catch (_) {
      return 0;
    }
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(int notificationId) async {
    try {
      await _client.from('notifications').update({'is_read': true}).eq('id', notificationId);
    } catch (_) {}
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _userId ?? '')
          .eq('is_read', false);
    } catch (_) {}
  }

  /// Delete a notification.
  Future<void> deleteNotification(int notificationId) async {
    try {
      await _client.from('notifications').delete().eq('id', notificationId);
    } catch (_) {}
  }

  /// Start polling for new notifications every N seconds.
  void startPolling(void Function(int unreadCount) onUpdate, {int intervalSec = 60}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: intervalSec), (_) async {
      final count = await getUnreadCount();
      onUpdate(count);
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
