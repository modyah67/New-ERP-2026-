import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/bank_account_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/models/bank_account_model.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../data/models/treasury_model.dart';
import '../../core/data_change_event_bus.dart';
import '../../ui/widgets/app_text_field.dart';

class TransportSupplierPaymentDialog extends StatefulWidget {
  final TransportSupplierModel supplier;

  const TransportSupplierPaymentDialog({
    super.key,
    required this.supplier,
  });

  @override
  State<TransportSupplierPaymentDialog> createState() =>
      _TransportSupplierPaymentDialogState();
}

class _TransportSupplierPaymentDialogState
    extends State<TransportSupplierPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _notesController = TextEditingController();

  final _transportDao = TransportSupplierDao();
  final _treasuryDao = TreasuryDao();
  final _bankDao = BankAccountDao();

  String _sourceType = 'treasury'; // 'treasury' or 'bank'
  int? _selectedSourceId;
  DateTime _paymentDate = DateTime.now();

  bool _isLoadingSources = true;
  bool _isSubmitting = false;

  List<TreasuryModel> _treasuries = [];
  List<BankAccountModel> _bankAccounts = [];

  @override
  void initState() {
    super.initState();
    _descController.text =
        'سداد دفعة لمورد النقل: ${widget.supplier.name}';
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoadingSources = true);
    try {
      final tList = await _treasuryDao.getAll();
      final bList = await _bankDao.getAll();

      if (mounted) {
        setState(() {
          _treasuries = tList;
          _bankAccounts = bList;
          if (_sourceType == 'treasury' && _treasuries.isNotEmpty) {
            _selectedSourceId = int.tryParse(_treasuries.first.id ?? '');
          } else if (_sourceType == 'bank' && _bankAccounts.isNotEmpty) {
            _selectedSourceId = _bankAccounts.first.id;
          }
          _isLoadingSources = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSources = false);
      }
    }
  }

  double get _currentAvailableBalance {
    if (_sourceType == 'treasury') {
      try {
        final t = _treasuries.firstWhere(
          (e) => int.tryParse(e.id ?? '') == _selectedSourceId,
        );
        return t.getBalance('EGP')?.balance ?? (t.balances.isNotEmpty ? t.balances.first.balance : 0.0);
      } catch (_) {
        return 0.0;
      }
    } else {
      try {
        final b = _bankAccounts.firstWhere(
          (e) => e.id == _selectedSourceId,
        );
        return b.balance;
      } catch (_) {
        return 0.0;
      }
    }
  }

  Future<void> _submitPayment() async {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSourceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار مصدر الدفع',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المبلغ يجب أن يكون أكبر من الصفر',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (amount > _currentAvailableBalance) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F2338),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
              SizedBox(width: 8),
              Text('تنبيه الرصيد',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ],
          ),
          content: Text(
            'المبلغ المطلوب صرفه (${amount.toStringAsFixed(2)} ج.م) يتجاوز الرصيد المتوفر في المصدر المختار (${_currentAvailableBalance.toStringAsFixed(2)} ج.م). هل ترغب في المتابعة؟',
            style: const TextStyle(
                fontFamily: 'Cairo', color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
              child: const Text('متابعة الصرف',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.black)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await _transportDao.recordPayment(
        supplierId: widget.supplier.id!,
        sourceType: _sourceType,
        sourceId: _selectedSourceId!,
        amount: amount,
        date: _paymentDate,
        description: _descController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      if (res['success'] == true) {
        DataChangeEventBus.instance.notifyTransportSuppliersChanged();
        DataChangeEventBus.instance.notifyAccountsChanged();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  'تم تسجيل سند الصرف بنجاح بمبلغ ${amount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        throw Exception(res['error'] ?? 'حدث خطأ غير متوقع');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تسجيل سند الصرف: $e',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
          backgroundColor: AppTheme.danger,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 580 ? screenWidth * 0.95 : 540,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.90),
            decoration: const BoxDecoration(
              color: Color(0xB305192D),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        _buildSupplierSummaryCard(),
                        const SizedBox(height: 18),
                        _buildSourceTypeSelector(),
                        const SizedBox(height: 14),
                        if (_isLoadingSources)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          _buildSourceDropdown(),
                        const SizedBox(height: 18),
                        AppTextField(
                          controller: _amountController,
                          label: 'المبلغ المراد صرفه (ج.م)',
                          prefixIcon: const Icon(Icons.payments_outlined, size: 20, color: AppTheme.accent),
                          isRequired: true,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
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
                        const SizedBox(height: 18),
                        _buildDatePicker(),
                        const SizedBox(height: 18),
                        AppTextField(
                          controller: _descController,
                          label: 'بيان السند (الوصف)',
                          prefixIcon: const Icon(Icons.description_outlined, size: 20, color: AppTheme.accent),
                        ),
                        const SizedBox(height: 18),
                        AppTextField(
                          controller: _notesController,
                          label: 'ملاحظات إضافية',
                          prefixIcon: const Icon(Icons.note_outlined, size: 20, color: AppTheme.accent),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 28),
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accent.withAlpha(50),
                  AppTheme.accent.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.accent.withAlpha(100),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.payment_outlined,
              color: AppTheme.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إضافة سند صرف / سداد دفعة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  'صرف مستحقات أو دفعات مقدمة لمقاول النقل',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierSummaryCard() {
    final balance = widget.supplier.balance;
    final isCredit = balance > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2338),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.supplier.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (widget.supplier.phone.isNotEmpty)
                  Text(
                    widget.supplier.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isCredit ? 'مستحق له (دائن)' : 'مقدمات عليه (مدين)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: isCredit ? AppTheme.warning : AppTheme.accent,
                ),
              ),
              Text(
                '${balance.abs().toStringAsFixed(2)} ج.م',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isCredit ? AppTheme.warning : AppTheme.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _sourceType = 'treasury';
                if (_treasuries.isNotEmpty) {
                  _selectedSourceId = int.tryParse(_treasuries.first.id ?? '');
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: _sourceType == 'treasury'
                    ? AppTheme.primary.withAlpha(50)
                    : const Color(0xFF0F2338),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _sourceType == 'treasury'
                      ? AppTheme.primary
                      : AppTheme.glassBorder,
                  width: _sourceType == 'treasury' ? 1.5 : 1,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'خزينة نقدية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _sourceType = 'bank';
                if (_bankAccounts.isNotEmpty) {
                  _selectedSourceId = _bankAccounts.first.id;
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: _sourceType == 'bank'
                    ? AppTheme.accent.withAlpha(50)
                    : const Color(0xFF0F2338),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _sourceType == 'bank'
                      ? AppTheme.accent
                      : AppTheme.glassBorder,
                  width: _sourceType == 'bank' ? 1.5 : 1,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_outlined,
                      color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'حساب بنكي',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceDropdown() {
    final available = _currentAvailableBalance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F2338),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedSourceId,
              isExpanded: true,
              dropdownColor: const Color(0xFF05192D),
              style: const TextStyle(
                  fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
              items: _sourceType == 'treasury'
                  ? _treasuries.map((t) {
                      final id = int.tryParse(t.id ?? '') ?? 0;
                      final bal = t.getBalance('EGP')?.balance ?? (t.balances.isNotEmpty ? t.balances.first.balance : 0.0);
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${bal.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                  color: AppTheme.accent, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList()
                  : _bankAccounts.map((b) {
                      return DropdownMenuItem<int>(
                        value: b.id,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${b.name} (${b.currency})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${b.balance.toStringAsFixed(2)} ${b.currency}',
                              style: const TextStyle(
                                  color: AppTheme.accent, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedSourceId = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'الرصيد المتاح في المصدر:',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${available.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: available > 0 ? AppTheme.success : AppTheme.danger,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2338),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تاريخ السند: ${_paymentDate.year}/${_paymentDate.month.toString().padLeft(2, '0')}/${_paymentDate.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontFamily: 'Cairo', color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _paymentDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: AppTheme.primary,
                      surface: Color(0xFF0F2338),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() => _paymentDate = picked);
              }
            },
            child: const Text('تغيير',
                style: TextStyle(fontFamily: 'Cairo', color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'إلغاء',
            style: TextStyle(
                fontFamily: 'Cairo', color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
                      'تأكيد وإصدار السند',
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

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
