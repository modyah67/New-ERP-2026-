import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'supplier_statement_cubit.dart';
import 'supplier_statement_state.dart';
import 'supplier_statement_pdf_service.dart';
import '../../data/models/statement_row_model.dart';
import '../../data/models/supplier_model.dart';

class SupplierStatementPage extends StatefulWidget {
  const SupplierStatementPage({super.key});

  @override
  State<SupplierStatementPage> createState() => _SupplierStatementPageState();
}

class _SupplierStatementPageState extends State<SupplierStatementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SupplierStatementCubit>().refreshSuppliers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupplierStatementCubit, SupplierStatementState>(
      builder: (context, state) {
        if (state is! SupplierStatementLoaded) return const SizedBox();
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

  Widget _buildHeader(BuildContext context, SupplierStatementLoaded state) {
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
                    child: const Icon(Icons.local_shipping_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('كشف حساب مورد',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'Cairo')),
                        Text('اختر مورداً وفترة زمنية لعرض الحركات',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    tooltip: 'إعادة تعيين',
                    onPressed: () =>
                        context.read<SupplierStatementCubit>().reset(),
                  ),
                ],
              ),
              if (state.statementRows.isNotEmpty) ...[
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
              child: const Icon(Icons.local_shipping_outlined,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('كشف حساب مورد',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
                Text('اختر مورداً وفترة زمنية لعرض الحركات',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 13)),
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
                ],
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'إعادة تعيين',
              onPressed: () => context.read<SupplierStatementCubit>().reset(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(BuildContext context, SupplierStatementLoaded state) {
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
                      _buildSupplierAutocomplete(
                          context, state, double.infinity),
                      const SizedBox(height: 12),
                      _buildDateColumn(
                          context,
                          'من تاريخ',
                          state.fromDate,
                          () => context
                              .read<SupplierStatementCubit>()
                              .pickFromDate(context),
                          double.infinity),
                      const SizedBox(height: 12),
                      _buildDateColumn(
                          context,
                          'إلى تاريخ',
                          state.toDate,
                          () => context
                              .read<SupplierStatementCubit>()
                              .pickToDate(context),
                          double.infinity),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('عرض الكشف'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => context
                              .read<SupplierStatementCubit>()
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
                        child: _buildSupplierAutocomplete(context, state, 0)),
                    const SizedBox(width: 16),
                    Expanded(
                        flex: 2,
                        child: _buildDateColumn(
                            context,
                            'من تاريخ',
                            state.fromDate,
                            () => context
                                .read<SupplierStatementCubit>()
                                .pickFromDate(context),
                            0)),
                    const SizedBox(width: 16),
                    Expanded(
                        flex: 2,
                        child: _buildDateColumn(
                            context,
                            'إلى تاريخ',
                            state.toDate,
                            () => context
                                .read<SupplierStatementCubit>()
                                .pickToDate(context),
                            0)),
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
                          onPressed: () => context
                              .read<SupplierStatementCubit>()
                              .loadStatement(),
                        ),
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

  Widget _buildSupplierAutocomplete(
      BuildContext context, SupplierStatementLoaded state, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('المورد',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, constraints) {
          return Autocomplete<SupplierModel>(
            displayStringForOption: (s) => '${s.supplierCode} - ${s.name}',
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return state.suppliers;
              return state.suppliers.where((s) =>
                  s.name
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()) ||
                  s.supplierCode
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (s) =>
                context.read<SupplierStatementCubit>().selectSupplier(s),
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
              textEditingController.addListener(() {
                if (textEditingController.text.isEmpty) {
                  context.read<SupplierStatementCubit>().selectSupplier(null);
                }
              });
              if (state.selectedSupplier != null &&
                  textEditingController.text.isEmpty) {
                textEditingController.text =
                    '${state.selectedSupplier!.supplierCode} - ${state.selectedSupplier!.name}';
              }
              return TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                onFieldSubmitted: (String value) {
                  onFieldSubmitted();
                },
                decoration: InputDecoration(
                  hintText: 'ابحث بالكود أو الاسم...',
                  prefixIcon:
                      const Icon(Icons.local_shipping_outlined, size: 18),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: state.selectedSupplier != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            textEditingController.clear();
                            context
                                .read<SupplierStatementCubit>()
                                .selectSupplier(null);
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
                              AutocompleteHighlightedOption.of(context) ==
                                  index;
                          return Material(
                            color: isHighlighted
                                ? AppTheme.accent.withValues(alpha: 0.1)
                                : Colors.transparent,
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppTheme.accent.withValues(alpha: 0.1),
                                child: const Icon(Icons.local_shipping_outlined,
                                    size: 16, color: AppTheme.accent),
                              ),
                              title: Text(option.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontSize: 15)),
                              subtitle: Text(option.supplierCode,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontFamily: 'Cairo',
                                      fontSize: 13)),
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
        }),
      ],
    );
  }

  Widget _buildDateColumn(BuildContext context, String label, DateTime? value,
      VoidCallback onTap, double width) {
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
        _datePicker(value: value, hint: 'اختر التاريخ', onTap: onTap),
      ],
    );
  }

  Widget _datePicker(
      {required DateTime? value,
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
                    : const TextStyle(
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

  Widget _buildContent(BuildContext context, SupplierStatementLoaded state) {
    if (state.selectedSupplier == null) {
      return _buildPlaceholder(
        icon: Icons.local_shipping_outlined,
        title: 'اختر مورداً',
        subtitle: 'اختر المورد وحدد الفترة الزمنية ثم اضغط "عرض الكشف"',
      );
    }
    if (state.statementRows.isEmpty) {
      return _buildPlaceholder(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد حركات',
        subtitle: 'لا توجد معاملات في الفترة المحددة',
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

  Widget _buildSummaryCards(SupplierStatementLoaded state) {
    final balance = state.finalBalance;
    final balColor = balance < 0 ? AppTheme.danger : AppTheme.success;
    final currency = state.selectedSupplier?.currency ?? 'EGP';
    final cards = [
      _summaryCard(
          label: 'إجمالي عليه',
          value: AppUtils.formatCurrency(state.totalDebit, currency),
          color: AppTheme.success,
          icon: Icons.arrow_downward),
      _summaryCard(
          label: 'إجمالي له',
          value: AppUtils.formatCurrency(state.totalCredit, currency),
          color: AppTheme.danger,
          icon: Icons.arrow_upward),
      _summaryCard(
        label: balance > 0
            ? 'الرصيد النهائي (له)'
            : balance < 0
                ? 'الرصيد النهائي (عليه)'
                : 'الرصيد النهائي (متوازن)',
        value: AppUtils.formatCurrency(balance.abs(), currency),
        color: balColor,
        icon: Icons.account_balance_outlined,
        isBold: true,
      ),
      _summaryCard(
          label: 'عدد الحركات',
          value: state.statementRows.length.toString(),
          color: AppTheme.primary,
          icon: Icons.format_list_numbered),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map((c) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: c,
                    ))
                .toList(),
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
      bool isBold = false}) {
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(value,
                          style: TextStyle(
                              fontSize: isBold ? 15 : 14,
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

  static const double _colRef = 160;
  static const double _colDate = 130;
  static const double _colAccount = 150;
  static const double _colDesc = 140;
  static const double _colQty = 50;
  static const double _colVolume = 70;
  static const double _colPrice = 80;
  static const double _colDebit = 100;
  static const double _colCredit = 100;
  static const double _colBalance = 110;
  static const double _colHPad = 24;
  static final double _tableWidth = _colRef +
      _colDate +
      _colAccount +
      _colDesc +
      _colQty +
      _colVolume +
      _colPrice +
      _colDebit +
      _colCredit +
      _colBalance +
      _colHPad;

  Widget _buildTable(SupplierStatementLoaded state) {
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
                                    state.statementRows[index],
                                    index,
                                    state.selectedSupplier?.currency ?? 'EGP'),
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
          const SizedBox(
              width: _colRef,
              child: Text('رقم الفاتورة أو المعاملة',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          const SizedBox(
              width: _colDate,
              child: Text('التاريخ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
         const SizedBox(
              width: _colAccount,
              child: Text('اسم الحساب',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          Expanded(
              flex: _colDesc.toInt(),
              child:const Text('البيان',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(
              width: _colQty,
              child: Text('العدد',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(
              width: _colVolume,
              child: Text('الكمية',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(
              width: _colPrice,
              child: Text('السعر',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(
              width: _colDebit,
              child: Text('منه',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(
              width: _colCredit,
              child: Text('له',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(
              width: _colBalance,
              child: Text('الرصيد',
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

  Widget _buildTableRow(StatementRow row, int index, String currency) {
    final isEven = index % 2 == 0;
    final balColor = row.balance < 0 ? AppTheme.danger : AppTheme.success;

    return Container(
      color: isEven
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
              width: _colRef,
              child: Text(row.transactionNumber,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          SizedBox(
              width: _colDate,
              child: Text(AppUtils.formatDate(AppUtils.parseDate(row.date)),
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 15))),
          SizedBox(
              width: _colAccount,
              child: Text(row.accountName,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                  overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: _colDesc.toInt(),
              child: Tooltip(
                message: row.description,
                waitDuration: const Duration(milliseconds: 350),
                child: Text(
                  row.description,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                ),
              )),
          SizedBox(
            width: _colQty,
            child: Text(
                row.piecesCount > 0
                    ? AppUtils.formatNumber(row.piecesCount)
                    : '—',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colVolume,
            child: Text(
                row.quantity > 0 ? AppUtils.formatNumber(row.quantity) : '—',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colPrice,
            child: Text(
                row.unitPrice > 0
                    ? AppUtils.formatCurrency(row.unitPrice, currency)
                    : '—',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colDebit,
            child: Text(
                row.debit > 0
                    ? AppUtils.formatCurrency(row.debit, currency)
                    : '—',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: row.debit > 0
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colCredit,
            child: Text(
                row.credit > 0
                    ? AppUtils.formatCurrency(row.credit, currency)
                    : '—',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: row.credit > 0
                        ? AppTheme.danger
                        : AppTheme.textSecondary,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colBalance,
            child: Column(
              children: [
                Text(AppUtils.formatCurrency(row.balance, currency),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: balColor,
                        fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
                Text(
                    row.balance > 0
                        ? 'له'
                        : row.balance < 0
                            ? 'عليه'
                            : 'متوازن',
                    style: TextStyle(
                        fontSize: 9, color: balColor, fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
              ],
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
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _printStatement(
      BuildContext context, SupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await SupplierStatementPdfService.generateAndPrint(
        supplier: supplier,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل إنشاء PDF: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _savePdf(
      BuildContext context, SupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await SupplierStatementPdfService.saveToFile(
        context,
        supplier: supplier,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل حفظ الملف: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }
}
