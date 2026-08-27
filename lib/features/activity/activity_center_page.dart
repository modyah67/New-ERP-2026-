import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';

class ActivityCenterPage extends StatefulWidget {
  const ActivityCenterPage({super.key});

  @override
  State<ActivityCenterPage> createState() => _ActivityCenterPageState();
}

class _ActivityCenterPageState extends State<ActivityCenterPage> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _activities = [];
  String _activeFilter = 'all';

  static const _filters = ['all', 'audit_logs_text', 'approval_history', 'notifications'];
  static const _filterLabels = {
    'all': 'الكل',
    'audit_logs_text': 'سجل التدقيق',
    'approval_history': 'سجل الاعتماد',
    'notifications': 'الإشعارات',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final activities = <Map<String, dynamic>>[];

      if (_activeFilter == 'all' || _activeFilter == 'audit_logs_text') {
        try {
          final rows = await _client
              .from('audit_logs_text')
              .select('*, profiles(full_name)')
              .order('created_at', ascending: false)
              .limit(50);
          for (final r in rows) {
            final profiles = r['profiles'] as Map? ?? {};
            activities.add({
              'type': 'audit',
              'action': r['action'],
              'entity_type': r['table_name'],
              'entity_id': '${r['record_id']}',
              'user_name': profiles['full_name'] ?? '',
              'created_at': r['created_at'],
            });
          }
        } catch (_) {}
      }

      if (_activeFilter == 'all' || _activeFilter == 'approval_history') {
        try {
          final rows = await _client
              .from('approval_history')
              .select('*, profiles(full_name)')
              .order('created_at', ascending: false)
              .limit(50);
          for (final r in rows) {
            final profiles = r['profiles'] as Map? ?? {};
            activities.add({
              'type': 'approval',
              'action': r['action'],
              'entity_type': r['entity_type'],
              'entity_id': r['entity_id'],
              'user_name': profiles['full_name'] ?? '',
              'created_at': r['created_at'],
            });
          }
        } catch (_) {}
      }

      if (_activeFilter == 'all' || _activeFilter == 'notifications') {
        try {
          final rows = await _client
              .from('notifications')
              .select('*, profiles(full_name)')
              .order('created_at', ascending: false)
              .limit(50);
          for (final r in rows) {
            final profiles = r['profiles'] as Map? ?? {};
            activities.add({
              'type': 'notification',
              'action': r['type'],
              'entity_type': r['entity_type'] ?? '',
              'entity_id': r['entity_id'] ?? '',
              'user_name': profiles['full_name'] ?? '',
              'created_at': r['created_at'],
              'title': r['title'],
              'body': r['body'],
            });
          }
        } catch (_) {}
      }

      activities.sort((a, b) {
        final da = a['created_at']?.toString() ?? '';
        final db = b['created_at']?.toString() ?? '';
        return db.compareTo(da);
      });

      if (!mounted) return;
      setState(() {
        _activities = activities;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'INSERT': case 'submitted': return AppTheme.info;
      case 'UPDATE': return AppTheme.warning;
      case 'DELETE': return AppTheme.danger;
      case 'approved': return AppTheme.primary;
      case 'rejected': return AppTheme.danger;
      default: return AppTheme.textSecondary;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'INSERT': case 'submitted': return Icons.add_circle_outline;
      case 'UPDATE': return Icons.edit_outlined;
      case 'DELETE': return Icons.delete_outline;
      case 'approved': return Icons.check_circle_outline;
      case 'rejected': return Icons.cancel_outlined;
      default: return Icons.circle_outlined;
    }
  }

  String _actionLabel(String type, String action) {
    if (type == 'audit') {
      switch (action) {
        case 'INSERT': return 'إنشاء';
        case 'UPDATE': return 'تحديث';
        case 'DELETE': return 'حذف';
        default: return action;
      }
    }
    if (type == 'approval') {
      switch (action) {
        case 'submitted': return 'تقديم';
        case 'approved': return 'اعتماد';
        case 'rejected': return 'رفض';
        default: return action;
      }
    }
    return action;
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
              _buildFilterRow(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: _activities.map(_buildActivityCard).toList(),
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
                child: const Icon(Icons.history_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مركز النشاطات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Activity Center', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
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

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: _filters.map((f) {
          final active = _activeFilter == f;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _activeFilter = f);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? AppTheme.primary : AppTheme.glassBorder.withValues(alpha: 30),
                  ),
                ),
                child: Text(
                  _filterLabels[f] ?? f,
                  style: TextStyle(
                    color: active ? AppTheme.primary : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> a) {
    final action = (a['action'] as String?) ?? '';
    final type = (a['type'] as String?) ?? '';
    final color = _actionColor(action);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x0800E5FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 20)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_actionIcon(action), color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _actionLabel(type, action),
                            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                          if (a['entity_type'] != null && (a['entity_type'] as String).isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              'في ${a['entity_type']}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'),
                            ),
                          ],
                          if (a['entity_id'] != null && (a['entity_id'] as String).isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '#${a['entity_id']}',
                              style: const TextStyle(color: AppTheme.info, fontSize: 12, fontFamily: 'Cairo'),
                            ),
                          ],
                        ],
                      ),
                      if (a['body'] != null) Text('${a['body']}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${a['user_name'] ?? ''} • ${_formatDate(a['created_at'])}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
