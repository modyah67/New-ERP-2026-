import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/cheque_model.dart';
import 'cheque_cubit.dart';
import 'cheque_state.dart';
import 'cheque_form_dialog.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ChequesPage extends StatelessWidget {
  const ChequesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChequeCubit(),
      child: const _ChequesView(),
    );
  }
}

class _ChequesView extends StatefulWidget {
  const _ChequesView();

  @override
  State<_ChequesView> createState() => _ChequesViewState();
}

class _ChequesViewState extends State<_ChequesView> {
  final ScrollController _scrollController = ScrollController();
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<ChequeCubit>().loadCheques();
    }
  }

  double _responsiveVal(double w, double small, double medium, double large) {
    if (w < 400) return small;
    if (w < 700) return medium;
    return large;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;

          return Column(
            children: [
              _buildHeader(w),
              if (_showFilters) _buildFilters(w),
              _buildStatsBar(w),
              Divider(
                  height: 1,
                  color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth > 900
                            ? constraints.maxWidth
                            : 900,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildColumnHeaders(w),
                          Divider(
                              height: 1,
                              color: isDark
                                  ? AppTheme.divider
                                  : const Color(0xFFE2E8F0)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Divider(
                  height: 1,
                  color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
              Expanded(
                child: BlocBuilder<ChequeCubit, ChequeState>(
                  builder: (context, state) {
                    if (state is ChequeLoading) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: isDark
                                  ? AppTheme.primary
                                  : const Color(0xFF0284C7)));
                    }
                    if (state is ChequeError) {
                      return Center(
                        child: Text(state.message,
                            style: const TextStyle(
                                color: AppTheme.danger, fontFamily: 'Cairo')),
                      );
                    }
                    if (state is! ChequeLoaded) return const SizedBox();
                    if (state.cheques.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 64,
                                color: isDark
                                    ? AppTheme.textMuted
                                    : const Color(0xFF94A3B8)),
                            const SizedBox(height: 16),
                            Text('لا توجد شيكات',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: _responsiveVal(
                                        w, 14.0, 16.0, 18.0),
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppTheme.textSecondary
                                        : const Color(0xFF64748B))),
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
                              maxWidth: constraints.maxWidth > 900 ? constraints.maxWidth : 900,
                            ),
                            child: SizedBox(
                              width: constraints.maxWidth > 900 ? constraints.maxWidth : 900,
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: state.cheques.length + (state.hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= state.cheques.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    );
                                  }
                                  return _ChequeRow(cheque: state.cheques[index]);
                                },
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
        },
      ),
    );
  }

  Widget _buildHeader(double w) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleSize = _responsiveVal(w, 16.0, 18.0, 22.0);
    final subtitleSize = _responsiveVal(w, 10.0, 11.0, 13.0);
    final pad = _responsiveVal(w, 12.0, 16.0, 24.0);
    final iconBoxSize = _responsiveVal(w, 36.0, 40.0, 44.0);
    final iconSize = _responsiveVal(w, 18.0, 20.0, 22.0);
    final primaryCol = isDark ? AppTheme.primary : const Color(0xFF0284C7);

    if (w < 700) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: primaryCol.withValues(alpha: isDark ? 0.1 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.receipt_long_outlined,
                      color: primaryCol, size: iconSize),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إدارة الشيكات',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                              fontFamily: 'Cairo')),
                      Text('شيكات صادرة وواردة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: subtitleSize,
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : const Color(0xFF64748B),
                              fontFamily: 'Cairo')),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _showFilters
                          ? Icons.filter_alt_off
                          : Icons.filter_alt_outlined,
                      color: primaryCol,
                      size: 20),
                  onPressed: () {
                    if (_showFilters) {
                      context.read<ChequeCubit>().clearAllFilters();
                    }
                    setState(() => _showFilters = !_showFilters);
                  },
                  tooltip: 'تصفية',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionBtn(
                  icon: Icons.add_outlined,
                  label: 'شيك صادر',
                  color: AppTheme.danger,
                  onTap: () => _showFormDialog('outgoing'),
                ),
                _ActionBtn(
                  icon: Icons.add_outlined,
                  label: 'شيك وارد',
                  color: AppTheme.success,
                  onTap: () => _showFormDialog('incoming'),
                ),
                _IconBtn(
                  icon: Icons.table_chart_outlined,
                  color: AppTheme.success,
                  tooltip: 'تصدير Excel',
                  onTap: _exportExcel,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
      child: Row(
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              color: primaryCol.withValues(alpha: isDark ? 0.1 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.receipt_long_outlined,
                color: primaryCol, size: iconSize),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إدارة الشيكات',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                Text('شيكات صادرة وواردة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: subtitleSize,
                        color: isDark
                            ? AppTheme.textSecondary
                            : const Color(0xFF64748B),
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
                _showFilters
                    ? Icons.filter_alt_off
                    : Icons.filter_alt_outlined,
                color: primaryCol),
            onPressed: () {
              if (_showFilters) {
                context.read<ChequeCubit>().clearAllFilters();
              }
              setState(() => _showFilters = !_showFilters);
            },
            tooltip: 'تصفية',
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: Icons.table_chart_outlined,
            color: AppTheme.success,
            tooltip: 'تصدير Excel',
            onTap: _exportExcel,
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            icon: Icons.add_outlined,
            label: 'شيك صادر',
            color: AppTheme.danger,
            onTap: () => _showFormDialog('outgoing'),
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            icon: Icons.add_outlined,
            label: 'شيك وارد',
            color: AppTheme.success,
            onTap: () => _showFormDialog('incoming'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(double w) {
    final pad = _responsiveVal(w, 12.0, 16.0, 24.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
      child: BlocBuilder<ChequeCubit, ChequeState>(
        builder: (context, state) {
          if (state is! ChequeLoaded) return const SizedBox();

          if (w < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown<String>(
                        value: state.typeFilter,
                        label: 'النوع',
                        items: const [null, 'outgoing', 'incoming'],
                        itemLabels: const ['الكل', 'صادر', 'وارد'],
                        onChanged: (v) => context.read<ChequeCubit>().setTypeFilter(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterDropdown<String>(
                        value: state.statusFilter,
                        label: 'الحالة',
                        items: const [null, 'pending', 'cleared', 'cancelled'],
                        itemLabels: const ['الكل', 'معلق', 'تم الصرف', 'ملغي'],
                        onChanged: (v) => context.read<ChequeCubit>().setStatusFilter(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateFilterField(
                        label: 'من تاريخ',
                        date: state.fromDate,
                        onChanged: (d) => context.read<ChequeCubit>().setFromDate(d),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateFilterField(
                        label: 'إلى تاريخ',
                        date: state.toDate,
                        onChanged: (d) => context.read<ChequeCubit>().setToDate(d),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  onChanged: (v) => context.read<ChequeCubit>().setSearchQuery(v),
                  decoration: const InputDecoration(
                    hintText: 'بحث برقم الشيك أو الاسم...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ],
            );
          }

          return Row(children: [
            Expanded(
              child: _FilterDropdown<String>(
                value: state.typeFilter,
                label: 'النوع',
                items: const [null, 'outgoing', 'incoming'],
                itemLabels: const ['الكل', 'صادر', 'وارد'],
                onChanged: (v) => context.read<ChequeCubit>().setTypeFilter(v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FilterDropdown<String>(
                value: state.statusFilter,
                label: 'الحالة',
                items: const [null, 'pending', 'cleared', 'cancelled'],
                itemLabels: const ['الكل', 'معلق', 'تم الصرف', 'ملغي'],
                onChanged: (v) => context.read<ChequeCubit>().setStatusFilter(v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateFilterField(
                label: 'من تاريخ',
                date: state.fromDate,
                onChanged: (d) => context.read<ChequeCubit>().setFromDate(d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateFilterField(
                label: 'إلى تاريخ',
                date: state.toDate,
                onChanged: (d) => context.read<ChequeCubit>().setToDate(d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                onChanged: (v) => context.read<ChequeCubit>().setSearchQuery(v),
                decoration: const InputDecoration(
                  hintText: 'بحث برقم الشيك أو الاسم...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _buildStatsBar(double w) {
    final pad = _responsiveVal(w, 12.0, 16.0, 24.0);

    return BlocBuilder<ChequeCubit, ChequeState>(
      builder: (context, state) {
        if (state is! ChequeLoaded) return const SizedBox();
        final pendingCount = state.pendingCount;

        if (w < 700) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatBadge(label: 'الشيكات المعلقة', value: '$pendingCount', color: AppTheme.warning),
                _StatBadge(label: 'إجمالي الشيكات', value: '${state.cheques.length}', color: AppTheme.primary),
              ],
            ),
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
          child: Row(children: [
            _StatBadge(label: 'الشيكات المعلقة', value: '$pendingCount', color: AppTheme.warning),
            const SizedBox(width: 12),
            _StatBadge(label: 'إجمالي الشيكات', value: '${state.cheques.length}', color: AppTheme.primary),
          ]),
        );
      },
    );
  }

  Widget _buildColumnHeaders(double w) {
    final pad = _responsiveVal(w, 12.0, 16.0, 24.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
      color: isDark
          ? AppTheme.primary.withValues(alpha: 0.08)
          : const Color(0xFFF1F5F9),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _ColH('رقم الشيك')),
          Expanded(flex: 1, child: _ColH('النوع', alignment: Alignment.center)),
          Expanded(flex: 2, child: _ColH('المستلم ')),
          Expanded(flex: 1, child: _ColH('المبلغ')),
          Expanded(flex: 1, child: _ColH('العملة')),
          Expanded(
              flex: 1,
              child: _ColH('تاريخ الاستحقاق', alignment: Alignment.center)),
          Expanded(flex: 1, child: _ColH('الحالة', alignment: Alignment.center)),
          Expanded(flex: 2, child: _ColH('')),
        ],
      ),
    );
  }

  void _showFormDialog(String type) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ChequeCubit>(),
        child: ChequeFormDialog(type: type),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final cubit = context.read<ChequeCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final allCheques = await cubit.fetchAllFilteredCheques();
      if (allCheques.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text('لا توجد شيكات للتصدير',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ));
        return;
      }
      final state = cubit.state as ChequeLoaded;
      final bytes = await _buildChequeStatementPdf(allCheques,
          fromDate: state.fromDate, toDate: state.toDate);
      final dir = await FileHelper.getExportDirectory();
      final fileName =
          'Cheques_Statement_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('تم الحفظ في: ${file.path}',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  Future<void> _exportExcel() async {
    final cubit = context.read<ChequeCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final allCheques = await cubit.fetchAllFilteredCheques();
      if (allCheques.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text('لا توجد شيكات للتصدير',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ));
        return;
      }
      final state = cubit.state as ChequeLoaded;
      final bytes = await _buildChequeStatementExcel(allCheques,
          fromDate: state.fromDate, toDate: state.toDate);
      final dir = await FileHelper.getExportDirectory();
      final fileName =
          'Cheques_Statement_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('تم الحفظ في: ${file.path}',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '...';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, Map<String, double>> _calcTotals(List<ChequeModel> cheques) {
    final cleared = <String, double>{};
    final pending = <String, double>{};
    for (final c in cheques) {
      final cur = c.currency;
      if (c.status == 'cleared') {
        cleared[cur] = (cleared[cur] ?? 0) + c.amount;
      } else if (c.status == 'pending') {
        pending[cur] = (pending[cur] ?? 0) + c.amount;
      }
    }
    return {'cleared': cleared, 'pending': pending};
  }

  double _clearedFor(Map<String, Map<String, double>> totals, String cur) =>
      (totals['cleared'] ?? {})[cur] ?? 0;

  double _pendingFor(Map<String, Map<String, double>> totals, String cur) =>
      (totals['pending'] ?? {})[cur] ?? 0;

  Future<Uint8List> _buildChequeStatementPdf(List<ChequeModel> cheques,
      {DateTime? fromDate, DateTime? toDate}) async {
    final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final font = pw.Font.ttf(regularData);
    final boldFont = pw.Font.ttf(boldData);
    final totals = _calcTotals(cheques);

    final dateRange = fromDate != null || toDate != null
        ? 'الفترة: ${_fmtDate(fromDate)} - ${_fmtDate(toDate)}'
        : 'جميع الشيكات';

    final bgData = await rootBundle.load('assets/images/statment.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(bgImage, fit: pw.BoxFit.cover),
        ),
      ),
      build: (ctx) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('فروتي فارمز',
                            style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 16,
                                color: PdfColors.blueGrey)),
                        pw.SizedBox(height: 2),
                        pw.Text('كشف حساب الشيكات',
                            style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 14,
                                color: PdfColors.black)),
                      ]),
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('إجمالي الشيكات: ${cheques.length}',
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                color: PdfColors.grey700)),
                        pw.Text(dateRange,
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                color: PdfColors.grey700)),
                      ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              _buildTotalsTable(totals, font, boldFont),
              pw.SizedBox(height: 16),
              _buildChequesTable(cheques, font, boldFont),
            ],
          ),
        ),
      ],
    ));
    return doc.save();
  }

  pw.Widget _buildTotalsTable(Map<String, Map<String, double>> totals,
      pw.Font font, pw.Font boldFont) {
    final allCurrencies = <String>{
      ...totals['cleared']!.keys,
      ...totals['pending']!.keys
    }.toList()
      ..sort();
    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle:
          pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white),
      cellStyle: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.black),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
      headers: const ['العملة', 'اجمالي الشيكات المتحصلة', 'اجمالي الشيكات المعلقة'],
      data: allCurrencies
          .map((cur) => [
                cur,
                '${_clearedFor(totals, cur).toStringAsFixed(2)} $cur',
                '${_pendingFor(totals, cur).toStringAsFixed(2)} $cur',
              ])
          .toList(),
    );
  }

  pw.Widget _buildChequesTable(
      List<ChequeModel> cheques, pw.Font font, pw.Font boldFont) {
    return pw.TableHelper.fromTextArray(
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      headerStyle:
          pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
      cellStyle: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.black),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellDecoration: (row, col, isHeader) => const pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
      headers: const [
        'رقم الشيك',
        'النوع',
        'المستلم ',
        'المبلغ',
        'العملة',
        'تاريخ التحرير',
        'تاريخ الاستحقاق',
        'الحالة'
      ],
      data: cheques
          .map((c) => [
                c.chequeNumber,
                c.type == 'outgoing' ? 'صادر' : 'وارد',
                c.counterpartyDisplay,
                c.amount.toStringAsFixed(2),
                c.currency,
                c.issueDate,
                c.dueDate,
                c.statusLabel,
              ])
          .toList(),
    );
  }

  Future<Uint8List> _buildChequeStatementExcel(List<ChequeModel> cheques,
      {DateTime? fromDate, DateTime? toDate}) async {
    final excel = Excel.createExcel();
    final totals = _calcTotals(cheques);

    final dateRange = fromDate != null || toDate != null
        ? 'الفترة: ${_fmtDate(fromDate)} - ${_fmtDate(toDate)}'
        : 'جميع الشيكات';

    final sheet1 = excel['ملخص'];
    _excelRow(sheet1, [dateRange]);
    _excelRow(sheet1, ['العملة', 'اجمالي الشيكات المحصلة', 'اجمالي الشيكات المعلقة'],
        bold: true);
    final allCurrencies = <String>{
      ...totals['cleared']!.keys,
      ...totals['pending']!.keys
    }.toList()
      ..sort();
    for (final cur in allCurrencies) {
      _excelRow(sheet1, [
        cur,
        _clearedFor(totals, cur).toStringAsFixed(2),
        _pendingFor(totals, cur).toStringAsFixed(2),
      ]);
    }

    final sheet2 = excel['الشيكات'];
    _excelRow(sheet2, [
      'رقم الشيك',
      'النوع',
      'المستلم',
      'المبلغ',
      'العملة',
      'تاريخ التحرير',
      'تاريخ الاستحقاق',
      'الحالة',
      'الملاحظات'
    ], bold: true);
    for (final c in cheques) {
      _excelRow(sheet2, [
        c.chequeNumber,
        c.type == 'outgoing' ? 'صادر' : 'وارد',
        c.counterpartyDisplay,
        c.amount.toStringAsFixed(2),
        c.currency,
        c.issueDate,
        c.dueDate,
        c.statusLabel,
        c.notes ?? '',
      ]);

      final rowIndex = sheet2.maxRows - 1;
      String hexColor;
      if (c.status == 'pending') {
        hexColor = '#FFF2CC'; // Light yellow
      } else if (c.status == 'cancelled') {
        hexColor = '#FFC7CE'; // Light red
      } else {
        hexColor = '#C6EFCE'; // Light green
      }

      sheet2
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
          .cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(hexColor),
      );
    }

    excel.setDefaultSheet(sheet1.sheetName);
    final bytes = excel.encode();
    if (bytes == null) throw Exception('فشل إنشاء ملف Excel');
    return Uint8List.fromList(bytes);
  }

  void _excelRow(Sheet sheet, List<String> values, {bool bold = false}) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }
}

