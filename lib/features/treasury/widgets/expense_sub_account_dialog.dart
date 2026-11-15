import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/dao/account_dao.dart';
import '../../../data/models/cost_center.dart';
import '../../../data/services/cost_center_service.dart';

/// Modal dialog for creating a dynamic Level 4/5 Expense Sub-Account in the Chart of Accounts
class ExpenseSubAccountDialog extends StatefulWidget {
  final String? initialParentCode;
  final String? initialCostCenterId;

  const ExpenseSubAccountDialog({
    super.key,
    this.initialParentCode,
    this.initialCostCenterId,
  });

  @override
  State<ExpenseSubAccountDialog> createState() => _ExpenseSubAccountDialogState();
}

class _ExpenseSubAccountDialogState extends State<ExpenseSubAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameArCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  late String _selectedParentCode;
  String? _selectedCostCenterId;
  bool _isAutoCode = true;
  bool _isLoadingCode = false;
  bool _isSaving = false;
  List<CostCenter> _costCenters = [];

  final List<Map<String, String>> _parentCategories = [
    {
      'code': '3131',
      'nameAr': 'مصروفات البوفيه وخدمات الإدارة (3131)',
      'defaultCc': 'general_admin',
    },
    {
      'code': '3132',
      'nameAr': 'استشارات واشتراكات ورسوم (3132)',
      'defaultCc': 'general_admin',
    },
    {
      'code': '3122',
      'nameAr': 'مصروفات تشغيل وبيع وتسويق (3122)',
      'defaultCc': 'packing_station',
    },
    {
      'code': '3112',
      'nameAr': 'مصروفات عاملين أخرى وانتقالات (3112)',
      'defaultCc': 'general_admin',
    },
    {
      'code': '3142',
      'nameAr': 'المصروفات والعمولات البنكية (3142)',
      'defaultCc': 'general_admin',
    },
    {
      'code': '3143',
      'nameAr': 'المصروفات المتنوعة الأخرى (3143)',
      'defaultCc': 'general_admin',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedParentCode = widget.initialParentCode ?? '3131';
    _selectedCostCenterId = widget.initialCostCenterId ?? _getDefaultCostCenter(_selectedParentCode);
    _loadNextCode();
    _loadCostCenters();
  }

  Future<void> _loadCostCenters() async {
    try {
      final centers = await CostCenterService().fetchCostCenters();
      if (mounted) {
        setState(() => _costCenters = centers);
        // If selected cost center is not in the list, clear selection
        if (_selectedCostCenterId != null && 
            !centers.any((c) => c.id == _selectedCostCenterId || c.code == _selectedCostCenterId)) {
          setState(() => _selectedCostCenterId = centers.isNotEmpty ? centers.first.id : null);
        }
      }
    } catch (_) {}
  }

  String _getDefaultCostCenter(String parentCode) {
    final match = _parentCategories.firstWhere(
      (c) => c['code'] == parentCode,
      orElse: () => _parentCategories.first,
    );
    return match['defaultCc'] ?? 'general_admin';
  }

  Future<void> _loadNextCode() async {
    if (!_isAutoCode) return;
    setState(() => _isLoadingCode = true);
    try {
      final code = await AccountDao().getNextSubAccountCode(_selectedParentCode);
      if (mounted) {
        setState(() {
          _codeCtrl.text = code;
          _isLoadingCode = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCode = false);
      }
    }
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final result = await AccountDao().createExpenseSubAccount(
        parentCode: _selectedParentCode,
        nameAr: _nameArCtrl.text.trim(),
        nameEn: _nameEnCtrl.text.trim().isNotEmpty ? _nameEnCtrl.text.trim() : null,
        costCenterId: _selectedCostCenterId,
        customCode: _codeCtrl.text.trim().isNotEmpty ? _codeCtrl.text.trim() : null,
      );

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء الحساب: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A2240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 40)),
      ),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 40)),
                      ),
                      child: const Icon(Icons.add_chart_rounded, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة حساب مصروف فرعي جديد',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'ربط الحساب بشجرة الحسابات ومركز التكلفة مباشرة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(color: AppTheme.glassBorder, height: 1),
                const SizedBox(height: 18),

                // 1. Parent Classification Dropdown
                const Text(
                  'التصنيف الرئيسي (الحساب الأب)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF061B3A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedParentCode,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF061B3A),
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                      items: _parentCategories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['code'],
                          child: Text(
                            cat['nameAr']!,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedParentCode) {
                          setState(() {
                            _selectedParentCode = val;
                            _selectedCostCenterId = _getDefaultCostCenter(val);
                          });
                          _loadNextCode();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Account Code (Auto/Custom)
                Row(
                  children: [
                    const Text(
                      'كود الحساب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        setState(() => _isAutoCode = !_isAutoCode);
                        if (_isAutoCode) _loadNextCode();
                      },
                      child: Row(
                        children: [
                          Icon(
                            _isAutoCode ? Icons.auto_awesome : Icons.edit_note,
                            size: 14,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isAutoCode ? 'تلقائي' : 'يدوي',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _codeCtrl,
                  readOnly: _isAutoCode,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'كود الحساب (مثال: 3214)',
                    prefixIcon: _isLoadingCode
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                            ),
                          )
                        : const Icon(Icons.numbers, size: 18, color: AppTheme.primary),
                    filled: true,
                    fillColor: const Color(0xFF061B3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب إدخال كود الحساب' : null,
                ),
                const SizedBox(height: 14),

                // 3. Arabic Account Name
                const Text(
                  'اسم حساب المصروف (بالعربية)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameArCtrl,
                  decoration: InputDecoration(
                    hintText: 'مثال: بوفيه وضيافة، صيانة سيارات، أدوات مكتبية...',
                    prefixIcon: const Icon(Icons.label_outline, size: 18, color: AppTheme.primary),
                    filled: true,
                    fillColor: const Color(0xFF061B3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى كتابة اسم حساب المصروف' : null,
                ),
                const SizedBox(height: 14),

                // 4. English Name (Optional)
                const Text(
                  'اسم الحساب بالإنجليزية (اختياري)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameEnCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'e.g. Hospitality, Car Maintenance, Office Supplies...',
                    prefixIcon: const Icon(Icons.translate, size: 18, color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: const Color(0xFF061B3A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                const SizedBox(height: 14),

                // 5. Default Cost Center Selector
                const Row(
                  children: [
                    Icon(Icons.hub_outlined, size: 14, color: AppTheme.accent),
                    SizedBox(width: 6),
                    Text(
                      'مركز التكلفة المرتبط افتراضياً',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF061B3A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCostCenterId,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF061B3A),
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.accent),
                      items: _costCenters.map((cc) {
                        return DropdownMenuItem<String>(
                          value: cc.id,
                          child: Row(
                            children: [
                              Icon(cc.icon, size: 14, color: cc.color),
                              const SizedBox(width: 8),
                              Text(
                                cc.nameAr,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: cc.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedCostCenterId = val),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 6. Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        _isSaving ? 'جارٍ الحفظ...' : 'حفظ وإضافة الحساب',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
