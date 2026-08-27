import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class ActivityTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> activities;

  const ActivityTimeline({super.key, required this.activities});

  IconData _iconForType(String type) {
    switch (type) {
      case 'shipment': return Icons.local_shipping;
      case 'customer': return Icons.person_add;
      case 'invoice': return Icons.receipt;
      default: return Icons.circle;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'shipment': return AppTheme.primary;
      case 'customer': return AppTheme.success;
      case 'invoice': return AppTheme.warning;
      default: return AppTheme.textMuted;
    }
  }

  String _timeAgo(String? timeStr) {
    if (timeStr == null) return '';
    final dt = DateTime.tryParse(timeStr);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} ي';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timeline, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            const Text(
              'آخر الأنشطة',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: activities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hourglass_empty, color: AppTheme.textMuted, size: 32),
                      const SizedBox(height: 8),
                      Text('لا توجد أنشطة حديثة',
                          style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: activities.length,
                  itemBuilder: (_, i) {
                    final a = activities[i];
                    final type = a['type'] as String? ?? '';
                    final color = _colorForType(type);
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Column(
                              children: [
                                Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(20),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color.withAlpha(60), width: 1.5),
                                  ),
                                  child: Icon(_iconForType(type), size: 12, color: color),
                                ),
                                if (i < activities.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: 1,
                                      color: Colors.white.withAlpha(10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['title']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _timeAgo(a['time'] as String?),
                                    style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 10,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
