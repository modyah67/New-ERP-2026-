import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme.dart';
import '../../../data/models/bank_account_transaction_model.dart';
import '../bank_accounts_cubit.dart';
import '../bank_accounts_state.dart';

/// نافذة منبثقة لتعديل حركة حساب بنكي مؤكدة ومسجلة مسبقاً
/// بعد التحقق الأمني من كلمة المرور (eslam2026).
class EditConfirmedBankTransactionDialog extends StatefulWidget {
  final BankAccountTransactionModel tx;
  final BankAccountsLoaded state;
  final BankAccountsCubit cubit;

  const EditConfirmedBankTransactionDialog({
    super.key,
    required this.tx,
    required this.state,
    required this.cubit,
  });

  @override
  State<EditConfirmedBankTransactionDialog> createState() =>
      _EditConfirmedBankTransactionDialogState();
}

class _EditConfirmedBankTransactionDialogState
    extends State<EditConfirmedBankTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descController;

  late String _transactionType;
  late int _selectedAccountId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.tx.amount.abs().toStringAsFixed(2),
    );
    _descController = TextEditingController(
      text: widget.tx.description ?? '',
    );

    _transactionType = widget.tx.type;
    _selectedAccountId = widget.tx.bankAccountId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _isDeposit =>
      _transactionType == 'deposit' ||
      _transactionType == 'currency_exchange_in' ||
      _transactionType == 'receipt';

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
      await widget.cubit.updateTransaction(
        transactionId: widget.tx.id,
        newAmount: parsedAmount,
        newDescription: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        newType: _transactionType,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تحديث الحركة البنكية وإعادة احتساب الأرصدة وقيود الأستاذ العام بنجاح',
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

    final currentAccount = widget.state.accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => widget.state.accounts.first,
    );

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
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
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
                          color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.account_balance_rounded,
                          color: Color(0xFF14B8A6),
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
                                  'تعديل حركة بنكية مؤكدة',
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
                                    color: AppTheme.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#${widget.tx.journalEntryId ?? widget.tx.id}',
                                    style: const TextStyle(
                                      color: AppTheme.accent,
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
                              'تعديل بيانات الحركة مع التحديث التلقائي لرصيد الحساب البنكي والأستاذ العام',
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

                  // ── محتوى الفورم ──
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // معلومات القيد والجهة إن وجدت
                          if (widget.tx.journalEntryId != null ||
                              widget.tx.relatedPartyName != null) ...[
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
                                      size: 16, color: AppTheme.accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (widget.tx.journalEntryId != null)
                                          'القيد المحاسبي: #${widget.tx.journalEntryId}',
                                        if (widget.tx.relatedPartyName != null &&
                                            widget.tx.relatedPartyName!.isNotEmpty)
                                          'الجهة المرتبطة: ${widget.tx.relatedPartyName}',
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
                                label: 'إيداع بنكي',
                                type: 'deposit',
                                icon: Icons.arrow_downward_rounded,
                                color: const Color(0xFF14B8A6),
                              ),
                              const SizedBox(width: 8),
                              _buildTypeChip(
                                label: 'صرف / تحويل',
                                type: 'withdraw',
                                icon: Icons.arrow_upward_rounded,
                                color: const Color(0xFFEC4899),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // المبلغ
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
                              suffixText: currentAccount.currency,
                              hintText: '0.00',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF031628)
                                  : Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'المبلغ مطلوب';
                              }
                              final parsed = double.tryParse(value.trim());
                              if (parsed == null || parsed <= 0) {
                                return 'أدخل مبلغ أكبر من صفر';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // الحساب البنكي
                          const Text(
                            'الحساب البنكي',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedAccountId,
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
                              prefixIcon: const Icon(Icons.account_balance_outlined, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: widget.state.accounts
                                .map((acc) => DropdownMenuItem(
                                      value: acc.id,
                                      child: Text('${acc.name} (${acc.currency})'),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedAccountId = val);
                              }
                            },
                          ),
                          const SizedBox(height: 16),

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
                              hintText: 'اكتب بيان أو شرح الحركة البنكية...',
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
                          backgroundColor: const Color(0xFF14B8A6),
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
    final isSelected = (_transactionType == type) ||
        (type == 'deposit' && _isDeposit) ||
        (type == 'withdraw' && !_isDeposit);

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

