import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/dao/transaction_dao.dart';
import 'account_cubit.dart';
import 'account_state.dart';
import 'account_form_dialog.dart';
import 'account_statement_pdf_service.dart';
import 'account_statement_excel_service.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final Set<int> _expandedAccountIds = {};

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AccountCubit>();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(controller),
            const SizedBox(height: 16),
            _buildSearchBar(controller),
            const SizedBox(height: 16),
            Expanded(child: _buildList(controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AccountCubit c) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_tree_outlined,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('شجرة الحسابات', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<AccountCubit, AccountState>(
                builder: (context, state) {
                  final count = state is AccountLoaded ? state.accounts.length : 0;
                  return Text('$count حساب', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                },
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'تحديث',
            onPressed: c.loadAll,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة حساب'),
            onPressed: () {
              c.prepareAddForm();
              showDialog(
                context: context,
                builder: (_) => BlocProvider.value(
                  value: c,
                  child: const AccountFormDialog(),
                ),
              );
            },
          ),
        ],
      );
  }

  Widget _buildSearchBar(AccountCubit c) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      style: const TextStyle(fontFamily: 'Cairo'),
      onChanged: (v) => c.onSearchChanged(v.trim()),
    );
  }

  List<Map<String, dynamic>> _buildVisibleRows(
      List<AccountModel> allAccounts,
      int? parentId,
      int depth,
  ) {
    final children = allAccounts.where((a) => a.parentId == parentId).toList();
    final list = <Map<String, dynamic>>[];
    for (final child in children) {
      final hasChildren = allAccounts.any((a) => a.parentId == child.id);
      list.add({
        'account': child,
        'depth': depth,
        'hasChildren': hasChildren,
      });
      if (_expandedAccountIds.contains(child.id)) {
        list.addAll(_buildVisibleRows(allAccounts, int.tryParse(child.id ?? ''), depth + 1));
      }
    }
    return list;
  }

  Widget _buildList(AccountCubit c) {
    return BlocBuilder<AccountCubit, AccountState>(
      builder: (context, state) {
        if (state is AccountLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is! AccountLoaded) {
          return _buildEmptyState();
        }

        final q = state.searchQuery.trim().toLowerCase();
        if (q.isNotEmpty) {
          final filtered = state.filteredAccounts;
          if (filtered.isEmpty) {
            return _buildEmptyState();
          }
          return ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _buildFlatAccountRow(filtered[i], c),
          );
        }

        final visibleRows = _buildVisibleRows(state.accounts, null, 0);
        if (visibleRows.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.separated(
          itemCount: visibleRows.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
          itemBuilder: (_, i) {
            final row = visibleRows[i];
            final acc = row['account'] as AccountModel;
            final depth = row['depth'] as int;
            final hasChildren = row['hasChildren'] as bool;
            return _buildTreeAccountRow(acc, depth, hasChildren, c);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_tree_outlined,
              size: 72,
              color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('لا توجد حسابات مطابقة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildFlatAccountRow(AccountModel acc, AccountCubit c) {
    return _buildAccountRowContent(acc, 0, false, c);
  }

  Widget _buildTreeAccountRow(AccountModel acc, int depth, bool hasChildren, AccountCubit c) {
    return _buildAccountRowContent(acc, depth, hasChildren, c);
  }

  Widget _buildAccountRowContent(AccountModel acc, int depth, bool hasChildren, AccountCubit c) {
    final balColor = acc.balance >= 0
        ? AppTheme.success
        : AppTheme.danger;
    final isExpanded = _expandedAccountIds.contains(acc.id);

    return InkWell(
      onTap: () => _showAccountTransactions(acc),
      child: Padding(
        padding: EdgeInsets.only(
          right: 16.0 + (depth * 24.0),
          left: 16.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            if (hasChildren)
              IconButton(
                icon: Icon(
                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_left,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedAccountIds.remove(acc.id);
                    } else {
                      if (acc.id != null) {
                        _expandedAccountIds.add(int.parse(acc.id!));
                      }
                    }
                  });
                },
              )
            else
              const SizedBox(width: 24),

            const SizedBox(width: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                acc.code,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Text(
                acc.name,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(width: 16),

            Text(
              AppUtils.formatCurrency(acc.balance),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: balColor,
                fontFamily: 'Cairo',
              ),
            ),

            const SizedBox(width: 16),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                  tooltip: 'تعديل',
                  onPressed: () {
                    c.prepareEditForm(acc);
                    showDialog(
                      context: context,
                      builder: (_) => BlocProvider.value(
                        value: c,
                        child: AccountFormDialog(account: acc),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                  tooltip: 'حذف',
                  onPressed: () => _confirmDelete(acc, c),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(AccountModel acc, AccountCubit c) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppTheme.glassBorder),
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text('هل أنت متأكد من رغبتك في حذف الحساب "${acc.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
            style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final error = await c.deleteAccount(acc);
              if (mounted) {
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف الحساب بنجاح'), backgroundColor: AppTheme.success),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAccountTransactions(AccountModel acc) async {
    final transactions = await TransactionDao().getByAccountId(int.parse(acc.id!));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => _AccountTransactionsDialog(
        account: acc,
        transactions: transactions,
      ),
    );
  }
}

class _AccountTransactionsDialog extends StatefulWidget {
  final AccountModel account;
  final List<TransactionModel> transactions;
  const _AccountTransactionsDialog({
    required this.account,
    required this.transactions,
  });

  @override
  State<_AccountTransactionsDialog> createState() => _AccountTransactionsDialogState();
}

class _AccountTransactionsDialogState extends State<_AccountTransactionsDialog> {
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<TransactionModel>.from(widget.transactions)
      ..sort((a, b) {
        final cmp = a.transactionDate.compareTo(b.transactionDate);
        return cmp != 0 ? cmp : (int.tryParse(a.id ?? '0') ?? 0).compareTo(int.tryParse(b.id ?? '0') ?? 0);
      });

    double openingBalance = 0;
    double runningBalance = 0;

    final filteredRows = <Map<String, dynamic>>[];
    double totalDebit = 0;
    double totalCredit = 0;

    for (final tx in sorted) {
      final txDate = DateTime.tryParse(tx.transactionDate) ?? DateTime.now();
      final isDebit = tx.type == 'debit';
      final effect = isDebit ? -tx.amount : tx.amount;

      final isBefore = _fromDate != null && txDate.isBefore(_fromDate!);

      if (isBefore) {
        openingBalance += effect;
        runningBalance = openingBalance;
      } else {
        final matchesFromDate = _fromDate == null || txDate.isAfter(_fromDate!.subtract(const Duration(days: 1)));
        final matchesToDate = _toDate == null || txDate.isBefore(_toDate!.add(const Duration(days: 1)));
        
        final q = _searchQuery.toLowerCase();
        final matchesSearch = q.isEmpty ||
            (tx.entryNumber?.toString().contains(q) ?? false) ||
            tx.description.toLowerCase().contains(q) ||
            (tx.type == 'debit' && 'مدين'.contains(q)) ||
            (tx.type == 'credit' && 'دائن'.contains(q));

        final balanceBefore = runningBalance;
        runningBalance += effect;

        if (matchesFromDate && matchesToDate && matchesSearch) {
          if (isDebit) {
            totalDebit += tx.amount;
          } else {
            totalCredit += tx.amount;
          }
          filteredRows.add({
            'tx': tx,
            'isDebit': isDebit,
            'balanceBefore': balanceBefore,
            'balanceAfter': runningBalance,
          });
        }
      }
    }

    final finalBalance = runningBalance;

    return Dialog(
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.glassBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: (MediaQuery.of(context).size.width * 0.75).clamp(850.0, 1150.0),
            height: (MediaQuery.of(context).size.height * 0.85).clamp(600.0, 800.0),
            decoration: AppTheme.glassCard(),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_tree_outlined, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${widget.account.code} — ${widget.account.name}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo')),
                          Text('الرصيد النهائي: ${AppUtils.formatCurrency(finalBalance)}', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                        ],
                      ),
                    ),
                    
                    IconButton(
                      icon: const Icon(Icons.print_outlined, color: AppTheme.primary),
                      tooltip: 'طباعة كشف الحساب',
                      onPressed: () {
                        AccountStatementPdfService.generateAndPrint(
                          account: widget.account,
                          rows: filteredRows,
                          totalDebit: totalDebit,
                          totalCredit: totalCredit,
                          openingBalance: openingBalance,
                          finalBalance: finalBalance,
                          fromDate: _fromDate,
                          toDate: _toDate,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.danger),
                      tooltip: 'حفظ كشف الحساب PDF',
                      onPressed: () async {
                        await AccountStatementPdfService.saveToFile(
                          context,
                          account: widget.account,
                          rows: filteredRows,
                          totalDebit: totalDebit,
                          totalCredit: totalCredit,
                          openingBalance: openingBalance,
                          finalBalance: finalBalance,
                          fromDate: _fromDate,
                          toDate: _toDate,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.table_chart_outlined, color: AppTheme.success),
                      tooltip: 'حفظ كشف الحساب Excel',
                      onPressed: () async {
                        try {
                          final path = await AccountStatementExcelService.saveToFile(
                            account: widget.account,
                            rows: filteredRows,
                            totalDebit: totalDebit,
                            totalCredit: totalCredit,
                            openingBalance: openingBalance,
                            finalBalance: finalBalance,
                            fromDate: _fromDate,
                            toDate: _toDate,
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
                                content: Text('فشل الحفظ: $e'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'بحث برقم القيد أو البيان...',
                          prefixIcon: const Icon(Icons.search, size: 16),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        onChanged: (v) {
                          setState(() {
                            _searchQuery = v.trim();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.primary),
                      label: Text(
                        _fromDate == null ? 'من تاريخ' : AppUtils.formatDate(_fromDate!),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() {
                            _fromDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.primary),
                      label: Text(
                        _toDate == null ? 'إلى تاريخ' : AppUtils.formatDate(_toDate!),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() {
                            _toDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18, color: AppTheme.textSecondary),
                      tooltip: 'إلغاء التصفية',
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                          _searchCtrl.clear();
                          _searchQuery = "";
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الرصيد السابق للفترة: ${AppUtils.formatCurrency(openingBalance)}',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primary),
                      ),
                      Text(
                        'إجمالي سحب (مدين): ${AppUtils.formatCurrency(totalDebit)} | إجمالي إيداع (دائن): ${AppUtils.formatCurrency(totalCredit)}',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('رقم القيد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                      SizedBox(width: 90, child: Text('التاريخ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                      SizedBox(width: 65, child: Text('النوع', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                      SizedBox(width: 90, child: Text('المبلغ', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                      SizedBox(width: 100, child: Text('رصيد قبل', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                      SizedBox(width: 100, child: Text('رصيد بعد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                      Expanded(child: Text('البيان', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Flexible(
                  child: filteredRows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('لا توجد عمليات تطابق البحث في هذا الحساب', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredRows.length,
                          separatorBuilder: (_, __) => const Divider(height: 16, thickness: 1.2, color: Color(0xFFE0E0E0)),
                          itemBuilder: (_, i) {
                            final row = filteredRows[i];
                            final tx = row['tx'] as TransactionModel;
                            final isDebit = row['isDebit'] as bool;
                            final balBefore = row['balanceBefore'] as double;
                            final balAfter = row['balanceAfter'] as double;

                            return InkWell(
                              onTap: () => _showTransactionDetails(tx),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        tx.entryNumber?.toString() ?? '—',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        AppUtils.formatDate(DateTime.tryParse(tx.transactionDate) ?? DateTime.now()),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 65,
                                      child: Text(
                                        isDebit ? 'مدين' : 'دائن',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: isDebit ? AppTheme.danger : AppTheme.success,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        AppUtils.formatCurrency(tx.amount),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isDebit ? AppTheme.danger : AppTheme.success,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        AppUtils.formatCurrency(balBefore),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textSecondary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        AppUtils.formatCurrency(balAfter),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: balAfter >= 0 ? AppTheme.success : AppTheme.danger,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        tx.description,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  void _showTransactionDetails(TransactionModel tx) {
    showDialog(
      context: context,
      builder: (_) => _TransactionDetailsDialog(tx: tx),
    );
  }
}

class _TransactionDetailsDialog extends StatelessWidget {
  final TransactionModel tx;
  const _TransactionDetailsDialog({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isDebit = tx.type == 'debit';
    final color = isDebit ? AppTheme.danger : AppTheme.success;

    return Dialog(
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.glassBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: MediaQuery.of(context).size.width < 540 ? MediaQuery.of(context).size.width * 0.95 : 500,
            decoration: AppTheme.glassCard(),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isDebit ? Icons.remove_circle_outline : Icons.add_circle_outline,
                      color: color, size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('تفاصيل القيد', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Cairo')),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _row('رقم القيد', tx.entryNumber?.toString() ?? '—'),
                _row('التاريخ', AppUtils.formatDate(
                    DateTime.tryParse(tx.transactionDate) ?? DateTime.now())),
                _row('النوع', isDebit ? 'مدين' : 'دائن', valueColor: color),
                _row('المبلغ', AppUtils.formatCurrency(tx.amount), valueColor: color),
                const Divider(height: 1),
                _row('الحساب', tx.accountName ?? '—'),
                _row('كود الحساب', tx.accountCode ?? '—'),
                if (tx.customerName != null) ...[
                  _row('العميل', tx.customerName!),
                  _row('كود العميل', tx.customerCode ?? '—'),
                ],
                if (tx.supplierName != null) ...[
                  _row('المورد', tx.supplierName!),
                  _row('كود المورد', tx.supplierCode ?? '—'),
                ],
                const Divider(height: 1),
                _row('البيان', tx.description),
                _row('تاريخ الإنشاء', tx.createdAt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Colors.white,
                )),
          ),
        ],
      ),
    );
  }
}
