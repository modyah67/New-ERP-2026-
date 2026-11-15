import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/cost_center.dart';
import '../../../data/models/treasury_model.dart';
import '../../../data/services/chart_of_accounts_cache_service.dart';
import '../../../data/services/custody_service.dart';
import '../treasury_cubit.dart';
import 'coa_expense_dropdown.dart';
import 'cost_center_selector_field.dart';
import 'expense_sub_account_dialog.dart';

/// A streamlined, comprehensive dialog for disbursing expenses directly from an employee custody.
///
/// Supports:
/// 1. Quick Expense Shortcuts: Staff Transportation (31123), Meals (31124), Temporary Labor (31125).
/// 2. Comprehensive Expense Branch Selection: Search and disburse to ANY expense account from COA.
/// 3. Inline creation of new expense sub-accounts directly saved to COA tree.
/// 4. Dynamic Cost Center selection for accurate managerial and financial cost allocation.
/// 5. Real-time balance validation against the selected employee custody.
class SimplifiedCustodyExpenseDialog extends StatefulWidget {
  final TreasuryModel? custodyTreasury;
  final List<TreasuryModel>? availableCustodies;
  final VoidCallback? onSuccess;

  const SimplifiedCustodyExpenseDialog({
    super.key,
    this.custodyTreasury,
    this.availableCustodies,
    this.onSuccess,
  });

  /// Convenient helper to display the dialog with standard enterprise styling.
  static Future<void> show(
    BuildContext context, {
    TreasuryModel? custodyTreasury,
    List<TreasuryModel>? availableCustodies,
    VoidCallback? onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        TreasuryCubit? cubit;
        try {
          cubit = context.read<TreasuryCubit>();
        } catch (_) {}

        final dialog = SimplifiedCustodyExpenseDialog(
          custodyTreasury: custodyTreasury,
          availableCustodies: availableCustodies,
          onSuccess: onSuccess,
        );

        if (cubit != null) {
          return BlocProvider.value(
            value: cubit,
            child: dialog,
          );
        }
        return dialog;
      },
    );
  }

  @override
  State<SimplifiedCustodyExpenseDialog> createState() =>
      _SimplifiedCustodyExpenseDialogState();
}

