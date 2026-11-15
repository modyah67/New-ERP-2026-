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
import 'cash_receipt_cubit.dart';
import 'cash_receipt_state.dart';

class CashReceiptPage extends StatelessWidget {
  const CashReceiptPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CashReceiptCubit(),
      child: const _CashReceiptScaffold(),
    );
  }
}

class _CashReceiptScaffold extends StatelessWidget {
  const _CashReceiptScaffold();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<CashReceiptCubit>();

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
  final CashReceiptCubit ctrl;
  const _Header({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('استلام نقدي',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
              Text('تسجيل المبالغ الواردة في الصندوق',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'Cairo')),
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
  final CashReceiptCubit ctrl;
  const _ModeToggle({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CashReceiptCubit, CashReceiptState>(
      buildWhen: (prev, curr) {
        if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
        return prev.mode != curr.mode;
      },
      builder: (context, state) {
        if (state is! CashReceiptLoaded) return const SizedBox();
        final isCustomer = state.mode == CashReceiptMode.customer;
        final isSupplier = state.mode == CashReceiptMode.supplier;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _ToggleBtn(
                label: 'استلام من عميل',
                icon: Icons.person_outline,
                active: isCustomer,
                onTap: () => ctrl.setMode(CashReceiptMode.customer),
              ),
              const SizedBox(width: 4),
              _ToggleBtn(
                label: 'استلام من مورد',
                icon: Icons.local_shipping_outlined,
                active: isSupplier,
                onTap: () => ctrl.setMode(CashReceiptMode.supplier),
              ),
              const SizedBox(width: 4),
              _ToggleBtn(
                label: 'أخرى',
                icon: Icons.account_tree_outlined,
                active: !isCustomer && !isSupplier,
                onTap: () => ctrl.setMode(CashReceiptMode.other),
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
  const _ToggleBtn(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

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
            Icon(icon,
                size: 16, color: active ? AppTheme.primary : Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: active ? AppTheme.primary : Colors.white70,
                )),
          ],
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  final CashReceiptCubit ctrl;
  const _FormPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<CashReceiptCubit, CashReceiptState>(
          builder: (context, state) {
            if (state is! CashReceiptLoaded) return const SizedBox();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: _receiptNumberCard(context, state)),
                  const SizedBox(width: 12),
                  Expanded(child: _dateCard(context, state)),
                ]),
                const SizedBox(height: 20),

                if (state.mode == CashReceiptMode.customer) ...[
                  _sectionLabel(
                      'العميل', Icons.person_outline, AppTheme.accent),
                  const SizedBox(height: 8),
                  _CustomerSearchField(ctrl: ctrl),
                  const SizedBox(height: 20),
                ],

                if (state.mode == CashReceiptMode.supplier) ...[
                  _sectionLabel(
                      'المورد', Icons.local_shipping_outlined, AppTheme.accent),
                  const SizedBox(height: 8),
                  _SupplierSearchField(ctrl: ctrl),
                  if (state.selectedSupplier != null) ...[
                    const SizedBox(height: 8),
                    _SupplierSelectionCard(
                      supplier: state.selectedSupplier!,
                      onClear: () => ctrl.clearSupplier(),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],

                _sectionLabel('الحساب من شجرة الحسابات',
                    Icons.account_tree_outlined, AppTheme.primary),
                const SizedBox(height: 8),
                _AccountSearchField(ctrl: ctrl),
                const SizedBox(height: 20),

                _sectionLabel('المبلغ', Icons.attach_money, AppTheme.success),
                const SizedBox(height: 8),
                BlocBuilder<CashReceiptCubit, CashReceiptState>(
                  buildWhen: (prev, curr) {
                    if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
                    return prev.selectedCustomer?.currency != curr.selectedCustomer?.currency ||
                        prev.selectedSupplier?.currency != curr.selectedSupplier?.currency ||
                        prev.mode != curr.mode;
                  },
                  builder: (context, state) {
                    String currencySymbol = 'ج.م';
                    if (state is CashReceiptLoaded) {
                      if (state.mode == CashReceiptMode.customer && state.selectedCustomer != null && state.selectedCustomer!.currency.isNotEmpty) {
                        currencySymbol = state.selectedCustomer!.currency;
                      } else if (state.mode == CashReceiptMode.supplier && state.selectedSupplier != null) {
                        currencySymbol = state.selectedSupplier!.isEgpOnlySupplier
                            ? 'ج.م'
                            : state.selectedSupplier!.currency;
                      }
                    }
                    return TextFormField(
                      controller: ctrl.amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          color: AppTheme.success),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixIcon: const Icon(Icons.attach_money, color: AppTheme.success),
                        suffixText: currencySymbol,
                        suffixStyle: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppTheme.success),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                _sectionLabel(
                    'ملاحظات', Icons.notes_outlined, AppTheme.textSecondary),
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
                  child: BlocBuilder<CashReceiptCubit, CashReceiptState>(
                    buildWhen: (prev, curr) {
                      if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
                      return prev.isSaving != curr.isSaving;
                    },
                    builder: (context, saveState) {
                      if (saveState is! CashReceiptLoaded) return const SizedBox();
                      return ElevatedButton.icon(
                        onPressed:
                            (ReadOnlyGuard.isReadOnly ||
                                    saveState.isSaving ||
                                    (saveState.mode == CashReceiptMode.customer && saveState.selectedCustomer == null) ||
                                    (saveState.mode == CashReceiptMode.supplier && saveState.selectedSupplier == null) ||
                                    (saveState.mode == CashReceiptMode.other && saveState.selectedAccount == null))
                                ? null
                                : () async {
                                    if (!await ReadOnlyGuard.checkAsync(context)) return;
                                    ctrl.save();
                                  },
                        icon: saveState.isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(
                            saveState.isSaving
                                ? 'جارى الحفظ...'
                                : 'حفظ الاستلام',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
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

  Widget _receiptNumberCard(BuildContext context, CashReceiptLoaded state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_outlined,
              size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رقم الإيصال',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo')),
                Text(state.receiptNumber,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: AppTheme.primary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh,
                size: 16, color: AppTheme.primary),
            tooltip: 'توليد رقم جديد',
            onPressed: ctrl.regenerateNumber,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _dateCard(BuildContext context, CashReceiptLoaded state) {
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
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('التاريخ',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Cairo')),
                  Text(AppUtils.formatDate(state.transactionDate),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          color: AppTheme.accent)),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 14, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cairo')),
    ]);
  }
}

class _CustomerSearchField extends StatefulWidget {
  final CashReceiptCubit ctrl;
  const _CustomerSearchField({required this.ctrl});

  @override
  State<_CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends State<_CustomerSearchField> {
  int _highlightedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.ctrl.customerCtrl.text;
    _searchCtrl.addListener(() {
      widget.ctrl.customerCtrl.text = _searchCtrl.text;
    });
    widget.ctrl.customerCtrl.addListener(_syncFromCtrl);
  }

  void _syncFromCtrl() {
    if (_searchCtrl.text != widget.ctrl.customerCtrl.text) {
      _searchCtrl.text = widget.ctrl.customerCtrl.text;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    widget.ctrl.customerCtrl.removeListener(_syncFromCtrl);
    super.dispose();
  }

  void _resetHighlight(int length) {
    if (_highlightedIndex >= length) _highlightedIndex = 0;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final results = widget.ctrl.customerResults;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + results.length) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (results.isEmpty) return KeyEventResult.handled;
      widget.ctrl.selectCustomer(results[_highlightedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToHighlighted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_highlightedIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 100),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Focus(
          focusNode: _searchFocus,
          onKeyEvent: _handleKeyEvent,
          child: TextFormField(
            controller: _searchCtrl,
            onChanged: (v) {
              widget.ctrl.searchCustomers(v);
              _resetHighlight(widget.ctrl.customerResults.length);
            },
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        widget.ctrl.searchCustomers('');
                      })
                  : null,
            ),
          ),
        ),
        BlocBuilder<CashReceiptCubit, CashReceiptState>(
          buildWhen: (prev, curr) {
            if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
            return prev.customerResults != curr.customerResults ||
                prev.isLoadingCustomers != curr.isLoadingCustomers;
          },
          builder: (context, state) {
            if (state is! CashReceiptLoaded) return const SizedBox();
            final results = state.customerResults;
            _resetHighlight(results.length);
            if (results.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: state.isLoadingCustomers
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.divider),
                      itemBuilder: (_, i) {
                        _itemKeys[i] = _itemKeys[i] ?? GlobalKey();
                        final c = results[i];
                        return Container(
                          key: _itemKeys[i],
                          color: i == _highlightedIndex
                              ? AppTheme.accent.withValues(alpha: 0.1)
                              : null,
                          child: _CustomerTile(
                            customer: c,
                            onTap: () => widget.ctrl.selectCustomer(c),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _SupplierSearchField extends StatefulWidget {
  final CashReceiptCubit ctrl;
  const _SupplierSearchField({required this.ctrl});

  @override
  State<_SupplierSearchField> createState() => _SupplierSearchFieldState();
}

class _SupplierSearchFieldState extends State<_SupplierSearchField> {
  int _highlightedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.ctrl.supplierCtrl.text;
    _searchCtrl.addListener(() {
      widget.ctrl.supplierCtrl.text = _searchCtrl.text;
    });
    widget.ctrl.supplierCtrl.addListener(_syncFromCtrl);
  }

  void _syncFromCtrl() {
    if (_searchCtrl.text != widget.ctrl.supplierCtrl.text) {
      _searchCtrl.text = widget.ctrl.supplierCtrl.text;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    widget.ctrl.supplierCtrl.removeListener(_syncFromCtrl);
    super.dispose();
  }

  void _resetHighlight(int length) {
    if (_highlightedIndex >= length) _highlightedIndex = 0;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final results = widget.ctrl.supplierResults;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + results.length) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (results.isEmpty) return KeyEventResult.handled;
      widget.ctrl.selectSupplier(results[_highlightedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToHighlighted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_highlightedIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 100),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Focus(
          focusNode: _searchFocus,
          onKeyEvent: _handleKeyEvent,
          child: TextFormField(
            controller: _searchCtrl,
            onChanged: (v) {
              widget.ctrl.searchSuppliers(v);
              _resetHighlight(widget.ctrl.supplierResults.length);
            },
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        widget.ctrl.searchSuppliers('');
                      })
                  : null,
            ),
          ),
        ),
        BlocBuilder<CashReceiptCubit, CashReceiptState>(
          buildWhen: (prev, curr) {
            if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
            return prev.supplierResults != curr.supplierResults ||
                prev.isLoadingSuppliers != curr.isLoadingSuppliers;
          },
          builder: (context, state) {
            if (state is! CashReceiptLoaded) return const SizedBox();
            final results = state.supplierResults;
            _resetHighlight(results.length);
            if (results.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: state.isLoadingSuppliers
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.divider),
                      itemBuilder: (_, i) {
                        _itemKeys[i] = _itemKeys[i] ?? GlobalKey();
                        final s = results[i];
                        return Container(
                          key: _itemKeys[i],
                          color: i == _highlightedIndex
                              ? AppTheme.accent.withValues(alpha: 0.1)
                              : null,
                          child: ListTile(
                            dense: true,
                            onTap: () => widget.ctrl.selectSupplier(s),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                              child: const Icon(Icons.local_shipping_outlined,
                                  size: 16, color: AppTheme.accent),
                            ),
                            title: Text(s.name,
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                'كود: ${s.supplierCode}  |  الأرصدة: ${_formatSupplierBalances(s)}',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: AppTheme.textSecondary)),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }

  String _formatSupplierBalances(SupplierModel s) {
    if (s.currentBalancesByCurrency.isNotEmpty) {
      final active = s.currentBalancesByCurrency.entries
          .where((e) => e.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((e) {
          final sym = SupplierModel.getCurrencySymbol(e.key);
          final dir = e.value > 0.001 ? '(له)' : '(عليه)';
          return '${AppUtils.formatNumber(e.value.abs())} $sym $dir';
        }).join('  •  ');
      }
    }
    final sym = SupplierModel.getCurrencySymbol(s.currency.isNotEmpty && s.currency != 'MULTI' ? s.currency : 'EGP');
    return '${AppUtils.formatCurrency(s.outstandingBalance.abs())} $sym';
  }
}

class _SupplierSelectionCard extends StatelessWidget {
  final SupplierModel supplier;
  final VoidCallback onClear;

  const _SupplierSelectionCard({
    required this.supplier,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEgpOnly = supplier.isEgpOnlySupplier;
    final balances = supplier.currentBalancesByCurrency;
    final allCurrencies = isEgpOnly
        ? <String>['EGP']
        : (<String>{'EGP', 'USD', 'EUR', 'GBP'}..addAll(balances.keys)).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2744) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.primary.withValues(alpha: 0.4) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (supplier.supplierCode.isNotEmpty)
                      Text(
                        'كود المورد: ${supplier.supplierCode}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إلغاء التحديد',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                onPressed: onClear,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 13, color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
              const SizedBox(width: 5),
              Text(
                'أرصدة المورد الحالية بالعملات:',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allCurrencies.map((c) {
              final bal = balances[c] ?? (supplier.currency == c ? supplier.outstandingBalance : 0.0);
              final sym = SupplierModel.getCurrencySymbol(c);
              final isCredit = bal > 0.001;
              final isDebit = bal < -0.001;
              final statusText = isCredit ? '(له)' : (isDebit ? '(عليه)' : '(0)');
              final statusColor = isCredit
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (isDebit
                      ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)));

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$c: ',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                      ),
                    ),
                    Text(
                      '${AppUtils.formatNumber(bal.abs())} $sym',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (!isEgpOnly && (supplier.supportsMultiCurrency || balances.length > 1)) ...[
            const SizedBox(height: 6),
            Text(
              'المعادل الإجمالي بالجنيه: ≈ ${AppUtils.formatCurrency(supplier.outstandingBalance)} ج.م',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountSearchField extends StatefulWidget {
  final CashReceiptCubit ctrl;
  const _AccountSearchField({required this.ctrl});

  @override
  State<_AccountSearchField> createState() => _AccountSearchFieldState();
}

class _AccountSearchFieldState extends State<_AccountSearchField> {
  int _highlightedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.ctrl.accountCtrl.text;
    _searchCtrl.addListener(() {
      widget.ctrl.accountCtrl.text = _searchCtrl.text;
    });
    widget.ctrl.accountCtrl.addListener(_syncFromCtrl);
  }

  void _syncFromCtrl() {
    if (_searchCtrl.text != widget.ctrl.accountCtrl.text) {
      _searchCtrl.text = widget.ctrl.accountCtrl.text;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    widget.ctrl.accountCtrl.removeListener(_syncFromCtrl);
    super.dispose();
  }

  void _resetHighlight(int length) {
    if (_highlightedIndex >= length) _highlightedIndex = 0;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final results = widget.ctrl.accountResults;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (results.isEmpty) return KeyEventResult.handled;
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + results.length) % results.length;
      });
      _scrollToHighlighted();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (results.isEmpty) return KeyEventResult.handled;
      widget.ctrl.selectAccount(results[_highlightedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToHighlighted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_highlightedIndex];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 100),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Focus(
          focusNode: _searchFocus,
          onKeyEvent: _handleKeyEvent,
          child: TextFormField(
            controller: _searchCtrl,
            onChanged: (v) {
              widget.ctrl.searchAccounts(v);
              _resetHighlight(widget.ctrl.accountResults.length);
            },
            onTap: () => widget.ctrl.searchAccounts(''),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        widget.ctrl.searchAccounts('');
                      })
                  : null,
            ),
          ),
        ),
        BlocBuilder<CashReceiptCubit, CashReceiptState>(
          buildWhen: (prev, curr) {
            if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
            return prev.accountResults != curr.accountResults ||
                prev.isLoadingAccounts != curr.isLoadingAccounts;
          },
          builder: (context, state) {
            if (state is! CashReceiptLoaded) return const SizedBox();
            final results = state.accountResults;
            _resetHighlight(results.length);
            if (results.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.divider),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: state.isLoadingAccounts
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.divider),
                      itemBuilder: (_, i) {
                        _itemKeys[i] = _itemKeys[i] ?? GlobalKey();
                        final a = results[i];
                        return Container(
                          key: _itemKeys[i],
                          color: i == _highlightedIndex
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : null,
                          child: _AccountTile(
                            account: a,
                            onTap: () => widget.ctrl.selectAccount(a),
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;
  final VoidCallback onTap;
  const _CustomerTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
        child: Text(customer.name.substring(0, 1),
            style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFamily: 'Cairo')),
      ),
      title: Text(customer.name,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
          'كود: ${customer.code.isNotEmpty ? customer.code : customer.id.toString()}  |  رصيد: ${AppUtils.formatCurrency(customer.balance, customer.currency)}',
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: AppTheme.textSecondary)),
      trailing: customer.balance > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('مديون',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: AppTheme.warning,
                      fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onTap;
  const _AccountTile({required this.account, required this.onTap});

  Color get _typeColor {
    switch (account.type) {
      case 'asset':
        return AppTheme.primary;
      case 'liability':
        return AppTheme.danger;
      case 'revenue':
        return AppTheme.success;
      case 'expense':
        return AppTheme.warning;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: _typeColor.withValues(alpha: 0.12),
        child:
            Icon(Icons.account_balance_outlined, size: 14, color: _typeColor),
      ),
      title: Text(account.displayName,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('كود: ${account.code}',
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: AppTheme.textSecondary)),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  final CashReceiptCubit ctrl;
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
              const Icon(Icons.history,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              const Text('سجل الاستلامات',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white)),
              const Spacer(),
              BlocBuilder<CashReceiptCubit, CashReceiptState>(
                buildWhen: (prev, curr) {
                if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
                return prev.receipts.length != curr.receipts.length;
              },
                builder: (context, state) {
                  if (state is! CashReceiptLoaded) return const SizedBox();
                  return Text('${state.receipts.length} عملية',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppTheme.textSecondary));
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: ctrl.loadReceipts,
                tooltip: 'تحديث',
              ),
            ],
          ),
        ),
        BlocBuilder<CashReceiptCubit, CashReceiptState>(
          buildWhen: (prev, curr) {
            if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
            return prev.historySearchQuery != curr.historySearchQuery ||
                prev.historyFromDate != curr.historyFromDate ||
                prev.historyToDate != curr.historyToDate;
          },
          builder: (context, state) {
            if (state is! CashReceiptLoaded) return const SizedBox();
            final hasFilter = state.historySearchQuery.isNotEmpty ||
                state.historyFromDate != null ||
                state.historyToDate != null;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        style:
                            const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم او كود العميل/المورد',
                          hintStyle: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12),
                          prefixIcon: const Icon(Icons.search, size: 16),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range,
                                size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              state.historyFromDate != null
                                  ? AppUtils.formatDate(
                                      state.historyFromDate!)
                                  : 'من تاريخ',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: state.historyFromDate != null
                                    ? Colors.white
                                    : AppTheme.textSecondary,
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range,
                                size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              state.historyToDate != null
                                  ? AppUtils.formatDate(
                                      state.historyToDate!)
                                  : 'إلى تاريخ',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: state.historyToDate != null
                                    ? Colors.white
                                    : AppTheme.textSecondary,
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
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.danger),
                      onPressed: ctrl.clearHistoryFilters,
                      tooltip: 'مسح الفلتر',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
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
                          _ColH('العميل/المورد', flex: 3),
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
          child: BlocBuilder<CashReceiptCubit, CashReceiptState>(
            buildWhen: (prev, curr) {
              if (prev is! CashReceiptLoaded || curr is! CashReceiptLoaded) return true;
              return prev.receipts != curr.receipts;
            },
            builder: (context, state) {
              if (state is! CashReceiptLoaded) return const SizedBox();
              if (state.receipts.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 48, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('لا توجد استلامات بعد',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: AppTheme.textSecondary,
                              fontSize: 14)),
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
                          itemCount: state.receipts.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppTheme.divider),
                          itemBuilder: (_, i) =>
                              _ReceiptRow(row: state.receipts[i]),
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
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary)),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ReceiptRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final customerName = row['customer_name'] as String? ?? '—';
    final supplierName = row['supplier_name'] as String? ?? '—';
    final partyName = row['mode'] == 'supplier' ? supplierName : customerName;
    final accountName = row['account_name'] as String? ?? '—';
    final description = row['description'] as String? ?? '';
    final amount = (row['amount'] as num).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(row['receipt_number'] as String? ?? '',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text(row['receipt_date'] as String? ?? '',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Text(partyName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Text(accountName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Text(description,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppTheme.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Text(AppUtils.formatCurrency(amount),
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.success)),
          ),
        ],
      ),
    );
  }
}
