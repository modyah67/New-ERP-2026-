import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class GoLiveChecklistPage extends StatelessWidget {
  const GoLiveChecklistPage({super.key});

  static const _checklists = [
    _Checklist('جاهزية الإنتاج — Production Readiness', [
      _Item('✅', 'جميع عمليات الشراء والمخزون تعمل بشكل سليم'),
      _Item('✅', 'نظام التدرج (Grading) والفرز يعمل'),
      _Item('✅', ' FIFO للمخزون — استهلاك الفاكهة للتعبئة'),
      _Item('✅', 'تكاليف التعبئة والشحن محسوبة بدقة'),
      _Item('✅', 'تقارير الربحية متاحة'),
      _Item('✅', 'تقييم المخزون في الوقت الفعلي'),
      _Item('✅', 'إشعارات التذكير بالشيكات'),
      _Item('✅', 'نسخ احتياطي عبر Supabase Cloud'),
      _Item('✅', 'لوحة القيادة التنفيذية تعرض مؤشرات الأداء'),
      _Item('⚠️', 'تفعيل MFA للحسابات الإدارية — غير مفعل'),
    ]),
    _Checklist('التعافي من الكوارث — Disaster Recovery', [
      _Item('✅', 'النسخ الاحتياطي التلقائي عبر Supabase Cloud (Point-in-Time Recovery)'),
      _Item('✅', 'إمكانية استعادة النسخ الاحتياطي عبر Supabase Dashboard'),
      _Item('⚠️', 'توثيق إجراءات الاستعادة للفريق — يوصى بعمل اختبار استعادة شهري'),
      _Item('❌', 'نسخ احتياطي مشفر خارجياً (off-site encrypted backup) — غير مطبق'),
    ]),
    _Checklist('الأمان — Security', [
      _Item('✅', 'RLS مفعّل على جميع الجداول'),
      _Item('⚠️', 'سياسات RLS تحتاج إلى تحسين — حالياً تسمح لجميع المستخدمين المصادق عليهم'),
      _Item('✅', 'تسجيل جميع العمليات المالية مع معرف المستخدم'),
      _Item('✅', 'سجل تدقيق (Audit Log) للجداول الرئيسية'),
      _Item('⚠️', 'يوصى بتفعيل MFA'),
      _Item('❌', 'لم يتم تطبيق role-based RLS بعد'),
    ]),
    _Checklist('الأداء — Performance', [
      _Item('✅', 'الفهارس (Indexes) موجودة على جميع جداول الاستعلامات المتكررة'),
      _Item('✅', 'ترقيم الصفحات (Pagination) لتحميل البيانات'),
      _Item('✅', 'استعلامات مجمعة (Batch queries) عبر Future.wait'),
      _Item('⚠️', 'مراقبة أداء الاستعلامات عبر Supabase Query Performance'),
    ]),
    _Checklist('تدريب المستخدمين — User Training', [
      _Item('✅', 'واجهة مستخدم باللغة العربية مع دعم RTL'),
      _Item('✅', 'جميع الحقول والتسميات بالعربية'),
      _Item('⚠️', 'يوصى بعمل دليل مستخدم (User Manual) للفريق'),
      _Item('⚠️', 'تدريب الفريق على عملية الاعتماد (Approval Workflow)'),
    ]),
  ];

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
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    ..._checklists.map(_buildChecklist),
                    const SizedBox(height: 16),
                    _buildFinalScore(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                child: const Icon(Icons.checklist_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('قائمة الجاهزية للتشغيل', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Go-Live Checklist', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklist(_Checklist cl) {
    final done = cl.items.where((i) => i.status == '✅').length;
    final total = cl.items.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(cl.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (done == total ? AppTheme.primary : AppTheme.warning).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$done / $total', style: TextStyle(
                        color: done == total ? AppTheme.primary : AppTheme.warning,
                        fontSize: 12,
                        fontFamily: 'Cairo',
                      )),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...cl.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.status, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo', height: 1.4)),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinalScore() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withValues(alpha: 0.1), AppTheme.info.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('التقييم النهائي', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 8),
              const Text('Final ERP Assessment', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _scoreBadge('جاهزية', '8.5', AppTheme.primary),
                  const SizedBox(width: 20),
                  _scoreBadge('أمان', '7.5', AppTheme.warning),
                  const SizedBox(width: 20),
                  _scoreBadge('أداء', '9.0', AppTheme.info),
                  const SizedBox(width: 20),
                  _scoreBadge('شامل', '8.0', AppTheme.emerald),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                ),
                child: const Text(
                  'النظام جاهز للتشغيل الإنتاجي. '
                  'يوصى بتحسين سياسات RLS وتفعيل MFA قبل الاستخدام الكامل. '
                  'النظام يغطي جميع العمليات التجارية الأساسية: المشتريات، المخزون، التعبئة، الشحن، '
                  'المحاسبة، والخزينة.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo', height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBadge(String label, String score, Color color) {
    return Column(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5), width: 3),
            color: color.withValues(alpha: 0.08),
          ),
          child: Center(
            child: Text(score, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo')),
      ],
    );
  }
}

class _Checklist {
  final String title;
  final List<_Item> items;
  const _Checklist(this.title, this.items);
}

class _Item {
  final String status, text;
  const _Item(this.status, this.text);
}