class _SimplifiedCustodyExpenseDialogState
    extends State<SimplifiedCustodyExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TreasuryModel? _selectedTreasury;
  QuickCustodyExpenseItem? _selectedItem =
      QuickCustodyExpenseItem.defaultItems.first;

  final CustodyService _custodyService = CustodyService();
  Map<String, AccountModel> _quickAccounts = {};
  List<Map<String, dynamic>> _allExpenseAccounts = [];
  String? _selectedExpenseAccountId;
  Map<String, dynamic>? _selectedExpenseAccountMap;
  String? _selectedCostCenterId;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initTreasury();
    _loadAccounts();
    _descCtrl.text = _selectedItem?.defaultDescription ?? 'مصروف عهدة';
  }

  void _initTreasury() {
    if (widget.custodyTreasury != null) {
      _selectedTreasury = widget.custodyTreasury;
    } else if (widget.availableCustodies != null &&
        widget.availableCustodies!.isNotEmpty) {
      _selectedTreasury = widget.availableCustodies!.first;
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final quickAccountsFuture = _custodyService.getQuickCustodyExpenseAccounts();
      final allAccountsFuture =
          ChartOfAccountsCacheService().getAdminExpenseAccounts(forceRefresh: true);

      final results = await Future.wait([quickAccountsFuture, allAccountsFuture]);
      final quickAccs = results[0] as Map<String, AccountModel>;
      var allAccs = results[1] as List<Map<String, dynamic>>;

      if (allAccs.isEmpty) {
        allAccs = await ChartOfAccountsCacheService().getExpenseAccounts();
      }

      if (mounted) {
        setState(() {
          _quickAccounts = quickAccs;
          _allExpenseAccounts = allAccs;

          // Initialize selected account and cost center if not already set
          if (_selectedExpenseAccountId == null) {
            final defaultQuick = _quickAccounts[_selectedItem?.code ?? '31123'];
            if (defaultQuick != null) {
              _selectedExpenseAccountId = defaultQuick.id?.toString();
              _selectedExpenseAccountMap = defaultQuick.toMap();
              _selectedCostCenterId = CostCenterHelper.freightLogistics.id;
            } else if (_allExpenseAccounts.isNotEmpty) {
              final first = _allExpenseAccounts.first;
              _selectedExpenseAccountId = first['id']?.toString();
              _selectedExpenseAccountMap = first;
              _selectedCostCenterId = COAExpenseDropdown.suggestCostCenter(first);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر تحميل حسابات المصروفات: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  double get _availableBalance {
    if (_selectedTreasury == null) return 0.0;
    return _selectedTreasury!.getBalance('EGP')?.balance ?? 0.0;
  }

  double get _enteredAmount {
    return double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
  }

  bool get _isAmountOverBalance {
    final entered = _enteredAmount;
    if (entered <= 0) return false;
    return entered > (_availableBalance + 0.001);
  }

  void _onSelectItem(QuickCustodyExpenseItem item) {
    setState(() {
      final previousDefault = _selectedItem?.defaultDescription;
      _selectedItem = item;

      // Locate matching account in quick accounts or all accounts
      final accModel = _quickAccounts[item.code];
      if (accModel != null) {
        _selectedExpenseAccountId = accModel.id?.toString();
        _selectedExpenseAccountMap = accModel.toMap();
      } else {
        final match = _allExpenseAccounts.firstWhereOrNull(
          (a) => (a['account_code'] ?? a['code'])?.toString() == item.code,
        );
        if (match != null) {
          _selectedExpenseAccountId = match['id']?.toString();
          _selectedExpenseAccountMap = match;
        }
      }

      // Auto-suggest specialized Cost Center
      if (item.code == '31123') {
        _selectedCostCenterId = CostCenterHelper.freightLogistics.id;
      } else if (item.code == '31124' || item.code == '31125') {
        _selectedCostCenterId = CostCenterHelper.packingStation.id;
      } else {
        _selectedCostCenterId = CostCenterHelper.generalAdmin.id;
      }

      if (_descCtrl.text.trim().isEmpty ||
          _descCtrl.text.trim() == previousDefault) {
        _descCtrl.text = item.defaultDescription;
      }
    });
  }

  Future<void> _openCreateNewBranchDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const ExpenseSubAccountDialog(
        initialParentCode: '3112',
      ),
    );

    if (result != null) {
      await _loadAccounts();
      if (mounted) {
        setState(() {
          _selectedExpenseAccountId = result['id']?.toString();
          _selectedExpenseAccountMap = result;
          final directCc = result['cost_center_id']?.toString();
          if (directCc != null && directCc.isNotEmpty) {
            _selectedCostCenterId = directCc;
          } else {
            _selectedCostCenterId ??= CostCenterHelper.generalAdmin.id;
          }

          final code = (result['account_code'] ?? result['code'] ?? '').toString();
          _selectedItem = QuickCustodyExpenseItem.defaultItems
              .firstWhereOrNull((i) => i.code == code);

          final name = result['account_name'] ?? result['name'] ?? '';
          _descCtrl.text = 'صرف $name';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTreasury == null) {
      setState(() => _errorMessage = 'يرجى اختيار عهدة الموظف');
      return;
    }

    final amount = _enteredAmount;
    if (amount <= 0) {
      setState(() => _errorMessage = 'المبلغ يجب أن يكون أكبر من صفر');
      return;
    }

    if (_isAmountOverBalance) {
      setState(() => _errorMessage =
          'المبلغ المطلوب (${amount.toStringAsFixed(2)}) أكبر من الرصيد المتوفر (${_availableBalance.toStringAsFixed(2)})');
      return;
    }

    final accountId = _selectedExpenseAccountId;
    if (accountId == null || accountId.isEmpty) {
      setState(() => _errorMessage = 'يرجى اختيار فرع أو بند المصروف من القائمة');
      return;
    }

    if (_selectedCostCenterId == null || _selectedCostCenterId!.trim().isEmpty) {
      setState(() => _errorMessage = 'يرجى اختيار مركز التكلفة / القسم المستفيد');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final treasuryId = _selectedTreasury!.id!;
      final expenseName = _selectedExpenseAccountMap?['account_name'] ??
          _selectedExpenseAccountMap?['name'] ??
          _selectedItem?.title ??
          'مصروف عهدة';

      final desc = _descCtrl.text.trim().isNotEmpty
          ? _descCtrl.text.trim()
          : (_selectedItem?.defaultDescription ?? 'صرف $expenseName');

      TreasuryCubit? cubit;
      try {
        cubit = context.read<TreasuryCubit>();
      } catch (_) {}

      if (cubit != null) {
        await cubit.spend(
          treasuryId: treasuryId,
          currency: 'EGP',
          amount: amount,
          description: desc,
          expenseAccountId: accountId,
          costCenterId: _selectedCostCenterId,
          notes: 'صرف عهدة: $expenseName',
        );
      } else {
        await _custodyService.spendCustody(
          treasuryId: treasuryId,
          currency: 'EGP',
          amount: amount,
          description: desc,
          expenseAccountId: accountId,
          costCenterId: _selectedCostCenterId,
          notes: 'صرف عهدة: $expenseName',
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم صرف ${amount.toStringAsFixed(2)} ج.م بنجاح من ${_selectedTreasury!.displayName} ($expenseName)',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppTheme.accent : const Color(0xFF0284C7);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                _buildHeader(isDark, primaryColor),

                // ── Body ──
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Custody & Balance Banner
                        _buildCustodyInfoBanner(isDark),
                        const SizedBox(height: 18),

                        // Error message if any
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.danger
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppTheme.danger, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Quick Expense Items Selector
                        _buildQuickAccountsSection(isDark),
                        const SizedBox(height: 18),

                        // Comprehensive Expense Branch Selector with "Create New Branch" button
                        _buildAllExpenseAccountsSection(isDark),
                        const SizedBox(height: 18),

                        // Cost Center Selector
                        _buildCostCenterSection(isDark),
                        const SizedBox(height: 18),

                        // Amount Field
                        _buildAmountField(isDark),
                        const SizedBox(height: 18),

                        // Description Field
                        _buildDescriptionField(isDark),
                        const SizedBox(height: 24),

                        // Action Buttons
                        _buildActionButtons(isDark),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.7)
            : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.request_quote_rounded,
                color: primaryColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'صرف مصروف من عهدة الموظف',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'نموذج مبسط وسريع لصرف العهدة وتوليد القيد المحاسبي آلياً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? AppTheme.textSecondary : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              color: isDark ? AppTheme.textSecondary : Colors.black54,
              size: 20,
            ),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }

  Widget _buildCustodyInfoBanner(bool isDark) {
    final balance = _availableBalance;
    final isLowBalance = balance <= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF0F172A),
                  const Color(0xFF1E293B),
                ]
              : [
                  const Color(0xFFF1F5F9),
                  const Color(0xFFF8FAFC),
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(
                'العهدة المنصرف منها:',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isLowBalance
                      ? AppTheme.danger.withValues(alpha: 0.15)
                      : const Color(0xFF059669).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'المتاح: ${AppUtils.formatCurrency(balance)} ج.م',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isLowBalance
                        ? AppTheme.danger
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.availableCustodies != null &&
              widget.availableCustodies!.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _selectedTreasury?.id,
              decoration: _inputDecoration('اختيار العهدة', isDark),
              dropdownColor:
                  isDark ? const Color(0xFF1E293B) : Colors.white,
              items: widget.availableCustodies!.map((c) {
                final b = c.getBalance('EGP')?.balance ?? 0.0;
                return DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    '${c.displayName} (رصيد: ${b.toStringAsFixed(2)} ج.م)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() {
                    _selectedTreasury = widget.availableCustodies!
                        .firstWhere((c) => c.id == id);
                  });
                }
              },
            )
          else
            Text(
              _selectedTreasury?.displayName ?? 'عهدة الموظف',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAccountsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flash_on_rounded,
                size: 16, color: Color(0xFFEAB308)),
            const SizedBox(width: 6),
            const Text(
              'الفروع السريعة المباشرة (اختياري)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_selectedItem == null && _selectedExpenseAccountId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'تم اختيار فرع مخصص من الشجرة ✓',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: QuickCustodyExpenseItem.defaultItems.map((item) {
            final isSelected = _selectedItem?.code == item.code;
            final itemColor = item.code == '31123'
                ? const Color(0xFF0284C7)
                : item.code == '31124'
                    ? const Color(0xFFEA580C)
                    : const Color(0xFF059669);

            final iconData = item.code == '31123'
                ? Icons.directions_car_rounded
                : item.code == '31124'
                    ? Icons.restaurant_rounded
                    : Icons.engineering_rounded;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => _onSelectItem(item),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? itemColor.withValues(alpha: isDark ? 0.25 : 0.12)
                          : (isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? itemColor
                            : (isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          iconData,
                          color: isSelected
                              ? itemColor
                              : (isDark ? Colors.white70 : Colors.black54),
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? (isDark ? Colors.white : itemColor)
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: itemColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.code,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: itemColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAllExpenseAccountsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 15, color: Color(0xFF0284C7)),
            const SizedBox(width: 6),
            const Text(
              'فرع / بند المصروف (شجرة الحسابات) *',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: _openCreateNewBranchDialog,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_circle_outline, size: 13, color: Color(0xFF0284C7)),
                    SizedBox(width: 4),
                    Text(
                      'إنشاء فرع جديد',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        COAExpenseDropdown(
          accounts: _allExpenseAccounts,
          selectedAccountId: _selectedExpenseAccountId,
          selectedCostCenterId: _selectedCostCenterId,
          isRequired: true,
          label: null,
          allowCreateSubAccount: true,
          showInlineCostCenterCard: false,
          onSelected: (acct, suggestedCc) {
            setState(() {
              _selectedExpenseAccountId = acct?['id']?.toString();
              _selectedExpenseAccountMap = acct;
              if (acct != null) {
                final directCc = acct['cost_center_id']?.toString();
                _selectedCostCenterId = (directCc != null && directCc.isNotEmpty)
                    ? directCc
                    : (suggestedCc ?? CostCenterHelper.generalAdmin.id);

                final code = (acct['account_code'] ?? acct['code'] ?? '').toString();
                _selectedItem = QuickCustodyExpenseItem.defaultItems
                    .firstWhereOrNull((i) => i.code == code);

                final acctName = acct['account_name'] ?? acct['name'] ?? '';
                if (_descCtrl.text.trim().isEmpty ||
                    QuickCustodyExpenseItem.defaultItems
                        .any((i) => i.defaultDescription == _descCtrl.text.trim())) {
                  _descCtrl.text = _selectedItem?.defaultDescription ?? 'صرف $acctName';
                }
              }
            });
          },
          onAccountCreated: () async {
            await _loadAccounts();
          },
        ),
      ],
    );
  }

  Widget _buildCostCenterSection(bool isDark) {
    return CostCenterSelectorField(
      label: 'مركز التكلفة / القسم المستفيد (Cost Center) *',
      selectedCostCenterId: _selectedCostCenterId,
      isRequired: true,
      onSelected: (ccId) {
        setState(() => _selectedCostCenterId = ccId);
      },
    );
  }

  Widget _buildAmountField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'المبلغ المنصرف *',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_isAmountOverBalance)
              const Text(
                'الرصيد غير كافٍ',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.danger,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _isAmountOverBalance
                ? AppTheme.danger
                : (isDark ? Colors.white : Colors.black),
          ),
          decoration: _inputDecoration('أدخل المبلغ بالجنيه', isDark).copyWith(
            prefixIcon: Icon(
              Icons.attach_money_rounded,
              color: _isAmountOverBalance
                  ? AppTheme.danger
                  : (isDark ? AppTheme.accent : const Color(0xFF0284C7)),
            ),
            suffixText: 'ج.م',
            suffixStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            final val = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
            if (val == null || val <= 0) return 'يرجى إدخال مبلغ صحيح';
            if (_isAmountOverBalance) return 'المبلغ المطلوب أكبر من رصيد العهدة';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDescriptionField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'البيان / تفاصيل وملاحظات المصروف *',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _descCtrl,
          maxLines: 2,
          decoration: _inputDecoration(
            'اكتب وصفاً مختصراً للمصروف...',
            isDark,
          ).copyWith(
            prefixIcon: const Icon(Icons.notes_rounded, size: 18),
          ),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black,
          ),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) {
              return 'يرجى كتابة بيان المصروف';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(
                color:
                    isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'إلغاء',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: (_isSaving || _isAmountOverBalance) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF059669).withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'تأكيد وصرف المصروف',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        color: isDark ? AppTheme.textSecondary : Colors.black38,
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Color(0xFF059669),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: AppTheme.danger,
        ),
      ),
    );
  }
}
