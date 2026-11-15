import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme.dart';
import '../../../data/models/treasury_model.dart';
import '../treasury_cubit.dart';
import '../treasury_state.dart';

/// نافذة منبثقة لتعديل حركة خزنة مؤكدة ومسجلة مسبقاً
/// بعد التحقق الأمني من كلمة المرور (eslam2026).
class EditConfirmedTreasuryTransactionDialog extends StatefulWidget {
  final TreasuryTransactionModel tx;
  final TreasuryLoaded state;
  final TreasuryCubit cubit;

  const EditConfirmedTreasuryTransactionDialog({
    super.key,
    required this.tx,
    required this.state,
    required this.cubit,
  });

  @override
  State<EditConfirmedTreasuryTransactionDialog> createState() =>
      _EditConfirmedTreasuryTransactionDialogState();
}

class _EditConfirmedTreasuryTransactionDialogState
    extends State<EditConfirmedTreasuryTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descController;

  late String _transactionType;
  late String _currency;
  String? _selectedCategoryId;
  String? _selectedTreasuryId;
  bool _isSaving = false;

  final List<String> _currencies = ['EGP', 'USD', 'EUR', 'SAR'];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.tx.amount.abs().toStringAsFixed(2),
    );
    _descController = TextEditingController(
      text: widget.tx.description ?? widget.tx.notes ?? '',
    );

    _transactionType = widget.tx.transactionType;
    final rawCurrency = widget.tx.currency.toUpperCase();
    _currency = _currencies.contains(rawCurrency) ? rawCurrency : 'EGP';

    _selectedCategoryId = widget.tx.categoryId;
    _selectedTreasuryId = widget.tx.treasuryId ??
        widget.state.selectedTreasury?.id ??
        (widget.state.treasuries.isNotEmpty
            ? widget.state.treasuries.first.id
            : null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _isExpense =>
      _transactionType == 'expense' ||
      _transactionType == 'withdrawal' ||
      _transactionType == 'custody_expense';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى إدخال مبلغ صحيح أكبر من الصفر',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final txId = int.tryParse(widget.tx.id ?? '');
      if (txId == null) {
        throw Exception('معرف الحركة غير صالح');
      }

      await widget.cubit.updateTransaction(
        transactionId: txId,
        amount: parsedAmount,
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        categoryId: _isExpense ? int.tryParse(_selectedCategoryId ?? '') : null,
        transactionType: _transactionType,
        treasuryId: int.tryParse(_selectedTreasuryId ?? ''),
        currency: _currency,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تحديث حركة الخزنة وإعادة احتساب الأرصدة وقيود الأستاذ العام بنجاح',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء حفظ التعديلات: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF04192F) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── الهيدر ──
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF0284C7),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                const Text(
                                  'تعديل حركة خزنة مؤكدة',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#${widget.tx.id}',
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'تعديل تفاصيل الحركة مع التحديث التلقائي لرصيد الخزنة والأستاذ العام',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppTheme.textMuted : Colors.black54,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── محتوى الفورم قابل للتمرير ──
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // معلومات القيد والجهة إن وجدت
                          if (widget.tx.journalEntryId != null ||
                              widget.tx.supplierName != null ||
                              widget.tx.customerName != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.glassBorder
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 16, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (widget.tx.journalEntryId != null)
                                          'القيد المحاسبي: #${widget.tx.journalEntryId}',
                                        if (widget.tx.supplierName != null &&
                                            widget.tx.supplierName!.isNotEmpty)
                                          'المورد: ${widget.tx.supplierName}',
                                        if (widget.tx.customerName != null &&
                                            widget.tx.customerName!.isNotEmpty)
                                          'العميل: ${widget.tx.customerName}',
                                      ].join('  •  '),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'Cairo',
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // نوع الحركة
                          const Text(
                            'نوع الحركة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildTypeChip(
                                label: 'صرف / مصروفات',
                                type: 'expense',
                                icon: Icons.arrow_upward_rounded,
                                color: AppTheme.danger,
                              ),
                              const SizedBox(width: 8),
                              _buildTypeChip(
                                label: 'إيداع / توريد',
                                type: 'deposit',
                                icon: Icons.arrow_downward_rounded,
                                color: AppTheme.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // المبلغ والعملة
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // المبلغ
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'المبلغ',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d+\.?\d{0,2}')),
                                      ],
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        prefixIcon: const Icon(
                                            Icons.attach_money_rounded,
                                            size: 18),
                                        suffixText: _currency,
                                        hintText: '0.00',
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF031628)
                                            : Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'المبلغ مطلوب';
                                        }
                                        final parsed =
                                            double.tryParse(value.trim());
                                        if (parsed == null || parsed <= 0) {
                                          return 'أدخل مبلغ أكبر من صفر';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // العملة
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'العملة',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      initialValue: _currency,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF031628)
                                            : Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      items: _currencies
                                          .map((c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(c),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _currency = val);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // الخزنة المستهدفة
                          const Text(
                            'الخزنة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedTreasuryId,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF031628)
                                  : Colors.white,
                              prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: widget.state.treasuries
                                .map((t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(t.name),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedTreasuryId = val);
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // التصنيف (في حالة الصرف)
                          if (_isExpense &&
                              widget.state.categories.isNotEmpty) ...[
                            const Text(
                              'بند / تصنيف المصروف',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: widget.state.categories
                                      .any((c) => c.id == _selectedCategoryId)
                                  ? _selectedCategoryId
                                  : null,
                              hint: const Text('اختر التصنيف',
                                  style: TextStyle(fontFamily: 'Cairo')),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF031628)
                                    : Colors.white,
                                prefixIcon: const Icon(Icons.category_outlined, size: 18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: widget.state.categories
                                  .map((cat) => DropdownMenuItem(
                                        value: cat.id,
                                        child: Text(cat.name),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() => _selectedCategoryId = val);
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // البيان / الوصف
                          const Text(
                            'البيان / الوصف',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _descController,
                            maxLines: 2,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: 'اكتب بيان أو شرح الحركة...',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF031628)
                                  : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── أزرار الحفظ والإلغاء ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? AppTheme.textMuted : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _submit,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          _isSaving ? 'جارٍ الحفظ...' : 'حفظ التعديلات',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip({
    required String label,
    required String type,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _transactionType == type ||
        (type == 'expense' && _isExpense) ||
        (type == 'deposit' && !_isExpense);

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _transactionType = type;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : AppTheme.glassBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : AppTheme.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                    color: isSelected ? color : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

