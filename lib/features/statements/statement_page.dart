import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'statement_cubit.dart';
import 'statement_state.dart';
import '../../data/models/statement_row_model.dart';
import 'statement_pdf_service.dart';
import 'statement_excel_service.dart';
import '../../data/models/customer_model.dart';
import '../../ui/widgets/app_search_field.dart';

class StatementPage extends StatefulWidget {
  const StatementPage({super.key});

  @override
  State<StatementPage> createState() => _StatementPageState();
}

class _StatementPageState extends State<StatementPage> {
  final _customerController = TextEditingController();
  final _customerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatementCubit>().refreshCustomers();
    });
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatementCubit, StatementState>(
      builder: (context, state) {
        if (state is StatementError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(state.message, style: const TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontSize: 14)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.read<StatementCubit>().loadStatement(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is! StatementLoaded) return const SizedBox();
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, state),
                const SizedBox(height: 20),
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

  Widget _buildHeader(BuildContext context, StatementLoaded state) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppTheme.accent, size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('كشف الحساب', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
            Text('اختر عميلاً وفترة زمنية لعرض الحركات',
                style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
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
                onPressed: () => _printStatement(context, state),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('حفظ PDF'),
                onPressed: () => _savePdf(context, state),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('حفظ Excel'),
                onPressed: () => _saveExcel(context, state),
              ),
            ],
          ),

        const SizedBox(width: 8),

        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'إعادة تعيين',
          onPressed: () {
            _customerController.clear();
            context.read<StatementCubit>().reset();
          },
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, StatementLoaded state) {
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
                  child: AppSearchField<CustomerModel>(
                    label: 'العميل',
                    hint: 'ابحث بالكود أو الاسم...',
                    controller: _customerController,
                    focusNode: _customerFocusNode,
                    prefixIcon: const Icon(Icons.person_outline, size: 18),
                    suggestionsCallback: (query) {
                      if (query.isEmpty) return state.customers;
                      return state.customers.where((c) =>
                          c.name.toLowerCase().contains(query.toLowerCase()) ||
                          c.code.toLowerCase().contains(query.toLowerCase())).toList();
                    },
                    itemBuilder: (context, customer) {
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.person_outline, size: 16, color: AppTheme.primary),
                        ),
                        title: Text(customer.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)),
                        subtitle: Text(customer.code, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                      );
                    },
                    onSelected: (customer) {
                      _customerController.text = '${customer.code} - ${customer.name}';
                      context.read<StatementCubit>().selectCustomer(customer);
                    },
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
                        hint:  'اختر التاريخ',
                        onTap: () => context.read<StatementCubit>().pickFromDate(context),
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
                        hint:  'اختر التاريخ',
                        onTap: () => context.read<StatementCubit>().pickToDate(context),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onPressed: () => context.read<StatementCubit>().loadStatement(),
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

  Widget _datePicker({
    required DateTime? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border:       Border.all(color: const Color(0xFFBDBDBD)),
          borderRadius: BorderRadius.circular(8),
          color:        Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              value != null
                  ? AppUtils.formatDate(value)
                  : hint,
              style: value != null
                  ? TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15)
                  : TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, StatementLoaded state) {
    if (state.selectedCustomer == null) {
      return _buildPlaceholder(
        icon:    Icons.person_search_outlined,
        title:   'اختر عميلاً',
        subtitle: 'اختر العميل وحدد الفترة الزمنية ثم اضغط "عرض الكشف"',
      );
    }

    return Column(
      children: [
        _buildSummaryCards(state),
        const SizedBox(height: 16),
        Expanded(
          child: state.statementRows.isEmpty
              ? _buildPlaceholder(
                  icon:    Icons.receipt_long_outlined,
                  title:   'لا توجد حركات',
                  subtitle: 'لا توجد معاملات في الفترة المحددة',
                )
              : _buildTable(state),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(StatementLoaded state) {
    final balance  = state.finalBalance;
    final balColor = balance > 0
        ? AppTheme.danger
        : AppTheme.success;
    final currency = state.selectedCustomer?.currency ?? 'EGP';

    return Row(
      children: [
        _summaryCard(
          label: 'إجمالي عليه',
          value: AppUtils.formatCurrency(state.totalDebit, currency),
          color: AppTheme.danger,
          icon:  Icons.arrow_upward,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: 'إجمالي له',
          value: AppUtils.formatCurrency(state.totalCredit, currency),
          color: AppTheme.success,
          icon:  Icons.arrow_downward,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: balance > 0
              ? 'الرصيد النهائي (عليه)'
              : balance < 0
                  ? 'الرصيد النهائي (له)'
                  : 'الرصيد النهائي (متوازن)',
          value: AppUtils.formatCurrency(balance.abs(), currency),
          color: balColor,
          icon:  Icons.account_balance_outlined,
          isBold: true,
        ),
        const SizedBox(width: 12),
        _summaryCard(
          label: 'عدد الحركات',
          value: state.statementRows.length.toString(),
          color: AppTheme.primary,
          icon:  Icons.format_list_numbered,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String  label,
    required String  value,
    required Color   color,
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
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color:        color.withValues(alpha: 0.1),
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
                            fontSize:   isBold ? 15 : 14,
                            fontWeight: FontWeight.bold,
                            color:      color,
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

  Widget _buildTable(StatementLoaded state) {
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
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) =>
                      _buildTableRow(
                    state.statementRows[index],
                    index,
                    state.selectedCustomer?.currency ?? 'EGP',
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
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          SizedBox(width: 120,
              child: Text('رقم الفاتورة أو المعاملة', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 90,
              child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 110,
              child: Text('اسم الحساب', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(
              child: Text('البيان', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 50,
              child: Text('العدد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 70,
              child: Text('الكمية', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 80,
              child: Text('السعر', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 100,
              child: Text('منه', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 100,
              child: Text('له', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: 110,
              child: Text('الرصيد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(StatementRow row, int index, String currency) {
    final isEven     = index % 2 == 0;

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(row.transactionNumber,
                style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),

          SizedBox(
            width: 90,
            child: Text(
              AppUtils.formatDate(
                  AppUtils.parseDate(row.date)),
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            ),
          ),

          SizedBox(
            width: 110,
            child: Text(row.accountName,
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                overflow: TextOverflow.ellipsis),
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
            width: 50,
            child: Text(
              row.piecesCount > 0
                  ? AppUtils.formatNumber(row.piecesCount)
                  : '—',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 70,
            child: Text(
              row.quantity > 0
                  ? AppUtils.formatNumber(row.quantity)
                  : '—',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 80,
            child: Text(
              row.unitPrice > 0
                  ? AppUtils.formatCurrency(row.unitPrice, currency)
                  : '—',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              row.debit > 0
                  ? AppUtils.formatCurrency(row.debit, currency)
                  : '—',
              style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.bold,
                color: row.debit > 0
                    ? AppTheme.danger
                    : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              row.credit > 0
                  ? AppUtils.formatCurrency(row.credit, currency)
                  : '—',
              style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.bold,
                color: row.credit > 0
                    ? AppTheme.success
                    : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 110,
            child: Column(
              children: [
                Text(
                  AppUtils.formatCurrency(row.balance, currency),
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.bold,
                    color:      row.balance > 0 ? AppTheme.danger : AppTheme.success,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  row.balance > 0
                      ? 'عليه'
                      : row.balance < 0
                          ? 'له'
                          : 'متوازن',
                  style: TextStyle(
                    fontSize:   9,
                    color:      row.balance > 0 ? AppTheme.danger : AppTheme.success,
                    fontFamily: 'Cairo',
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
    required String   title,
    required String   subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _printStatement(BuildContext context, StatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      await StatementPdfService.generateAndPrint(
        customer:        customer,
        rows:            state.statementRows,
        totalDebit:      state.totalDebit,
        totalCredit:     state.totalCredit,
        finalBalance:    state.finalBalance,
        fromDate:        state.fromDate,
        toDate:          state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إنشاء PDF: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _savePdf(BuildContext context, StatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      await StatementPdfService.saveToFile(
        context,
        customer:        customer,
        rows:            state.statementRows,
        totalDebit:      state.totalDebit,
        totalCredit:     state.totalCredit,
        finalBalance:    state.finalBalance,
        fromDate:        state.fromDate,
        toDate:          state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الملف: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _saveExcel(BuildContext context, StatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      final path = await StatementExcelService.saveToFile(
        context,
        customer:        customer,
        rows:            state.statementRows,
        totalDebit:      state.totalDebit,
        totalCredit:     state.totalCredit,
        finalBalance:    state.finalBalance,
        fromDate:        state.fromDate,
        toDate:          state.toDate,
        statementNumber: state.statementNumber,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ في: $path'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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
