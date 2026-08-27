import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../cubit/fiscal_year_cubit.dart';
import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import 'create_fiscal_year_dialog.dart';
import 'edit_fiscal_year_dialog.dart';
import 'set_current_fiscal_year_dialog.dart';
import 'reopen_fiscal_year_dialog.dart';

class FiscalYearListPage extends StatefulWidget {
  const FiscalYearListPage({super.key});

  @override
  State<FiscalYearListPage> createState() => _FiscalYearListPageState();
}

class _FiscalYearListPageState extends State<FiscalYearListPage> {
  @override
  void initState() {
    super.initState();
    context.read<FiscalYearCubit>().loadFiscalYears();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('السنة المالية'),
        backgroundColor: AppTheme.surface,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.dashboard),
          //   tooltip: 'لوحة التحكم',
          //   onPressed: () => context.push('/fiscal-year-dashboard'),
          // ),
          // IconButton(
          //   icon: const Icon(Icons.history),
          //   tooltip: 'مركز الاسترداد',
          //   onPressed: () => context.push('/fiscal-year-recovery'),
          // ),
          // IconButton(
          //   icon: const Icon(Icons.medical_services),
          //   tooltip: 'التشخيص والمراجعة',
          //   onPressed: () => context.push('/fiscal-year-diagnostics'),
          // ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('إنشاء سنة'),
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            builder: (_) => const CreateFiscalYearDialog(),
          );
          if (result == true && mounted) {
            context.read<FiscalYearCubit>().loadFiscalYears();
          }
        },
      ),
      body: BlocBuilder<FiscalYearCubit, FiscalYearState>(
        builder: (context, state) {
          if (state is FiscalYearLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is FiscalYearClosingInProgress) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(state.progress.currentStep ?? 'جاري الإغلاق...'),
                ],
              ),
            );
          }
          if (state is FiscalYearClosingFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text('فشل الإغلاق:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(state.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<FiscalYearCubit>().loadFiscalYears(),
                      child: const Text('رجوع للسنوات المالية'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is FiscalYearError) {
            return Center(child: Text(state.message));
          }
          if (state is FiscalYearReopeningInProgress) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري إعادة الفتح...'),
                ],
              ),
            );
          }
          if (state is FiscalYearReopeningFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text('فشل إعادة الفتح:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(state.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<FiscalYearCubit>().loadFiscalYears(),
                      child: const Text('رجوع للسنوات المالية'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is FiscalYearLoaded) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.fiscalYears.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final fy = state.fiscalYears[index];
                final isCurrent = fy.isCurrent;
                return ListTile(
                  title: Text('${fy.year} – ${fy.name}'),
                  subtitle: Text('من ${_formatDate(fy.startDate)} إلى ${_formatDate(fy.endDate)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusChip(fy),
                      const SizedBox(width: 8),
                      if (isCurrent)
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final updated = await showDialog<bool>(
                            context: context,
                            builder: (_) => EditFiscalYearDialog(fiscalYear: fy),
                          );
                          if (updated == true && mounted) {
                            context.read<FiscalYearCubit>().loadFiscalYears();
                          }
                        },
                      ),
                      if (!isCurrent)
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'تعيين الحالية',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => SetCurrentFiscalYearDialog(fiscalYear: fy),
                            );
                            if (confirm == true && mounted) {
                              context.read<FiscalYearCubit>().setCurrent(fy.id);
                            }
                          },
                        ),
                      if (fy.status.canTransitionToClosing)
                        IconButton(
                          icon: const Icon(Icons.lock_clock),
                          tooltip: 'إغلاق السنة',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('تأكيد الإغلاق'),
                                content: Text('هل تريد إغلاق السنة المالية ${fy.year}؟'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(_).pop(false), child: const Text('إلغاء')),
                                  TextButton(onPressed: () => Navigator.of(_).pop(true), child: const Text('نعم')),
                                ],
                              ),
                            );
                              if (confirm == true && mounted) {
                                final userId = Supabase.instance.client.auth.currentUser?.id ?? '00000000-0000-0000-0000-000000000000';
                                context.read<FiscalYearCubit>().closeFiscalYear(
                                  fiscalYearId: fy.id,
                                  userId: userId,
                                );
                              }
                          },
                        ),
                     // if (fy.status == FiscalYearStatus.closed)
                        // IconButton(
                        //   icon: const Icon(Icons.refresh),
                        //   tooltip: 'إعادة فتح',
                        //   onPressed: () async {
                        //     final reason = await showDialog<String>(
                        //       context: context,
                        //       builder: (_) => ReopenFiscalYearDialog(fiscalYear: fy),
                        //     );
                        //     if (reason != null && mounted) {
                        //       final userId = Supabase.instance.client.auth.currentUser?.id ?? '00000000-0000-0000-0000-000000000000';
                        //       context.read<FiscalYearCubit>().reopenFiscalYear(
                        //         fiscalYearId: fy.id,
                        //         userId: userId,
                        //         reason: reason,
                        //       );
                        //     }
                        //   },
                        // ),
                    ],
                  ),
                  onTap: () {},
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildStatusChip(FiscalYear fy) {
    Color color;
    String label;
    switch (fy.status) {
      case FiscalYearStatus.draft:
        color = Colors.grey;
        label = 'مسودة';
        break;
      case FiscalYearStatus.active:
        color = Colors.green;
        label = 'نشطة';
        break;
      case FiscalYearStatus.closing:
        color = Colors.orange;
        label = 'جاري الإغلاق';
        break;
      case FiscalYearStatus.closed:
        color = Colors.red;
        label = 'مغلقة';
        break;
      case FiscalYearStatus.archived:
        color = Colors.purple;
        label = 'مؤرشفة';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
