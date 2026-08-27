import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/statement_row_model.dart';
import 'brief_statement_cubit.dart';
import 'brief_statement_state.dart';
import 'brief_statement_pdf_service.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';

class BriefStatementPage extends StatefulWidget {
  final bool isCustomerMode;
  const BriefStatementPage({super.key, required this.isCustomerMode});

  @override
  State<BriefStatementPage> createState() => _BriefStatementPageState();
}

class _BriefStatementPageState extends State<BriefStatementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cubit = context.read<BriefStatementCubit>();
      cubit.setCustomerMode(widget.isCustomerMode);
      cubit.reset();
    });
  }

  @override
  void didUpdateWidget(covariant BriefStatementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCustomerMode != widget.isCustomerMode) {
      final cubit = context.read<BriefStatementCubit>();
      cubit.setCustomerMode(widget.isCustomerMode);
      cubit.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BriefStatementCubit, BriefStatementState>(
      builder: (context, state) {
        if (state is! BriefStatementLoaded) return const SizedBox();
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, state),
                const SizedBox(height: 16),
                _buildFilterBar(context, state),
                const SizedBox(height: 16),
                Expanded(child: _buildContent(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, BriefStatementLoaded state) {
    final isCustomer = widget.isCustomerMode;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.summarize_outlined,
            color: AppTheme.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCustomer ? 'كشف عميل مختصر' : 'كشف مورد مختصر',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
            ),
            Text(
              isCustomer
                  ? 'عرض الحركات مجمعة للعميل على مستوى الفاتورة أو السند بدون تفاصيل الأصناف'
                  : 'عرض الحركات مجمعة للمورد على مستوى الفاتورة أو السند بدون تفاصيل الأصناف',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            ),
          ],
        ),
        const Spacer(),

        if (state.statementRows.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('طباعة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
                onPressed: _printStatement,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('حفظ PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
                onPressed: _savePdf,
              ),
            ],
          ),

        const SizedBox(width: 8),

        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'إعادة تعيين',
          onPressed: () => context.read<BriefStatementCubit>().reset(),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, BriefStatementLoaded state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isCustomerMode ? 'العميل' : 'المورد',
                        style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      state.isCustomerMode
                          ? _buildCustomerAutocomplete(context, state)
                          : _buildSupplierAutocomplete(context, state),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('من تاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
                      const SizedBox(height: 6),
                      _datePicker(
                        value: state.fromDate,
                        hint: 'اختر التاريخ',
                        onTap: () => context.read<BriefStatementCubit>().pickFromDate(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إلى تاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
                      const SizedBox(height: 6),
                      _datePicker(
                        value: state.toDate,
                        hint: 'اختر التاريخ',
                        onTap: () => context.read<BriefStatementCubit>().pickToDate(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('عرض الكشف'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => context.read<BriefStatementCubit>().loadStatement(),
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

  Widget _buildCustomerAutocomplete(BuildContext context, BriefStatementLoaded state) {
    return LayoutBuilder(builder: (context, constraints) {
      return Autocomplete<CustomerModel>(
        displayStringForOption: (c) => '${c.code} - ${c.name}',
        optionsBuilder: (textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return state.customers;
          }
          final q = textEditingValue.text.toLowerCase();
          return state.customers.where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q));
        },
        onSelected: (c) => context.read<BriefStatementCubit>().selectCustomer(c),
        fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
          textCtrl.addListener(() {
            if (textCtrl.text.isEmpty) {
              context.read<BriefStatementCubit>().selectCustomer(null);
            }
          });
          if (state.selectedCustomer != null && textCtrl.text.isEmpty) {
            final c = state.selectedCustomer!;
            textCtrl.text = '${c.code} - ${c.name}';
          }
          return TextFormField(
            controller: textCtrl,
            focusNode: focusNode,
            onFieldSubmitted: (_) => onFieldSubmitted(),
            decoration: InputDecoration(
              hintText: 'ابحث بالكود أو الاسم...',
              prefixIcon: const Icon(Icons.person_outline, size: 18),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: state.selectedCustomer != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        textCtrl.clear();
                        context.read<BriefStatementCubit>().selectCustomer(null);
                      },
                    )
                  : const Icon(Icons.arrow_drop_down),
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
                    return Builder(builder: (context) {
                      final bool isHighlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      return Material(
                        color: isHighlighted ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_outline,
                                size: 14, color: AppTheme.primary),
                          ),
                          title: Text(option.name, style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                          subtitle: Text(option.code, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    });
                  },
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildSupplierAutocomplete(BuildContext context, BriefStatementLoaded state) {
    return LayoutBuilder(builder: (context, constraints) {
      return Autocomplete<SupplierModel>(
        displayStringForOption: (s) => '${s.supplierCode} - ${s.name}',
        optionsBuilder: (textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return state.suppliers;
          }
          final q = textEditingValue.text.toLowerCase();
          return state.suppliers.where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.supplierCode.toLowerCase().contains(q));
        },
        onSelected: (s) => context.read<BriefStatementCubit>().selectSupplier(s),
        fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
          textCtrl.addListener(() {
            if (textCtrl.text.isEmpty) {
              context.read<BriefStatementCubit>().selectSupplier(null);
            }
          });
          if (state.selectedSupplier != null && textCtrl.text.isEmpty) {
            final s = state.selectedSupplier!;
            textCtrl.text = '${s.supplierCode} - ${s.name}';
          }
          return TextFormField(
            controller: textCtrl,
            focusNode: focusNode,
            onFieldSubmitted: (_) => onFieldSubmitted(),
            decoration: InputDecoration(
              hintText: 'ابحث بالكود أو الاسم...',
              prefixIcon: const Icon(Icons.local_shipping_outlined, size: 18),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: state.selectedSupplier != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        textCtrl.clear();
                        context.read<BriefStatementCubit>().selectSupplier(null);
                      },
                    )
                  : const Icon(Icons.arrow_drop_down),
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
                    return Builder(builder: (context) {
                      final bool isHighlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      return Material(
                        color: isHighlighted ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.local_shipping_outlined,
                                size: 14, color: AppTheme.primary),
                          ),
                          title: Text(option.name, style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                          subtitle: Text(option.supplierCode, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                          onTap: () => onSelected(option),
                        ),
                      );
                    });
                  },
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _datePicker({
    required DateTime? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFBDBDBD)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              value != null ? AppUtils.formatDate(value) : hint,
              style: value != null
                  ? TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)
                  : TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, BriefStatementLoaded state) {
    final isCustomer = state.isCustomerMode;
    final selected = isCustomer ? state.selectedCustomer : state.selectedSupplier;

    if (selected == null) {
      return _buildPlaceholder(
        icon: isCustomer ? Icons.person_search_outlined : Icons.find_in_page_outlined,
        title: isCustomer ? 'اختر عميلاً' : 'اختر مورداً',
        subtitle: 'حدد الاسم والفترة الزمنية ثم اضغط "عرض الكشف"',
      );
    }

    if (state.statementRows.isEmpty) {
      return _buildPlaceholder(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد حركات',
        subtitle: 'لا توجد معاملات مسجلة في هذه الفترة',
      );
    }

    return Column(
      children: [
        _buildSummaryCards(state),
        const SizedBox(height: 16),
        Expanded(child: _buildTable(state)),
      ],
    );
  }

  Widget _buildSummaryCards(BriefStatementLoaded state) {
    final balance = state.finalBalance;
    final isCustomer = state.isCustomerMode;
    final currency = isCustomer
        ? (state.selectedCustomer?.currency ?? 'EGP')
        : (state.selectedSupplier?.currency ?? 'EGP');

    Color balColor = AppTheme.primary;
    String balLabel = 'الرصيد النهائي (متوازن)';

    if (balance != 0) {
      if (isCustomer) {
        balColor = balance > 0 ? AppTheme.danger : AppTheme.success;
        balLabel = balance > 0 ? 'الرصيد النهائي (عليه)' : 'الرصيد النهائي (له)';
      } else {
        balColor = balance > 0 ? AppTheme.success : AppTheme.danger;
        balLabel = balance > 0 ? 'الرصيد النهائي (له)' : 'الرصيد النهائي (عليه)';
      }
    }

    return Row(
      children: [
        _summaryCard(
          label: isCustomer ? 'إجمالي عليه (مدين)' : 'إجمالي عليه (مدين)',
          value: AppUtils.formatCurrency(state.totalDebit, currency),
          color: AppTheme.danger,
          icon: Icons.arrow_upward,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: isCustomer ? 'إجمالي له (دائن)' : 'إجمالي له (دائن)',
          value: AppUtils.formatCurrency(state.totalCredit, currency),
          color: AppTheme.success,
          icon: Icons.arrow_downward,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: balLabel,
          value: AppUtils.formatCurrency(balance.abs(), currency),
          color: balColor,
          icon: Icons.account_balance_outlined,
          isBold: true,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: 'عدد الحركات مجمعة',
          value: state.statementRows.length.toString(),
          color: AppTheme.primary,
          icon: Icons.format_list_numbered,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    bool isBold = false,
  }) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: isBold ? 15 : 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontFamily: 'Cairo',
                          ),
                        ),
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

  Widget _buildTable(BriefStatementLoaded state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: state.statementRows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) => _buildTableRow(
                    state,
                    state.statementRows[index],
                    index,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('رقم الفاتورة أو المعاملة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 90, child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 110, child: Text('اسم الحساب', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(child: Text('البيان', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 100, child: Text('منه', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('له', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 130, child: Text('الرصيد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BriefStatementLoaded state, StatementRow row, int index) {
    final isEven = index % 2 == 0;
    final isCustomer = state.isCustomerMode;
    final currency = isCustomer
        ? (state.selectedCustomer?.currency ?? 'EGP')
        : (state.selectedSupplier?.currency ?? 'EGP');

    final double balVal = row.balance;
    Color balColor = Colors.white;
    String balDirection = 'متوازن';

    if (balVal != 0) {
      if (isCustomer) {
        balColor = balVal > 0 ? AppTheme.danger : AppTheme.success;
        balDirection = balVal > 0 ? 'عليه' : 'له';
      } else {
        balColor = balVal > 0 ? AppTheme.success : AppTheme.danger;
        balDirection = balVal > 0 ? 'له' : 'عليه';
      }
    }

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(row.transactionNumber, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),

          SizedBox(
            width: 90,
            child: Text(
              AppUtils.formatDate(AppUtils.parseDate(row.date)),
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            ),
          ),

          SizedBox(
            width: 110,
            child: Text(
              row.accountName,
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            child: Tooltip(
              message: row.description,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                row.description,
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              row.debit > 0 ? AppUtils.formatCurrency(row.debit, currency) : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: row.debit > 0 ? AppTheme.danger : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              row.credit > 0 ? AppUtils.formatCurrency(row.credit, currency) : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: row.credit > 0 ? AppTheme.success : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 130,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppUtils.formatCurrency(row.balance.abs(), currency),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: balColor,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                if (row.type != 'opening')
                  Text(
                    balDirection,
                    style: TextStyle(
                      fontSize: 10,
                      color: balColor,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _printStatement() async {
    final rawState = context.read<BriefStatementCubit>().state;
    if (rawState is! BriefStatementLoaded) return;
    final isCustomer = rawState.isCustomerMode;
    final customer = rawState.selectedCustomer;
    final supplier = rawState.selectedSupplier;

    try {
      await BriefStatementPdfService.generateAndPrint(
        isCustomerMode: isCustomer,
        customer: customer,
        supplier: supplier,
        rows: rawState.statementRows,
        totalDebit: rawState.totalDebit,
        totalCredit: rawState.totalCredit,
        finalBalance: rawState.finalBalance,
        totalMeters: rawState.totalMeters,
        fromDate: rawState.fromDate,
        toDate: rawState.toDate,
        statementNumber: rawState.statementNumber,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء PDF: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _savePdf() async {
    final rawState = context.read<BriefStatementCubit>().state;
    if (rawState is! BriefStatementLoaded) return;
    final isCustomer = rawState.isCustomerMode;
    final customer = rawState.selectedCustomer;
    final supplier = rawState.selectedSupplier;

    try {
      await BriefStatementPdfService.saveToFile(
        context,
        isCustomerMode: isCustomer,
        customer: customer,
        supplier: supplier,
        rows: rawState.statementRows,
        totalDebit: rawState.totalDebit,
        totalCredit: rawState.totalCredit,
        finalBalance: rawState.finalBalance,
        totalMeters: rawState.totalMeters,
        fromDate: rawState.fromDate,
        toDate: rawState.toDate,
        statementNumber: rawState.statementNumber,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ الملف: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }
}
