import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';
import '../../core/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final c = context.read<SettingsCubit>();

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.settings_outlined,
                          color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Text('الإعدادات العامة', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                  ],
                ),
                const SizedBox(height: 30),

                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: AppTheme.glassCard(),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('تصدير البيانات (Excel)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo')),
                            const SizedBox(height: 8),
                            Text('تصدير جميع بيانات النظام إلى ملف Excel - كل قسم في ورقة منفصلة', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                            const Divider(height: 32),
                            BlocBuilder<SettingsCubit, SettingsState>(
                              builder: (context, state) {
                                final isExporting = state is ExportProgressState;
                                final progress = isExporting ? state.current / state.total : 0.0;
                                final section = isExporting ? state.section : '';
                                final current = isExporting ? state.current : 0;
                                final total = isExporting ? state.total : 0;

                                return Column(
                                  children: [
                                    if (isExporting) ...[
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'جاري تصدير $section ($current/$total)',
                                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            '${(progress * 100).toStringAsFixed(0)}%',
                                            style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 8,
                                          backgroundColor: Colors.white10,
                                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton.icon(
                                        onPressed: isExporting ? null : () => c.exportAllToExcel(context),
                                        icon: Icon(
                                          isExporting ? Icons.hourglass_top : Icons.file_download_outlined,
                                          size: 22,
                                        ),
                                        label: Text(
                                          isExporting ? 'جاري التصدير...' : 'تصدير جميع البيانات',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primary,
                                          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
