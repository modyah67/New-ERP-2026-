import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_model.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../data/models/cost_center.dart';
import '../treasury/widgets/cost_center_selector_field.dart';

class FruitTypeFormDialog extends StatefulWidget {
  final FruitTypeModel? item;
  const FruitTypeFormDialog({super.key, this.item});

  @override
  State<FruitTypeFormDialog> createState() => _FruitTypeFormDialogState();
}

class _FruitTypeFormDialogState extends State<FruitTypeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dao = FruitTypeDao();
  final _scrollCtrl = ScrollController();

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;

  late final FocusNode _nameFocus;
  String? _currency;
  String? _weightCurrency;
  String? _cartonCurrency;
  String? _purchaseMode;
  String? _selectedCostCenterId;

  bool _saving = false;

  static const _currencies = ['EGP', 'USD', 'EUR', 'GBP'];
  static const _currencyLabels = {
    'EGP': 'جنيه مصري',
    'USD': 'دولار',
    'EUR': 'يورو',
    'GBP': 'جنيه إسترليني',
  };

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _nameController = TextEditingController();
    _nameFocus = FocusNode();

    _nameController.addListener(() {
      if (_purchaseMode == 'shared' && mounted) setState(() {});
    });

    if (widget.item != null) {
      final item = widget.item!;
      _codeController.text = item.code;
      _nameController.text = item.name;
      _currency = item.currency;
      _weightCurrency = item.currency;
      _cartonCurrency = item.currency;
      _purchaseMode = item.purchaseMode;
      _selectedCostCenterId = item.costCenterId;
    } else {
      _currency = 'EGP';
      _weightCurrency = 'EGP';
      _cartonCurrency = 'EGP';
      _generateCode();
    }
  }

  Future<void> _generateCode() async {
    final code = await _dao.generateCode();
    if (mounted) {
      setState(() => _codeController.text = code);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    final isShared = _purchaseMode == 'shared';
    if (isShared) {
      if (_weightCurrency == null || _weightCurrency!.isEmpty) return;
      if (_cartonCurrency == null || _cartonCurrency!.isEmpty) return;
    } else {
      if (_currency == null || _currency!.isEmpty) return;
    }
    if (_purchaseMode == null || _purchaseMode!.isEmpty) return;
    if (_selectedCostCenterId == null || _selectedCostCenterId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('يجب اختيار مركز التكلفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
            ],
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      if (widget.item != null) {
        final item = FruitTypeModel(
          id: widget.item?.id,
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          color: null,
          sortOrder: widget.item?.sortOrder ?? 0,
          isActive: widget.item?.isActive ?? true,
          currency: _currency!,
          purchaseMode: _purchaseMode,
          costCenterId: _selectedCostCenterId,
        );
        await _dao.update(item);
      } else if (isShared) {
        await _dao.insertSharedFruitType(
          baseCode: _codeController.text.trim(),
          baseName: _nameController.text.trim(),
          weightCurrency: _weightCurrency!,
          cartonCurrency: _cartonCurrency!,
          costCenterId: _selectedCostCenterId,
        );
      } else {
        final item = FruitTypeModel(
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          color: null,
          sortOrder: 0,
          isActive: true,
          currency: _currency!,
          purchaseMode: _purchaseMode,
          costCenterId: _selectedCostCenterId,
        );
        await _dao.insert(item);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                widget.item != null
                    ? 'تم تعديل صنف الفاكهة بنجاح'
                    : isShared
                        ? 'تم إنشاء صنف الفاكهة المشترك (وزن وكراتين) بنجاح'
                        : 'تم إضافة صنف الفاكهة بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ _save fruit type error: $e');
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'فشل الحفظ: $e',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dialogContent = Container(
      width: screenWidth < 500 ? screenWidth * 0.95 : 520,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xB305192D) : Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isEditing, isDark),
              Flexible(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'كود الصنف',
                            controller: _codeController,
                            hint: '1',
                            isRequired: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'كود الصنف مطلوب';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'اسم الصنف',
                            controller: _nameController,
                            focusNode: _nameFocus,
                            hint: 'أدخل اسم الصنف',
                            isRequired: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'طريقة الشراء *',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? AppTheme.textSecondary : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _purchaseMode,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        fontSize: 13,
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار طريقة الشراء' : null,
                      decoration: InputDecoration(
                        hintText: 'اختر طريقة الشراء',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey : const Color(0xFF94A3B8),
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'weight',
                          child: Text(
                            'الوزن',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'carton',
                          child: Text(
                            'الكراتين',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isEditing)
                          DropdownMenuItem(
                            value: 'shared',
                            child: Row(
                              children: [
                                Icon(Icons.alt_route, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                const SizedBox(width: 8),
                                Text(
                                  'مشترك (وزن وكراتين)',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _purchaseMode = v;
                          if (v == 'shared') {
                            _weightCurrency ??= _currency ?? 'EGP';
                            _cartonCurrency ??= _currency ?? 'EGP';
                          } else {
                            _currency ??= _weightCurrency ?? 'EGP';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_purchaseMode == 'shared') ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'عملة صنف الوزن *',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _weightCurrency,
                                  isExpanded: true,
                                  dropdownColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار عملة الوزن' : null,
                                  decoration: InputDecoration(
                                    hintText: 'عملة الوزن',
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.grey : const Color(0xFF94A3B8),
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                    ),
                                  ),
                                  items: _currencies.map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      _currencyLabels[c] ?? c,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      ),
                                    ),
                                  )).toList(),
                                  onChanged: (v) { setState(() => _weightCurrency = v); },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'عملة صنف الكراتين *',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _cartonCurrency,
                                  isExpanded: true,
                                  dropdownColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: isDark ? Colors.white : Colors.black,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار عملة الكراتين' : null,
                                  decoration: InputDecoration(
                                    hintText: 'عملة الكراتين',
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.grey : const Color(0xFF94A3B8),
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                    ),
                                  ),
                                  items: _currencies.map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      _currencyLabels[c] ?? c,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      ),
                                    ),
                                  )).toList(),
                                  onChanged: (v) { setState(() => _cartonCurrency = v); },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'العملة *',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? AppTheme.textSecondary : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _currency,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontSize: 13,
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'يرجى اختيار العملة' : null,
                        decoration: InputDecoration(
                          hintText: 'اختر العملة',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey : const Color(0xFF94A3B8),
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                          ),
                        ),
                        items: _currencies.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            _currencyLabels[c] ?? c,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        )).toList(),
                        onChanged: (v) {
                          setState(() {
                            _currency = v;
                            _weightCurrency = v;
                            _cartonCurrency = v;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    CostCenterSelectorField(
                      label: 'مركز التكلفة المرتبط (خط المحصول الزراعي) *',
                      selectedCostCenterId: _selectedCostCenterId,
                      isRequired: true,
                      filterType: CostCenterType.variety,
                      showNoneOption: false,
                      onSelected: (id) {
                        setState(() => _selectedCostCenterId = id);
                      },
                    ),
                    if (_purchaseMode == 'shared') ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? AppTheme.accent.withValues(alpha: 0.35) : const Color(0xFF86EFAC),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: isDark ? AppTheme.accent : const Color(0xFF16A34A)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'إنشاء تلقائي ثنائي لصنف مشترك:',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'سيتم إنشاء سجلين مستقلين في قاعدة البيانات:\n'
                                    '• ${_nameController.text.trim().isEmpty ? "[اسم الصنف]" : _nameController.text.trim()} - وزن (شراء بالوزن/كجم) [${_currencyLabels[_weightCurrency] ?? _weightCurrency ?? "العملة"}]\n'
                                    '• ${_nameController.text.trim().isEmpty ? "[اسم الصنف]" : _nameController.text.trim()} - كراتين (شراء بالكرتونة) [${_currencyLabels[_cartonCurrency] ?? _cartonCurrency ?? "العملة"}]\n'
                                    'يضمن ذلك حفظ الدقة المحاسبية ومخزون FIFO وفواتير المشتريات مع دمج العرض تلقائياً في بطاقة موحدة.',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      color: isDark ? Colors.white70 : Colors.black87,
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
                  ],
                ),
              ),
              _buildButtons(isEditing, isDark),
            ],
          ),
        ),
      ),
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1.2),
      ),
      child: isDark
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: dialogContent,
              ),
            )
          : dialogContent,
    );
  }

  Widget _buildHeader(bool isEditing, bool isDark) {
    final name = _nameController.text.trim();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _avatarColor(name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? 'تعديل صنف فاكهة' : 'إضافة صنف فاكهة جديد',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black, size: 22),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(String name) {
    final colors = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF97316),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Widget _buildButtons(bool isEditing, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? AppTheme.textSecondary : Colors.black,
                side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFCBD5E1), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isEditing ? Icons.save_outlined : Icons.add, size: 18),
              label: Text(
                _saving ? 'جاري الحفظ...' : isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              ),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
