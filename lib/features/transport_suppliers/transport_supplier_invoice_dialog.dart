import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../ui/widgets/app_text_field.dart';

class TransportSupplierInvoiceDialog extends StatefulWidget {
  final TransportSupplierModel? preselectedSupplier;
  final List<TransportSupplierModel> suppliers;

  const TransportSupplierInvoiceDialog({
    super.key,
    this.preselectedSupplier,
    this.suppliers = const [],
  });

  static Future<bool?> show(
    BuildContext context, {
    TransportSupplierModel? supplier,
    List<TransportSupplierModel> suppliers = const [],
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TransportSupplierInvoiceDialog(
        preselectedSupplier: supplier,
        suppliers: suppliers,
      ),
    );
  }

  @override
  State<TransportSupplierInvoiceDialog> createState() =>
      _TransportSupplierInvoiceDialogState();
}

class _TransportSupplierInvoiceDialogState
    extends State<TransportSupplierInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dao = TransportSupplierDao();

  late int? _selectedSupplierId;
  final _truckCountController = TextEditingController(text: '1');
  final _amountController = TextEditingController();
  final _routeFromController = TextEditingController();
  final _routeToController = TextEditingController();
  final _referenceController = TextEditingController();
  final _descController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;
  bool _isManuallyEditedDesc = false;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.preselectedSupplier?.id;
    if (_selectedSupplierId == null && widget.suppliers.isNotEmpty) {
      _selectedSupplierId = widget.suppliers.first.id;
    }
    _updateDefaultDescription(force: true);
  }

  @override
  void dispose() {
    _truckCountController.dispose();
    _amountController.dispose();
    _routeFromController.dispose();
    _routeToController.dispose();
    _referenceController.dispose();
    _descController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateDefaultDescription({bool force = false}) {
    if (_isManuallyEditedDesc && !force) return;

    final supplier = widget.suppliers.firstWhere(
      (s) => s.id == _selectedSupplierId,
      orElse: () => widget.preselectedSupplier ?? const TransportSupplierModel(name: '', createdAt: ''),
    );
    final count = double.tryParse(_truckCountController.text.trim()) ?? 1.0;
    final countFormatted = count % 1 == 0 ? count.toInt().toString() : count.toString();
    final countText = 'عدد $countFormatted ${count > 1 ? 'عربيات' : 'عربية'}';
    final from = _routeFromController.text.trim();
    final to = _routeToController.text.trim();
    final notes = _notesController.text.trim();

    String desc = 'استحقاق نقل';
    if (from.isNotEmpty || to.isNotEmpty) {
      desc += ' من ${from.isNotEmpty ? from : '—'} إلى ${to.isNotEmpty ? to : '—'}';
    } else if (supplier.name.isNotEmpty) {
      desc += ' - ${supplier.name}';
    }
    desc += ' - $countText';
    if (notes.isNotEmpty) {
      desc += ' (سيارات: $notes)';
    }

    _descController.text = desc;
  }

  Future<void> _pickDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(
                  primary: Color(0xFF00B4D8),
                  surface: Color(0xFF0F2338),
                )
              : const ColorScheme.light(
                  primary: Color(0xFF0284C7),
                  surface: Colors.white,
                  onSurface: Color(0xFF0F172A),
                ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submitInvoice() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار مقاول / مورد النقل',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final trucks = double.tryParse(_truckCountController.text.trim()) ?? 1.0;

    setState(() => _isSubmitting = true);

    try {
      final res = await _dao.recordInvoice(
        supplierId: _selectedSupplierId!,
        amount: amount,
        numberOfTrucks: trucks,
        routeFrom: _routeFromController.text.trim().isNotEmpty
            ? _routeFromController.text.trim()
            : null,
        routeTo: _routeToController.text.trim().isNotEmpty
            ? _routeToController.text.trim()
            : null,
        date: _selectedDate,
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        referenceNumber: _referenceController.text.trim().isNotEmpty
            ? _referenceController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تسجيل استحقاق النقل بنجاح بقيمة ${NumberFormat('#,##0.00').format(amount)} ج.م وقيدها محاسبياً',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['message']?.toString() ?? 'فشل تسجيل الاستحقاق',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
          setState(() => _isSubmitting = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ الفاتورة: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final primaryAccent = isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: screenWidth < 620 ? screenWidth * 0.95 : 580,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.90,
          ),
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF0A192F), Color(0xFF051322)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF00B4D8).withValues(alpha: 0.3)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.6)
                    : const Color(0xFF0F172A).withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(isDark),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    children: [
                      _buildSupplierSelector(isDark),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: AppTextField(
                              controller: _amountController,
                              label: 'المبلغ المستحق (ج.م)',
                              prefixIcon: Icon(Icons.payments_outlined,
                                  size: 20, color: primaryAccent),
                              isRequired: true,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*$')),
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'يرجى إدخال المبلغ';
                                }
                                final val = double.tryParse(v.trim());
                                if (val == null || val <= 0) {
                                  return 'المبلغ غير صالح';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: _buildTruckCountField(isDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _routeFromController,
                              label: 'موقع التحميل (من)',
                              hint: 'مثال: مزرعة الإسماعيلية',
                              prefixIcon: Icon(Icons.trip_origin_rounded,
                                  size: 18, color: primaryAccent),
                              onChanged: (_) {
                                _updateDefaultDescription();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: AppTextField(
                              controller: _routeToController,
                              label: 'وجهة الوصول (إلى)',
                              hint: 'مثال: مخزن التاج الرئيسي',
                              prefixIcon: Icon(Icons.location_on_rounded,
                                  size: 18,
                                  color: isDark ? AppTheme.accent : const Color(0xFF0D9488)),
                              onChanged: (_) {
                                _updateDefaultDescription();
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildDatePicker(isDark),
                          ),
                          const SizedBox(width: 14),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        controller: _descController,
                        label: 'بيان الاستحقاق (الوصف)',
                        prefixIcon: Icon(Icons.description_outlined,
                            size: 20, color: primaryAccent),
                        suffixIcon: IconButton(
                          tooltip: 'إعادة توليد البيان تلقائياً',
                          icon: Icon(Icons.auto_fix_high_rounded,
                              size: 18, color: primaryAccent),
                          onPressed: () {
                            setState(() {
                              _isManuallyEditedDesc = false;
                              _updateDefaultDescription(force: true);
                            });
                          },
                        ),
                        onChanged: (_) {
                          _isManuallyEditedDesc = true;
                        },
                      ),
                      const SizedBox(height: 28),
                      _buildActionButtons(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1B3A57) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF00B4D8).withValues(alpha: 0.15)
                  : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسجيل استحقاق / فاتورة نقل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'إثبات مديونية شحن ونقل وترحيل القيد المحاسبي تلقائياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierSelector(bool isDark) {
    if (widget.preselectedSupplier != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF05192D) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF1B3A57) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.local_shipping_rounded,
              color: isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مقاول / مورد النقل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    widget.preselectedSupplier!.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'الرصيد: ${NumberFormat('#,##0.00').format(widget.preselectedSupplier!.balance)} ج.م',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: AppTheme.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختيار مورد النقل *',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF05192D) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF1B3A57) : const Color(0xFFCBD5E1),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedSupplierId,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 14,
              ),
              items: widget.suppliers.map((s) {
                return DropdownMenuItem<int>(
                  value: s.id,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${NumberFormat('#,##0.00').format(s.balance)} ج.م',
                        style: TextStyle(
                          color: s.balance > 0 ? AppTheme.danger : AppTheme.success,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedSupplierId = val;
                  _updateDefaultDescription();
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTruckCountField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'عدد السيارات *',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF05192D) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF1B3A57) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.remove,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 16,
                onPressed: () {
                  final cur = double.tryParse(_truckCountController.text.trim()) ?? 1.0;
                  if (cur > 0.5) {
                    final next = cur - 1;
                    _truckCountController.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
                    _updateDefaultDescription();
                    setState(() {});
                  }
                },
              ),
              Expanded(
                child: TextFormField(
                  controller: _truckCountController,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) {
                    _updateDefaultDescription();
                    setState(() {});
                  },
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.add,
                  color: isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 16,
                onPressed: () {
                  final cur = double.tryParse(_truckCountController.text.trim()) ?? 1.0;
                  final next = cur + 1;
                  _truckCountController.text = next % 1 == 0 ? next.toInt().toString() : next.toString();
                  _updateDefaultDescription();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تاريخ الاستحقاق',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF05192D) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF1B3A57) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  color: isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  DateFormat('yyyy/MM/dd').format(_selectedDate),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'إلغاء',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitInvoice,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF00B4D8) : AppTheme.lightPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: isDark ? 4 : 1,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'حفظ وتسجيل الاستحقاق',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
