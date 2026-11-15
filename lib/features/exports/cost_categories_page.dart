import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/services/cost_category_service.dart';

class CostReportCategoriesPage extends StatefulWidget {
  const CostReportCategoriesPage({super.key});

  @override
  State<CostReportCategoriesPage> createState() => _CostReportCategoriesPageState();
}

class _CostReportCategoriesPageState extends State<CostReportCategoriesPage> {
  final CostCategoryService _service = CostCategoryService();
  bool _loading = true;
  List<Map<String, dynamic>> _categories = [];
  StreamSubscription<void>? _eventSub;

  String _supplierTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _eventSub = DataChangeEventBus.instance.costCategoriesStream.listen((_) {
      _loadCategories();
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final response = await _service.listCategories();
      if (mounted) {
        setState(() {
          _categories = response;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تحميل التصنيفات: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _seedStandardCategories() async {
    setState(() => _loading = true);
    try {
      final count = await _service.seedStandardSupplierCategories();
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                count > 0
                    ? 'تم تهيئة وتحديث $count تصنيف (محطات، تخصيمات، مصاريف إدارية) بنجاح!'
                    : 'جميع التصنيفات القياسية (محطات، تخصيمات، مصاريف إدارية) مهيأة بالفعل ومطابقة للنظام.',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء التهيئة: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Color _getCategoryColor(dynamic id) {
    final colors = [
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Orange
      const Color(0xFF3B82F6), // Blue
      const Color(0xFFEC4899), // Pink
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF6366F1), // Indigo
      const Color(0xFFEF4444), // Red
    ];
    final hash = id.toString().hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _getScopeLabel(String? scope) {
    return CostCategoryScope.fromCode(scope).labelAr;
  }

  Color _getScopeColor(String? scope) {
    return CostCategoryScope.fromCode(scope).color;
  }

  String _getSupplierTypeLabel(String? type) {
    return CostCategoryService.getSupplierTypeLabel(type);
  }

  Color _getSupplierTypeColor(String? type) {
    if (type == 'deduction') {
      return const Color(0xFF8B5CF6); // Purple
    } else if (type == 'admin') {
      return const Color(0xFF0284C7); // Cyan / Blue
    } else if (type == 'transport') {
      return const Color(0xFF10B981); // Emerald
    }
    return const Color(0xFFF59E0B); // Amber
  }

  void _showAddCategoryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController();
    CostCategoryScope selectedScope = CostCategoryScope.packing;
    String selectedParentCode = '3124';
    String selectedSupplierType = 'station';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final canSubmit = name.isNotEmpty && !isSaving;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              textDirection: TextDirection.rtl,
              children: [
                Icon(Icons.category_rounded,
                    color: isDark ? AppTheme.neonCyan : AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'إضافة تصنيف تكلفة جديد',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'اسم التصنيف / البند',
                        hintText: 'مثال: تشغيل، تبريد، رسوم فحص، تخصيم عربي...',
                        labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontFamily: 'Cairo',
                            fontSize: 13),
                        hintStyle: TextStyle(
                            color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                            fontFamily: 'Cairo',
                            fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                          fontSize: 14),
                      onChanged: (val) {
                        setDialogState(() {
                          final clean = val.trim();
                          if (CostCategoryService.stationSupplierCategories.contains(clean)) {
                            selectedSupplierType = 'station';
                            selectedScope = CostCategoryScope.packing;
                            selectedParentCode = '3124';
                          } else if (CostCategoryService.deductionSupplierCategories.contains(clean)) {
                            selectedSupplierType = 'deduction';
                            selectedScope = CostCategoryScope.packing;
                            selectedParentCode = '3126';
                          } else if (CostCategoryService.adminSupplierCategories.contains(clean) ||
                              clean.contains('إدار') || clean.contains('ادار')) {
                            selectedSupplierType = 'admin';
                            selectedScope = CostCategoryScope.generalAdmin;
                            selectedParentCode = '3133';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSupplierType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'نوع المورد المرتبط (Supplier Type)',
                        labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontFamily: 'Cairo',
                            fontSize: 13),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'station', child: Text('موردي المحطات 🏭')),
                        DropdownMenuItem(value: 'deduction', child: Text('موردي التخصيمات 📋')),
                        DropdownMenuItem(value: 'admin', child: Text('مصاريف إدارية 💼')),
                        DropdownMenuItem(value: 'transport', child: Text('موردي النقل 🚛')),
                        DropdownMenuItem(value: 'general', child: Text('عام / أخرى 🌐')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            selectedSupplierType = v;
                            if (v == 'station') {
                              selectedScope = CostCategoryScope.packing;
                              selectedParentCode = '3124';
                            } else if (v == 'deduction') {
                              selectedScope = CostCategoryScope.packing;
                              selectedParentCode = '3126';
                            } else if (v == 'admin') {
                              selectedScope = CostCategoryScope.generalAdmin;
                              selectedParentCode = '3133';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CostCategoryScope>(
                      initialValue: selectedScope,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'نطاق التطبيق (Scope)',
                        labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontFamily: 'Cairo',
                            fontSize: 13),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      items: [
                        CostCategoryScope.generalAdmin,
                        CostCategoryScope.packing,
                        CostCategoryScope.shipment,
                        CostCategoryScope.all,
                      ].map((scope) {
                        return DropdownMenuItem<CostCategoryScope>(
                          value: scope,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(scope.icon, size: 16, color: scope.color),
                              const SizedBox(width: 8),
                              Text(
                                '${scope.labelAr} (${scope.parentAccountCode})',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            selectedScope = v;
                            selectedParentCode = v.parentAccountCode;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.neonCyan.withValues(alpha: 0.08)
                            : const Color(0xFF0284C7).withValues(alpha: 0.08),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.neonCyan.withValues(alpha: 0.25)
                              : const Color(0xFF0284C7).withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الربط المحاسبي التلقائي ونوع المورد',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'سيتم ربط هذا البند تلقائياً بنوع المورد المحدد، وحساب التكاليف في دليل الحسابات، ليظهر بفلترة تلقائية عند اختيار البند في أوامر التعبئة.',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final res = await _service.createCategory(
                            name: name,
                            scope: selectedScope.code,
                            parentAccountCode: selectedParentCode,
                            supplierType: selectedSupplierType,
                          );

                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadCategories();

                          if (mounted) {
                            final acctCode = res['account_code'] ?? '3124X';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 4),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                content: Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'تم حفظ وتوليد "$name" بنجاح!\nحساب الأستاذ: $acctCode | نوع المورد: ${_getSupplierTypeLabel(selectedSupplierType)}',
                                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('فشل إضافة التصنيف: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppTheme.primary
                      : (isDark ? AppTheme.textSecondary.withAlpha(80) : const Color(0xFFCBD5E1)),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('حفظ وتوليد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> cat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: cat['name'] as String? ?? '');
    final rawScope = cat['scope'] as String? ?? 'general_admin';
    final initialScope = CostCategoryScope.fromCode(rawScope);
    final availableScopes = <CostCategoryScope>{
      CostCategoryScope.generalAdmin,
      CostCategoryScope.packing,
      CostCategoryScope.shipment,
      CostCategoryScope.all,
      initialScope,
    }.toList();
    CostCategoryScope selectedScope = initialScope;
    String rawSt = cat['supplier_type']?.toString().toLowerCase().trim() ?? 'station';
    String selectedSupplierType = ['station', 'deduction', 'admin', 'transport', 'general'].contains(rawSt)
        ? rawSt
        : 'station';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final canSubmit = name.isNotEmpty && !isSaving;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'تعديل: ${cat['name']}',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم التصنيف',
                      labelStyle: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSupplierType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'نوع المورد المرتبط (Supplier Type)',
                      labelStyle: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'station', child: Text('موردي المحطات 🏭')),
                      DropdownMenuItem(value: 'deduction', child: Text('موردي التخصيمات 📋')),
                      DropdownMenuItem(value: 'admin', child: Text('مصاريف إدارية 💼')),
                      DropdownMenuItem(value: 'transport', child: Text('موردي النقل 🚛')),
                      DropdownMenuItem(value: 'general', child: Text('عام / أخرى 🌐')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedSupplierType = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<CostCategoryScope>(
                    initialValue: selectedScope,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'نطاق التصنيف (Scope)',
                      labelStyle: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    items: availableScopes.map((scope) {
                      return DropdownMenuItem<CostCategoryScope>(
                        value: scope,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(scope.icon, size: 16, color: scope.color),
                            const SizedBox(width: 8),
                            Text(scope.labelAr,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                )),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedScope = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        setDialogState(() => isSaving = true);
                        try {
                          await _service.updateCategory(
                            id: cat['id'],
                            name: name,
                            scope: selectedScope.code,
                            supplierType: selectedSupplierType,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadCategories();
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('فشل التعديل: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppTheme.primary
                      : (isDark ? AppTheme.textSecondary.withAlpha(80) : const Color(0xFFCBD5E1)),
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('حفظ وتوليد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteCategory(Map<String, dynamic> cat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSystem = cat['is_system'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'حذف التصنيف',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من حذف "${cat['name']}"؟',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
              ),
              if (isSystem) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: isDark ? 0.1 : 0.08),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: isDark ? 0.3 : 0.35),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه: هذا تصنيف افتراضي من النظام.',
                          style: TextStyle(
                            color: isDark ? AppTheme.warning : const Color(0xFFB45309),
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _service.deleteCategory(cat['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadCategories();
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  String errMsg = e.toString();
                  if (errMsg.contains('مستخدم')) {
                    errMsg = 'لا يمكن حذف هذا التصنيف لأنه مستخدم في سجلات بنود التكلفة';
                  }
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx2) => AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                      title: Text('خطأ بالحذف',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          )),
                      content: Text(errMsg,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                            fontFamily: 'Cairo',
                          )),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx2),
                          child: const Text('موافق', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text(
              'حذف',
              style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF03121F) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF051B2B) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFE2E8F0),
            height: 1,
          ),
        ),
        title: Text(
          'إدارة تصنيفات بنود التكلفة',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(RoutePaths.home);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B)),
            tooltip: 'تهيئة التصنيفات القياسية (محطات، تخصيمات، مصاريف إدارية)',
            onPressed: _seedStandardCategories,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            tooltip: 'تحديث',
            onPressed: _loadCategories,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary),
            tooltip: 'إضافة تصنيف',
            onPressed: _showAddCategoryDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                children: [
                  // Filter Chips Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF051B2B) : Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('الكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                            selected: _supplierTypeFilter == 'all',
                            onSelected: (sel) {
                              if (sel) setState(() => _supplierTypeFilter = 'all');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('موردي المحطات 🏭', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                            selected: _supplierTypeFilter == 'station',
                            selectedColor: const Color(0xFFF59E0B).withAlpha(60),
                            onSelected: (sel) {
                              if (sel) setState(() => _supplierTypeFilter = 'station');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('موردي التخصيمات 📋', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                            selected: _supplierTypeFilter == 'deduction',
                            selectedColor: const Color(0xFF8B5CF6).withAlpha(60),
                            onSelected: (sel) {
                              if (sel) setState(() => _supplierTypeFilter = 'deduction');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('مصاريف إدارية 💼', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                            selected: _supplierTypeFilter == 'admin',
                            selectedColor: const Color(0xFF0284C7).withAlpha(60),
                            onSelected: (sel) {
                              if (sel) setState(() => _supplierTypeFilter = 'admin');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Categories List
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final displayedCategories = _categories.where((c) {
                          if (_supplierTypeFilter == 'all') return true;
                          final st = c['supplier_type'] as String? ?? 'general';
                          return st == _supplierTypeFilter;
                        }).toList();

                        if (displayedCategories.isEmpty) {
                          return Center(
                            child: Text(
                              'لا توجد تصنيفات مطابقة للفلتر المحدد',
                              style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                fontFamily: 'Cairo',
                                fontSize: 15,
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: displayedCategories.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final cat = displayedCategories[index];
                            final catColor = _getCategoryColor(cat['id']);
                            final accountCode = cat['account_code']?.toString();
                            final accountName = cat['account_name']?.toString();
                            final costCenterId = cat['cost_center_id']?.toString();
                            final costCenterName = cat['cost_center_name']?.toString();
                            final suppType = cat['supplier_type'] as String? ?? 'general';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                                ),
                                boxShadow: isDark
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.04),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: catColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: catColor.withValues(alpha: 0.4),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              cat['name'] as String? ?? 'بدون اسم',
                                              style: TextStyle(
                                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                fontFamily: 'Cairo',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Supplier Type Badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getSupplierTypeColor(suppType)
                                                    .withValues(alpha: isDark ? 0.15 : 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: _getSupplierTypeColor(suppType)
                                                      .withValues(alpha: isDark ? 0.35 : 0.4),
                                                ),
                                              ),
                                              child: Text(
                                                _getSupplierTypeLabel(suppType),
                                                style: TextStyle(
                                                  color: _getSupplierTypeColor(suppType),
                                                  fontFamily: 'Cairo',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // Scope Badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getScopeColor(cat['scope'] as String?)
                                                    .withValues(alpha: isDark ? 0.15 : 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: _getScopeColor(cat['scope'] as String?)
                                                      .withValues(alpha: isDark ? 0.3 : 0.35),
                                                ),
                                              ),
                                              child: Text(
                                                _getScopeLabel(cat['scope'] as String?),
                                                style: TextStyle(
                                                  color: _getScopeColor(cat['scope'] as String?),
                                                  fontFamily: 'Cairo',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (cat['is_system'] == true) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.grey.withValues(alpha: 0.1)
                                                      : const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isDark
                                                        ? Colors.grey.withValues(alpha: 0.3)
                                                        : const Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                                child: Text(
                                                  'افتراضي',
                                                  style: TextStyle(
                                                    color: isDark ? Colors.grey : const Color(0xFF64748B),
                                                    fontFamily: 'Cairo',
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            // COA Account Badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? AppTheme.neonCyan.withValues(alpha: 0.1)
                                                    : const Color(0xFF0284C7).withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isDark
                                                      ? AppTheme.neonCyan.withValues(alpha: 0.3)
                                                      : const Color(0xFF0284C7).withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.account_tree_outlined,
                                                      size: 12,
                                                      color: isDark
                                                          ? AppTheme.neonCyan
                                                          : const Color(0xFF0284C7)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'حساب الأستاذ: ${accountCode != null ? "$accountCode - ${accountName ?? ''}" : "قيد المزامنة"}',
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? AppTheme.neonCyan
                                                          : const Color(0xFF0284C7),
                                                      fontFamily: 'Cairo',
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Cost Center Badge (only if explicitly linked)
                                            if (costCenterId != null && costCenterId.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? AppTheme.accent.withValues(alpha: 0.1)
                                                      : const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isDark
                                                        ? AppTheme.accent.withValues(alpha: 0.3)
                                                        : const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.pie_chart_outline_rounded,
                                                        size: 12,
                                                        color: isDark
                                                            ? AppTheme.accent
                                                            : const Color(0xFF7C3AED)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'مركز التكلفة: $costCenterId [${costCenterName ?? ''}]',
                                                      style: TextStyle(
                                                        color: isDark
                                                            ? AppTheme.accent
                                                            : const Color(0xFF7C3AED),
                                                        fontFamily: 'Cairo',
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.edit_outlined,
                                        color: isDark ? AppTheme.accent : const Color(0xFF2563EB),
                                        size: 20),
                                    onPressed: () => _showEditCategoryDialog(cat),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                    onPressed: () => _deleteCategory(cat),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
