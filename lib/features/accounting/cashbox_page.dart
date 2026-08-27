import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../data/models/cashbox_model.dart';
import 'cashbox_cubit.dart';
import 'cashbox_state.dart';
import 'cashbox_entry_dialog.dart';

class CashboxPage extends StatelessWidget {
  const CashboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CashboxCubit(),
      child: const _CashboxScaffold(),
    );
  }
}

class _CashboxScaffold extends StatelessWidget {
  const _CashboxScaffold();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CashboxCubit>();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(controller, context),
            const SizedBox(height: 20),
            _buildBalanceCard(controller),
            const SizedBox(height: 16),
            _buildFilterBar(controller, context),
            const SizedBox(height: 16),
            Expanded(child: _buildTable(controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(CashboxCubit controller, BuildContext context) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.point_of_sale_outlined,
                color: AppTheme.success, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الصندوق', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              Text('متابعة حركات النقدية',
                  style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: AppTheme.danger),
            label: const Text('صرف',
                style: TextStyle(color: AppTheme.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.danger),
            ),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => BlocProvider.value(
                value: controller,
                child: const CashboxEntryDialog(
                  initialType: TransactionType.credit,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_circle_outline,
                size: 18),
            label: const Text('إيداع'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
            ),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => BlocProvider.value(
                value: controller,
                child: const CashboxEntryDialog(
                  initialType: TransactionType.debit,
                ),
              ),
            ),
          ),
        ],
      );
  }

  Widget _buildBalanceCard(CashboxCubit controller) {
    return BlocBuilder<CashboxCubit, CashboxState>(
      builder: (context, state) {
        if (state is! CashboxLoaded) return const SizedBox();
        final balance = state.currentBalance;
        final color = balance >= 0
            ? AppTheme.success
            : AppTheme.danger;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: AppTheme.glassCard(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('رصيد الصندوق الحالي',
                              style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            AppUtils.formatCurrency(balance.abs()),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              balance >= 0
                                  ? 'رصيد متاح'
                                  : 'عجز في الصندوق',
                              style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const VerticalDivider(width: 40),

                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _periodStat(
                              label: 'إجمالي الإيداعات',
                              value: AppUtils.formatCurrency(state.totalIn),
                              icon: Icons.arrow_downward,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _periodStat(
                              label: 'إجمالي الصرف',
                              value: AppUtils.formatCurrency(state.totalOut),
                              icon: Icons.arrow_upward,
                              color: AppTheme.danger,
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
      },
    );
  }

  Widget _periodStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
      CashboxCubit controller, BuildContext context) {
    return BlocBuilder<CashboxCubit, CashboxState>(
      buildWhen: (prev, curr) {
        if (prev is! CashboxLoaded || curr is! CashboxLoaded) return true;
        return prev.fromDate != curr.fromDate ||
            prev.toDate != curr.toDate ||
            prev.entries.length != curr.entries.length;
      },
      builder: (context, state) {
        if (state is! CashboxLoaded) return const SizedBox();
        return Row(
          children: [
            Text('الفترة:', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
            const SizedBox(width: 12),

            _datePicker(
              value: state.fromDate,
              hint: 'من تاريخ',
              onTap: () => controller.pickFromDate(context),
            ),
            const SizedBox(width: 10),
            const Text('—', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
            const SizedBox(width: 10),

            _datePicker(
              value: state.toDate,
              hint: 'إلى تاريخ',
              onTap: () => controller.pickToDate(context),
            ),

            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'تحديث',
              onPressed: controller.loadAll,
            ),
            const Spacer(),

            Text(
              '${state.entries.length} قيد',
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            ),
          ],
        );
      },
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
            horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
              color: const Color(0xFFBDBDBD)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 14,
                color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              value != null
                  ? AppUtils.formatDate(value)
                  : hint,
              style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(CashboxCubit controller) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: BlocBuilder<CashboxCubit, CashboxState>(
            builder: (context, state) {
              if (state is! CashboxLoaded) return const SizedBox();
              if (state.entries.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.point_of_sale_outlined,
                          size: 72,
                          color: AppTheme.textSecondary
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      const Text('لا توجد قيود في هذه الفترة',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                      const SizedBox(height: 8),
                      const Text(
                          'اضغط "إيداع" أو "صرف" لإضافة قيد',
                          style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  _buildTableHeader(),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.entries.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) =>
                          _buildTableRow(
                        state.entries[index],
                        index,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          const SizedBox(width: 40,
              child: Text('#', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          const SizedBox(width: 110,
              child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(
              child: Text('البيان', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          const SizedBox(width: 60,
              child: Text('النوع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 150,
              child: Text('المبلغ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 160,
              child: Text('الرصيد بعد القيد',
                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14),
                  textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(CashboxModel entry, int index) {
    final isEven = index % 2 == 0;
    final isDebit = entry.type == TransactionType.debit;
    final amtColor = isDebit
        ? AppTheme.success
        : AppTheme.danger;
    final balColor = entry.balanceAfter >= 0
        ? AppTheme.success
        : AppTheme.danger;

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('${index + 1}',
                style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),

          SizedBox(
            width: 110,
            child: Text(
              AppUtils.formatDate(
                  AppUtils.parseDate(entry.transactionDate)),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
            ),
          ),

          Expanded(
            child: Row(
              children: [
                Icon(
                  isDebit
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 14,
                  color: amtColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.description,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: 60,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: amtColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isDebit ? 'إيداع' : 'صرف',
                  style: TextStyle(
                    fontSize: 10,
                    color: amtColor,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
          ),

          SizedBox(
            width: 150,
            child: Text(
              '${isDebit ? '+' : '-'} ${AppUtils.formatCurrency(entry.amount)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: amtColor,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 160,
            child: Text(
              AppUtils.formatCurrency(
                  entry.balanceAfter.abs()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: balColor,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
