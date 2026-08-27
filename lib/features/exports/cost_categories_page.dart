import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';

class CostReportCategoriesPage extends StatefulWidget {
  const CostReportCategoriesPage({super.key});

  @override
  State<CostReportCategoriesPage> createState() => _CostReportCategoriesPageState();
}

class _CostReportCategoriesPageState extends State<CostReportCategoriesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final List response = await _client.rpc('list_cost_report_categories');
      setState(() {
        _categories = response.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
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

  Color _getCategoryColor(dynamic id) {
    final colors = [
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Orange
      const Color(0xFF3B82F6), // Blue
      const Color(0xFFEC4899), // Pink
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFF6B7280), // Gray
      const Color(0xFFEF4444), // Red
      const Color(0xFF06B6D4), // Cyan
    ];
    final hash = id.toString().hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _getScopeLabel(String? scope) {
    switch (scope) {
      case 'packing':
        return 'بنود تعبئة';
      case 'shipment':
        return 'بنود شحنة';
      case 'packing_waste':
        return 'هالك التعبئة';
      case 'all':
      case 'both':
      default:
        return 'الكل';
    }
  }

  Color _getScopeColor(String? scope) {
    switch (scope) {
      case 'packing':
        return const Color(0xFF10B981);
      case 'shipment':
        return const Color(0xFF3B82F6);
      case 'packing_waste':
        return const Color(0xFFEC4899);
      case 'all':
      case 'both':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    String selectedScope = 'all';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final canSubmit = name.isNotEmpty;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: const Text(
              'إضافة تصنيف جديد',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
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
                      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.glassBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedScope,
                    decoration: InputDecoration(
                      labelText: 'نطاق التصنيف (Scope)',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.glassBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    dropdownColor: const Color(0xFF1A2940),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'packing', child: Text('بنود تعبئة (Packing)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'shipment', child: Text('بنود شحنة (Shipment)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'packing_waste', child: Text('هالك التعبئة (Packing Waste)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'all', child: Text('الكل (All)', style: TextStyle(fontFamily: 'Cairo'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedScope = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        try {
                          await _client.rpc('create_cost_report_category', params: {
                            'p_name': name,
                            'p_scope': selectedScope,
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadCategories();
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('فشل الإضافة: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit ? AppTheme.primary : AppTheme.textSecondary.withAlpha(80),
                  foregroundColor: Colors.white,
                ),
                child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> cat) {
    final nameCtrl = TextEditingController(text: cat['name'] as String? ?? '');
    final rawScope = cat['scope'] as String? ?? 'all';
    String selectedScope = rawScope == 'both' ? 'all' : rawScope;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final name = nameCtrl.text.trim();
          final canSubmit = name.isNotEmpty;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2940),
            title: Text(
              'تعديل: ${cat['name']}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
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
                      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.glassBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedScope,
                    decoration: InputDecoration(
                      labelText: 'نطاق التصنيف (Scope)',
                      labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.glassBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    dropdownColor: const Color(0xFF1A2940),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'packing', child: Text('بنود تعبئة (Packing)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'shipment', child: Text('بنود شحنة (Shipment)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'packing_waste', child: Text('هالك التعبئة (Packing Waste)', style: TextStyle(fontFamily: 'Cairo'))),
                      DropdownMenuItem(value: 'all', child: Text('الكل (All)', style: TextStyle(fontFamily: 'Cairo'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedScope = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        try {
                          await _client.rpc('update_cost_report_category', params: {
                            'p_id': cat['id'],
                            'p_name': name,
                            'p_scope': selectedScope,
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadCategories();
                        } catch (e) {
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
                  backgroundColor: canSubmit ? AppTheme.primary : AppTheme.textSecondary.withAlpha(80),
                  foregroundColor: Colors.white,
                ),
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteCategory(Map<String, dynamic> cat) {
    final isSystem = cat['is_system'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2940),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'حذف التصنيف',
          textDirection: TextDirection.rtl,
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من حذف "${cat['name']}"؟',
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
              ),
              if (isSystem) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه: هذا تصنيف افتراضي من النظام.',
                          style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
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
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _client.rpc('delete_cost_report_category', params: {'p_id': cat['id']});
                if (ctx.mounted) Navigator.pop(ctx);
                _loadCategories();
              } catch (e) {
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  String errMsg = e.toString();
                  if (errMsg.contains('مستخدم')) {
                    errMsg = 'لا يمكن حذف هذا التصنيف لأنه مستخدم في سجلات بنود التكلفة';
                  }
                  showDialog(
                    context: context,
                    builder: (ctx2) => AlertDialog(
                      backgroundColor: const Color(0xFF1A2940),
                      title: const Text('خطأ بالحذف', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      content: Text(errMsg, textDirection: TextDirection.rtl, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
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
    return Scaffold(
      backgroundColor: const Color(0xFF03121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF051B2B),
        elevation: 0,
        title: const Text(
          'إدارة تصنيفات بنود التكلفة',
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.neonCyan),
            onPressed: _showAddCategoryDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _categories.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد تصنيفات حالياً',
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 16),
                  ),
                )
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final catColor = _getCategoryColor(cat['id']);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: Row(
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
                                  Text(
                                    cat['name'] as String? ?? 'بدون اسم',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _getScopeColor(cat['scope'] as String?).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: _getScopeColor(cat['scope'] as String?).withValues(alpha: 0.3)),
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
                                            color: Colors.grey.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                          ),
                                          child: const Text(
                                            'افتراضي',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontFamily: 'Cairo',
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.accent, size: 20),
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
                  ),
                ),
    );
  }
}
