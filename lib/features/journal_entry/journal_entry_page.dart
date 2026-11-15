import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../core/router.dart';
import 'journal_entry_cubit.dart';
import 'journal_entry_state.dart';
import 'journal_entry_pdf_service.dart';
import 'journal_entry_excel_service.dart';
import '../../data/models/transaction_model.dart';
import '../../data/services/warehouse_transfer_journal_service.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = (entry['lines'] as List?) ?? [];
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: isDark
              ? AppTheme.glassCard()
              : BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title ?? 'القيد المحاسبي رقم ${entry['entryNum'] ?? ''}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                            fontFamily: 'Cairo'),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.remove_red_eye_outlined,
                          size: 20, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                      tooltip: 'معاينة قبل الطباعة',
                      onPressed: () =>
                          JournalEntryPdfService.showPreviewDialog(context, entry),
                    ),
                    IconButton(
                      icon: Icon(Icons.print_outlined,
                          size: 20, color: isDark ? AppTheme.primary : const Color(0xFF0F172A)),
                      tooltip: 'طباعة القيد',
                      onPressed: () =>
                          JournalEntryPdfService.printSingleVoucher(entry),
                    ),
                    if (isDialog)
                      IconButton(
                        icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                        onPressed: () => context.pop(),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: isDark ? null : const Color(0xFFE2E8F0)),
                const SizedBox(height: 12),
                _buildEntryDetailRow('رقم القيد', '#${entry['entryNum'] ?? ''}', isDark: isDark),
                _buildEntryDetailRow(
                    'التاريخ',
                    AppUtils.formatDate(
                        DateTime.tryParse(entry['date'] ?? '') ??
                            DateTime.now()),
                    isDark: isDark),
                Builder(
                  builder: (context) {
                    final summaryTransferCtx =
                        WarehouseTransferJournalService.extractTransferContext(entry: entry);
                    final debitAccountDisplay = summaryTransferCtx.isTransfer &&
                            summaryTransferCtx.receivingWarehouse != null
                        ? WarehouseTransferJournalService.formatTransferAccountName(
                            baseAccountName: entry['debitName']?.toString() ?? 'مخزون المحاصيل',
                            isDebit: true,
                            context: summaryTransferCtx,
                            includePrefix: true,
                          )
                        : 'من حـ/ ${entry['debitName'] ?? ''}';

                    final creditAccountDisplay = summaryTransferCtx.isTransfer &&
                            summaryTransferCtx.sendingWarehouse != null
                        ? WarehouseTransferJournalService.formatTransferAccountName(
                            baseAccountName: entry['creditName']?.toString() ?? 'مخزون المحاصيل',
                            isDebit: false,
                            context: summaryTransferCtx,
                            includePrefix: true,
                          )
                        : 'إلى حـ/ ${entry['creditName'] ?? ''}';

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entry['debitName'] != null &&
                            (entry['debitName'] as String).isNotEmpty)
                          _buildEntryDetailRow(
                              'الطرف المدين (من حـ/)',
                              debitAccountDisplay,
                              valueColor: isDark ? AppTheme.success : const Color(0xFF047857),
                              bold: true,
                              isDark: isDark),
                        if (entry['creditName'] != null &&
                            (entry['creditName'] as String).isNotEmpty)
                          _buildEntryDetailRow(
                              'الطرف الدائن (إلى حـ/)',
                              creditAccountDisplay,
                              valueColor: isDark ? AppTheme.danger : const Color(0xFFB91C1C),
                              bold: true,
                              isDark: isDark),
                      ],
                    );
                  },
                ),
                if (entry['notes'] != null &&
                    (entry['notes'] as String).isNotEmpty)
                  _buildEntryDetailRow('البيان', entry['notes'], isDark: isDark),
                
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark
                            ? AppTheme.primary.withValues(alpha: 0.3)
                            : const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('إجمالي القيد:',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? AppTheme.primary : const Color(0xFF15803D))),
                      Text(AppUtils.formatCurrency(entry['amount'], entry['currency'] ?? 'EGP'),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isDark ? Colors.white : Colors.black)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(Icons.account_tree_outlined,
                        color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'تفاصيل أطراف القيد (من حـ/ - إلى حـ/)',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    List<dynamic> effectiveLines = List.from(lines);

                    // If lines is empty but we have summary debit/credit info, synthesize double-entry lines
                    if (effectiveLines.isEmpty && (entry['amount'] != null || entry['debitName'] != null)) {
                      final double amt = (entry['amount'] as num?)?.toDouble() ?? 0.0;
                      final String curr = entry['currency']?.toString() ?? 'EGP';
                      final double? base = (entry['totalBaseAmount'] as num?)?.toDouble();
                      if (entry['debitName'] != null) {
                        effectiveLines.add({
                          'account_name': entry['debitName'],
                          'account_code': entry['debitCode'] ?? '',
                          'debit': amt,
                          'credit': 0.0,
                          'currency': curr,
                          'amount_in_base_currency': base ?? amt,
                          'description': entry['notes'] ?? '',
                        });
                      }
                      if (entry['creditName'] != null) {
                        effectiveLines.add({
                          'account_name': entry['creditName'],
                          'account_code': entry['creditCode'] ?? '',
                          'debit': 0.0,
                          'credit': amt,
                          'currency': curr,
                          'amount_in_base_currency': base ?? amt,
                          'description': entry['notes'] ?? '',
                        });
                      }
                    }

                    if (effectiveLines.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Text('لا توجد تفاصيل أطراف متاحة لهذا القيد',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                        ),
                      );
                    }

                    // Sort lines: Debits (من حـ/) first, then Credits (إلى حـ/)
                    effectiveLines.sort((a, b) {
                      double aDeb = 0;
                      if (a is Map) {
                        aDeb = (a['debit'] as num?)?.toDouble() ?? 0.0;
                      } else if (a is TransactionModel) {
                        if (a.type == 'debit') aDeb = a.amount;
                      }
                      double bDeb = 0;
                      if (b is Map) {
                        bDeb = (b['credit'] as num?)?.toDouble() ?? 0.0;
                      } else if (b is TransactionModel) {
                        if (b.type == 'debit') bDeb = b.amount;
                      }
                      if (aDeb > 0 && bDeb == 0) return -1;
                      if (aDeb == 0 && bDeb > 0) return 1;
                      return 0;
                    });

                    double totalDebits = 0;
                    double totalCredits = 0;
                    for (final l in effectiveLines) {
                      if (l is Map) {
                        totalDebits += (l['debit'] as num?)?.toDouble() ?? 0.0;
                        totalCredits += (l['credit'] as num?)?.toDouble() ?? 0.0;
                      } else if (l is TransactionModel) {
                        if (l.type == 'debit') totalDebits += l.amount;
                        if (l.type == 'credit') totalCredits += l.amount;
                      }
                    }
                    final bool isEntryBalanced = (totalDebits - totalCredits).abs() <= 0.05 && totalDebits > 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1)),
                            borderRadius: BorderRadius.circular(8),
                            color: isDark ? null : Colors.white,
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 82,
                              columnSpacing: 22,
                              horizontalMargin: 16,
                              headingRowColor: WidgetStateProperty.all(
                                  isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC)),
                              columns: [
                                DataColumn(label: Text('الطرف المحاسبي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : Colors.black))),
                                DataColumn(label: Text('اسم الحساب / المخزن', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : Colors.black))),
                                DataColumn(label: Text('كود الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : Colors.black))),
                                DataColumn(label: Text('مدين (من حـ/)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : const Color(0xFF047857)))),
                                DataColumn(label: Text('دائن (إلى حـ/)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : const Color(0xFFB91C1C)))),
                                DataColumn(label: Text('البيان / تفاصيل الصنف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? null : Colors.black))),
                              ],
                              rows: effectiveLines.map((line) {
                                final isMap = line is Map;
                                double debit = 0;
                                double credit = 0;
                                
                                if (isMap) {
                                  debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
                                  credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
                                } else {
                                  if (line.type == 'debit') debit = line.amount;
                                  if (line.type == 'credit') credit = line.amount;
                                }
                                
                                final isDebit = debit > 0;
                                final typeLabel = isDebit ? 'من حـ/ (مدين)' : 'إلى حـ/ (دائن)';
                                final typeColor = isDebit
                                    ? (isDark ? AppTheme.success : const Color(0xFF047857))
                                    : (isDark ? AppTheme.danger : const Color(0xFFB91C1C));
                                final typeBg = isDebit
                                    ? (isDark ? AppTheme.success.withValues(alpha: 0.15) : const Color(0xFFECFDF5))
                                    : (isDark ? AppTheme.danger.withValues(alpha: 0.15) : const Color(0xFFFEF2F2));
                                final typeBorder = isDebit
                                    ? (isDark ? AppTheme.success.withValues(alpha: 0.3) : const Color(0xFFA7F3D0))
                                    : (isDark ? AppTheme.danger.withValues(alpha: 0.3) : const Color(0xFFFECACA));
                                final prefix = isDebit ? 'من حـ/ ' : 'إلى حـ/ ';

                                var rawAccountName = isMap ? (line['account_name'] ?? 'غير معروف') : (line.accountName ?? 'غير معروف');
                                var accountCode = isMap ? (line['account_code'] ?? '') : (line.accountCode ?? '');

                                if (rawAccountName == null || rawAccountName == 'غير معروف' || rawAccountName.toString().trim().isEmpty) {
                                  if (isDebit && entry['debitName'] != null && entry['debitName'].toString().isNotEmpty && entry['debitName'] != 'حساب غير معروف') {
                                    rawAccountName = entry['debitName'];
                                  } else if (!isDebit && entry['creditName'] != null && entry['creditName'].toString().isNotEmpty && entry['creditName'] != 'حساب غير معروف') {
                                    rawAccountName = entry['creditName'];
                                  }
                                }
                                if (accountCode == null || accountCode.toString().trim().isEmpty) {
                                  if (isDebit && entry['debitCode'] != null && entry['debitCode'].toString().isNotEmpty) {
                                    accountCode = entry['debitCode'];
                                  } else if (!isDebit && entry['creditCode'] != null && entry['creditCode'].toString().isNotEmpty) {
                                    accountCode = entry['creditCode'];
                                  }
                                }

                                final lineDesc = isMap
                                    ? (line['description']?.toString() ?? entry['notes']?.toString() ?? '—')
                                    : ((line as dynamic).description?.toString() ?? entry['notes']?.toString() ?? '—');

                                final lineTransferCtx = WarehouseTransferJournalService.extractTransferContext(
                                  entry: entry,
                                  line: line,
                                );
                                final targetWarehouse = isDebit
                                    ? lineTransferCtx.receivingWarehouse
                                    : lineTransferCtx.sendingWarehouse;

                                final formattedAccountName = lineTransferCtx.isTransfer && targetWarehouse != null
                                    ? WarehouseTransferJournalService.formatTransferAccountName(
                                        baseAccountName: rawAccountName.toString(),
                                        isDebit: isDebit,
                                        context: lineTransferCtx,
                                        includePrefix: true,
                                      )
                                    : (rawAccountName.toString().startsWith('من ح') || rawAccountName.toString().startsWith('إلى ح')
                                        ? rawAccountName.toString()
                                        : '$prefix$rawAccountName');

                                final lineCurr = isMap ? (line['currency']?.toString() ?? entry['currency']?.toString() ?? 'EGP') : ((line as dynamic).currency ?? 'EGP');
                                final baseAmt = isMap ? (line['amount_in_base_currency'] as num?)?.toDouble() : null;

                                return DataRow(cells: [
                                  DataCell(Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: typeBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: typeBorder),
                                    ),
                                    child: Text(typeLabel, style: TextStyle(fontFamily: 'Cairo', color: typeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                  )),
                                  DataCell(_buildAccountNameCell(
                                    formattedName: formattedAccountName,
                                    warehouseName: targetWarehouse,
                                    isDebit: isDebit,
                                    isTransfer: lineTransferCtx.isTransfer,
                                    isDark: isDark,
                                  )),
                                  DataCell(Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(accountCode,
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: isDark ? Colors.white70 : Colors.black,
                                            fontWeight: FontWeight.bold)),
                                  )),
                                  DataCell(_buildAmountCell(
                                    amount: debit,
                                    currency: lineCurr,
                                    baseAmount: baseAmt,
                                    isDebit: true,
                                    isActive: isDebit,
                                    isDark: isDark,
                                  )),
                                  DataCell(_buildAmountCell(
                                    amount: credit,
                                    currency: lineCurr,
                                    baseAmount: baseAmt,
                                    isDebit: false,
                                    isActive: !isDebit,
                                    isDark: isDark,
                                  )),
                                  DataCell(_buildLineDescriptionCell(lineDesc, isDebit, entry: entry, isDark: isDark)),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: (isEntryBalanced ? AppTheme.success : AppTheme.warning)
                                .withValues(alpha: isDark ? 0.08 : 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: (isEntryBalanced
                                    ? (isDark ? AppTheme.success : const Color(0xFF86EFAC))
                                    : (isDark ? AppTheme.warning : const Color(0xFFFDE68A)))),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isEntryBalanced ? Icons.check_circle_outline : Icons.info_outline,
                                    size: 16,
                                    color: isEntryBalanced
                                        ? (isDark ? AppTheme.success : const Color(0xFF047857))
                                        : (isDark ? AppTheme.warning : const Color(0xFFB45309)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isEntryBalanced ? 'القيد متوازن محاسبياً (100%)' : 'تنبيه: مراجعة توازن القيد',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isEntryBalanced
                                          ? (isDark ? AppTheme.success : const Color(0xFF047857))
                                          : (isDark ? AppTheme.warning : const Color(0xFFB45309)),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'إجمالي المدين: ${AppUtils.formatCurrency(totalDebits, entry['currency'] ?? 'EGP')}  |  إجمالي الدائن: ${AppUtils.formatCurrency(totalCredits, entry['currency'] ?? 'EGP')}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildAccountNameCell({
    required String formattedName,
    required String? warehouseName,
    required bool isDebit,
    required bool isTransfer,
    bool isDark = true,
  }) {
    final badgeColor = isDebit
        ? (isDark ? AppTheme.success : const Color(0xFF047857))
        : (isDark ? AppTheme.danger : const Color(0xFFB91C1C));

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formattedName,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        if (isTransfer && warehouseName != null && warehouseName.isNotEmpty) ...[
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: badgeColor.withValues(alpha: isDark ? 0.3 : 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDebit ? Icons.move_to_inbox_outlined : Icons.outbox_outlined,
                  size: 11,
                  color: badgeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  isDebit ? 'مخزن الوجهة (المستلم): $warehouseName' : 'مخزن المصدر (المرسل): $warehouseName',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAmountCell({
    required double amount,
    required String currency,
    required double? baseAmount,
    required bool isDebit,
    required bool isActive,
    bool isDark = true,
  }) {
    if (!isActive || amount <= 0) {
      return Center(
        child: Text(
          '—',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final color = isDebit
        ? (isDark ? AppTheme.success : const Color(0xFF047857))
        : (isDark ? AppTheme.danger : const Color(0xFFB91C1C));
    final bool hasConversion = currency != 'EGP' &&
        baseAmount != null &&
        (baseAmount - amount).abs() > 0.01;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppUtils.formatCurrency(amount, currency),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            color: color,
          ),
        ),
        if (hasConversion) ...[
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.currency_exchange, size: 10, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                const SizedBox(width: 4),
                Text(
                  '≈ ${AppUtils.formatCurrency(baseAmount, 'EGP')}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLineDescriptionCell(String lineDesc, bool isDebit, {Map<String, dynamic>? entry, bool isDark = true}) {
    // 1. Detect transfer lines
    final bool isTransferLine = (entry != null &&
            (entry['sourceType'] == 'stock_transfer' || entry['source_type'] == 'stock_transfer')) ||
        lineDesc.contains('تحويل مخزني') ||
        lineDesc.contains('تحويل من مخزن') ||
        (lineDesc.contains('وارد إلى') && lineDesc.contains('من')) ||
        (lineDesc.contains('منصرف من') && lineDesc.contains('إلى'));

    if (isTransferLine) {
      final transferContext = WarehouseTransferJournalService.extractTransferContext(
        entry: entry ?? {},
        line: {'description': lineDesc},
      );

      final routeText = (transferContext.fromWarehouse != null && transferContext.toWarehouse != null)
          ? '${transferContext.fromWarehouse}  ➔  ${transferContext.toWarehouse}'
          : null;

      final directionLabel = isDebit ? 'وارد (استلام)' : 'منصرف (إرسال)';
      final directionColor = isDebit
          ? (isDark ? AppTheme.success : const Color(0xFF047857))
          : (isDark ? AppTheme.danger : const Color(0xFFB91C1C));

      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 460),
        child: Tooltip(
          message: lineDesc,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: (isDark ? AppTheme.cyan : const Color(0xFF0284C7)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.swap_horiz_rounded, size: 14, color: isDark ? AppTheme.cyan : const Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 8),
                  if (routeText != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? AppTheme.cyan : const Color(0xFF0284C7)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: (isDark ? AppTheme.cyan : const Color(0xFF0284C7)).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        routeText,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.cyan : const Color(0xFF0284C7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: directionColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: directionColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      directionLabel,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: directionColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                lineDesc,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    // 2. Detect item-level purchase inventory lines (standard or crop)
    final bool isItemLine = lineDesc.contains('مخزون') && lineDesc.contains('كمية:');

    if (isItemLine) {
      final parts = lineDesc.split(' - ').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

      String itemName = 'صنف مخزون';
      String? qtyPricePart;
      String? refPart;

      if (parts.isNotEmpty) {
        // Handle "مخزون المحاصيل - مانجو - كمية: X - سعر: Y - لوط: Z"
        // or "مخزون - اسم الصنف - كمية: X - بسعر: Y - فاتورة: Z"
        final headerIndex = parts[0].startsWith('مخزون') ? 0 : -1;
        if (headerIndex == 0 && parts.length >= 2) {
          // parts[0] could be 'مخزون' or 'مخزون المحاصيل'
          itemName = parts[1];
          qtyPricePart = parts.sublist(2).where((p) =>
              p.contains('كمية:') || p.contains('بسعر:') || p.contains('سعر:')).join(' | ');
          refPart = parts.firstWhere(
              (p) => p.contains('فاتورة') || p.contains('لوط:'), orElse: () => '');
        } else {
          itemName = parts[0].replaceFirst(RegExp(r'^مخزون\s*(المحاصيل)?\s*-\s*'), '');
          qtyPricePart = parts.sublist(1).where((p) =>
              p.contains('كمية:') || p.contains('بسعر:') || p.contains('سعر:')).join(' | ');
          refPart = parts.firstWhere(
              (p) => p.contains('فاتورة') || p.contains('لوط:'), orElse: () => '');
        }
      }

      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 440),
        child: Tooltip(
          message: lineDesc,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, size: 13, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      itemName,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (qtyPricePart != null && qtyPricePart.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: isDark ? 0.1 : 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: isDark ? 0.25 : 0.4)),
                      ),
                      child: Text(
                        qtyPricePart,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.primary : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                    if (refPart != null && refPart.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        refPart,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bool isSupplierLine = lineDesc.contains('مستحقات مورد') || lineDesc.contains('مورد:');

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
      child: Tooltip(
        message: lineDesc,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: (isSupplierLine ? AppTheme.accent : (isDark ? Colors.white : Colors.black))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                isSupplierLine ? Icons.person_outline : Icons.description_outlined,
                size: 13,
                color: isSupplierLine ? (isDark ? AppTheme.accent : const Color(0xFF0284C7)) : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                lineDesc,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isSupplierLine
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? Colors.white70 : Colors.black),
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
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
          constraints: const BoxConstraints(maxWidth: 950),
          child: SingleChildScrollView(
            child: _buildSingleEntryCard(entry, 'تفاصيل القيد المحاسبي', isDialog: true),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryDetailRow(String label, String value,
      {Color? valueColor, bool bold = false, bool? isDark}) {
    final dark = isDark ?? (Theme.of(context).brightness == Brightness.dark);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: TextStyle(
                    color: dark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ?? (dark ? Colors.white : Colors.black),
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddEntryDialog(BuildContext context, JournalEntryCubit c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: [
        if (_isSingleEntryMode)
          IconButton(
            icon: Icon(Icons.arrow_forward_ios, color: isDark ? Colors.white : Colors.black, size: 20),
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
            color: (isDark ? AppTheme.primary : const Color(0xFF0284C7)).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.receipt_long_outlined,
              color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 22),
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
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    fontFamily: 'Cairo')),
            Text(
              _isSingleEntryMode
                  ? 'عرض تفصيلي للقيد المحاسبي'
                  : 'سجل ودفتر قيود اليومية العامة',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontWeight: FontWeight.bold,
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
                        hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? null : Colors.black),
                    onChanged: (v) {
                      c.setHistorySearchQuery(v);
                      c.loadHistory();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Text('من: ',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? null : Colors.black)),
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
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? null : Colors.black,
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
                Text('إلى: ',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? null : Colors.black)),
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
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? null : Colors.black,
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
                  label: Text('إلغاء الفلاتر',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? null : const Color(0xFF0284C7))),
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
        c.stepDebitHighlight(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        c.stepDebitHighlight(-1);
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
        c.stepCreditHighlight(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        c.stepCreditHighlight(-1);
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
        return prev.isSaving != curr.isSaving ||
            prev.selectedDebitAccount != curr.selectedDebitAccount ||
            prev.selectedCreditAccount != curr.selectedCreditAccount;
      },
      builder: (formContext, state) {
        final isSaving = (state is JournalEntryLoaded) && state.isSaving;
        final isDark = Theme.of(formContext).brightness == Brightness.dark;

        return PopScope(
          canPop: !isSaving,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: isDark
                        ? AppTheme.glassCard()
                        : BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.swap_horiz_outlined,
                                  color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('إنشاء قيد مزدوج جديد',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black,
                                        fontFamily: 'Cairo')),
                              ),
                              if (isDialog)
                                IconButton(
                                  icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
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
                          Divider(color: isDark ? null : const Color(0xFFE2E8F0)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text('تاريخ العملية: ',
                                  style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                      fontWeight: FontWeight.bold,
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
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? null : Colors.black,
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
                          Text('الطرف المدين (من حـ/) *',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.debitCtrl,
                            focusNode: c.debitFocusNode,
                            enabled: !isSaving,
                            decoration: InputDecoration(
                              hintText: 'بحث واختيار الحساب المدين (من حـ/)...',
                              hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  fontFamily: 'Cairo'),
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
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                            ),
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? null : Colors.black),
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
                                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                  border: Border.all(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1)),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
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
                                          ? (isDark ? AppTheme.primary.withValues(alpha: 0.08) : const Color(0xFFE0F2FE))
                                          : Colors.transparent,
                                      child: ListTile(
                                        title: Text('من حـ/ ${acc.code} - ${acc.displayName}',
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? null : Colors.black)),
                                        trailing: Text(
                                            AppUtils.formatCurrency(acc.balance),
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? null : Colors.black)),
                                        onTap: isSaving ? null : () => c.selectDebitAccount(acc),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text('الطرف الدائن (إلى حـ/) *',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.creditCtrl,
                            focusNode: c.creditFocusNode,
                            enabled: !isSaving,
                            decoration: InputDecoration(
                              hintText: 'بحث واختيار الحساب الدائن (إلى حـ/)...',
                              hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  fontFamily: 'Cairo'),
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
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                            ),
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? null : Colors.black),
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
                                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                  border: Border.all(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1)),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
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
                                          ? (isDark ? AppTheme.primary.withValues(alpha: 0.08) : const Color(0xFFE0F2FE))
                                          : Colors.transparent,
                                      child: ListTile(
                                        title: Text('إلى حـ/ ${acc.code} - ${acc.displayName}',
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? null : Colors.black)),
                                        trailing: Text(
                                            AppUtils.formatCurrency(acc.balance),
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? null : Colors.black)),
                                        onTap: isSaving ? null : () => c.selectCreditAccount(acc),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text('مبلغ القيد *',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.amountCtrl,
                            enabled: !isSaving,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              hintText: 'أدخل المبلغ...',
                              hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  fontFamily: 'Cairo'),
                              prefixIcon: const Icon(Icons.attach_money,
                                  color: AppTheme.primary, size: 18),
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                            ),
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? null : Colors.black),
                          ),
                          const SizedBox(height: 16),
                          Text('البيان / ملاحظات القيد',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: c.notesCtrl,
                            enabled: !isSaving,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'وصف أو بيان القيد المحاسبي...',
                              hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  fontFamily: 'Cairo'),
                              prefixIcon: const Icon(Icons.notes,
                                  color: AppTheme.primary, size: 18),
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? AppTheme.divider : const Color(0xFFCBD5E1))),
                            ),
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? null : Colors.black),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final s = c.state;
                                    if (s is! JournalEntryLoaded) return;
                                    final amountText =
                                        c.amountCtrl.text.trim().replaceAll(',', '');
                                    final amount = double.tryParse(amountText);

                                    // Resolve or verify debit account
                                    var debitAcc = s.selectedDebitAccount;
                                    if (debitAcc == null && c.debitCtrl.text.trim().isNotEmpty) {
                                      debitAcc = c.findAccount(c.debitCtrl.text.trim());
                                      if (debitAcc != null) {
                                        c.selectDebitAccount(debitAcc);
                                      }
                                    }

                                    // Resolve or verify credit account
                                    var creditAcc = s.selectedCreditAccount;
                                    if (creditAcc == null && c.creditCtrl.text.trim().isNotEmpty) {
                                      creditAcc = c.findAccount(c.creditCtrl.text.trim());
                                      if (creditAcc != null) {
                                        c.selectCreditAccount(creditAcc);
                                      }
                                    }

                                    if (debitAcc == null) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('يرجى اختيار الطرف المدين (من حـ/) أولاً'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }
                                    if (creditAcc == null) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        const SnackBar(
                                          content: Text('يرجى اختيار الطرف الدائن (إلى حـ/) أولاً'),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                      return;
                                    }
                                    if (debitAcc.id == creditAcc.id) {
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

                                    if (!await ReadOnlyGuard.checkAsync(formContext)) return;

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
                                    } else if (!ok && formContext.mounted) {
                                      ScaffoldMessenger.of(formContext).showSnackBar(
                                        SnackBar(
                                          content: Text(c.lastErrorMessage ?? 'فشل في حفظ القيد المحاسبي، يرجى المحاولة مرة أخرى'),
                                          backgroundColor: AppTheme.danger,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: isDark
              ? AppTheme.glassCard()
              : BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
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
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text('لا توجد قيود مسجلة مطابقة للبحث',
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 15)),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                            isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC)),
                        columns: [
                          DataColumn(
                              label: Text('التاريخ',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('رقم القيد',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('إجمالي القيد',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('البيان والملاحظات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black,
                                      fontSize: 13))),
                          DataColumn(
                              label: Text('الإجراءات',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black,
                                      fontSize: 13))),
                        ],
                        rows: entries.map((entry) {
                          return DataRow(
                            cells: [
                              DataCell(Text(
                                  AppUtils.formatDate(
                                      DateTime.tryParse(entry['date']) ??
                                          DateTime.now()),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black))),
                              DataCell(Text('#${entry['entryNum']}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black))),
                              DataCell(Text(
                                  AppUtils.formatCurrency(entry['amount'], entry['currency'] ?? 'EGP'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? null : Colors.black))),
                              DataCell(
                                SizedBox(
                                  width: 250,
                                  child: Text(entry['notes'] ?? '—',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? null : Colors.black),
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
                                      label: Text('عرض التفاصيل',
                                          style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? null : const Color(0xFF0284C7))),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.remove_red_eye_outlined,
                                          size: 18, color: AppTheme.accent),
                                      tooltip: 'معاينة قبل الطباعة',
                                      onPressed: () => JournalEntryPdfService
                                          .showPreviewDialog(context, entry),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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
