import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/account_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import 'accounting_cubit.dart';
import 'accounting_state.dart';

class AccountingEntryDialog extends StatelessWidget {
  final String entryType;
  const AccountingEntryDialog({super.key, required this.entryType});

  String get _title => switch (entryType) {
        'debit_customer' => 'دفع الكتروني للعميل ',
        'credit_customer' => 'تحصيل الكتروني من العميل',
        'debit_supplier' => 'دفع الكتروني للمورد',
        'credit_supplier' => 'تحصيل الكتروني من المورد',
        _ => 'قيد',
      };
  Color get _color => switch (entryType) {
        'debit_customer' => AppTheme.danger,
        'credit_customer' => AppTheme.success,
        'debit_supplier' => AppTheme.warning,
        'credit_supplier' => AppTheme.primary,
        _ => AppTheme.primary,
      };
  IconData get _icon => switch (entryType) {
        'debit_customer' => Icons.person_remove_outlined,
        'credit_customer' => Icons.person_add_outlined,
        'debit_supplier' => Icons.remove_shopping_cart_outlined,
        'credit_supplier' => Icons.add_shopping_cart_outlined,
        _ => Icons.swap_horiz,
      };
  bool get _isCustomer => entryType.contains('customer');
  String get _hint => switch (entryType) {
        'credit_customer' =>
          'استلام فلوس من العميل من خلال فودافون كاش / انستا باي',
        'debit_customer' => 'دفع فلوس  للعميل فودافون كاش / انستا باي',
        'credit_supplier' =>
          'استلام فلوس من المورد من خلال فودافون كاش / انستا باي',
        'debit_supplier' => 'دفع فلوس  للمورد من خلال فودافون كاش / انستا باي',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AccountingCubit(),
      child: _AccountingEntryDialogBody(
        entryType: entryType,
        title: _title,
        color: _color,
        icon: _icon,
        isCustomer: _isCustomer,
        hint: _hint,
      ),
    );
  }
}

class _AccountingEntryDialogBody extends StatelessWidget {
  final String entryType;
  final String title;
  final Color color;
  final IconData icon;
  final bool isCustomer;
  final String hint;

  const _AccountingEntryDialogBody({
    required this.entryType,
    required this.title,
    required this.color,
    required this.icon,
    required this.isCustomer,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.read<AccountingCubit>();

    final screenWidth = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: const Color(0xCC05192D),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.glassBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: screenWidth < 500 ? screenWidth * 0.95 : 540,
            decoration: AppTheme.glassCard(),
            padding: const EdgeInsets.all(28),
            child: Form(
              key: c.formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    if (hint.isNotEmpty) ...[
                      _hintBanner(),
                      const SizedBox(height: 14),
                    ],
                    isCustomer ? _customerSearch(c) : _supplierSearch(c),
                    const SizedBox(height: 14),
                    _datePicker(c, context),
                    const SizedBox(height: 14),
                    _amountField(c),
                    const SizedBox(height: 14),
                    _accountSearch(c),
                    const SizedBox(height: 14),
                    _notesField(c),
                    const SizedBox(height: 24),
                    _buttons(c, context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo')),
          Text(isCustomer ? 'قيد عميل' : 'قيد مورد',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
        ]),
        const Spacer(),
        IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop()),
      ]);

