import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../ui/widgets/page_wrapper.dart';
import 'comprehensive_backup_cubit.dart';
import 'data_migration_template_service.dart';
import 'data_migration_import_service.dart';
import 'widgets/data_audit_dialog.dart';

class ComprehensiveBackupPage extends StatelessWidget {
  const ComprehensiveBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ComprehensiveBackupCubit(),
      child: const _ComprehensiveBackupView(),
    );
  }
}

class _ComprehensiveBackupView extends StatelessWidget {
  const _ComprehensiveBackupView();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final state = context.read<ComprehensiveBackupCubit>().state;
        if (state is ComprehensiveBackupInProgress) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('الرجاء الانتظار حتى اكتمال النسخ الاحتياطي'),
                backgroundColor: Colors.orange),
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      child: PageWrapper(
        title: 'النسخ الاحتياطي وإدارة البيانات',
        icon: Icons.backup,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 650;
            return Padding(
              padding: EdgeInsets.all(isMobile ? 0.0 : 24.0),
              child: ListView(
                children: [
                  // ── 1. Data Migration Templates Card ───────────────────
                  const _DataMigrationTemplatesCard(),
                  const SizedBox(height: 32),

                  const Divider(thickness: 1.5),
                  const SizedBox(height: 24),

              // ── 2. Full System Backup Section ──────────────────────
              const Text(
                'استخراج نسخة احتياطية شاملة من بيانات النظام',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'سيتم إنشاء مجلد في "المستندات" يحتوي على:\n'
                '• البيانات (العملاء، الموردون، المخلصين، شركات الشحن، المساهمين) - PDF + Excel\n'
                '• كشوفات الحساب (كشف حساب لكل كيان) - PDF + Excel\n'
                '• الحسابات (أرصدة الخزائن + حركات الخزائن + الحسابات البنكية) - Excel\n'
                '• الشيكات (شيت مجمع لجميع الشيكات مع تلوين الحالة) - Excel\n'
                '• الميزان التجريبي (ملخص + جدول كامل) - Excel\n'
                '• دفتر قيود اليومية (تفصيل جميع القيود وأطرافها بدقة) - Excel\n'
                '• دفتر الاستاذ (ملخص + جدول كامل بالرصيد الجاري) - Excel\n'
                '• الميزانية العامة (الأصول + الخصوم + حقوق الملكية) - Excel\n'
                '• قائمة الدخل (الإيرادات + تكلفة البضاعة + المصروفات) - Excel\n'
                '• التدفقات النقدية (تشغيلية + استثمارية + تمويلية) - Excel\n'
                '• المخازن (المواد الخام + أصناف الفاكهة + المشتريات + المحطات + التحويلات + متابعة المخازن + فواتير شراء المحاصيل + أوامر التعبئة + تقارير الفرز) - Excel + PDF\n'
                '• الفواتير و الارباح (الشحنات التصديرية) - PDF',
                style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 32),

              BlocBuilder<ComprehensiveBackupCubit, ComprehensiveBackupState>(
                builder: (context, state) {
                  if (state is ComprehensiveBackupInProgress) {
                    final progress = state.totalSteps > 0
                        ? state.step / state.totalSteps
                        : 0.0;
                    return Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            // Category badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Text(
                                state.currentCategory,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.currentTask,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 8),
                            Text('${state.step} / ${state.totalSteps}'),
                            const SizedBox(height: 16),
                            const Text(
                              'تحذير: يرجى عدم إغلاق التطبيق أو التنقل لصفحة أخرى حتى تكتمل العملية.',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (state is ComprehensiveBackupSuccess) {
                    return Card(
                      color: Colors.green.shade50,
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'اكتمل النسخ الاحتياطي بنجاح!',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'تم حفظ جميع الملفات في مجلد النسخ الاحتياطي',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                context
                                    .read<ComprehensiveBackupCubit>()
                                    .reset();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('إجراء نسخ احتياطي جديد'),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  if (state is ComprehensiveBackupError) {
                    return Card(
                      color: Colors.red.shade50,
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            const Icon(Icons.error,
                                color: Colors.red, size: 64),
                            const SizedBox(height: 16),
                            Text(
                              state.message,
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                context
                                    .read<ComprehensiveBackupCubit>()
                                    .reset();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('المحاولة مرة أخرى'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  // Initial state
                  return Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        context
                            .read<ComprehensiveBackupCubit>()
                            .startBackup();
                      },
                      icon: const Icon(Icons.backup, size: 28),
                      label: const Text('بدء النسخ الاحتياطي الشامل'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
  ),
);
  }
}

class _DataMigrationTemplatesCard extends StatefulWidget {
  const _DataMigrationTemplatesCard();

  @override
  State<_DataMigrationTemplatesCard> createState() => _DataMigrationTemplatesCardState();
}

class _DataMigrationTemplatesCardState extends State<_DataMigrationTemplatesCard> {
  bool _isExporting = false;
  String? _statusMessage;

  Future<void> _exportUnified() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري توليد وحفظ ملف قوالب Excel الموحد...';
    });

    try {
      final path = await DataMigrationTemplateService.exportUnifiedWorkbook();
      if (!mounted) return;
      final isNewCopy = path.contains('_(');
      final msg = isNewCopy
          ? 'تم تصدير ملف القوالب بنجاح كنسخة جديدة (لأن الملف السابق مفتوح حالياً في برنامج آخر):\n$path'
          : 'تم تصدير ملف القوالب الموحد بنجاح:\n$path';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'تم',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تصدير القوالب: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _exportIndividual() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري تصدير حزمة ملفات القوالب المنفصلة...';
    });

    try {
      final folderPath = await DataMigrationTemplateService.exportIndividualTemplates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تصدير قوالب الـ ${DataMigrationTemplateService.allTableSpecs.length} جداول بنجاح في المجلد:\n$folderPath',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.blueGrey.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تصدير القوالب المنفصلة: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _exportMockData() async {
    final selectedCount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.playlist_add_check, color: Colors.indigo),
            SizedBox(width: 10),
            Text('توليد ملف بيانات تجريبي (Mock Data)', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حدد حجم البيانات التجريبية المراد توليدها لكل تبويب لاختبار الأداء والواجهات (UI Overflow):',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            ListTile(
              dense: true,
              leading: const Icon(Icons.speed, color: Colors.teal),
              title: const Text('100 صف لكل تبويب (~1,400 سجل)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('الحجم القياسي السريع لاختبار الوظائف', style: TextStyle(fontSize: 11)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.teal.shade200)),
              onTap: () => Navigator.pop(ctx, 100),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.layers, color: Colors.indigo),
              title: const Text('250 صف لكل تبويب (~3,500 سجل)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('اختبار حمل متوسط واختبار الـ Scrolling', style: TextStyle(fontSize: 11)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.indigo.shade200)),
              onTap: () => Navigator.pop(ctx, 250),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.storage, color: Colors.deepOrange),
              title: const Text('500 صف لكل تبويب (~7,000 سجل)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('اختبار تدفق بيانات ضخم وأقصى حمل لقاعدة البيانات', style: TextStyle(fontSize: 11)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.deepOrange.shade200)),
              onTap: () => Navigator.pop(ctx, 500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (selectedCount == null) return;

    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري توليد وحفظ ملف البيانات التجريبية ($selectedCount صف/تبويب)...';
    });

    try {
      final path = await DataMigrationTemplateService.exportMockDataWorkbook(rowCountPerSheet: selectedCount);
      if (!mounted) return;
      final isNewCopy = path.contains('_(');
      final msg = isNewCopy
          ? 'تم تصدير ملف البيانات التجريبية ($selectedCount صف/تبويب) كنسخة جديدة (لأن الملف السابق مفتوح حالياً):\n$path'
          : 'تم تصدير ملف البيانات التجريبية ($selectedCount صف/تبويب) بنجاح:\n$path';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.indigo.shade800,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'تم',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تصدير ملف البيانات التجريبية: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _importExcelFile() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'جاري فتح نافذة اختيار ملف Excel (.xlsx)...';
    });

    try {
      final summary = await DataMigrationImportService.pickAndImportFile(
        onProgress: ({
          required String currentSheet,
          required int sheetIndex,
          required int totalSheets,
          required int currentRecord,
          required int totalRecordsInSheet,
          required String statusMessage,
        }) {
          if (mounted) {
            setState(() {
              _statusMessage = '[$sheetIndex/$totalSheets] $statusMessage';
            });
          }
        },
      );

      if (!mounted) return;

      if (summary == null) {
        // User cancelled selection
        return;
      }

      // Show summary dialog
      _showImportSummaryDialog(summary);

      // Show toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            summary.isSuccess
                ? 'تم استيراد ورفع ${summary.totalRecords} سجلاً بنجاح من ${summary.totalSheetsProcessed} تبويباً.'
                : 'تمت عملية الاستيراد مع وجود ${summary.totalFailed} أخطاء. راجع تفاصيل التقرير.',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: summary.isSuccess ? Colors.teal.shade800 : Colors.amber.shade900,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل استيراد ورفع البيانات: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _showImportSummaryDialog(MigrationImportSummary summary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              summary.isSuccess ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              color: summary.isSuccess ? Colors.teal : Colors.amber.shade800,
              size: 26,
            ),
            const SizedBox(width: 10),
            Text(
              summary.isSuccess ? 'تقرير اكتمال رفع وترحيل البيانات' : 'تقرير نتائج استيراد البيانات',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Stat Cards
              Row(
                children: [
                  _buildStatCard('إجمالي التبويبات', '${summary.totalSheetsProcessed}', Colors.blueGrey),
                  const SizedBox(width: 8),
                  _buildStatCard('تمت إضافتها (جديد)', '${summary.totalInserted}', Colors.green),
                  const SizedBox(width: 8),
                  _buildStatCard('تم تحديثها', '${summary.totalUpdated}', Colors.blue),
                  const SizedBox(width: 8),
                  _buildStatCard('فشل / أخطاء', '${summary.totalFailed}', summary.totalFailed > 0 ? Colors.red : Colors.grey),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'الملف: ${summary.fileName} • استغرقت العملية: ${(summary.duration.inMilliseconds / 1000).toStringAsFixed(1)} ثانية',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const Divider(height: 18),
              Expanded(
                child: ListView(
                  children: summary.sheetResults.values.map((sheetRes) {
                    final hasErrors = sheetRes.hasErrors;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: hasErrors ? Colors.red.shade200 : Colors.grey.shade200),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          hasErrors ? Icons.error_outline : Icons.check_circle,
                          color: hasErrors ? Colors.red : Colors.teal,
                          size: 22,
                        ),
                        title: Text(
                          sheetRes.sheetName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          'جدول: ${sheetRes.tableName} | جديد: ${sheetRes.insertedCount} • تحديث: ${sheetRes.updatedCount} • أخطاء: ${sheetRes.failedCount}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        children: [
                          if (sheetRes.errorMessages.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: sheetRes.errorMessages
                                    .map((e) => Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Text('• $e', style: const TextStyle(color: Colors.red, fontSize: 11)),
                                        ))
                                    .toList(),
                              ),
                            )
                          ] else ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('تمت معالجة كافة صفوف هذا التبويب بنجاح ودون أخطاء.', style: TextStyle(fontSize: 12, color: Colors.green)),
                            )
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade800), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showSpecsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.table_chart_outlined, color: Colors.teal),
            SizedBox(width: 10),
            Text('تفاصيل أعمدة القوالب ومطابقة Supabase', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 750,
          height: 480,
          child: ListView.builder(
            itemCount: DataMigrationTemplateService.allTableSpecs.length,
            itemBuilder: (ctx, i) {
              final spec = DataMigrationTemplateService.allTableSpecs[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade50,
                    child: Text('${i + 1}', style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(
                    '${spec.arabicTitle} (${spec.tableId})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'التبويب: ${spec.sheetName} • ${spec.columns.length} عموداً برمجياً',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spec.description,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                          ),
                          const Divider(height: 16),
                          ...spec.columns.map((c) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    SelectableText(
                                      c.columnName,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (c.isRequired)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('إلزامي', style: TextStyle(color: Colors.red, fontSize: 9)),
                                      ),
                                    const SizedBox(width: 8),
                                    Text('(${c.arabicLabel})', style: const TextStyle(fontSize: 12)),
                                    if (c.allowedValuesHint != null) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '← ${c.allowedValuesHint!}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 650;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.teal.shade200, width: 1.2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.teal.shade50.withValues(alpha: 0.5), Colors.white],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.table_chart_outlined, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'قوالب إدخال البيانات الافتتاحية (Data Migration Templates)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'تصدير قوالب Excel فارغة (صف العناوين فقط) بأسماء برمجية مطابقة تماماً لجداول Supabase لملء الأرصدة والبيانات الأساسية.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Chips for covered tables
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTableChip('العملاء - تصديري', Icons.flight_takeoff),
                _buildTableChip('العملاء - محلي', Icons.storefront),
                _buildTableChip('موردين المحاصيل', Icons.eco),
                _buildTableChip('موردين مواد التعبئة', Icons.inventory_2),
                _buildTableChip('الموردين المشتركين', Icons.handshake),
                _buildTableChip('موردي المحطات', Icons.precision_manufacturing),
                _buildTableChip('موردي النقل', Icons.local_shipping),
                _buildTableChip('موردي التخصيمات', Icons.receipt_long),
                _buildTableChip('المخلص البحري', Icons.directions_boat),
                _buildTableChip('المخلص الجوي', Icons.airplanemode_active),
                _buildTableChip('شركات الشحن', Icons.anchor),
                _buildTableChip('المحطات', Icons.domain),
                _buildTableChip('فئات مواد التعبئة', Icons.category),
                _buildTableChip('مواد التعبئة والمستلزمات', Icons.inventory_2),
              ],
            ),
            const SizedBox(height: 20),

            if (_isExporting) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(color: Colors.teal),
                    const SizedBox(height: 10),
                    Text(
                      _statusMessage ?? 'جاري التصدير...',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => DataAuditDialog.show(context),
                    icon: const Icon(Icons.fact_check_rounded, size: 20),
                    label: const Text(
                      'التحقق من صحة واكتمال البيانات (Data Audit Report)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A), // Deep Royal Navy
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 22, vertical: isMobile ? 10 : 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _importExcelFile,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                    label: const Text(
                      'استيراد ورفع ملف Excel (Data Migration)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E), // Dark Teal
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 22, vertical: isMobile ? 10 : 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _exportUnified,
                    icon: const Icon(Icons.download, size: 20),
                    label: Text(
                      'تصدير ملف Excel الموحد (${DataMigrationTemplateService.allTableSpecs.length} تبويباً)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade800,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _exportMockData,
                    icon: const Icon(Icons.playlist_add_check, size: 20),
                    label: const Text(
                      'تصدير ملف تجريبي بالبيانات (Mock Data)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade800,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: isMobile ? 10 : 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportIndividual,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text(
                      'تصدير كحزمة ملفات منفصلة (مجلد)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal.shade900,
                      side: BorderSide(color: Colors.teal.shade700),
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: isMobile ? 10 : 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showSpecsDialog,
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('عرض تفاصيل الأعمدة والشروط'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.indigo.shade800,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.teal.shade800),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade900),
          ),
        ],
      ),
    );
  }
}
