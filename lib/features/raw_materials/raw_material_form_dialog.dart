import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/tenant_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/exchange_rate_dao.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/station_model.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_dropdown.dart';

class RawMaterialFormDialog extends StatefulWidget {
  final RawMaterialModel? item;
  const RawMaterialFormDialog({super.key, this.item});

  @override
  State<RawMaterialFormDialog> createState() => _RawMaterialFormDialogState();
}

class _RawMaterialFormDialogState extends State<RawMaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dao = RawMaterialDao();
  final _client = Supabase.instance.client;

  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _initialQtyController;
  late final TextEditingController _initialPriceController;
  late final TextEditingController _exchangeRateController;
  late final FocusNode _nameFocus;

  String _unit = 'piece';
  String? _currency;
  String? _categoryId;
  int? _selectedStationId;
  bool _saving = false;
  bool _loadingCategories = true;
  bool _loadingStations = true;

  List<Map<String, dynamic>> _categories = [];
  List<StationModel> _stations = [];

  static const _units = ['piece', 'kg', 'box', 'roll', 'bag', 'meter', 'liter'];
  static const _unitLabels = {
    'piece': 'قطعة', 'kg': 'كجم', 'box': 'كرتونة',
    'roll': 'لفة', 'bag': 'كيس', 'meter': 'متر', 'liter': 'لتر',
  };
  static const _currencies = ['EGP', 'USD', 'EUR', 'GBP'];
  static const _currencyLabels = {
    'EGP': 'جنيه مصري', 'USD': 'دولار', 'EUR': 'يورو', 'GBP': 'جنيه إسترليني',
  };

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _nameController = TextEditingController();
    _initialQtyController = TextEditingController();
    _initialPriceController = TextEditingController();
    _exchangeRateController = TextEditingController();
    _nameFocus = FocusNode();

    if (_isEditing) {
      final item = widget.item!;
      _codeController.text = item.code;
      _nameController.text = item.name;
      _unit = item.unit;
      _currency = item.currency;
      _categoryId = item.categoryId;
      _initialQtyController.text = item.initialQuantity > 0 ? item.initialQuantity.toStringAsFixed(0) : '';
      _initialPriceController.text = item.initialAvgPrice > 0 ? item.initialAvgPrice.toStringAsFixed(2) : '';
    } else {
      _generateCode();
    }

    _loadCategories();
    _loadStations();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await _client.from('raw_material_categories').select('id, name').order('name');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data);
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadStations() async {
    try {
      final stations = await StationDao().getAll();
      if (mounted) {
        setState(() {
          _stations = stations;
          _loadingStations = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _generateCode() async {
    final code = await _dao.generateCode();
    debugPrint('RawMaterialForm: generated code = $code');
    if (mounted) {
      setState(() => _codeController.text = code);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _initialQtyController.dispose();
    _initialPriceController.dispose();
    _exchangeRateController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_currency == null || _currency!.isEmpty) return;
    setState(() => _saving = true);

    try {
      final trimmedName = _nameController.text.trim();
      final isDuplicate = await _dao.isNameExists(
        trimmedName,
        excludeId: widget.item?.id,
      );
      if (isDuplicate) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'لا يمكن إضافة مادة تعبئة بهذا الاسم لأنها موجودة بالفعل.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      if (_isEditing) {
        final item = RawMaterialModel(
          id: widget.item?.id,
          code: _codeController.text.trim(),
          name: trimmedName,
          unit: _unit,
          currency: _currency!,
          categoryId: _categoryId,
          minimumStock: 3000,
          defaultPurchasePrice: widget.item?.defaultPurchasePrice ?? 0,
          initialQuantity: widget.item?.initialQuantity ?? 0,
          initialAvgPrice: widget.item?.initialAvgPrice ?? 0,
        );
        await _dao.update(item);
      } else {
        final initialQty = double.tryParse(_initialQtyController.text.trim()) ?? 0;
        final initialPrice = double.tryParse(_initialPriceController.text.trim()) ?? 0;
        final hasQty = initialQty > 0;
        final hasPrice = initialPrice > 0;
        final hasStation = _selectedStationId != null;

        String? errorMsg;
        if (hasQty && !hasPrice) {
          errorMsg = 'أدخل سعر الوحدة المبدأي';
        } else if (!hasQty && hasPrice) {
          errorMsg = 'أدخل الكمية المبدأية';
        } else if (hasStation && !hasQty && !hasPrice) {
          errorMsg = 'أدخل الكمية والسعر المبدأيين';
        } else if (hasQty && hasPrice && !hasStation) {
          errorMsg = 'اختر المحطة اللي الرصيد المبدأي موجود فيها';
        }

        if (errorMsg != null) {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(errorMsg, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                ],
              ),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }

        final item = RawMaterialModel(
          code: _codeController.text.trim(),
          name: trimmedName,
          unit: _unit,
          currency: _currency!,
          categoryId: _categoryId,
          minimumStock: 3000,
        );
        final newId = await _dao.insert(item);

        if (initialQty > 0 && _selectedStationId != null) {
          final name = '$trimmedName (مادة تعبئة)';
          final code = _codeController.text.trim();
          final stationId = _selectedStationId!;

          final existingSp = await _client
              .from('station_products')
              .select('id, quantity')
              .eq('station_id', stationId)
              .eq('raw_material_id', newId)
              .maybeSingle();

          if (existingSp != null) {
            await _client.from('station_products').update({
              'quantity': (existingSp['quantity'] as num? ?? 0) + initialQty.toInt(),
              'product_name': name,
              'product_code': code,
              'item_type': 'material',
            }).eq('id', existingSp['id']);
          } else {
            await _client.from('station_products').insert({
              'station_id': stationId,
              'product_name': name,
              'product_code': code,
              'quantity': initialQty.toInt(),
              'item_type': 'material',
              'raw_material_id': newId,
            });
          }

          final customRate = _currency == 'EGP'
              ? 1.0
              : (double.tryParse(_exchangeRateController.text.trim()) ?? 1.0);

          await _client.from('station_product_batches').insert({
            'station_id': stationId,
            'product_name': name,
            'product_code': code,
            'quantity': initialQty.toInt(),
            'remaining_quantity': initialQty.toInt(),
            'unit_cost': initialPrice,
            'source_type': 'opening',
            'source_date': DateTime.now().toIso8601String().substring(0, 10),
            'exchange_rate': customRate,
            'currency': _currency,
            'supplier_name': '',
            'item_type': 'material',
            'raw_material_id': newId,
          });

          await _client.from('stock_batches').insert({
            'batch_number': 'OPENING-${DateTime.now().millisecondsSinceEpoch}',
            'product_id': newId,
            'quantity': initialQty,
            'remaining_quantity': initialQty,
            'purchase_cost': initialPrice,
            'average_cost': initialPrice,
            'exchange_rate': customRate,
            'currency': _currency,
            'status': 'active',
            'user_id': _client.auth.currentUser?.id,
          });

          await _client.from('raw_materials').update({
            'quantity': initialQty,
            'default_purchase_price': initialPrice,
          }).eq('id', newId);

          try {
            await _client.from('raw_materials').update({
              'initial_quantity': initialQty,
              'initial_avg_price': initialPrice,
            }).eq('id', newId);
          } catch (e) {
            debugPrint('⚠️ raw_material_form: Failed to update initial quantity/price: $e');
          }

          try {
            final tenantId = TenantService().tenantId;
            final glRes = await _client.rpc('rpc_record_raw_material_opening_gl', params: {
              'p_raw_material_id': newId,
              'p_quantity': initialQty,
              'p_unit_price': initialPrice,
              'p_currency': _currency,
              'p_exchange_rate': customRate,
              if (tenantId != null) 'p_company_id': tenantId,
            });
            debugPrint('✅ raw_material_form: Posted Opening GL Entry with custom rate ($customRate): $glRes');
          } catch (e) {
            debugPrint('⚠️ raw_material_form: Failed to post Opening GL Entry: $e');
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isEditing ? 'تم تعديل المادة الخام بنجاح' : 'تم إضافة المادة الخام بنجاح',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.message.contains('duplicate key') || e.message.contains('23505')
          ? 'خطأ: هذا الكود موجود من قبل'
          : 'فشل الحفظ: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14))),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('فشل الحفظ: $e', style: const TextStyle(fontFamily: 'Cairo', fontSize: 14))),
            ],
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

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 520,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: const BoxDecoration(
              color: Color(0xB305192D),
              borderRadius: BorderRadius.all(Radius.circular(24)),
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
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                        children: [
                          const SizedBox(height: 20),
                          AppTextField(
                            label: 'كود المادة',
                            controller: _codeController,
                            hint: '1',
                            readOnly: _isEditing,
                            isRequired: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'كود المادة مطلوب';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'اسم المادة',
                            controller: _nameController,
                            focusNode: _nameFocus,
                            hint: 'أدخل اسم المادة الخام',
                            isRequired: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppDropdown<String>(
                            label: 'العملة',
                            hint: 'اختر العملة',
                            isRequired: true,
                            selectedItem: _currency,
                            items: _currencies,
                            itemAsString: (c) => _currencyLabels[c] ?? c,
                            validator: (v) => v == null ? 'يرجى اختيار العملة' : null,
                            onChanged: (v) async {
                              setState(() => _currency = v);
                              if (v != null && v != 'EGP') {
                                try {
                                  final rate = await ExchangeRateDao().getRate(v);
                                  if (rate > 0 && mounted) {
                                    _exchangeRateController.text = rate.toStringAsFixed(2);
                                  }
                                } catch (_) {}
                              } else {
                                _exchangeRateController.clear();
                              }
                            },
                          ),
                          if (_currency != null && _currency != 'EGP' && !_isEditing) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Text('سعر الصرف', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 13)),
                                const SizedBox(width: 4),
                                const Text('*', style: TextStyle(color: AppTheme.danger, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _exchangeRateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}$')),
                              ],
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'أدخل سعر الصرف';
                                final val = double.tryParse(v.trim());
                                if (val == null || val <= 0) return 'قيمة غير صالحة';
                                return null;
                              },
                              decoration: InputDecoration(
                                hintText: 'مثال: 50.00',
                                hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.accent),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.danger),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.danger),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'سعر صرف العملة مقابل الجنيه المصري',
                              style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 11),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: AppDropdown<String>(
                                  label: 'الوحدة',
                                  selectedItem: _unit,
                                  items: _units,
                                  itemAsString: (u) => _unitLabels[u] ?? u,
                                  onChanged: (v) {
                                    if (v != null) setState(() => _unit = v);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'الفئة *',
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo'),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_loadingCategories)
                                      const SizedBox(
                                        height: 48,
                                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                      )
                                    else
                                      DropdownButtonFormField<String>(
                                        initialValue: _categoryId,
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF0A2340),
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: AppTheme.glassBorder),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: AppTheme.glassBorder),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: AppTheme.accent),
                                          ),
                                        ),
                                        hint: const Text('اختر الفئة', style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                                        items: _categories.map((c) {
                                          return DropdownMenuItem<String>(
                                            value: c['id'].toString(),
                                            child: Text(c['name']?.toString() ?? '', style: const TextStyle(fontFamily: 'Cairo')),
                                          );
                                        }).toList(),
                                        onChanged: (v) => setState(() => _categoryId = v),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'الفئة مطلوبة';
                                          return null;
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (!_isEditing) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 18, color: AppTheme.accent),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'الرصيد المبدأي (اختياري)',
                                          style: TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'أدخل الكمية والسعر الموجودين قبل تشغيل النظام',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo'),
                                  ),
                                   const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AppTextField(
                                          label: 'الكمية المبدأية',
                                          controller: _initialQtyController,
                                          hint: '0',
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: AppTextField(
                                          label: 'سعر الوحدة المبدأي',
                                          controller: _initialPriceController,
                                          hint: '0.00',
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  if (_loadingStations)
                                    const SizedBox(
                                      height: 48,
                                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                    )
                                  else
                                    DropdownButtonFormField<int>(
                                      initialValue: _selectedStationId,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF0A2340),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: AppTheme.glassBorder),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: AppTheme.glassBorder),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: AppTheme.accent),
                                        ),
                                      ),
                                      hint: const Text('اختر المحطة *', style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
                                      items: _stations.where((s) => s.isActive).map((s) {
                                        return DropdownMenuItem<int>(
                                          value: int.tryParse(s.id ?? ''),
                                          child: Text(s.name, style: const TextStyle(fontFamily: 'Cairo')),
                                        );
                                      }).toList(),
                                      onChanged: (v) => setState(() => _selectedStationId = v),
                                      validator: (v) {
                                        final qty = double.tryParse(_initialQtyController.text.trim()) ?? 0;
                                        if (qty > 0 && (v == null)) return 'اختر المحطة';
                                        return null;
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isEditing ? Icons.edit_outlined : Icons.add_box_outlined,
              color: AppTheme.accent, size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? 'تعديل مادة خام' : 'إضافة مادة خام جديدة',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 12,
        overflowSpacing: 12,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              shadowColor: AppTheme.accent.withValues(alpha: 0.3),
            ),
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_isEditing ? Icons.save_outlined : Icons.add, size: 18),
            label: Text(
              _saving ? 'جاري الحفظ...' : _isEditing ? 'حفظ التعديلات' : 'إضافة المادة',
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}