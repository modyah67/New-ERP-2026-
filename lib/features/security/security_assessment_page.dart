import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SecurityAssessmentPage extends StatelessWidget {
  const SecurityAssessmentPage({super.key});

  static const _sections = [
    _Section('مراجعة أمان النظام — Security Assessment Report', '', [
      _Item('النطاق', 'تمت مراجعة طبقات أمان النظام: قاعدة البيانات Supabase (RLS, Row Level Security)'
          '، طبقة التطبيق Flutter (المستخدمون والأدوار)، وطبقة API.'),
    ]),
    _Section('1. Row Level Security (RLS)', 'النتيجة: ❗️ جزئي — بحاجة إلى تحسين', [
      _Item('الحالة الحالية', 'جميع جداول قاعدة البيانات لديها RLS مفعّل. لكن سياسات RLS الحالية'
          ' تسمح لجميع المستخدمين المصادق عليهم (authenticated) بتنفيذ جميع العمليات (FOR ALL USING (auth.role() = \'authenticated\')).'
          ' هذا يعني أن أي مستخدم مسجل لديه صلاحية كاملة على جميع الجداول.'),
      _Item('المخاطر', 'لا يوجد فصل صلاحيات على مستوى الصف (row-level).'
          ' مستخدم عادي يمكنه نظرياً تعديل أو حذف بيانات حساسة مثل الحسابات (accounts) والمعاملات المالية (transactions).'),
      _Item('التوصية', 'تطبيق RLS قائم على الدور (role-based RLS).'
          ' على سبيل المثال، سياسة للجدول accounts:'
          '\n  • FOR SELECT USING (auth.uid() IN (SELECT user_id FROM user_roles WHERE role IN (\'admin\',\'accountant\')))'
          '\n  • FOR INSERT/UPDATE/DELETE USING (auth.uid() IN (SELECT user_id FROM user_roles WHERE role = \'admin\'))'
          '\nيجب تكرار هذا النمط لجميع الجداول المالية الحساسة.'),
    ]),
    _Section('2. إدارة الصلاحيات والأدوار', 'النتيجة: ✅ مقبول', [
      _Item('النظام الحالي', 'يوجد نظام أدوار (roles) في جدول user_roles مع صلاحيات (permissions) كجدول JSONB.'
          ' التطبيق يتحقق من الصلاحيات في طبقة Flutter قبل تنفيذ العمليات.'),
      _Item('التقييم', 'التحكم بالصلاحيات على مستوى التطبيق (application-level) يعمل بشكل سليم.'
          ' لكنه غير مدعوم بـ RLS على مستوى قاعدة البيانات، مما يخلق ثغرة أمنية محتملة إذا تم الوصول إلى Supabase مباشرة.'
          ' التوصية بتطبيق RLS مكرر (defense in depth).'),
    ]),
    _Section('3. تدقيق العمليات (Audit Logging)', 'النتيجة: ✅ جيد جداً', [
      _Item('النظام الحالي', 'يوجد جدولان للتدقيق:'
          '\n  • audit_logs — للجداول ذات المفاتيح UUID (يتم التعبئة تلقائياً عبر trigger على 5 جداول رئيسية)'
          '\n  • audit_logs_text — للجداول ذات المفاتيح INTEGER (تم إنشاؤه في التحديث 058)'
          '\nبالإضافة إلى ذلك، جدول approval_history يسجل جميع عمليات الاعتماد والرفض.'),
      _Item('التقييم', 'نظام تدقيق متكامل يغطي جميع العمليات الحيوية. يوصى بإضافة triggers إضافية'
          ' لتغطية جداول: treasuries, cheques, packing_orders.'),
    ]),
    _Section('4. العمليات الحساسة', 'النتيجة: ✅ مراقبة', [
      _Item('المالية', 'جميع المعاملات المالية (transactions, cash_receipts, cash_payments)'
          ' تسجل created_by (معرف المستخدم) و created_at (الطابع الزمني).'
          ' لا يمكن حذف المعاملات المالية دون أثر.'),
      _Item('المخزون', 'حركات المخزون مسجلة في stock_movements مع معرف المستخدم.'),
      _Item('الشحنات', 'تحديث حالة الشحنة مسجل عبر audit_logs trigger.'),
    ]),
    _Section('5. المصادقة (Authentication)', 'النتيجة: ✅ سليم', [
      _Item('النظام', 'يستخدم Supabase Auth مع إعادة توجيه تلقائي لغير المسجلين إلى /login.'
          ' جميع المستخدمين بحاجة إلى تسجيل الدخول عبر البريد الإلكتروني/كلمة المرور.'),
      _Item('التوصية', 'تفعيل المصادقة متعددة العوامل (MFA) للحسابات الإدارية.'
          ' تفعيل سياسة كلمة مرور قوية (minimum 8 characters, mixed case, numbers, symbols).'),
    ]),
    _Section('6. أمان API', 'النتيجة: ✅ سليم', [
      _Item('التقييم', 'جميع الطلبات عبر Supabase client محمية بمفتاح anon key ومحددة بسياسات RLS.'
          ' لا يتم كشف Service Role Key في التطبيق.'),
    ]),
    _Section('الخلاصة والتوصيات', '', [
      _Item('الأولويات العاجلة', '1. تطبيق RLS قائم على الأدوار (role-based RLS) لجميع الجداول المالية.'
          '\n2. تفعيل MFA للحسابات الإدارية.'
          '\n3. إضافة المزيد من audit triggers لتغطية treasuries و cheques و packing_orders.'),
      _Item('تحسينات مقترحة', '• تدقيق دوري للصلاحيات (quarterly permissions review)'
          '\n• backups مشفرة'
          '\n• تسجيل محاولات الدخول الفاشلة'
          '\n• تحديد صلاحيات API على مستوى Supabase (API settings → API settings → JWT expiry)'),
      _Item('الدرجة الإجمالية', '7.5 / 10 — النظام آمن بدرجة مقبولة مع وجود فرص للتحسين في RLS و MFA.'),
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
                  children: _sections.map(_buildSection).toList(),
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
                child: const Icon(Icons.security_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تقرير تقييم الأمان', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('Security Assessment Report', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_Section section) {
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
                      child: Text(section.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ],
                ),
                if (section.score.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: section.score.startsWith('✅') ? AppTheme.primary.withValues(alpha: 0.15)
                          : section.score.startsWith('❗️') ? AppTheme.warning.withValues(alpha: 0.15)
                          : AppTheme.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(section.score, style: TextStyle(
                      color: section.score.startsWith('✅') ? AppTheme.primary
                          : section.score.startsWith('❗️') ? AppTheme.warning
                          : AppTheme.info,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    )),
                  ),
                ],
                const SizedBox(height: 12),
                ...section.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      const SizedBox(height: 4),
                      Text(item.content, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo', height: 1.6)),
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
}

class _Section {
  final String title, score;
  final List<_Item> items;
  const _Section(this.title, this.score, this.items);
}

class _Item {
  final String label, content;
  const _Item(this.label, this.content);
}
