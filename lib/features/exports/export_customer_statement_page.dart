import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/language_dialog.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../ui/widgets/app_search_field.dart';
import 'export_customer_statement_cubit.dart';
import 'export_customer_statement_state.dart';
import 'export_customer_statement_pdf_service.dart';
import 'export_customer_statement_excel_service.dart';

class ExportCustomerStatementPage extends StatefulWidget {
  const ExportCustomerStatementPage({super.key});

  @override
  State<ExportCustomerStatementPage> createState() =>
      _ExportCustomerStatementPageState();
}

class _ExportCustomerStatementPageState
    extends State<ExportCustomerStatementPage> {
  final _customerController = TextEditingController();
  final _customerFocusNode = FocusNode();

  @override
  void dispose() {
    _customerController.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExportCustomerStatementCubit,
        ExportCustomerStatementState>(
      builder: (context, state) {
        if (state is ExportCustomerStatementError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppTheme.danger),
                const SizedBox(height: 16),
                Text(state.message,
                    style: const TextStyle(
                        color: AppTheme.danger,
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      context.read<ExportCustomerStatementCubit>().init(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is! ExportCustomerStatementLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;
              final content = Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, state),
                    const SizedBox(height: 16),
                    _buildFilterBar(context, state),
                    const SizedBox(height: 16),
                    if (isMobile)
                      _buildContent(context, state)
                    else
                      Expanded(child: _buildContent(context, state)),
                  ],
                ),
              );
              if (isMobile) {
                return SingleChildScrollView(
                    child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: content,
                ));
              }
              return content;
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, ExportCustomerStatementLoaded state) {
    final hasData =
        state.selectedCustomer != null && state.statementRows.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('كشف حساب العميل (التصدير)',
                        style: AppTheme.heading2.copyWith(fontSize: 20),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    tooltip: 'إعادة تعيين',
                    onPressed: () =>
                        context.read<ExportCustomerStatementCubit>().reset(),
                  ),
                ],
              ),
              if (hasData) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon:
                            const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('طباعة'),
                        onPressed: () => _printStatement(context, state),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('حفظ PDF'),
                        onPressed: () => _savePdf(context, state),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('حفظ Excel'),
                        onPressed: () => _saveExcel(context, state),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }
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
                Icons.receipt_long_outlined,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text('كشف حساب العميل (التصدير)',
                style: AppTheme.heading2.copyWith(fontSize: 20)),
            const Spacer(),
            if (hasData) ...[
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
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'إعادة تعيين',
              onPressed: () =>
                  context.read<ExportCustomerStatementCubit>().reset(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(
      BuildContext context, ExportCustomerStatementLoaded state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 700;
                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: AppSearchField<CustomerModel>(
                          label: 'العميل',
                          hint: 'ابحث بالكود أو الاسم...',
                          controller: _customerController,
                          focusNode: _customerFocusNode,
                          prefixIcon:
                              const Icon(Icons.person_outline, size: 18),
                          suggestionsCallback: (query) {
                            if (query.isEmpty) return state.customers;
                            return state.customers
                                .where((c) =>
                                    c.name
                                        .toLowerCase()
                                        .contains(query.toLowerCase()) ||
                                    c.code
                                        .toLowerCase()
                                        .contains(query.toLowerCase()))
                                .toList();
                          },
                          itemBuilder: (context, customer) {
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.1),
                                child: const Icon(Icons.person_outline,
                                    size: 16, color: AppTheme.primary),
                              ),
                              title: Text(customer.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontSize: 15)),
                              subtitle: Text(customer.code,
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontSize: 13)),
                            );
                          },
                          onSelected: (customer) {
                            _customerController.text =
                                '${customer.code} - ${customer.name}';
                            context
                                .read<ExportCustomerStatementCubit>()
                                .selectCustomer(customer);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('من تاريخ',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 14)),
                            const SizedBox(height: 6),
                            _buildDateField(
                              context: context,
                              value: state.fromDate,
                              hint: 'من تاريخ',
                              onTap: () => context
                                  .read<ExportCustomerStatementCubit>()
                                  .pickFromDate(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('إلى تاريخ',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 14)),
                            const SizedBox(height: 6),
                            _buildDateField(
                              context: context,
                              value: state.toDate,
                              hint: 'إلى تاريخ',
                              onTap: () => context
                                  .read<ExportCustomerStatementCubit>()
                                  .pickToDate(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('عرض الكشف',
                              style:
                                  TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => context
                              .read<ExportCustomerStatementCubit>()
                              .loadStatement(),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
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
                          return state.customers
                              .where((c) =>
                                  c.name
                                      .toLowerCase()
                                      .contains(query.toLowerCase()) ||
                                  c.code
                                      .toLowerCase()
                                      .contains(query.toLowerCase()))
                              .toList();
                        },
                        itemBuilder: (context, customer) {
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  AppTheme.primary.withValues(alpha: 0.1),
                              child: const Icon(Icons.person_outline,
                                  size: 16, color: AppTheme.primary),
                            ),
                            title: Text(customer.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 15)),
                            subtitle: Text(customer.code,
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                          );
                        },
                        onSelected: (customer) {
                          _customerController.text =
                              '${customer.code} - ${customer.name}';
                          context
                              .read<ExportCustomerStatementCubit>()
                              .selectCustomer(customer);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('من تاريخ',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          _buildDateField(
                            context: context,
                            value: state.fromDate,
                            hint: 'من تاريخ',
                            onTap: () => context
                                .read<ExportCustomerStatementCubit>()
                                .pickFromDate(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('إلى تاريخ',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          _buildDateField(
                            context: context,
                            value: state.toDate,
                            hint: 'إلى تاريخ',
                            onTap: () => context
                                .read<ExportCustomerStatementCubit>()
                                .pickToDate(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('عرض الكشف',
                            style:
                                TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => context
                            .read<ExportCustomerStatementCubit>()
                            .loadStatement(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField({
    required BuildContext context,
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
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? AppUtils.formatDate(value) : hint,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: value != null
                    ? const TextStyle(
                        color: Colors.white, fontFamily: 'Cairo', fontSize: 15)
                    : TextStyle(
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, ExportCustomerStatementLoaded state) {
    if (state.selectedCustomer == null) {
      return _buildPlaceholder(
        icon: Icons.person_search_outlined,
        title: 'اختر عميلاً',
        subtitle: 'اختر العميل وحدد الفترة الزمنية ثم اضغط "عرض الكشف"',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isScrollable =
            !constraints.hasBoundedHeight || constraints.maxHeight > 800;
        final tableWidget = state.statementRows.isEmpty
            ? _buildPlaceholder(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد حركات',
                subtitle: 'لا توجد معاملات تصدير في الفترة المحددة',
              )
            : _buildTable(state);
        return Column(
          mainAxisSize: isScrollable ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _buildSummaryCards(state),
            const SizedBox(height: 16),
            if (state.fromDate != null && state.openingBalance != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(
                  builder: (ctx) {
                    final isNeg = state.openingBalance < 0;
                    final noteColor = isNeg ? AppTheme.danger : AppTheme.info;
                    final curr = state.selectedCustomer?.currency ?? 'EGP';
                    final absVal =
                        AppUtils.formatNumber(state.openingBalance.abs());
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: noteColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: noteColor.withAlpha(60)),
                      ),
                      child: RichText(
                        textDirection: TextDirection.rtl,
                        text: TextSpan(
                          style: TextStyle(
                              color: noteColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'Cairo'),
                          children: [
                            const TextSpan(text: 'ملحوظة: الرصيد السابق = '),
                            if (isNeg)
                              TextSpan(
                                  text: '- ',
                                  style: const TextStyle(fontSize: 18)),
                            TextSpan(text: '$absVal $curr'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isScrollable)
              SizedBox(height: 400, child: tableWidget)
            else
              Expanded(child: tableWidget),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(ExportCustomerStatementLoaded state) {
    final balance = state.finalBalance;
    final balColor = balance > 0 ? AppTheme.danger : AppTheme.success;
    final currency = state.selectedCustomer?.currency ?? 'EGP';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final cards = [
          _summaryCard(
            label: 'إجمالي عليه',
            value: _formatCurrency(state.totalDebit, currency),
            color: AppTheme.danger,
            icon: Icons.arrow_upward,
            compact: isMobile,
          ),
          _summaryCard(
            label: 'إجمالي له',
            value: _formatCurrency(state.totalCredit, currency),
            color: AppTheme.success,
            icon: Icons.arrow_downward,
            compact: isMobile,
          ),
          _summaryCard(
            label: balance > 0
                ? 'الرصيد النهائي (عليه)'
                : balance < 0
                    ? 'الرصيد النهائي (له)'
                    : 'الرصيد النهائي (متوازن)',
            value: _formatCurrency(balance.abs(), currency),
            color: balColor,
            icon: Icons.account_balance_outlined,
            isBold: true,
            compact: isMobile,
          ),
          _summaryCard(
            label: 'عدد الحركات',
            value: state.statementRows.length.toString(),
            color: AppTheme.primary,
            icon: Icons.format_list_numbered,
            compact: isMobile,
          ),
        ];
        if (isMobile) {
          return SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => SizedBox(width: 160, child: cards[i]),
            ),
          );
        }
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    bool isBold = false,
    bool compact = false,
  }) {
    final pad = compact ? 8.0 : 16.0;
    final iconSize = compact ? 32.0 : 40.0;
    final iconInner = compact ? 16.0 : 20.0;
    final fontSize = compact ? 11.0 : 13.0;
    final valSize = compact ? 12.0 : (isBold ? 15.0 : 14.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: iconInner),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: fontSize)),
                      SizedBox(height: compact ? 2 : 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: valSize,
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
    );
  }

  static const double _colShipNo = 150;
  static const double _colDate = 130;
  static const double _colAccount = 150;
  static const double _colDesc = 140;
  static const double _colCartons = 50;
  static const double _colDebit = 100;
  static const double _colCredit = 100;
  static const double _colBalance = 110;
  static const double _colNotes = 100;
  static const double _colHPad = 24;
  static final double _tableWidth = _colShipNo +
      _colDate +
      _colAccount +
      _colDesc +
      _colCartons +
      _colDebit +
      _colCredit +
      _colBalance +
      _colNotes +
      _colHPad;

  Widget _buildTable(ExportCustomerStatementLoaded state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final minWidth = constraints.maxWidth > _tableWidth
                        ? constraints.maxWidth
                        : _tableWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: minWidth,
                        child: Column(
                          children: [
                            _buildTableHeader(),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView.separated(
                                itemCount: state.statementRows.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (context, index) => _buildTableRow(
                                    context,
                                    state.statementRows[index],
                                    state.selectedCustomer?.currency ?? 'EGP',
                                    state.rowNotes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          SizedBox(width: _colShipNo, child: Text('رقم الشحنة',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          SizedBox(width: _colDate, child: Text('التاريخ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          SizedBox(width: _colAccount, child: Text('نوع الحساب',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          Expanded(child: Text('البيان',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colCartons, child: Text('الكراتين',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colDebit, child: Text('المدين',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colCredit, child: Text('الدائن',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colBalance, child: Text('الرصيد',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colNotes, child: Text('ملاحظات',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  String _formatCurrency(double amount, String currency) {
    final code = currency.isNotEmpty ? currency : 'EGP';
    return '${AppUtils.formatNumber(amount)} $code';
  }

  Widget _buildTableRow(BuildContext context, StatementRow row, String currency,
      Map<String, String> rowNotes) {
    return Container(
      color: Colors.white.withValues(alpha: 0.03),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: _colShipNo, child: Text(row.transactionNumber,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right),
          ),
          SizedBox(width: _colDate, child: Text(
              _formatDateDisplay(row.date),
              style: TextStyle(
                  color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: _colAccount, child: Text(row.accountName,
                style: TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(child: Text(
              row.description.replaceAll(' - ', ' \u200E-\u200E '),
              style: TextStyle(
                  color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                  overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: _colCartons, child: Text(
              row.piecesCount > 0
                  ? AppUtils.formatNumber(row.piecesCount)
                  : '—',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: _colDebit, child: Text(
              row.debit > 0 ? _formatCurrency(row.debit, currency) : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: row.debit > 0 ? AppTheme.danger : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: _colCredit, child: Text(
              row.credit > 0 ? _formatCurrency(row.credit, currency) : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color:
                    row.credit > 0 ? AppTheme.success : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: _colBalance, child: Column(
              children: [
                Text(
                  _formatCurrency(row.balance, currency),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: row.balance > 0 ? AppTheme.danger : AppTheme.success,
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
                    fontSize: 9,
                    color: row.balance > 0 ? AppTheme.danger : AppTheme.success,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(width: _colNotes, child: GestureDetector(
              onTap: () => _showNoteDialog(context, row.transactionNumber),
              child: (rowNotes[row.transactionNumber] ?? '').isNotEmpty
                  ? Text(rowNotes[row.transactionNumber]!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2)
                  : Icon(Icons.edit_note_rounded,
                      size: 18, color: AppTheme.textMuted.withAlpha(120)),
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
          Icon(icon,
              size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _printStatement(
      BuildContext context, ExportCustomerStatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = customer.currency.isNotEmpty ? customer.currency : 'EGP';
        obNote =
            'Note: Opening balance = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      await ExportCustomerStatementPdfService.print(
        customer: customer,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء PDF: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _savePdf(
      BuildContext context, ExportCustomerStatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = customer.currency.isNotEmpty ? customer.currency : 'EGP';
        obNote =
            'Note: Opening balance = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      final path = await ExportCustomerStatementPdfService.saveToFile(
        customer: customer,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
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

  Future<void> _saveExcel(
      BuildContext context, ExportCustomerStatementLoaded state) async {
    final customer = state.selectedCustomer;
    if (customer == null) return;

    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = customer.currency.isNotEmpty ? customer.currency : 'EGP';
        obNote =
            'Note: Opening balance = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      final path = await ExportCustomerStatementExcelService.saveToFile(
        customer: customer,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
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

  void _showNoteDialog(BuildContext context, String transactionNumber) {
    final loadedState = context.read<ExportCustomerStatementCubit>().state;
    final currentNote = (loadedState is ExportCustomerStatementLoaded)
        ? (loadedState.rowNotes[transactionNumber] ?? '')
        : '';
    final controller = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('ملاحظة',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'أضف ملاحظة...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          if (currentNote.isNotEmpty)
            TextButton(
              onPressed: () {
                context
                    .read<ExportCustomerStatementCubit>()
                    .setRowNote(transactionNumber, '');
                Navigator.pop(ctx);
              },
              child: const Text('حذف',
                  style:
                      TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              context
                  .read<ExportCustomerStatementCubit>()
                  .setRowNote(transactionNumber, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  String _formatDateDisplay(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return '—';
    if (dateStr.contains('/')) return dateStr;
    try {
      return AppUtils.formatDate(AppUtils.parseDate(dateStr));
    } catch (_) {
      return dateStr;
    }
  }
}