  Widget _hintBanner() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(hint,
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 12, color: color))),
        ]),
      );

  Widget _customerSearch(AccountingCubit c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('العميل *', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 6),
      Autocomplete<CustomerModel>(
        optionsBuilder: (txt) {
          c.customerSearchText = txt.text;
          return c.filterCustomersByQuery(c.customerSearchText);
        },
        displayStringForOption: (cu) => '${cu.name} — ${cu.id.toString()}',
        onSelected: (cu) => c.selectedCustomer = cu,
        fieldViewBuilder: (_, textCtrl, focus, onFieldSubmit) => TextFormField(
          controller: textCtrl,
          focusNode: focus,
          onFieldSubmitted: (_) => onFieldSubmit(),
          validator: (_) =>
              c.selectedCustomer == null ? 'يرجى اختيار العميل' : null,
          decoration: InputDecoration(
            hintText: 'ابحث باسم العميل أو الكود...',
            prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
            suffixIcon: BlocBuilder<AccountingCubit, AccountingState>(
              builder: (context, state) {
                if (c.selectedCustomer != null) {
                  return _codeBadge(c.selectedCustomer!.id.toString());
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => _optionsList(
          ctx,
          options,
          onSel,
          (item) => item.name,
          (item) => item.id.toString(),
          (item) => AppUtils.formatCurrency(item.balance),
          (item) => item.balance > 0 ? AppTheme.danger : AppTheme.success,
        ),
      ),
    ]);
  }

  Widget _supplierSearch(AccountingCubit c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('المورد *', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 6),
      Autocomplete<SupplierModel>(
        optionsBuilder: (txt) {
          c.supplierSearchText = txt.text;
          return c.filterSuppliersByQuery(c.supplierSearchText);
        },
        displayStringForOption: (s) => '${s.name} — ${s.supplierCode}',
        onSelected: (s) => c.selectedSupplier = s,
        fieldViewBuilder: (_, textCtrl, focus, onFieldSubmit) => TextFormField(
          controller: textCtrl,
          focusNode: focus,
          onFieldSubmitted: (_) => onFieldSubmit(),
          validator: (_) =>
              c.selectedSupplier == null ? 'يرجى اختيار المورد' : null,
          decoration: InputDecoration(
            hintText: 'ابحث باسم المورد أو الكود...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: BlocBuilder<AccountingCubit, AccountingState>(
              builder: (context, state) {
                if (c.selectedSupplier != null) {
                  return _codeBadge(c.selectedSupplier!.supplierCode);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => _optionsList(
          ctx,
          options,
          onSel,
          (item) => item.name,
          (item) => item.supplierCode,
          (item) => AppUtils.formatCurrency(0.0),
          (_) => AppTheme.textSecondary,
        ),
      ),
    ]);
  }

  Widget _optionsList<T extends Object>(
    BuildContext context,
    Iterable<T> options,
    AutocompleteOnSelected<T> onSel,
    String Function(T) name,
    String Function(T) code,
    String Function(T) balance,
    Color Function(T) balColor,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Align(
      alignment: Alignment.topRight,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: screenWidth < 500 ? screenWidth * 0.95 : 480,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = options.elementAt(i);
              final highlightedIndex =
                  AutocompleteHighlightedOption.of(context);
              final isHighlighted = highlightedIndex == i;
              return Material(
                color: isHighlighted
                    ? color.withValues(alpha: 0.1)
                    : Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Text(name(item).substring(0, 1),
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 12)),
                  ),
                  title: Text(name(item), style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                  subtitle: Text(code(item), style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                  trailing: Text(balance(item),
                      style: TextStyle(
                          fontSize: 12,
                          color: balColor(item),
                          fontFamily: 'Cairo')),
                  onTap: () => onSel(item),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _codeBadge(String code) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(code,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
    );
  }

  Widget _datePicker(AccountingCubit c, BuildContext ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 6),
      BlocBuilder<AccountingCubit, AccountingState>(
        buildWhen: (prev, curr) {
        final prevDate = prev is AccountingLoaded ? prev.entryDate : null;
        final currDate = curr is AccountingLoaded ? curr.entryDate : null;
        return prevDate != currDate;
      },
        builder: (context, state) {
          if (state is! AccountingLoaded) return const SizedBox();
          return InkWell(
            onTap: () => c.pickDate(ctx),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFBDBDBD)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(AppUtils.formatDate(state.entryDate),
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
              ]),
            ),
          );
        },
      ),
    ]);
  }

  Widget _amountField(AccountingCubit c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(
          text:
              const TextSpan(text: 'المبلغ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), children: [
        TextSpan(
            text: ' *',
            style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo'))
      ])),
      const SizedBox(height: 6),
      TextFormField(
        controller: c.amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
          final d = double.tryParse(v.trim());
          if (d == null || d <= 0) return 'أدخل مبلغاً صحيحاً';
          return null;
        },
        decoration: InputDecoration(
          hintText: '0.00',
          prefixIcon: Icon(Icons.attach_money, size: 18, color: color),
          suffixText: 'ج.م',
        ),
      ),
    ]);
  }

  Widget _accountSearch(AccountingCubit c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('الحساب *', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 6),
      Autocomplete<AccountModel>(
        optionsBuilder: (txt) => c.filterAccountsByQuery(txt.text),
        displayStringForOption: (a) => '${a.name} — ${a.code}',
        onSelected: (a) {
          c.selectedAccount = a;
          c.accountValidated = false;
        },
        fieldViewBuilder: (_, textCtrl, focus, onFieldSubmit) => TextFormField(
          controller: textCtrl,
          focusNode: focus,
          onFieldSubmitted: (_) => onFieldSubmit(),
          validator: (_) {
            if (c.selectedAccount == null && c.accountValidated) {
              return 'يرجى اختيار الحساب';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: 'ابحث بالكود أو الاسم...',
            prefixIcon: const Icon(Icons.account_tree_outlined, size: 18),
            suffixIcon: BlocBuilder<AccountingCubit, AccountingState>(
              builder: (context, state) {
                return c.selectedAccount != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          textCtrl.clear();
                          c.selectedAccount = null;
                          c.accountValidated = false;
                        },
                      )
                    : const Icon(Icons.arrow_drop_down);
              },
            ),
            errorText: c.selectedAccount == null && c.accountValidated
                ? 'يرجى اختيار الحساب'
                : null,
          ),
        ),
        optionsViewBuilder: (ctx, onSel, options) => _accountOptionsList(
          ctx,
          options,
          onSel,
          color,
        ),
      ),
    ]);
  }

  Widget _accountOptionsList(
    BuildContext context,
    Iterable<AccountModel> options,
    AutocompleteOnSelected<AccountModel> onSel,
    Color color,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Align(
      alignment: Alignment.topRight,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: screenWidth < 500 ? screenWidth * 0.95 : 480,
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            itemCount: options.length,
            itemBuilder: (_, i) {
              final a = options.elementAt(i);
              final highlightedIndex =
                  AutocompleteHighlightedOption.of(context);
              final isHighlighted = highlightedIndex == i;
              return Material(
                color:
                    isHighlighted ? color.withValues(alpha: 0.1) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(Icons.account_balance_wallet_outlined,
                        size: 16, color: color),
                  ),
                  title: Text(a.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                  subtitle: Text(a.code, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                  trailing: Text(AppUtils.formatCurrency(a.balance),
                      style: TextStyle(
                          fontSize: 12,
                          color: a.balance >= 0
                              ? AppTheme.success
                              : AppTheme.danger,
                          fontFamily: 'Cairo')),
                  onTap: () => onSel(a),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _notesField(AccountingCubit c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ملاحظات', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
      const SizedBox(height: 6),
      TextFormField(
        controller: c.notesController,
        maxLines: 2,
        decoration: const InputDecoration(hintText: 'ملاحظات اختيارية...'),
      ),
    ]);
  }

  Widget _buttons(AccountingCubit c, BuildContext context) {
    return BlocBuilder<AccountingCubit, AccountingState>(
      buildWhen: (prev, curr) {
        final prevSaving = prev is AccountingLoaded ? prev.isSaving : null;
        final currSaving = curr is AccountingLoaded ? curr.isSaving : null;
        return prevSaving != currSaving;
      },
      builder: (context, state) {
        if (state is! AccountingLoaded) return const SizedBox();
        final saving = state.isSaving;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const Text('إلغاء')),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(icon, size: 18),
              label: Text(saving ? 'جاري الحفظ...' : title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: (saving || ReadOnlyGuard.isReadOnly)
                  ? null
                  : () async {
                      if (!await ReadOnlyGuard.checkAsync(context)) return;
                      final isCustomer = entryType.contains('customer');
                      final ok = await c.saveEntry(entryType);
                      if (ok) {
                        Navigator.of(context).pop();
                        await c.postSaveRefresh(isCustomer);
                      }
                    },
            ),
          ],
        );
      },
    );
  }
}
