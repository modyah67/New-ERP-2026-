import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/read_only_guard.dart';
import '../../../data/models/cost_center.dart';
import '../../../data/services/cost_center_service.dart';
import '../../../ui/widgets/app_text_field.dart';

/// Modal dialog for manually creating or defining crop-centric seasonal
/// cost centers or operational lines by accountants.
class CostCenterFormDialog extends StatefulWidget {
  final ValueChanged<CostCenter?>? onSaved;

  const CostCenterFormDialog({
    super.key,
    this.onSaved,
  });

  static Future<CostCenter?> show(BuildContext context, {ValueChanged<CostCenter?>? onSaved}) {
    return showDialog<CostCenter>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CostCenterFormDialog(onSaved: onSaved),
    );
  }

  @override
  State<CostCenterFormDialog> createState() => _CostCenterFormDialogState();
}

class _CostCenterFormDialogState extends State<CostCenterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  CostCenterType _type = CostCenterType.variety;

  final _nameArCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _seasonCtrl = TextEditingController(text: '2026-2027');
  final _openingBalanceCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  int? _selectedStationId;
  List<Map<String, dynamic>> _stations = [];
  bool _loadingStations = true;

  Color _selectedColor = const Color(0xFF10B981);
  IconData _selectedIcon = Icons.eco;

  bool _saving = false;

  static const List<String> _cropSuggestions = [
    'مانجو',
    'عنب',
    'برتقال',
    'فراولة',
    'ليمون',
    'يوسفي',
    'رمان',
    'موز',
    'خوخ',
    'مشمش',
    'بلح',
    'تين',
  ];

  static const List<Color> _colorPalette = [
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFF97316), // Orange
    Color(0xFF8B5CF6), // Purple
    Color(0xFF0D74CE), // Primary Blue
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEF4444), // Crimson
    Color(0xFFEAB308), // Gold
  ];

  static const List<IconData> _iconList = [
    Icons.eco,
    Icons.agriculture,
    Icons.hub_outlined,
    Icons.inventory_2_outlined,
    Icons.factory_outlined,
    Icons.local_shipping_outlined,
    Icons.business_outlined,
    Icons.account_balance_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _loadStations();
    _nameArCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _seasonCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadStations() async {
    try {
      final res = await Supabase.instance.client
          .from('stations')
          .select('id, name, code')
          .order('id');
      if (mounted) {
        setState(() {
          _stations = List<Map<String, dynamic>>.from(res);
          _loadingStations = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingStations = false);
      }
    }
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _seasonCtrl.dispose();
    _openingBalanceCtrl.dispose();
    _notesCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _formatPreviewTitle() {
    final rawName = _nameArCtrl.text.trim();
    if (rawName.isEmpty) return 'اسم المركز';
    if (_type == CostCenterType.variety) {
      final canon = CostCenter.canonicalCropName(rawName);
      final season = _seasonCtrl.text.trim();
      return season.isNotEmpty ? '$canon (موسم $season)' : canon;
    }
    return rawName;
  }

  String _formatPreviewCode() {
    final rawName = _nameArCtrl.text.trim();
    if (_type == CostCenterType.variety) {
      final canon = CostCenter.canonicalCropName(rawName);
      final slug = CostCenterHelper.resolveCropSlug(canon);
      final season = _seasonCtrl.text.trim();
      return 'CC-${slug != "CROP" ? slug : "CROP"}-${season.isNotEmpty ? season : "2026-2027"}';
    }
    return 'CC-OP-XXXX';
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;

    final nameAr = _nameArCtrl.text.trim();
    final nameEn = _nameEnCtrl.text.trim().isNotEmpty ? _nameEnCtrl.text.trim() : null;
    final season = _seasonCtrl.text.trim();
    final openingBalance = double.tryParse(_openingBalanceCtrl.text.trim()) ?? 0.0;
    final notes = _notesCtrl.text.trim();

    setState(() => _saving = true);

    try {
      final createdCenter = await CostCenterService.instance.createCostCenter(
        nameAr: nameAr,
        nameEn: nameEn,
        type: _type,
        cropName: _type == CostCenterType.variety ? nameAr : null,
        season: season.isNotEmpty ? season : '2026-2027',
        branchId: _selectedStationId,
        openingBalance: openingBalance,
        color: '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        icon: _selectedIcon.codePoint.toString(),
        notes: notes.isNotEmpty ? notes : null,
      );

      if (!mounted) return;
      widget.onSaved?.call(createdCenter);
      Navigator.pop(context, createdCenter);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                'تم إنشاء مركز التكلفة "${_formatPreviewTitle()}" بنجاح',
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
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل إنشاء مركز التكلفة: $e',
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 560 ? screenWidth * 0.95 : 560,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xB305192D) : Colors.white,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    Flexible(
                      child: ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          _buildPreviewBadge(),
                          const SizedBox(height: 16),
                          _buildTypeSelector(),
                          const SizedBox(height: 16),
                          if (_type == CostCenterType.variety) ...[
                            _buildCropField(),
                            const SizedBox(height: 14),
                            _buildSeasonField(),
                          ] else ...[
                            _buildOperationalNameFields(),
                          ],
                          const SizedBox(height: 14),
                          _buildStationSelector(),
                          const SizedBox(height: 14),
                          _buildOpeningBalanceField(),
                          const SizedBox(height: 16),
                          _buildVisualStylingSection(),
                          const SizedBox(height: 14),
                          _buildNotesField(),
                        ],
                      ),
                    ),
                    _buildButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _selectedColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _selectedColor.withValues(alpha: 0.5)),
            ),
            child: Icon(_selectedIcon, color: _selectedColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إنشاء مركز تكلفة جديد',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'تعريف مركز تكلفة محصولي أو خط تشغيلي وفقاً للمعايير المحاسبية',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: isDark ? Colors.white70 : const Color(0xFF64748B), size: 22),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBadge() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _formatPreviewTitle();
    final code = _formatPreviewCode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _selectedColor.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _selectedColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _selectedColor.withValues(alpha: isDark ? 0.25 : 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_selectedIcon, color: _selectedColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'الكود المقترح: $code  •  النوع: ${_type == CostCenterType.variety ? "خط إنتاجي محصولي" : "مركز تشغيلي"}',
                  style: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF475569),
                    fontFamily: 'Cairo',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع مركز التكلفة *',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTypeOption(
                type: CostCenterType.variety,
                title: 'خط محصول زراعي / موسمي',
                subtitle: 'مانجو، عنب، برتقال (لكل موسم)',
                icon: Icons.eco,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTypeOption(
                type: CostCenterType.operational,
                title: 'مركز تشغيلي / إداري',
                subtitle: 'محطة تعبئة، فرز، لوجستيات',
                icon: Icons.factory_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeOption({
    required CostCenterType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _type == type;
    return InkWell(
      onTap: () {
        setState(() {
          _type = type;
          if (type == CostCenterType.variety && _selectedColor == const Color(0xFF0D74CE)) {
            _selectedColor = const Color(0xFF10B981);
            _selectedIcon = Icons.eco;
          } else if (type == CostCenterType.operational && _selectedColor == const Color(0xFF10B981)) {
            _selectedColor = const Color(0xFF0D74CE);
            _selectedIcon = Icons.factory_outlined;
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: isDark ? 0.2 : 0.12)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.primary : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? (isDark ? Colors.white : AppTheme.primary)
                          : (isDark ? Colors.white70 : const Color(0xFF0F172A)),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: isDark ? Colors.white38 : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'اسم المحصول *',
          controller: _nameArCtrl,
          hint: 'مثال: مانجو، عنب، برتقال',
          isRequired: true,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'اسم المحصول مطلوب';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _cropSuggestions.map((crop) {
            final isSelected = _nameArCtrl.text.trim() == crop;
            return InkWell(
              onTap: () {
                setState(() {
                  _nameArCtrl.text = crop;
                  _selectedColor = CostCenterHelper.resolveColor(null, crop);
                  _selectedIcon = CostCenterHelper.resolveIcon(null, crop);
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary
                      : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                  ),
                ),
                child: Text(
                  crop,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF334155)),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSeasonField() {
    return AppTextField(
      label: 'الموسم الزراعي *',
      controller: _seasonCtrl,
      hint: '2026-2027',
      isRequired: true,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'الموسم مطلوب';
        return null;
      },
    );
  }

  Widget _buildOperationalNameFields() {
    return Column(
      children: [
        AppTextField(
          label: 'اسم مركز التكلفة التشغيلي *',
          controller: _nameArCtrl,
          hint: 'مثال: محطة التعبئة والتغليف، خط الفرز',
          isRequired: true,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
            return null;
          },
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'الاسم بالإنجليزية (اختياري)',
          controller: _nameEnCtrl,
          hint: 'e.g. Packing Station Line',
        ),
      ],
    );
  }

  Widget _buildStationSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المحطة / الفرع المرتبط (اختياري)',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        _loadingStations
            ? const SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                ),
              )
            : DropdownButtonFormField<int?>(
                initialValue: _selectedStationId,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF0F2238) : Colors.white,
                decoration: InputDecoration(
                  hintText: 'عام لجميع المحطات أو اختر محطة محددة',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey : const Color(0xFF64748B),
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
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('عام (لكل المحطات والعمليات)',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        )),
                  ),
                  ..._stations.map((st) {
                    final id = st['id'] as int;
                    final name = st['name']?.toString() ?? 'محطة $id';
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(name,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          )),
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _selectedStationId = v),
              ),
      ],
    );
  }

  Widget _buildOpeningBalanceField() {
    return AppTextField(
      label: 'الرصيد الافتتاحي / المدور (جنيه مصري)',
      controller: _openingBalanceCtrl,
      hint: '0',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  Widget _buildVisualStylingSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اللون والرمز المميز',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Color Palette
            Expanded(
              flex: 3,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colorPalette.map((col) {
                  final isSelected = _selectedColor.toARGB32() == col.toARGB32();
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = col),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? (isDark ? Colors.white : const Color(0xFF0F172A)) : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 8)]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 12),
            // Icon Selector
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _iconList.map((ic) {
                  final isSelected = _selectedIcon == ic;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = ic),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _selectedColor.withValues(alpha: isDark ? 0.3 : 0.15)
                            : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? _selectedColor : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                      ),
                      child: Icon(
                        ic,
                        size: 18,
                        color: isSelected
                            ? (isDark ? Colors.white : _selectedColor)
                            : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return AppTextField(
      label: 'ملاحظات / وصف المركز',
      controller: _notesCtrl,
      hint: 'تفاصيل إضافية عن النشاط أو المعايير المحاسبية',
      maxLines: 2,
    );
  }

  Widget _buildButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: AppTheme.primary.withValues(alpha: 0.3),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add, size: 18),
              label: Text(
                _saving ? 'جاري الإنشاء...' : 'إنشاء مركز التكلفة',
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
