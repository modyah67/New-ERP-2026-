import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../ui/widgets/page_wrapper.dart';
import 'comprehensive_backup_cubit.dart';

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
    return WillPopScope(
      onWillPop: () async {
        final state = context.read<ComprehensiveBackupCubit>().state;
        if (state is ComprehensiveBackupInProgress) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('الرجاء الانتظار حتى اكتمال النسخ الاحتياطي'),
                backgroundColor: Colors.orange),
          );
          return false;
        }
        return true;
      },
      child: PageWrapper(
        title: 'النسخ الاحتياطي الشامل',
        icon: Icons.backup,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              const Text(
                'استخراج نسخة احتياطية من بيانات النظام.',
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
        ),
      ),
    );
  }
}