class _ColH extends StatelessWidget {
  final String text;
  final Alignment alignment;
  const _ColH(this.text, {this.alignment = Alignment.centerRight});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      alignment: alignment,
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black)),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: IconButton(
          icon: Icon(icon, size: 18, color: color),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? color.withValues(alpha: 0.3)
                : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppTheme.textSecondary
                      : const Color(0xFF475569))),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final List<T?> items;
  final List<String> itemLabels;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.itemLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<T?>(
      initialValue: value,
      dropdownColor: isDark ? const Color(0xFF0A1630) : Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: List.generate(
          items.length,
          (i) => DropdownMenuItem(
                value: items[i],
                child: Text(itemLabels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600)),
              )),
      onChanged: onChanged,
      style: TextStyle(
          fontFamily: 'Cairo',
          color: isDark ? Colors.white : Colors.black,
          fontSize: 12),
    );
  }
}

class _DateFilterField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final ValueChanged<DateTime?> onChanged;
  const _DateFilterField(
      {required this.label, required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppTheme.primary,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: date != null
              ? GestureDetector(
                  onTap: () => onChanged(null),
                  child: Icon(Icons.close,
                      size: 16,
                      color: isDark
                          ? AppTheme.textSecondary
                          : const Color(0xFF64748B)),
                )
              : Icon(Icons.calendar_today,
                  size: 14,
                  color: isDark
                      ? AppTheme.textSecondary
                      : const Color(0xFF64748B)),
        ),
        child: Text(
          date != null
              ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
              : '',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black),
        ),
      ),
    );
  }
}

