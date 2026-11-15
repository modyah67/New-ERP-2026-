import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/restore_service.dart';
import 'data_migration_template_service.dart';

class BackupHistoryPage extends StatefulWidget {
  const BackupHistoryPage({super.key});

  @override
  State<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends State<BackupHistoryPage> {
  final _backupService = BackupService();
  final _restoreService = RestoreService();
  bool _loading = true;
  bool _running = false;
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> _validation = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _backupService.getHistory(),
        _restoreService.validateRestore(),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as List<Map<String, dynamic>>;
        _validation = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _running = true);
    final ok = await _backupService.createBackup();
    if (!mounted) return;
    if (ok) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.primary),
        );
      }
    }
    setState(() => _running = false);
  }

  Future<void> _validateAndRestore() async {
    final valid = _validation['accounts_ok'] == true &&
        _validation['products_ok'] == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(valid ? 'البيانات سليمة — يمكن الاستعادة' : 'تحذير: بعض الجداول الأساسية مفقودة', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: valid ? AppTheme.primary : AppTheme.danger,
      ),
    );
  }

  Future<void> _exportTemplates() async {
    try {
      final path = await DataMigrationTemplateService.exportUnifiedWorkbook();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تصدير قوالب Excel الموحدة بنجاح:\n$path', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء تصدير القوالب: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
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
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        children: [
                          _buildActionsCard(),
                          const SizedBox(height: 16),
                          _buildValidationCard(),
                          const SizedBox(height: 16),
                          _buildHistorySection(),
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
                child: const Icon(Icons.backup_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('النسخ الاحتياطي والاستعادة', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Backup & Restore', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
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

  Widget _glassContainer(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 30)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return _glassContainer(
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _running ? null : _createBackup,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.backup_outlined, size: 18),
              label: const Text('إنشاء نسخة احتياطية', style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _validateAndRestore,
              icon: const Icon(Icons.restore_outlined, size: 18),
              label: const Text('التحقق والاستعادة', style: TextStyle(fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.warning,
                side: const BorderSide(color: AppTheme.warning),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exportTemplates,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('قوالب Excel فارغة', style: TextStyle(fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationCard() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_outlined, color: AppTheme.info, size: 18),
              SizedBox(width: 8),
              Text('التحقق من سلامة البيانات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 12),
          _validRow('حسابات', _validation['accounts_ok'] == true),
          _validRow('منتجات', _validation['products_ok'] == true),
          _validRow('شحنات تصدير', _validation['export_shipments_ok'] == true),
        ],
      ),
    );
  }

  Widget _validRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? AppTheme.primary : AppTheme.danger, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('سجل النسخ الاحتياطي', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          const SizedBox(height: 12),
          ..._history.map((h) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: (h['status'] == 'completed'
                        ? AppTheme.primary
                        : h['status'] == 'failed'
                            ? AppTheme.danger
                            : AppTheme.warning
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    h['status'] == 'completed' ? Icons.check_circle_outlined
                        : h['status'] == 'failed' ? Icons.error_outlined
                        : Icons.hourglass_top_outlined,
                    color: h['status'] == 'completed' ? AppTheme.primary
                        : h['status'] == 'failed' ? AppTheme.danger
                        : AppTheme.warning,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${h['file_name'] ?? '—'}', style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo')),
                      Text('${h['created_by_name'] ?? ''} • ${_formatDate(h['created_at'])}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (h['type'] == 'scheduled' ? AppTheme.info : AppTheme.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(h['type'] == 'scheduled' ? 'مجدول' : 'يدوي', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo')),
                ),
              ],
            ),
          )),
          if (_history.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('لا توجد نسخ احتياطية بعد', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic d) {
    if (d == null) return '';
    final s = d.toString();
    if (s.length >= 16) return s.substring(0, 16).replaceAll('T', ' ');
    return s;
  }
}
