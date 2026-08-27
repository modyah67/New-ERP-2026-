import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/dao/cheque_dao.dart';
import '../data/dao/settings_dao.dart';

class ChequeNotificationService {
  final ChequeDao _chequeDao = ChequeDao();
  final SettingsDao _settingsDao = SettingsDao();
  Timer? _timer;
  List<Map<String, dynamic>> _lastNotifications = [];

  void _log(String msg) => debugPrint('🔔 ChequeNotification: $msg');

  int _checkIntervalMinutes = 30;

  /// Start periodic polling.
  /// Returns the count of due-soon cheques on first check (for badge).
  Future<int> start({VoidCallback? onNotification}) async {
    final days = await _getNotificationDays();
    _log('Starting notification service (days_ahead=$days, interval=${_checkIntervalMinutes}m)');
    final count = await _check(days, onNotification: onNotification);

    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _checkIntervalMinutes), (_) async {
      await _check(days, onNotification: onNotification);
    });

    return count;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setCheckInterval(int minutes) {
    _checkIntervalMinutes = minutes;
    _log('Check interval updated to $minutes minutes');
  }

  Future<int> _check(int days, {VoidCallback? onNotification}) async {
    try {
      final cheques = await _chequeDao.getPendingForNotification(days);

      if (cheques.isNotEmpty) {
        final newIds = cheques.map((c) => c['id'].toString()).toSet();
        final oldIds = _lastNotifications.map((c) => c['id'].toString()).toSet();

        if (newIds.difference(oldIds).isNotEmpty) {
          _lastNotifications = cheques;
          _log('${cheques.length} cheque(s) due within $days day(s)');
          onNotification?.call();
        }
      }

      return cheques.length;
    } catch (e) {
      _log('Check error: $e');
      return 0;
    }
  }

  Future<int> _getNotificationDays() async {
    try {
      final val = await _settingsDao.getSetting('cheque_notification_days');
      return int.tryParse(val ?? '') ?? 3;
    } catch (_) {
      return 3;
    }
  }

  /// Get the current notification setting.
  Future<int> getNotificationDays() => _getNotificationDays();

  /// Update the notification setting.
  Future<void> setNotificationDays(int days) async {
    await _settingsDao.saveSetting('cheque_notification_days', days.toString());
    _log('Notification days updated to $days');
  }

  /// Get cached notification data for display.
  List<Map<String, dynamic>> get pendingNotifications => _lastNotifications;

  void clearNotifications() {
    _lastNotifications = [];
  }

  void dispose() {
    stop();
  }
}
