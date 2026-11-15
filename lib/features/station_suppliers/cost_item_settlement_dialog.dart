import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_expected_cost_item_model.dart';

class CostItemSettlementDialog extends StatefulWidget {
  static double computeProjectedSupplierBalance({
    required double currentBalance,
    required double enteredActualCost,
    required bool isAlreadySettled,
    double? previousActualAmount,
    bool isDualCostSupplier = true,
    double variance = 0.0,
  }) {
    if (!isDualCostSupplier) {
      return currentBalance + variance;
    }
    if (isAlreadySettled) {
      return currentBalance + (enteredActualCost - (previousActualAmount ?? 0.0));
    }
    return currentBalance + enteredActualCost;
  }
  final SupplierExpectedCostItemModel item;
  final VoidCallback onSettled;

  const CostItemSettlementDialog({
    super.key,
    required this.item,
    required this.onSettled,
  });

  static Future<void> show(
    BuildContext context, {
    required SupplierExpectedCostItemModel item,
    required VoidCallback onSettled,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CostItemSettlementDialog(
        item: item,
        onSettled: onSettled,
      ),
    );
  }

  @override
  State<CostItemSettlementDialog> createState() =>
      _CostItemSettlementDialogState();
}

class _CostItemSettlementDialogState extends State<CostItemSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final SupplierDao _dao = SupplierDao();

  late final TextEditingController _actualCostCtrl;
  late final TextEditingController _invoiceRefCtrl;
  late final TextEditingController _notesCtrl;

  bool _submitting = false;
  double _currentActualCost = 0.0;

  @override
  void initState() {
    super.initState();
    final initialActual = widget.item.actualAmount;
    _currentActualCost = initialActual ?? 0.0;
    _actualCostCtrl = TextEditingController(
      text: initialActual != null && initialActual > 0
          ? initialActual.toStringAsFixed(2)
          : '',
    );
    _invoiceRefCtrl = TextEditingController(
      text: widget.item.invoiceRef ?? '',
    );
    _notesCtrl = TextEditingController(
      text: widget.item.settlementNotes ?? '',
    );

    _actualCostCtrl.addListener(_onCostChanged);
  }

  void _onCostChanged() {
    final text = _actualCostCtrl.text.trim();
    final val = double.tryParse(text) ?? 0.0;
    if (val != _currentActualCost) {
      setState(() {
        _currentActualCost = val;
      });
    }
  }

  bool get _hasEnteredActualCost => _actualCostCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _actualCostCtrl.removeListener(_onCostChanged);
    _actualCostCtrl.dispose();
    _invoiceRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _variance => _hasEnteredActualCost
      ? (_currentActualCost - widget.item.expectedAmount)
      : 0.0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final res = await _dao.settleCostItem(
        costItemId: widget.item.costItemId,
        actualAmount: _currentActualCost,
        invoiceRef: _invoiceRefCtrl.text.trim().isEmpty
            ? null
            : _invoiceRefCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        final success = res['success'] == true;
        if (success) {
          DataChangeEventBus.instance.notifySuppliersChanged();
          DataChangeEventBus.instance.notifyPackingOrdersChanged();

          Navigator.of(context).pop();
          widget.onSettled();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      res['message']?.toString() ??
                          'تمت تسوية التكلفة الفعلية وتحديث الأرباح بنجاح',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['error']?.toString() ?? 'فشلت عملية التسوية',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء التسوية: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final item = widget.item;
    final variance = _variance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxWidth: 620),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 120 : 30),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withAlpha(150)
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: Color(0xFF0D9488), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.isActual
                                ? 'تعديل تسوية التكلفة الفعلية'
                                : 'تسوية التكلفة الفعلية (Actual Settlement)',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'أمر تعبئة: #${item.orderNumber} • بند: ${item.itemName}',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Body Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Supplier Info Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.supplierType == 'station'
                                    ? Icons.factory_rounded
                                    : Icons.assignment_turned_in_rounded,
                                color: item.supplierType == 'station'
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF8B5CF6),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'المورد: ${item.supplierName ?? "غير محدد"} ${item.supplierCode != null ? "(${item.supplierCode})" : ""}',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B),
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: item.isActual
                                      ? AppTheme.success.withAlpha(25)
                                      : AppTheme.warning.withAlpha(25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: item.isActual
                                        ? AppTheme.success.withAlpha(80)
                                        : AppTheme.warning.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  item.isActual ? 'مسوى فعلياً ✓' : 'تقديري ⏳',
                                  style: TextStyle(
                                    color: item.isActual
                                        ? AppTheme.success
                                        : AppTheme.warning,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Cost Inputs Section
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Expected Cost (Read-Only)
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'التكلفة التقديرية (المسجلة)',
                                          style: TextStyle(
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B),
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B)
                                                .withAlpha(20),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'تقديري',
                                            style: TextStyle(
                                              color: Color(0xFFF59E0B),
                                              fontFamily: 'Cairo',
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${AppUtils.formatCurrency(item.expectedAmount)} ج.م',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (item.displayQuantity > 0 && item.displayUnitPrice > 0) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        'الكمية: ${item.displayQuantity.toStringAsFixed(item.displayQuantity.truncateToDouble() == item.displayQuantity ? 0 : 2)} × ${AppUtils.formatCurrency(item.displayUnitPrice)} ج.م',
                                        style: TextStyle(
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Actual Cost Input
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'التكلفة الفعلية (ج.م) *',
                                        style: TextStyle(
                                          color: isDark
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF334155),
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (item.expectedAmount > 0)
                                        InkWell(
                                          onTap: () {
                                            _actualCostCtrl.text = item
                                                .expectedAmount
                                                .toStringAsFixed(2);
                                            _actualCostCtrl.selection =
                                                TextSelection.fromPosition(
                                              TextPosition(
                                                  offset: _actualCostCtrl
                                                      .text.length),
                                            );
                                          },
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.copy_rounded,
                                                    size: 11,
                                                    color: Color(0xFF0D9488)),
                                                SizedBox(width: 3),
                                                Text(
                                                  'مطابقة التقديري',
                                                  style: TextStyle(
                                                    color: Color(0xFF0D9488),
                                                    fontFamily: 'Cairo',
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _actualCostCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d+\.?\d{0,2}')),
                                    ],
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      hintText: item.expectedAmount > 0
                                          ? AppUtils.formatCurrency(
                                              item.expectedAmount)
                                          : '0.00',
                                      suffixText: 'ج.م',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF0D9488),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'يرجى إدخال التكلفة الفعلية';
                                      }
                                      final num = double.tryParse(v.trim());
                                      if (num == null || num < 0) {
                                        return 'قيمة غير صالحة';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Invoice Reference Input
                        Text(
                          'رقم الفاتورة / إشعار المحطة (Invoice Reference)',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF334155),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _invoiceRefCtrl,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            hintText: 'مثال: INV-2026-884 أو إشعار تسوية 12',
                            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Settlement Notes
                        Text(
                          'ملاحظات التسوية والتسجيل',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF334155),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            hintText: 'أي تفاصيل أو بنود تسوية تم الاتفاق عليها مع المحطة/المورد...',
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Variance & Profitability Live Preview Box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: !_hasEnteredActualCost || variance == 0
                                ? (isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9))
                                : (variance > 0
                                    ? const Color(0xFFEF4444).withAlpha(18)
                                    : const Color(0xFF10B981).withAlpha(18)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !_hasEnteredActualCost || variance == 0
                                  ? (isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1))
                                  : (variance > 0
                                      ? const Color(0xFFEF4444).withAlpha(80)
                                      : const Color(0xFF10B981).withAlpha(80)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    !_hasEnteredActualCost
                                        ? Icons.info_outline_rounded
                                        : (variance == 0
                                            ? Icons.check_circle_outline_rounded
                                            : (variance > 0
                                                ? Icons.trending_down_rounded
                                                : Icons.trending_up_rounded)),
                                    color: !_hasEnteredActualCost || variance == 0
                                        ? (isDark
                                            ? Colors.white70
                                            : const Color(0xFF475569))
                                        : (variance > 0
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF10B981)),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Builder(builder: (context) {
                                    final isDualCost = SupplierModel.isEgpOnlyCategoryOrCode(
                                          item.supplierType,
                                          item.supplierCode,
                                        ) ||
                                        item.category.toLowerCase() == 'station' ||
                                        item.category.toLowerCase() == 'deduction' ||
                                        item.category.toLowerCase() == 'deductions';
                                    return Text(
                                      isDualCost
                                          ? 'مؤشر الانحراف التحليلي وأثره على الربحية:'
                                          : 'أثر التسوية على الأرباح ومستحقات المورد:',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    );
                                  }),
                                  const Spacer(),
                                  Text(
                                    !_hasEnteredActualCost
                                        ? '0.00 ج.م'
                                        : '${variance > 0 ? "+" : ""}${AppUtils.formatCurrency(variance)} ج.م',
                                    style: TextStyle(
                                      color: !_hasEnteredActualCost || variance == 0
                                          ? (isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A))
                                          : (variance > 0
                                              ? const Color(0xFFEF4444)
                                              : const Color(0xFF10B981)),
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Builder(builder: (context) {
                                final isDualCost = SupplierModel.isEgpOnlyCategoryOrCode(
                                      item.supplierType,
                                      item.supplierCode,
                                    ) ||
                                    item.category.toLowerCase() == 'station' ||
                                    item.category.toLowerCase() == 'deduction' ||
                                    item.category.toLowerCase() == 'deductions';
                                final isAlreadySettled = item.isActual &&
                                    item.actualAmount != null &&
                                    (item.reconciledAt != null || item.varianceJournalEntryId != null);
                                final double projectedBalance =
                                    CostItemSettlementDialog.computeProjectedSupplierBalance(
                                  currentBalance: item.supplierOutstandingBalance ?? 0.0,
                                  enteredActualCost: _currentActualCost,
                                  isAlreadySettled: isAlreadySettled,
                                  previousActualAmount: item.actualAmount,
                                  isDualCostSupplier: isDualCost,
                                  variance: variance,
                                );

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      !_hasEnteredActualCost
                                          ? (isDualCost
                                              ? 'أدخل التكلفة الفعلية المعتمدة أعلاه؛ يُضاف للمورد المبلغ الفعلي فقط ويظل الانحراف مؤشراً تحليلياً.'
                                              : 'أدخل التكلفة الفعلية أعلاه أو اضغط على "مطابقة التقديري" لمعاينة أثر الفروقات على الأرباح ورصيد المورد.')
                                          : (variance == 0
                                              ? (isDualCost
                                                  ? 'التكلفة الفعلية مطابقة للتقديري: سيتم اعتماد المبلغ الفعلي فقط (${AppUtils.formatCurrency(_currentActualCost)} ج.م) في حساب المورد دون أي فروقات.'
                                                  : 'التكلفة الفعلية مطابقة تماماً للتكلفة التقديرية المسجلة، لا توجد أي فروقات على الأرباح أو رصيد المورد.')
                                              : (isDualCost
                                                  ? (variance > 0
                                                      ? '⚠️ انحراف بالزيادة عن التقديري بمقدار ${AppUtils.formatCurrency(variance)} ج.م (بيان تحليلي والربحية فقط) — يُرحّل للمورد صافي الفعلي (${AppUtils.formatCurrency(_currentActualCost)} ج.م) فقط.'
                                                      : '✅ وفر عن التقديري بمقدار ${AppUtils.formatCurrency(variance.abs())} ج.م (بيان تحليلي والربحية فقط) — يُرحّل للمورد صافي الفعلي (${AppUtils.formatCurrency(_currentActualCost)} ج.م) فقط دون خصم أو إضافة للانحراف.')
                                                  : (variance > 0
                                                      ? '⚠️ التكلفة الفعلية أكبر من التقديرية بمقدار ${AppUtils.formatCurrency(variance)} ج.م: سيتم زيادة مستحقات المورد وتخفيض صافي ربح الشحنات المصدرة تلقائياً.'
                                                      : '✅ وفر في التكلفة بمقدار ${AppUtils.formatCurrency(variance.abs())} ج.م: سيتم تخفيض مستحقات المورد وزيادة صافي ربح الشحنات المصدرة تلقائياً.'))),
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFCBD5E1)
                                            : const Color(0xFF334155),
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (item.supplierOutstandingBalance != null &&
                                        _hasEnteredActualCost &&
                                        (isDualCost ? _currentActualCost > 0 : variance != 0)) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF0F172A).withAlpha(150) : Colors.white.withAlpha(200),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.account_balance_wallet_outlined,
                                                size: 14,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'رصيد المورد الحالي: ${AppUtils.formatCurrency(item.supplierOutstandingBalance!)} ج.م  ←  بعد اعتماد الفعلي: ${AppUtils.formatCurrency(projectedBalance)} ج.م',
                                                style: TextStyle(
                                                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              }),

                              if (item.linkedShipments.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                Text(
                                  'الشحنات التصديرية المرتبطة التي سيتم تحديث أرباحها (${item.linkedShipments.length}):',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: item.linkedShipments.map((s) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF0F172A)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      child: Text(
                                        'شحنة #${s['shipment_no'] ?? s['shipment_id']}',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Footer Actions
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withAlpha(150)
                      : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _submitting ? null : () => Navigator.of(context).pop(),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded,
                              size: 18, color: Colors.white),
                      label: Text(
                        item.isActual ? 'حفظ تعديل التسوية' : 'اعتماد وتسوية التكلفة',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
