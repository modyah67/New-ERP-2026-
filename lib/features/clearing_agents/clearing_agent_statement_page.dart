import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/language_dialog.dart';
import '../../core/statement_pdf_service.dart';
import '../../core/statement_excel_service.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/statement_row_model.dart';
import 'clearing_agent_statement_cubit.dart';
import 'clearing_agent_statement_state.dart';

class ClearingAgentStatementPage extends StatefulWidget {
  const ClearingAgentStatementPage({super.key});

  @override
  State<ClearingAgentStatementPage> createState() =>
      _ClearingAgentStatementPageState();
}

class _ClearingAgentStatementPageState
    extends State<ClearingAgentStatementPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ClearingAgentStatementCubit,
        ClearingAgentStatementState>(
      builder: (context, state) {
        if (state is ClearingAgentStatementError) {
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
                      context.read<ClearingAgentStatementCubit>().init(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is! ClearingAgentStatementLoaded) {
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
      BuildContext context, ClearingAgentStatementLoaded state) {
    final hasData =
        state.selectedAgent != null && state.statementRows.isNotEmpty;
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
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: AppTheme.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('كشف حساب المخلص',
                        style: AppTheme.heading2.copyWith(fontSize: 20),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    tooltip: 'إعادة تعيين',
                    onPressed: () =>
                        context.read<ClearingAgentStatementCubit>().reset(),
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
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long_outlined,
                  color: AppTheme.accent, size: 24),
            ),
            const SizedBox(width: 12),
            Text('كشف حساب المخلص',
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
                  context.read<ClearingAgentStatementCubit>().reset(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(
      BuildContext context, ClearingAgentStatementLoaded state) {
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
                      _buildAgentAutocomplete(context, state),
                      const SizedBox(height: 12),
                      _buildDateColumn(
                          context,
                          'من تاريخ',
                          state.fromDate,
                          () => context
                              .read<ClearingAgentStatementCubit>()
                              .pickFromDate(context)),
                      const SizedBox(height: 12),
                      _buildDateColumn(
                          context,
                          'إلى تاريخ',
                          state.toDate,
                          () => context
                              .read<ClearingAgentStatementCubit>()
                              .pickToDate(context)),
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
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => context
                              .read<ClearingAgentStatementCubit>()
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
                        child: _buildAgentAutocomplete(context, state)),
                    const SizedBox(width: 12),
                    Expanded(
                        flex: 2,
                        child: _buildDateColumn(
                            context,
                            'من تاريخ',
                            state.fromDate,
                            () => context
                                .read<ClearingAgentStatementCubit>()
                                .pickFromDate(context))),
                    const SizedBox(width: 12),
                    Expanded(
                        flex: 2,
                        child: _buildDateColumn(
                            context,
                            'إلى تاريخ',
                            state.toDate,
                            () => context
                                .read<ClearingAgentStatementCubit>()
                                .pickToDate(context))),
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
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => context
                            .read<ClearingAgentStatementCubit>()
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

  Widget _buildAgentAutocomplete(
      BuildContext context, ClearingAgentStatementLoaded state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('المخلص',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return Autocomplete<ClearingAgentModel>(
              displayStringForOption: (a) => '${a.code} - ${a.name}',
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return state.agents;
                return state.agents.where((a) =>
                    a.name
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()) ||
                    a.code
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (a) =>
                  context.read<ClearingAgentStatementCubit>().selectAgent(a),
              fieldViewBuilder: (context, textEditingController, focusNode,
                  onFieldSubmitted) {
                textEditingController.addListener(() {
                  if (textEditingController.text.isEmpty) {
                    context
                        .read<ClearingAgentStatementCubit>()
                        .selectAgent(null);
                  }
                });
                if (state.selectedAgent != null &&
                    textEditingController.text.isEmpty) {
                  textEditingController.text =
                      '${state.selectedAgent!.code} - ${state.selectedAgent!.name}';
                }
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالكود أو الاسم...',
                    prefixIcon: const Icon(Icons.person_outline, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: state.selectedAgent != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              textEditingController.clear();
                              context
                                  .read<ClearingAgentStatementCubit>()
                                  .selectAgent(null);
                            },
                          )
                        : const Icon(Icons.arrow_drop_down),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final optionsList = options.toList();
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
                        itemCount: optionsList.length,
                        itemBuilder: (context, index) {
                          final option = optionsList[index];
                          return ListTile(
                            title: Text('${option.code} - ${option.name}',
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 14)),
                            dense: true,
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateColumn(
      BuildContext context, String label, DateTime? value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        _buildDateField(
            context: context, value: value, hint: label, onTap: onTap),
      ],
    );
  }

  Widget _buildDateField(
      {required BuildContext context,
      required DateTime? value,
      required String hint,
      required VoidCallback onTap}) {
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
      BuildContext context, ClearingAgentStatementLoaded state) {
    if (state.selectedAgent == null) {
      return _buildPlaceholder(
          icon: Icons.person_search_outlined,
          title: 'اختر مخلص',
          subtitle: 'اختر المخلص وحدد الفترة ثم اضغط "عرض الكشف"');
    }
    if (state.statementRows.isEmpty) {
      return _buildPlaceholder(
          icon: Icons.receipt_long_outlined,
          title: 'لا توجد حركات',
          subtitle: 'لا توجد تكاليف في الفترة المحددة');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isScrollable =
            !constraints.hasBoundedHeight || constraints.maxHeight > 800;
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
                    final curr = state.selectedAgent?.currency ?? 'EGP';
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
              SizedBox(height: 400, child: _buildTable(state))
            else
              Expanded(child: _buildTable(state)),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(ClearingAgentStatementLoaded state) {
    final currency = state.selectedAgent?.currency ?? 'EGP';
    final balance = state.finalBalance;
    final balColor = balance > 0
        ? AppTheme.success
        : balance < 0
            ? AppTheme.danger
            : AppTheme.textSecondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final cards = [
          _summaryCard(
              label: 'إجمالي عليه',
              value: _formatCurrency(state.totalDebit, currency),
              color: AppTheme.danger,
              icon: Icons.arrow_upward,
              compact: isMobile),
          _summaryCard(
              label: 'إجمالي له',
              value: _formatCurrency(state.totalCredit, currency),
              color: AppTheme.success,
              icon: Icons.arrow_downward,
              compact: isMobile),
          _summaryCard(
            label: balance > 0
                ? 'الرصيد النهائي (له)'
                : balance < 0
                    ? 'الرصيد النهائي (عليه)'
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
              compact: isMobile),
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

  Widget _summaryCard(
      {required String label,
      required String value,
      required Color color,
      required IconData icon,
      bool isBold = false,
      bool compact = false}) {
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
                      borderRadius: BorderRadius.circular(10)),
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
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: valSize,
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontFamily: 'Cairo')),
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
  static const double _colDebit = 100;
  static const double _colCredit = 100;
  static const double _colBalance = 110;
  static const double _colNotes = 100;
  static const double _colHPad = 24;
  static final double _tableWidth = _colShipNo +
      _colDate +
      _colAccount +
      _colDesc +
      _colDebit +
      _colCredit +
      _colBalance +
      _colNotes +
      _colHPad;

  Widget _buildTable(ClearingAgentStatementLoaded state) {
    final currency = state.selectedAgent?.currency ?? 'EGP';
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
                                    currency,
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
                  textAlign: TextAlign.right)),
          SizedBox(width: _colDate, child: Text(_formatDateDisplay(row.date),
                  style: TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right)),
          SizedBox(width: _colAccount, child: Text(row.accountName,
                  style: TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
          Expanded(child: Text(row.description.replaceAll(' - ', ' \u200E-\u200E '),
                  style: TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colDebit, child: Text(
                  row.debit > 0 ? _formatCurrency(row.debit, currency) : '—',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: row.debit > 0
                          ? AppTheme.danger
                          : AppTheme.textSecondary,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colCredit, child: Text(
                  row.credit > 0 ? _formatCurrency(row.credit, currency) : '—',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: row.credit > 0
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      fontFamily: 'Cairo'),
                  textAlign: TextAlign.center)),
          SizedBox(width: _colBalance, child: Column(
              children: [
                Text(_formatCurrency(row.balance.abs(), currency),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: row.balance > 0
                            ? AppTheme.success
                            : row.balance < 0
                                ? AppTheme.danger
                                : AppTheme.textSecondary,
                        fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
                Text(
                    row.balance > 0
                        ? 'له'
                        : row.balance < 0
                            ? 'عليه'
                            : 'متوازن',
                    style: TextStyle(
                        fontSize: 9,
                        color: row.balance > 0
                            ? AppTheme.success
                            : row.balance < 0
                                ? AppTheme.danger
                                : AppTheme.textSecondary,
                        fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
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

  Widget _buildPlaceholder(
      {required IconData icon,
      required String title,
      required String subtitle}) {
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

  String _formatCurrency(double amount, String currency) =>
      '${AppUtils.formatNumber(amount)} $currency';

  String _formatDateDisplay(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return '—';
    if (dateStr.contains('/')) return dateStr;
    try {
      return AppUtils.formatDate(AppUtils.parseDate(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _printStatement(
      BuildContext context, ClearingAgentStatementLoaded state) async {
    final agent = state.selectedAgent;
    if (agent == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = agent.currency;
        obNote =
            'ملحوظة: الرصيد السابق = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      await StatementPdfService.printPdf(
        title: 'كشف حساب المخلص',
        vendorName: agent.name,
        vendorCode: agent.code,
        currency: agent.currency,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل إنشاء PDF: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _savePdf(
      BuildContext context, ClearingAgentStatementLoaded state) async {
    final agent = state.selectedAgent;
    if (agent == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = agent.currency;
        obNote =
            'ملحوظة: الرصيد السابق = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      final path = await StatementPdfService.saveToFile(
        title: 'كشف حساب المخلص',
        vendorName: agent.name,
        vendorCode: agent.code,
        currency: agent.currency,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم الحفظ في: $path'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الملف: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _saveExcel(
      BuildContext context, ClearingAgentStatementLoaded state) async {
    final agent = state.selectedAgent;
    if (agent == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      String? obNote;
      if (state.fromDate != null && state.openingBalance != 0) {
        final curr = agent.currency;
        obNote =
            'ملحوظة: الرصيد السابق = ${AppUtils.formatNumber(state.openingBalance)} $curr';
      }
      final path = await StatementExcelService.saveToFile(
        title: 'كشف حساب المخلص',
        vendorName: agent.name,
        vendorCode: agent.code,
        currency: agent.currency,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم الحفظ في: $path'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الملف: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showNoteDialog(BuildContext context, String transactionNumber) {
    final loadedState = context.read<ClearingAgentStatementCubit>().state;
    final currentNote = (loadedState is ClearingAgentStatementLoaded)
        ? (loadedState.rowNotes[transactionNumber] ?? '')
        : '';
    final controller = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.glassBorder)),
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
                borderSide: const BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          if (currentNote.isNotEmpty)
            TextButton(
              onPressed: () {
                context
                    .read<ClearingAgentStatementCubit>()
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
                  .read<ClearingAgentStatementCubit>()
                  .setRowNote(transactionNumber, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}
