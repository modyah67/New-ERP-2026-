import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/services/notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationService();
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final notifications = await _service.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return AppTheme.danger;
      case 'warning': return AppTheme.warning;
      default: return AppTheme.info;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'approval_request': return Icons.approval_outlined;
      case 'low_inventory': return Icons.inventory_outlined;
      case 'shipment_ready': return Icons.local_shipping_outlined;
      case 'cheque_due': return Icons.receipt_outlined;
      case 'overdue_customer': return Icons.person_off_outlined;
      case 'negative_treasury': return Icons.account_balance_wallet_outlined;
      case 'exchange_rate': return Icons.currency_exchange_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  String _formatDate(dynamic d) {
    if (d == null) return '';
    final s = d.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', ' ');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
            ),
          ),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: [
                          if (_notifications.any((n) => n['is_read'] != true))
                            _buildMarkAllRead(),
                          const SizedBox(height: 8),
                          ..._notifications.map(_buildNotificationCard),
                          if (_notifications.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 60),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.notifications_off_outlined, color: AppTheme.textSecondary, size: 48),
                                    SizedBox(height: 12),
                                    Text('لا توجد إشعارات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 16)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 50))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مركز الإشعارات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Notification Center', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarkAllRead() {
    return GestureDetector(
      onTap: () async {
        await _service.markAllAsRead();
        await _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.15)),
        ),
        child: const Row(
          children: [
            Icon(Icons.done_all_outlined, color: AppTheme.info, size: 16),
            SizedBox(width: 8),
            Text('تحديد الكل كمقروء', style: TextStyle(color: AppTheme.info, fontSize: 13, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final severity = (n['severity'] as String?) ?? 'info';
    final isRead = n['is_read'] == true;
    final color = _severityColor(severity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: isRead ? const Color(0x0800E5FF) : color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRead ? AppTheme.glassBorder.withValues(alpha: 20) : color.withValues(alpha: 0.2),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                if (!isRead) {
                  await _service.markAsRead(n['id'] as int);
                  await _load();
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_typeIcon(n['type'] ?? ''), color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${n['title'] ?? ''}',
                                  style: TextStyle(
                                    color: isRead ? AppTheme.textSecondary : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${n['body'] ?? ''}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                          const SizedBox(height: 6),
                          Text(_formatDate(n['created_at']), style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
