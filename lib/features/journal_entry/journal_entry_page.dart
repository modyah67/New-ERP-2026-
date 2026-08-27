import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/router.dart';
import '../accounting/account_cubit.dart';
import '../accounting/account_form_dialog.dart';
import 'journal_entry_cubit.dart';
import 'journal_entry_state.dart';
import 'journal_entry_pdf_service.dart';
import 'journal_entry_excel_service.dart';

class JournalEntryPage extends StatefulWidget {
  final String? initialEntryNumber;
  final String? initialJournalEntryId;

  const JournalEntryPage({super.key, this.initialEntryNumber, this.initialJournalEntryId});

  @override
  State<JournalEntryPage> createState() => _JournalEntryPageState();
}

class _JournalEntryPageState extends State<JournalEntryPage> {
  late JournalEntryCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = JournalEntryCubit(
      initialJournalEntryId: widget.initialJournalEntryId,
      initialEntryNumber: widget.initialEntryNumber,
    );
  }

  @override
  void didUpdateWidget(JournalEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialJournalEntryId != widget.initialJournalEntryId ||
        oldWidget.initialEntryNumber != widget.initialEntryNumber) {
      if (widget.initialJournalEntryId != null && widget.initialJournalEntryId!.isNotEmpty) {
        _cubit.loadEntryById(widget.initialJournalEntryId!);
      } else if (widget.initialEntryNumber != null && widget.initialEntryNumber!.isNotEmpty) {
        _cubit.setHistorySearchQuery(widget.initialEntryNumber!);
        _cubit.loadHistory();
      } else {
        _cubit.loadAll();
      }
    }
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: _JournalEntryScaffold(
        initialEntryNumber: widget.initialEntryNumber,
        initialJournalEntryId: widget.initialJournalEntryId,
      ),
    );
  }
}

class _JournalEntryScaffold extends StatefulWidget {
  final String? initialEntryNumber;
  final String? initialJournalEntryId;

  const _JournalEntryScaffold({super.key, this.initialEntryNumber, this.initialJournalEntryId});

  @override
  State<_JournalEntryScaffold> createState() => _JournalEntryScaffoldState();
}

