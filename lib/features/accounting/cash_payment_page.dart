import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import 'cash_payment_cubit.dart';
import 'cash_payment_state.dart';
import '../../data/models/account_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';

class CashPaymentPage extends StatelessWidget {
  const CashPaymentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CashPaymentCubit(),
      child: const _CashPaymentScaffold(),
    );
  }
}

class _CashPaymentScaffold extends StatelessWidget {
  const _CashPaymentScaffold();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<CashPaymentCubit>();

    return Scaffold(
      body: Column(
        children: [
          _Header(ctrl: ctrl),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 600;
                final formWidth = isCompact ? constraints.maxWidth : 480.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: formWidth,
                      child: _FormPanel(ctrl: ctrl),
                    ),
                    if (!isCompact) const VerticalDivider(width: 1),
                    if (!isCompact) Expanded(child: _HistoryPanel(ctrl: ctrl)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _Header({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.danger,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          const Icon(Icons.outbox_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صرف نقدي', style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              Text('تسجيل المبالغ المنصرفة من الصندوق',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(width: 32),
          _ModeToggle(ctrl: ctrl),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _ModeToggle({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CashPaymentCubit, CashPaymentState>(
      buildWhen: (prev, curr) {
        if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
        return prev.mode != curr.mode;
      },
      builder: (context, state) {
        if (state is! CashPaymentLoaded) return const SizedBox();
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _ToggleBtn(
                label: 'صرف لمورد',
                icon: Icons.local_shipping_outlined,
                active: state.mode == CashPaymentMode.supplier,
                onTap: () => ctrl.setMode(CashPaymentMode.supplier),
              ),
              const SizedBox(width: 4),
              _ToggleBtn(
                label: 'صرف لعميل',
                icon: Icons.person_outlined,
                active: state.mode == CashPaymentMode.customer,
                onTap: () => ctrl.setMode(CashPaymentMode.customer),
              ),
              const SizedBox(width: 4),
              _ToggleBtn(
                label: 'أخرى',
                icon: Icons.account_tree_outlined,
                active: state.mode == CashPaymentMode.other,
                onTap: () => ctrl.setMode(CashPaymentMode.other),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn({required this.label, required this.icon,
    required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: active ? AppTheme.danger : Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold,
              color: active ? AppTheme.danger : Colors.white70,
            )),
          ],
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _FormPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<CashPaymentCubit, CashPaymentState>(
          builder: (context, state) {
            if (state is! CashPaymentLoaded) return const SizedBox();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: _paymentNumberCard(context, state)),
                  const SizedBox(width: 12),
                  Expanded(child: _dateCard(context, state)),
                ]),
                const SizedBox(height: 20),

                if (state.mode == CashPaymentMode.supplier) ...[
                  _sectionLabel('المورد', Icons.local_shipping_outlined, AppTheme.accent),
                  const SizedBox(height: 8),
                  _SupplierSearchField(ctrl: ctrl),
                  const SizedBox(height: 20),
                ],

                if (state.mode == CashPaymentMode.customer) ...[
                  _sectionLabel('العميل', Icons.person_outlined, AppTheme.accent),
                  const SizedBox(height: 8),
                  _CustomerSearchField(ctrl: ctrl),
                  const SizedBox(height: 20),
                ],

                _sectionLabel('الحساب من شجرة الحسابات',
                    Icons.account_tree_outlined, AppTheme.primary),
                const SizedBox(height: 8),
                _AccountSearchField(ctrl: ctrl),
                const SizedBox(height: 20),

                _sectionLabel('المبلغ', Icons.attach_money, AppTheme.danger),
                const SizedBox(height: 8),
                BlocBuilder<CashPaymentCubit, CashPaymentState>(
                  buildWhen: (prev, curr) {
                    if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                    return prev.selectedSupplier?.currency != curr.selectedSupplier?.currency ||
                        prev.selectedCustomer?.currency != curr.selectedCustomer?.currency;
                  },
                  builder: (context, state) {
                    final currencySymbol = (state is CashPaymentLoaded && state.selectedSupplier != null)
                        ? (state.selectedSupplier!.isEgpOnlySupplier ? 'ج.م' : state.selectedSupplier!.currency)
                        : (state is CashPaymentLoaded && state.selectedCustomer != null)
                            ? state.selectedCustomer!.currency
                            : 'ج.م';
                    return TextFormField(
                      controller: ctrl.amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo', color: AppTheme.danger),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixIcon: const Icon(Icons.attach_money, color: AppTheme.danger),
                        suffixText: currencySymbol,
                        suffixStyle: const TextStyle(fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold, color: AppTheme.danger),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                _sectionLabel('ملاحظات', Icons.notes_outlined, AppTheme.textSecondary),
                const SizedBox(height: 8),
                TextFormField(
                  controller: ctrl.notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'ملاحظات اختيارية...',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: BlocBuilder<CashPaymentCubit, CashPaymentState>(
                    buildWhen: (prev, curr) {
                      if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                      return prev.isSaving != curr.isSaving;
                    },
                    builder: (context, saveState) {
                      if (saveState is! CashPaymentLoaded) return const SizedBox();
                      return ElevatedButton.icon(
                        onPressed:
                            (ReadOnlyGuard.isReadOnly ||
                                    saveState.isSaving ||
                                    (saveState.mode == CashPaymentMode.customer && saveState.selectedCustomer == null) ||
                                    (saveState.mode == CashPaymentMode.supplier && saveState.selectedSupplier == null) ||
                                    (saveState.mode == CashPaymentMode.other && saveState.selectedAccount == null))
                                ? null
                                : () async {
                                    if (!await ReadOnlyGuard.checkAsync(context)) return;
                                    ctrl.save();
                                  },
                        icon: saveState.isSaving
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(saveState.isSaving ? 'جارى الحفظ...' : 'حفظ الصرف',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _paymentNumberCard(BuildContext context, CashPaymentLoaded state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رقم الإيصال',
                    style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                Text(state.paymentNumber,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo', color: AppTheme.primary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: AppTheme.primary),
            tooltip: 'توليد رقم جديد',
            onPressed: ctrl.regenerateNumber,
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _dateCard(BuildContext context, CashPaymentLoaded state) {
    return InkWell(
      onTap: () => ctrl.pickDate(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('التاريخ',
                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                  Text(AppUtils.formatDate(state.transactionDate),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo', color: AppTheme.accent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: color,
        )),
      ],
    );
  }
}

class _SupplierSearchField extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _SupplierSearchField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<SupplierModel>(
          displayStringForOption: (s) => s.name,
          optionsBuilder: (textEditingValue) async {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<SupplierModel>.empty();
            }
            await ctrl.searchSuppliers(textEditingValue.text);
            return ctrl.supplierResults;
          },
          onSelected: ctrl.selectSupplier,
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            textEditingController.addListener(() {
              if (textEditingController.text.isEmpty) {
                ctrl.clearSupplier();
              }
            });

            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                     event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                  if (ctrl.supplierResults.isEmpty) {
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                onFieldSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  hintText: 'ابحث بالكود أو الاسم...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: BlocBuilder<CashPaymentCubit, CashPaymentState>(
                    buildWhen: (prev, curr) {
                      if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                      return prev.isLoadingSuppliers != curr.isLoadingSuppliers ||
                          prev.selectedSupplier != curr.selectedSupplier;
                    },
                    builder: (context, state) {
                      if (state is! CashPaymentLoaded) return const SizedBox();
                      if (state.isLoadingSuppliers) {
                        return const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (state.selectedSupplier != null) {
                        return IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            textEditingController.clear();
                            ctrl.clearSupplier();
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: constraints.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final highlightedIndex =
                          AutocompleteHighlightedOption.of(context);
                      final isHighlighted = highlightedIndex == index;
                      return Container(
                        color: isHighlighted
                            ? AppTheme.primary.withValues(alpha: 0.08)
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.local_shipping_outlined,
                                size: 16, color: AppTheme.primary),
                          ),
                          title: Text(option.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                          subtitle: Text(option.supplierCode, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      }
    );
  }
}

class _CustomerSearchField extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _CustomerSearchField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<CustomerModel>(
          displayStringForOption: (c) => c.name,
          optionsBuilder: (textEditingValue) async {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<CustomerModel>.empty();
            }
            await ctrl.searchCustomers(textEditingValue.text);
            return ctrl.customerResults;
          },
          onSelected: ctrl.selectCustomer,
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            textEditingController.addListener(() {
              if (textEditingController.text.isEmpty) {
                ctrl.clearCustomer();
              }
            });

            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                     event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                  if (ctrl.customerResults.isEmpty) {
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                onFieldSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  hintText: 'ابحث بالكود أو الاسم...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: BlocBuilder<CashPaymentCubit, CashPaymentState>(
                    buildWhen: (prev, curr) {
                      if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                      return prev.isLoadingCustomers != curr.isLoadingCustomers ||
                          prev.selectedCustomer != curr.selectedCustomer;
                    },
                    builder: (context, state) {
                      if (state is! CashPaymentLoaded) return const SizedBox();
                      if (state.isLoadingCustomers) {
                        return const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (state.selectedCustomer != null) {
                        return IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            textEditingController.clear();
                            ctrl.clearCustomer();
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: constraints.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final highlightedIndex =
                          AutocompleteHighlightedOption.of(context);
                      final isHighlighted = highlightedIndex == index;
                      return Container(
                        color: isHighlighted
                            ? AppTheme.accent.withValues(alpha: 0.08)
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_outlined,
                                size: 16, color: AppTheme.accent),
                          ),
                          title: Text(option.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                          subtitle: Text(option.code, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      }
    );
  }
}

class _AccountSearchField extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _AccountSearchField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Autocomplete<AccountModel>(
          displayStringForOption: (a) => '${a.displayName} (${a.code})',
          optionsBuilder: (textEditingValue) async {
            await ctrl.searchAccounts(textEditingValue.text);
            return ctrl.accountResults;
          },
          onSelected: ctrl.selectAccount,
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            textEditingController.addListener(() {
              if (textEditingController.text.isEmpty) {
                ctrl.clearAccount();
              }
            });
            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                     event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                  if (ctrl.accountResults.isEmpty) {
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                onFieldSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الحساب أو رقمه...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: BlocBuilder<CashPaymentCubit, CashPaymentState>(
                    buildWhen: (prev, curr) {
                      if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                      return prev.isLoadingAccounts != curr.isLoadingAccounts ||
                          prev.selectedAccount != curr.selectedAccount;
                    },
                    builder: (context, state) {
                      if (state is! CashPaymentLoaded) return const SizedBox();
                      if (state.isLoadingAccounts) {
                        return const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (state.selectedAccount != null) {
                        return IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            textEditingController.clear();
                            ctrl.clearAccount();
                          },
                        );
                      }
                      return const Icon(Icons.arrow_drop_down);
                    },
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: constraints.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final highlightedIndex =
                          AutocompleteHighlightedOption.of(context);
                      final isHighlighted = highlightedIndex == index;
                      return Container(
                        color: isHighlighted
                            ? AppTheme.accent.withValues(alpha: 0.08)
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                            child: const Icon(Icons.account_balance_wallet_outlined,
                                size: 16, color: AppTheme.accent),
                          ),
                          title: Text(option.displayName,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Cairo',
                                  fontSize: 15)),
                          subtitle: Text('كود: ${option.code}',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      }
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  final CashPaymentCubit ctrl;
  const _HistoryPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: const Color(0x1A00E5FF),
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              const Text('سجل الصرف',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold,
                      fontSize: 14, color: Colors.white)),
              const Spacer(),
              BlocBuilder<CashPaymentCubit, CashPaymentState>(
                buildWhen: (prev, curr) {
                if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
                return prev.payments.length != curr.payments.length;
              },
                builder: (context, state) {
                  if (state is! CashPaymentLoaded) return const SizedBox();
                  return Text('${state.payments.length} عملية',
                      style: const TextStyle(fontFamily: 'Cairo',
                          fontSize: 12, color: AppTheme.textSecondary));
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: ctrl.loadPayments,
                tooltip: 'تحديث',
              ),
            ],
          ),
        ),
        BlocBuilder<CashPaymentCubit, CashPaymentState>(
          buildWhen: (prev, curr) {
            if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
            return prev.historySearchQuery != curr.historySearchQuery ||
                prev.historyFromDate != curr.historyFromDate ||
                prev.historyToDate != curr.historyToDate;
          },
          builder: (context, state) {
            if (state is! CashPaymentLoaded) return const SizedBox();
            final hasFilter = state.historySearchQuery.isNotEmpty ||
                state.historyFromDate != null ||
                state.historyToDate != null;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        onChanged: ctrl.setHistorySearch,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم أو كود المورد/العميل',
                          hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                          prefixIcon: const Icon(Icons.search, size: 16),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () => ctrl.pickHistoryFromDate(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              state.historyFromDate != null
                                  ? AppUtils.formatDate(state.historyFromDate!)
                                  : 'من تاريخ',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 11,
                                color: state.historyFromDate != null
                                    ? Colors.white : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () => ctrl.pickHistoryToDate(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              state.historyToDate != null
                                  ? AppUtils.formatDate(state.historyToDate!)
                                  : 'إلى تاريخ',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 11,
                                color: state.historyToDate != null
                                    ? Colors.white : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (hasFilter) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                      onPressed: ctrl.clearHistoryFilters,
                      tooltip: 'مسح الفلتر',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth > 850 ? constraints.maxWidth : 850,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0x1A00E5FF),
                      child: const Row(
                        children: [
                          _ColH('رقم الإيصال', flex: 3),
                          _ColH('التاريخ', flex: 2),
                          _ColH('المورد/العميل', flex: 3),
                          _ColH('الحساب', flex: 3),
                          _ColH('الملاحظات', flex: 3),
                          _ColH('المبلغ', flex: 2),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<CashPaymentCubit, CashPaymentState>(
            buildWhen: (prev, curr) {
              if (prev is! CashPaymentLoaded || curr is! CashPaymentLoaded) return true;
              return prev.payments != curr.payments;
            },
            builder: (context, state) {
              if (state is! CashPaymentLoaded) return const SizedBox();
              if (state.payments.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.outbox_outlined, size: 48, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('لا توجد عمليات صرف',
                          style: TextStyle(fontFamily: 'Cairo',
                              color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth > 850 ? constraints.maxWidth : 850,
                      ),
                      child: SizedBox(
                        width: constraints.maxWidth > 850 ? constraints.maxWidth : 850,
                        child: ListView.separated(
                          itemCount: state.payments.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
                          itemBuilder: (_, i) => _PaymentRow(row: state.payments[i]),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColH extends StatelessWidget {
  final String text;
  final int flex;
  const _ColH(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
              fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PaymentRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final supplierName = row['supplier_name'] as String?;
    final customerName = row['customer_name'] as String?;
    final partyName = supplierName ?? customerName ?? '—';
    final accountName = row['account_name'] as String? ?? '—';
    final description = row['description'] as String? ?? '';
    final amount = (row['amount'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3,
            child: Text(row['payment_number'] as String? ?? '',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
          Expanded(flex: 2,
            child: Text(row['payment_date'] as String? ?? '',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(flex: 3,
            child: Text(partyName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(flex: 3,
            child: Text(accountName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(flex: 3,
            child: Text(description,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                    color: AppTheme.textSecondary)),
          ),
          Expanded(flex: 2,
            child: Text('- ${AppUtils.formatCurrency(amount)}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                    fontWeight: FontWeight.bold, color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
