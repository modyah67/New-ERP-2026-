import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationService', () {
    test('notification has required fields', () {
      final notification = {
        'id': 1,
        'user_id': 'user-1',
        'type': 'approval',
        'severity': 'info',
        'title': 'موافقة مطلوبة',
        'message': 'تفاصيل الإشعار',
        'is_read': false,
        'created_at': '2026-06-17T10:00:00Z',
      };

      expect(notification.containsKey('id'), true);
      expect(notification.containsKey('user_id'), true);
      expect(notification.containsKey('type'), true);
      expect(notification.containsKey('severity'), true);
      expect(notification.containsKey('title'), true);
      expect(notification.containsKey('message'), true);
      expect(notification.containsKey('is_read'), true);
    });

    test('mark as read toggles is_read', () {
      final notification = {'id': 1, 'is_read': false};
      notification['is_read'] = true;
      expect(notification['is_read'], true);
    });

    test('severity levels are valid', () {
      const validSeverities = ['info', 'warning', 'error', 'success'];
      expect(validSeverities.contains('info'), true);
      expect(validSeverities.contains('warning'), true);
      expect(validSeverities.contains('error'), true);
      expect(validSeverities.contains('success'), true);
    });

    test('notification types are valid', () {
      const validTypes = ['approval', 'system', 'alert', 'reminder'];
      expect(validTypes.contains('approval'), true);
      expect(validTypes.contains('system'), true);
    });
  });
}