class _JournalEntryScaffoldState extends State<_JournalEntryScaffold> {
  bool get _isSingleEntryMode => widget.initialJournalEntryId != null && widget.initialJournalEntryId!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<JournalEntryCubit>();

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(controller, context),
              const SizedBox(height: 20),
              if (_isSingleEntryMode)
                _buildSingleEntryView(controller)
              else
                _buildJournalHistoryCard(controller),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleEntryView(JournalEntryCubit c) {
    return BlocBuilder<JournalEntryCubit, JournalEntryState>(
      buildWhen: (prev, curr) {
        if (prev is! JournalEntryLoaded || curr is! JournalEntryLoaded) return true;
        return prev.journalEntries != curr.journalEntries || curr.isSingleEntryLoading != prev.isSingleEntryLoading;
      },
      builder: (context, state) {
        if (state is! JournalEntryLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.isSingleEntryLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (state.singleEntryError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Text(
                state.singleEntryError!,
                style: const TextStyle(
                    color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 16),
              ),
            ),
          );
        }
        final entries = state.journalEntries;
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Text('تعذر العثور على القيد المحاسبي.',
                  style: TextStyle(
                      color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
            ),
          );
        }
        final entry = entries.first;
        return _buildSingleEntryCard(entry, state.singleEntryTitle);
      },
    );
  }

  Widget _buildSingleEntryCard(Map<String, dynamic> entry, String? title, {bool isDialog = false}) {
    final lines = (entry['lines'] as List?) ?? [];
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        color: AppTheme.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title ?? 'القيد المحاسبي رقم ${entry['entryNum'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Cairo'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print_outlined,
                          size: 20, color: AppTheme.primary),
                      tooltip: 'طباعة القيد',
                      onPressed: () =>
                          JournalEntryPdfService.printSingleVoucher(entry),
                    ),
                    if (isDialog)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => context.pop(),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _buildEntryDetailRow('رقم القيد', '#${entry['entryNum'] ?? ''}'),
                _buildEntryDetailRow(
                    'التاريخ',
                    AppUtils.formatDate(
                        DateTime.tryParse(entry['date'] ?? '') ??
                            DateTime.now())),
                if (entry['notes'] != null &&
                    (entry['notes'] as String).isNotEmpty)
                  _buildEntryDetailRow('البيان', entry['notes']),
                
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي القيد:', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
                      Text(AppUtils.formatCurrency(entry['amount'], entry['currency'] ?? 'EGP'), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                const Text('تفاصيل أطراف القيد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                const SizedBox(height: 12),
                if (lines.isNotEmpty)
                  Builder(
                    builder: (context) {
                      final effectiveLines = lines;

                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.05)),
                            columns: const [
                              DataColumn(label: Text('الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('كود الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('نوع الحركة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('مدين (+)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('دائن (-)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                            ],
                            rows: effectiveLines.map((line) {
                              // line might be a TransactionModel or a Map depending on if it came from history or single entry load
                              final isMap = line is Map;
                              final accountName = isMap ? (line['account_name'] ?? 'غير معروف') : (line.accountName ?? 'غير معروف');
                              final accountCode = isMap ? (line['account_code'] ?? '') : (line.accountCode ?? '');
                              
                              // Determine amount, debit and credit
                              double debit = 0;
                              double credit = 0;
                              
                              if (isMap) {
                                debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
                                credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
                              } else {
                                if (line.type == 'debit') debit = line.amount;
                                if (line.type == 'credit') credit = line.amount;
                              }
                              
                              final typeLabel = debit > 0 ? 'مدين' : 'دائن';
                              final typeColor = debit > 0 ? AppTheme.success : AppTheme.danger;
                              final lineCurr = isMap ? (line['currency']?.toString() ?? entry['currency']?.toString() ?? 'EGP') : ((line as dynamic).currency ?? 'EGP');
                              final baseAmt = isMap ? (line['amount_in_base_currency'] as num?)?.toDouble() : null;

                              String formatAmount(double amt) {
                                if (amt <= 0) return '—';
                                if (lineCurr != 'EGP' && baseAmt != null && (baseAmt - amt).abs() > 0.01) {
                                  return '${AppUtils.formatCurrency(amt, lineCurr)} (${AppUtils.formatCurrency(baseAmt, 'EGP')})';
                                }
                                return AppUtils.formatCurrency(amt, lineCurr);
                              }

                              return DataRow(cells: [
                                DataCell(Text(accountName, style: const TextStyle(fontFamily: 'Cairo'))),
                                DataCell(Text(accountCode, style: const TextStyle(fontFamily: 'Cairo'))),
                                DataCell(Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(typeLabel, style: TextStyle(fontFamily: 'Cairo', color: typeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                )),
                                DataCell(Text(formatAmount(debit), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                DataCell(Text(formatAmount(credit), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('لا توجد تفاصيل متاحة', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEntryDetailsDialog(BuildContext context, Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            child: _buildSingleEntryCard(entry, 'تفاصيل القيد المحاسبي', isDialog: true),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryDetailRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  void _showAddEntryDialog(BuildContext context, JournalEntryCubit c) {
    c.amountCtrl.clear();
    c.notesCtrl.clear();
    c.clearDebitSelection();
    c.clearCreditSelection();
    c.setTransactionDate(DateTime.now());

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => BlocProvider.value(
        value: c,
        child: Dialog(
        backgroundColor: const Color(0xCC05192D),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        child: SingleChildScrollView(
          child: Container(
            width: 750,
            child: _buildJournalFormCard(c, context: dialogContext, isDialog: true),
        ),
      ),
      ),
    ));
  }

  Widget _buildHeader(JournalEntryCubit c, BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: [
        if (_isSingleEntryMode)
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
            tooltip: 'رجوع',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(RoutePaths.journalEntry);
              }
            },
          ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.receipt_long_outlined,
              color: AppTheme.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isSingleEntryMode
                  ? (c.state is JournalEntryLoaded
                      ? (c.state as JournalEntryLoaded).singleEntryTitle ?? 'القيد المحاسبي'
                      : 'القيد المحاسبي')
                  : 'دفتر قيود اليومية',
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Cairo')),
            Text(
              _isSingleEntryMode
                  ? 'عرض تفصيلي للقيد المحاسبي'
                  : 'سجل ودفتر قيود اليومية العامة',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13)),
          ],
        ),
        const SizedBox(width: 24),
        if (!_isSingleEntryMode)
          Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث برقم القيد، الحساب، البيان...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                    onChanged: (v) {
                      c.setHistorySearchQuery(v);
                      c.loadHistory();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                const Text('من: ',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                BlocBuilder<JournalEntryCubit, JournalEntryState>(
                  buildWhen: (prev, curr) {
                    if (prev is! JournalEntryLoaded ||
                        curr is! JournalEntryLoaded) return true;
                    return prev.historyFromDate != curr.historyFromDate;
                  },
                  builder: (context, state) {
                    if (state is! JournalEntryLoaded) return const SizedBox();
                    return Text(
                      state.historyFromDate != null
                          ? AppUtils.formatDate(state.historyFromDate!)
                          : 'الكل',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppTheme.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => c.pickHistoryFromDate(context),
                ),
                const SizedBox(width: 16),
                const Text('إلى: ',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                BlocBuilder<JournalEntryCubit, JournalEntryState>(
                  buildWhen: (prev, curr) {
                    if (prev is! JournalEntryLoaded ||
                        curr is! JournalEntryLoaded) return true;
                    return prev.historyToDate != curr.historyToDate;
                  },
                  builder: (context, state) {
                    if (state is! JournalEntryLoaded) return const SizedBox();
                    return Text(
                      state.historyToDate != null
                          ? AppUtils.formatDate(state.historyToDate!)
                          : 'الكل',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined,
                      size: 14, color: AppTheme.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => c.pickHistoryToDate(context),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: c.clearHistoryFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 14),
                  label: const Text('إلغاء الفلاتر',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
        const SizedBox(width: 12),
        // PopupMenuButton<String>(
        //   icon: const Icon(Icons.print_outlined, color: AppTheme.primary),
        //   tooltip: 'خيارات الطباعة',
        //   onSelected: (val) {
        //     if (val == 'tree') {
        //       JournalEntryPdfService.printTree(c.accounts);
        //     } else if (val == 'journal') {
        //       JournalEntryPdfService.printHistory(c.journalEntries);
        //     }
        //   },
        //   itemBuilder: (context) => [
        //     const PopupMenuItem(
        //       value: 'tree',
        //       child: Row(
        //         children: [
        //           Icon(Icons.account_tree_outlined,
        //               size: 18, color: AppTheme.primary),
        //           SizedBox(width: 8),
        //           Text('طباعة شجرة الحسابات',
        //               style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        //         ],
        //       ),
        //     ),
        //     const PopupMenuItem(
        //       value: 'journal',
        //       child: Row(
        //         children: [
        //           Icon(Icons.receipt_long_outlined,
        //               size: 18, color: AppTheme.primary),
        //           SizedBox(width: 8),
        //           Text('طباعة دفتر القيود',
        //               style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        //         ],
        //       ),
        //     ),
        //   ],
        // ),
        const SizedBox(width: 8),
        if (!_isSingleEntryMode) ...[
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download_outlined, color: Colors.green),
            tooltip: 'تصدير إكسل',
            onSelected: (val) {
              if (val == 'tree') {
                JournalEntryExcelService.exportAccountsTree(context!, c.accounts);
              } else if (val == 'journal') {
                JournalEntryExcelService.exportJournalEntries(
                    context!, c.journalEntries);
              }
            },
            itemBuilder: (context) => [
              // const PopupMenuItem(
              //   value: 'tree',
              //   child: Row(
              //     children: [
              //       Icon(Icons.table_chart_outlined,
              //           size: 18, color: Colors.green),
              //       SizedBox(width: 8),
              //       Text('تصدير شجرة الحسابات (Excel)',
              //           style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              //     ],
              //   ),
              // ),
              const PopupMenuItem(
                value: 'journal',
                child: Row(
                  children: [
                    Icon(Icons.list_alt_outlined, size: 18, color: Colors.green),
                    SizedBox(width: 8),
                    Text('تصدير قيود اليومية (Excel)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'تحديث البيانات',
            onPressed: c.loadAll,
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _showAddEntryDialog(context, c),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة قيد جديد',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
        ],
      ),
    );
  }

  Widget _buildJournalFormCard(JournalEntryCubit c,
      {BuildContext? context, bool isDialog = false}) {
    c.debitFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final currentState = c.state;
      if (currentState is! JournalEntryLoaded) return KeyEventResult.ignored;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (currentState.debitResults.isNotEmpty) {
          c.emit(currentState.copyWith(
            debitHighlightIdx: (currentState.debitHighlightIdx + 1)
                .clamp(0, currentState.debitResults.length - 1),
          ));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (currentState.debitResults.isNotEmpty) {
          c.emit(currentState.copyWith(
            debitHighlightIdx: (currentState.debitHighlightIdx - 1)
                .clamp(0, currentState.debitResults.length - 1),
          ));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (currentState.debitResults.isNotEmpty) {
          final idx = currentState.debitHighlightIdx;
          if (idx >= 0 && idx < currentState.debitResults.length) {
            c.selectDebitAccount(currentState.debitResults[idx]);
          }
        }
        Future.microtask(() => c.creditFocusNode.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    c.creditFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final currentState = c.state;
      if (currentState is! JournalEntryLoaded) return KeyEventResult.ignored;

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (currentState.creditResults.isNotEmpty) {
          c.emit(currentState.copyWith(
            creditHighlightIdx: (currentState.creditHighlightIdx + 1)
                .clamp(0, currentState.creditResults.length - 1),
          ));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (currentState.creditResults.isNotEmpty) {
          c.emit(currentState.copyWith(
            creditHighlightIdx: (currentState.creditHighlightIdx - 1)
                .clamp(0, currentState.creditResults.length - 1),
          ));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (currentState.creditResults.isNotEmpty) {
          final idx = currentState.creditHighlightIdx;
          if (idx >= 0 && idx < currentState.creditResults.length) {
            c.selectCreditAccount(currentState.creditResults[idx]);
          }
        }
        Future.microtask(() => c.amountFocusNode.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    c.amountFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        Future.microtask(() => c.notesFocusNode.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    return BlocBuilder<JournalEntryCubit, JournalEntryState>(
      buildWhen: (prev, curr) {
        if (prev is! JournalEntryLoaded || curr is! JournalEntryLoaded) return true;
        return prev.isSaving != curr.isSaving;
      },
      builder: (formContext, state) {
        final isSaving = (state is JournalEntryLoaded) && state.isSaving;

        return PopScope(
          canPop: !isSaving,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: AppTheme.glassCard(),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.swap_horiz_outlined,
                                  color: AppTheme.primary, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text('إنشاء قيد مزدوج جديد',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        fontFamily: 'Cairo')),
                              ),
                              if (isDialog)
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: isSaving
                                      ? null
                                      : () {
                                          if (context != null && context.canPop()) {
                                            context.pop();
                                          }
                                        },
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text('تاريخ العملية: ',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                      fontSize: 14)),
                              const SizedBox(width: 12),
                              BlocBuilder<JournalEntryCubit, JournalEntryState>(
                                buildWhen: (prev, curr) {
                                  if (prev is! JournalEntryLoaded ||
                                      curr is! JournalEntryLoaded) return true;
                                  return prev.transactionDate != curr.transactionDate;
                                },
                                builder: (context, state) {
                                  if (state is! JournalEntryLoaded) return const SizedBox();
                                  return Text(
                                    AppUtils.formatDate(state.transactionDate),
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 18, color: AppTheme.primary),
                                onPressed: isSaving ? null : () => c.pickTransactionDate(context!),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('الحساب المدين (المستلم للمال) *',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.debitCtrl,
                            focusNode: c.debitFocusNode,
                            enabled: !isSaving,
                            decoration: InputDecoration(
                              hintText: 'بحث واختيار الحساب المدين...',
                              prefixIcon: const Icon(Icons.arrow_downward,
                                  color: AppTheme.success, size: 18),
                              suffixIcon:
                                  BlocBuilder<JournalEntryCubit, JournalEntryState>(
                                buildWhen: (prev, curr) {
                                  if (prev is! JournalEntryLoaded ||
                                      curr is! JournalEntryLoaded) return true;
                                  return prev.selectedDebitAccount !=
                                      curr.selectedDebitAccount;
                                },
                                builder: (context, state) {
                                  if (state is! JournalEntryLoaded) return const SizedBox();
                                  return state.selectedDebitAccount != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: isSaving ? null : c.clearDebitSelection)
                                      : const SizedBox();
                                },
                              ),
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            onChanged: c.searchDebit,
                          ),
                          BlocBuilder<JournalEntryCubit, JournalEntryState>(
                            buildWhen: (prev, curr) => prev != curr,
                            builder: (context, state) {
                              if (state is! JournalEntryLoaded) return const SizedBox();
                              if (state.debitResults.isEmpty) return const SizedBox();
                              return Container(
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(color: AppTheme.divider),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                constraints: const BoxConstraints(maxHeight: 180),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: state.debitResults.length,
                                  itemBuilder: (context, idx) {
                                    final acc = state.debitResults[idx];
                                    final isHighlighted = state.debitHighlightIdx == idx;
                                    return Material(
                                      color: isHighlighted
                                          ? AppTheme.primary.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      child: ListTile(
                                        title: Text('${acc.code} - ${acc.name}',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo', fontSize: 12)),
                                        trailing: Text(
                                            AppUtils.formatCurrency(acc.balance),
                                            style: const TextStyle(fontSize: 12)),
                                        onTap: isSaving ? null : () => c.selectDebitAccount(acc),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text('الحساب الدائن (المسحوب منه المال) *',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.creditCtrl,
                            focusNode: c.creditFocusNode,
                            enabled: !isSaving,
                            decoration: InputDecoration(
                              hintText: 'بحث واختيار الحساب الدائن...',
                              prefixIcon: const Icon(Icons.arrow_upward,
                                  color: AppTheme.danger, size: 18),
                              suffixIcon:
                                  BlocBuilder<JournalEntryCubit, JournalEntryState>(
                                buildWhen: (prev, curr) {
                                  if (prev is! JournalEntryLoaded ||
                                      curr is! JournalEntryLoaded) return true;
                                  return prev.selectedCreditAccount !=
                                      curr.selectedCreditAccount;
                                },
                                builder: (context, state) {
                                  if (state is! JournalEntryLoaded) return const SizedBox();
                                  return state.selectedCreditAccount != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: isSaving ? null : c.clearCreditSelection)
                                      : const SizedBox();
                                },
                              ),
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            onChanged: c.searchCredit,
                          ),
                          BlocBuilder<JournalEntryCubit, JournalEntryState>(
                            buildWhen: (prev, curr) => prev != curr,
                            builder: (context, state) {
                              if (state is! JournalEntryLoaded) return const SizedBox();
                              if (state.creditResults.isEmpty) return const SizedBox();
                              return Container(
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(color: AppTheme.divider),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                constraints: const BoxConstraints(maxHeight: 180),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: state.creditResults.length,
                                  itemBuilder: (context, idx) {
                                    final acc = state.creditResults[idx];
                                    final isHighlighted = state.creditHighlightIdx == idx;
                                    return Material(
                                      color: isHighlighted
                                          ? AppTheme.primary.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      child: ListTile(
                                        title: Text('${acc.code} - ${acc.name}',
                                            style: const TextStyle(
                                                fontFamily: 'Cairo', fontSize: 12)),
                                        trailing: Text(
                                            AppUtils.formatCurrency(acc.balance),
                                            style: const TextStyle(fontSize: 12)),
                                        onTap: isSaving ? null : () => c.selectCreditAccount(acc),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text('المبلغ المطلوب نقله *',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.amountCtrl,
                            focusNode: c.amountFocusNode,
                            enabled: !isSaving,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              suffixText: 'ج.م',
                            ),
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          const Text('البيان / الوصف التفصيلي',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.notesCtrl,
                            focusNode: c.notesFocusNode,
                            enabled: !isSaving,
                            decoration: const InputDecoration(
                              hintText: 'أدخل تفاصيل وملاحظات القيد...',
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (state is! JournalEntryLoaded) return;
                                    final s = state;
                                    final amountText =
                                        c.amountCtrl.text.trim().replaceAll(',', '');
                                    final amount = double.tryParse(amountText);

                                    if (s.selectedDebitAccount == null) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('يرجى اختيار الحساب المدين أولاً'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }
                                    if (s.selectedCreditAccount == null) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('يرجى اختيار الحساب الدائن أولاً'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }
                                    if (s.selectedDebitAccount!.id ==
                                        s.selectedCreditAccount!.id) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('لا يمكن اختيار نفس الحساب للطرفين المدين والدائن'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }
                                    if (amount == null || amount <= 0) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'يرجى إدخال مبلغ صحيح للقيد أكبر من الصفر'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }

                                    final ok = await c.saveEntry();
                                    if (ok && formContext.mounted) {
                                      if (isDialog && context != null && context.mounted && context.canPop()) {
                                        context.pop();
                                      }
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم تسجيل وحفظ القيد بنجاح ✓'),
                                          backgroundColor: AppTheme.success,
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(
                                isSaving ? 'جاري تسجيل القيد...' : 'تسجيل وحفظ القيد'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (isSaving)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      color: const Color(0xE6031935),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF041E42),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.4)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(
                                  color: AppTheme.primary,
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 20),
                              Text(
                                'جاري تسجيل وحفظ القيد...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'يرجى الانتظار لحين اكتمال ترحيل العملية المحاسبية',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJournalHistoryCard(JournalEntryCubit c) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BlocBuilder<JournalEntryCubit, JournalEntryState>(
                  buildWhen: (prev, curr) {
                    if (prev is! JournalEntryLoaded ||
                        curr is! JournalEntryLoaded) return true;
                    return prev.journalEntries != curr.journalEntries;
                  },
                  builder: (context, state) {
                    if (state is! JournalEntryLoaded) return const SizedBox();
                    final entries = state.journalEntries;

                    if (entries.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text('لا توجد قيود مسجلة مطابقة للبحث',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Cairo',
                                  fontSize: 15)),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(
                              label: Text('التاريخ',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('رقم القيد',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('إجمالي القيد',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('البيان والملاحظات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('الإجراءات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                        ],
                        rows: entries.map((entry) {
                          return DataRow(
                            cells: [
                              DataCell(Text(
                                  AppUtils.formatDate(
                                      DateTime.tryParse(entry['date']) ??
                                          DateTime.now()),
                                  style: const TextStyle(fontSize: 12))),
                              DataCell(Text('#${entry['entryNum']}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Text(
                                  AppUtils.formatCurrency(entry['amount'], entry['currency'] ?? 'EGP'),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold))),
                              DataCell(
                                SizedBox(
                                  width: 250,
                                  child: Text(entry['notes'] ?? '—',
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _showEntryDetailsDialog(context, entry),
                                      icon: const Icon(Icons.visibility_outlined, size: 16),
                                      label: const Text('عرض التفاصيل', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.print_outlined,
                                          size: 18, color: AppTheme.primary),
                                      tooltip: 'طباعة سند القيد',
                                      onPressed: () => JournalEntryPdfService
                                          .printSingleVoucher(entry),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
