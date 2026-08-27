import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import 'user_management_cubit.dart';

class PermissionsDialog extends StatefulWidget {
  final String userId;
  final Map<String, dynamic>? currentRole;

  const PermissionsDialog({
    super.key,
    required this.userId,
    this.currentRole,
  });

  @override
  State<PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<PermissionsDialog> {
  bool _hasOwnerSafe = false;
  List<String> _allowedPages = [];

  final List<Map<String, String>> _appPages = [
    {'path': '/home', 'label': 'الرئيسية'},
    {'path': '/raw-materials', 'label': 'مواد التعبئة'},
    {'path': '/fruit-types', 'label': 'أصناف الفاكهة'},
    {'path': '/purchases', 'label': 'المشتريات'},
    {'path': '/suppliers', 'label': 'الموردون'},
    {'path': '/customers', 'label': 'العملاء'},
    {'path': '/clearing-agents', 'label': 'المخلصين'},
    {'path': '/shipping-companies', 'label': 'شركات الشحن'},
    {'path': '/shareholders', 'label': 'المساهمين'},
    {'path': '/export-customer-statement', 'label': 'كشف حساب العميل'},
    {'path': '/supplier-statement-page', 'label': 'كشف حساب الموردين'},
    {'path': '/clearing-agent-statement', 'label': 'كشف حساب المخلص'},
    {'path': '/shipping-company-statement', 'label': 'كشف حساب شركات الشحن'},
    {'path': '/shareholder-statement', 'label': 'كشف حساب المساهم'},
    {'path': '/stations', 'label': 'المخازن الفرعية'},
    {'path': '/warehouse-tracking', 'label': 'متابعة المخازن'},
    {'path': '/transfers', 'label': 'تحويل بين المخازن'},
    {'path': '/chart-of-accounts', 'label': 'شجرة الحسابات'},
    {'path': '/accounts', 'label': 'الخزينة الرئيسية'},
    {'path': '/bank-accounts', 'label': 'الحسابات البنكية'},
    {'path': '/cheques', 'label': 'الشيكات'},
    {'path': '/trial-balance', 'label': 'الميزان التجريبي'},
    {'path': '/general-ledger', 'label': 'دفتر الأستاذ'},
    {'path': '/journal-entry', 'label': 'قيود اليومية'},
    {'path': '/balance-sheet', 'label': 'الميزانية العامة'},
     {'path': '/income-statement', 'label': 'قائمة الدخل'},
    {'path': '/cash-flow', 'label': 'التدفقات النقدية'},
    {'path': '/fiscal-year-closing', 'label': 'السنوات المالية'},
    {'path': '/lots', 'label': 'شراء المحاصيل'},
    {'path': '/lots/returns', 'label': 'مرتجع المحاصيل'},
    {'path': '/sorting', 'label': 'الفرز'},
    {'path': '/packing', 'label': 'التعبئة'},
    {'path': '/exports', 'label': 'الشحنات التصديرية'},
    {'path': '/proforma-invoices', 'label': 'فواتير مبدئية'},
    {'path': '/exports/profit', 'label': 'الربحية'},
    {'path': '/exports/costing-readonly', 'label': 'الربحية (اضافة تكلفة الشحنات فقط)'},
    {'path': '/exports/cost-summary', 'label': 'تقارير التكاليف'},
    {'path': '/exports/cost-categories', 'label': 'إدارة تصنيفات التكاليف'},
    {'path': '/exports/profit-distribution', 'label': 'توزيع الأرباح'},
    {'path': '/user-management', 'label': 'إدارة المستخدمين'},
    {'path': '/backup', 'label': 'النسخ الاحتياطي'},
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.currentRole;

    final rawPages = r?['allowed_pages'];
    if (rawPages is List) {
      _allowedPages = rawPages.map((e) => e.toString()).toList();
      _hasOwnerSafe = _allowedPages.contains('/owner-safe');
      _allowedPages.remove('/owner-safe');
    } else {
      _allowedPages = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 48).clamp(280.0, 420.0);
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      title: const Text('الصلاحيات (الصفحات المسموحة)',
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.glassBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CheckboxListTile(
                  title: const Text('خزينة المالك',
                      style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 14)),
                  subtitle: const Text('التعامل المباشر مع الخزينة الرئيسية',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: 12)),
                  value: _hasOwnerSafe,
                  activeColor: AppTheme.primary,
                  checkColor: Colors.white,
                  dense: true,
                  onChanged: (v) => setState(() => _hasOwnerSafe = v ?? false),
                ),
              ),
              const SizedBox(height: 20),

              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('الصفحات المسموحة للموظف',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _toggleAll,
                            child: Text(
                              _allowedPages.length == _appPages.length
                                  ? 'إلغاء تحديد الكل'
                                  : 'تحديد الكل',
                              style: const TextStyle(
                                  color: AppTheme.primary, fontFamily: 'Cairo'),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الصفحات المسموحة للموظف',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: 14)),
                      TextButton(
                        onPressed: _toggleAll,
                        child: Text(
                          _allowedPages.length == _appPages.length
                              ? 'إلغاء تحديد الكل'
                              : 'تحديد الكل',
                          style: const TextStyle(
                              color: AppTheme.primary, fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),

              // Pages List
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.glassBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: _appPages.map((page) {
                    final isSelected = _allowedPages.contains(page['path']);
                    return CheckboxListTile(
                      title: Text(page['label']!,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cairo',
                              fontSize: 14)),
                      value: isSelected,
                      activeColor: AppTheme.primary,
                      checkColor: Colors.white,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _allowedPages.add(page['path']!);
                          } else {
                            _allowedPages.remove(page['path']!);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        if (widget.currentRole != null)
          TextButton(
            onPressed: () {
              context.read<UserManagementCubit>().removeUserRole(widget.userId);
              Navigator.pop(context);
            },
            child: const Text('إزالة الصلاحيات',
                style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
          ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  void _toggleAll() {
    setState(() {
      if (_allowedPages.length == _appPages.length) {
        _allowedPages.clear();
      } else {
        _allowedPages = _appPages.map((p) => p['path']!).toList();
      }
    });
  }

  void _save() {
    final pagesToSave = List<String>.from(_allowedPages);
    if (_hasOwnerSafe) {
      if (!pagesToSave.contains('/owner-safe')) {
        pagesToSave.add('/owner-safe');
      }
      if (!pagesToSave.contains('/accounts')) {
        pagesToSave.add('/accounts');
      }
    } else {
      pagesToSave.remove('/owner-safe');
    }

    context.read<UserManagementCubit>().setUserRole(
      userId: widget.userId,
      role: 'employee',
      permissions: {
        'allowed_pages': pagesToSave,
      },
    );
    Navigator.pop(context);
  }
}