class _ChequeRow extends StatelessWidget {
  final ChequeModel cheque;
  const _ChequeRow({required this.cheque});

  Color get _typeColor =>
      cheque.isOutgoing ? AppTheme.danger : AppTheme.success;

  Color get _statusColor {
    switch (cheque.status) {
      case 'pending':
        return AppTheme.warning;
      case 'cleared':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.textSecondary;
    }
  }

  String get _statusBg {
    switch (cheque.status) {
      case 'pending':
        return 'معلق';
      case 'cleared':
        return 'تم الصرف';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(cheque.chequeNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: isDark ? 0.1 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(cheque.typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: _typeColor,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(cheque.counterpartyDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 1,
            child: Text(AppUtils.formatNumber(cheque.amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black)),
          ),
          Expanded(
            flex: 1,
            child: Text(cheque.currency,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: isDark ? AppTheme.accent : const Color(0xFF0D9488),
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 1,
            child: Container(
              alignment: Alignment.center,
              child: Text(
                  cheque.dueDate.length >= 10
                      ? cheque.dueDate.substring(0, 10)
                      : cheque.dueDate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.textSecondary
                          : const Color(0xFF475569),
                      fontWeight: FontWeight.w500)),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: isDark ? 0.1 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_statusBg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: _statusColor,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cheque.isPending)
                  _RowBtn(
                    icon: Icons.check_circle_outline,
                    color: AppTheme.success,
                    tooltip: 'تسوية',
                    onTap: () => _confirmClear(context),
                  ),
                if (cheque.isPending)
                  _RowBtn(
                    icon: Icons.cancel_outlined,
                    color: AppTheme.danger,
                    tooltip: 'إلغاء',
                    onTap: () => _confirmCancel(context),
                  ),
                if (cheque.isCleared)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success
                          .withValues(alpha: isDark ? 0.1 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        cheque.clearedAt != null &&
                                cheque.clearedAt!.length >= 10
                            ? cheque.clearedAt!.substring(0, 10)
                            : 'تم',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppTheme.success,
                            fontWeight: FontWeight.bold)),
                  ),
                if (cheque.isCancelled)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          AppTheme.danger.withValues(alpha: isDark ? 0.1 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ملغي',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppTheme.danger,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0A1630) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        title: Text(cheque.isIncoming ? 'تحصيل الشيك' : 'صرف الشيك',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        content: Text(
            'هل أنت متأكد من ${cheque.isIncoming ? 'تحصيل' : 'صرف'} الشيك رقم ${cheque.chequeNumber}؟\n'
            'سيتم ترحيل القيود المحاسبية وتحديث رصيد البنك والحسابات المتعلقة تلقائياً.',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondary
                          : const Color(0xFF64748B),
                      fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final cubit = context.read<ChequeCubit>();
              final messenger = ScaffoldMessenger.of(context);
              cubit.clearCheque(int.parse(cheque.id!)).then((_) {
                messenger.showSnackBar(SnackBar(
                  content: Text(
                      cheque.isIncoming
                          ? 'تم تحصيل الشيك وإيداعه بالبنك بنجاح'
                          : 'تم صرف الشيك من البنك بنجاح',
                      style: const TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.success,
                ));
              }).catchError((e) {
                messenger.showSnackBar(SnackBar(
                  content:
                      Text('$e', style: const TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.danger,
                ));
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: Text(cheque.isIncoming ? 'تأكيد التحصيل' : 'تأكيد الصرف',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0A1630) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        title: Text('إلغاء الشيك',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من إلغاء الشيك رقم ${cheque.chequeNumber}؟',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('رجوع',
                  style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondary
                          : const Color(0xFF64748B),
                      fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final cubit = context.read<ChequeCubit>();
              final messenger = ScaffoldMessenger.of(context);
              cubit.cancelCheque(int.parse(cheque.id!)).then((_) {
                messenger.showSnackBar(const SnackBar(
                  content: Text('تم إلغاء الشيك',
                      style: TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.warning,
                ));
              }).catchError((e) {
                messenger.showSnackBar(SnackBar(
                  content:
                      Text('$e', style: const TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: AppTheme.danger,
                ));
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('تأكيد الإلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _RowBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _RowBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 32, height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: IconButton(
          icon: Icon(icon, size: 16, color: color),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}
