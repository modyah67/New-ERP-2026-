import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/statement_row_model.dart';
import 'shareholder_statement_cubit.dart';
import 'shareholder_statement_state.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ShareholderStatementPage extends StatefulWidget {
  const ShareholderStatementPage({super.key});

  @override
  State<ShareholderStatementPage> createState() => _ShareholderStatementPageState();
}

class _ShareholderStatementPageState extends State<ShareholderStatementPage> {
  final _searchController = TextEditingController();
  final _numberFormat = NumberFormat('#,##0.00', 'ar');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _titleFontSize(double w) {
    if (w < 400) return 16.0;
    if (w < 700) return 18.0;
    return 20.0;
  }

  double _labelFontSize(double w) {
    if (w < 400) return 11.0;
    if (w < 700) return 12.0;
    return 14.0;
  }

  double _bodyFontSize(double w) {
    if (w < 400) return 11.0;
    if (w < 700) return 12.0;
    return 13.0;
  }

  double _summaryLabelFontSize(double w) {
    if (w < 400) return 9.0;
    if (w < 700) return 10.0;
    return 11.0;
  }

  double _summaryValueFontSize(double w) {
    if (w < 400) return 11.0;
    if (w < 700) return 12.0;
    return 14.0;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShareholderStatementCubit, ShareholderStatementState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final isMobile = w < 700;
                final hPad = w < 400 ? 8.0 : w < 700 ? 12.0 : 16.0;
                final col = Column(
                  children: [
                    _buildHeader(context, state, w),
                    SizedBox(height: hPad),
                    _buildFilterBar(context, state, w),
                    SizedBox(height: hPad),
                    if (isMobile)
                      _buildContent(context, state, w)
                    else
                      Expanded(child: _buildContent(context, state, w)),
                  ],
                );
                if (isMobile) {
                  return SingleChildScrollView(child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: col,
                  ));
                }
                return col;
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ShareholderStatementState state, double w) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + (w < 400 ? 10 : 16),
            bottom: w < 400 ? 10 : 16,
            left: w < 400 ? 12 : 20,
            right: w < 400 ? 12 : 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: w < 700
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.person_outline, color: AppTheme.primary, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('كشف حساب المساهم',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppTheme.textPrimary, fontSize: _titleFontSize(w), fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        ),
                      ],
                    ),
                    if (state.selectedShareholder != null && state.rows.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildExportButton(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'PDF',
                            onPressed: () => _exportPdf(context, state),
                          ),
                          const SizedBox(width: 8),
                          _buildExportButton(
                            icon: Icons.table_chart_outlined,
                            label: 'Excel',
                            onPressed: () => _exportExcel(context, state),
                          ),
                          const SizedBox(width: 8),
                          _buildExportButton(
                            icon: Icons.refresh_rounded,
                            label: '',
                            onPressed: () => context.read<ShareholderStatementCubit>().loadStatement(),
                            small: true,
                          ),
                        ],
                      ),
                    ] else if (state.selectedShareholder == null || state.rows.isEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildExportButton(
                          icon: Icons.refresh_rounded,
                          label: '',
                          onPressed: () => context.read<ShareholderStatementCubit>().loadStatement(),
                          small: true,
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppTheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.person_outline, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('كشف حساب المساهم',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: _titleFontSize(w), fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                    if (state.selectedShareholder != null && state.rows.isNotEmpty) ...[
                      _buildExportButton(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'PDF',
                        onPressed: () => _exportPdf(context, state),
                      ),
                      const SizedBox(width: 8),
                      _buildExportButton(
                        icon: Icons.table_chart_outlined,
                        label: 'Excel',
                        onPressed: () => _exportExcel(context, state),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildExportButton(
                      icon: Icons.refresh_rounded,
                      label: '',
                      onPressed: () => context.read<ShareholderStatementCubit>().loadStatement(),
                      small: true,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildExportButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool small = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: small
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: small
            ? Icon(icon, color: AppTheme.textSecondary, size: 22)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppTheme.textSecondary, size: 18),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, ShareholderStatementState state, double w) {
    final pad = w < 400 ? 10.0 : 16.0;
    final labelSize = _labelFontSize(w);
    final bodySize = _bodyFontSize(w);
    final spacing = w < 400 ? 8.0 : 12.0;

    if (w < 700) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterField(
                    label: 'المساهم',
                    labelSize: labelSize,
                    child: _buildShareholderSearch(state, bodySize),
                  ),
                  SizedBox(height: spacing),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterField(
                          label: 'من تاريخ',
                          labelSize: labelSize,
                          child: _buildDateField(
                            context: context,
                            value: state.fromDate,
                            label: 'من تاريخ',
                            fontSize: bodySize,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: state.fromDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null && context.mounted) {
                                context.read<ShareholderStatementCubit>().setFromDate(picked);
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: _buildFilterField(
                          label: 'إلى تاريخ',
                          labelSize: labelSize,
                          child: _buildDateField(
                            context: context,
                            value: state.toDate,
                            label: 'إلى تاريخ',
                            fontSize: bodySize,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: state.toDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null && context.mounted) {
                                context.read<ShareholderStatementCubit>().setToDate(picked);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing),
                  _buildFilterField(
                    label: 'العملة',
                    labelSize: labelSize,
                    child: _buildCurrencyDropdown(state, bodySize),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                Expanded(
                  flex: 3,
                  child: _buildFilterField(
                    label: 'المساهم',
                    labelSize: labelSize,
                    child: _buildShareholderSearch(state, bodySize),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  flex: 2,
                  child: _buildFilterField(
                    label: 'من تاريخ',
                    labelSize: labelSize,
                    child: _buildDateField(
                      context: context,
                      value: state.fromDate,
                      label: 'من تاريخ',
                      fontSize: bodySize,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: state.fromDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null && context.mounted) {
                          context.read<ShareholderStatementCubit>().setFromDate(picked);
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  flex: 2,
                  child: _buildFilterField(
                    label: 'إلى تاريخ',
                    labelSize: labelSize,
                    child: _buildDateField(
                      context: context,
                      value: state.toDate,
                      label: 'إلى تاريخ',
                      fontSize: bodySize,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: state.toDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null && context.mounted) {
                          context.read<ShareholderStatementCubit>().setToDate(picked);
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  flex: 2,
                  child: _buildFilterField(
                    label: 'العملة',
                    labelSize: labelSize,
                    child: _buildCurrencyDropdown(state, bodySize),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterField({required String label, required double labelSize, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: labelSize)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildShareholderSearch(ShareholderStatementState state, double fontSize) {
    return Autocomplete<ShareholderModel>(
      displayStringForOption: (s) => '${s.code} - ${s.name}',
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return state.shareholders;
        return state.shareholders.where((s) =>
            s.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
            s.code.toLowerCase().contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: (s) {
        _searchController.text = '${s.code} - ${s.name}';
        context.read<ShareholderStatementCubit>().selectShareholder(s);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        textEditingController.addListener(() {
          if (textEditingController.text.isEmpty) {
            context.read<ShareholderStatementCubit>().selectShareholder(null);
          }
        });
        if (state.selectedShareholder != null && textEditingController.text.isEmpty) {
          textEditingController.text = '${state.selectedShareholder!.code} - ${state.selectedShareholder!.name}';
        }
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          onFieldSubmitted: (_) => onFieldSubmitted(),
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: fontSize),
          decoration: InputDecoration(
            hintText: 'ابحث بالكود أو الاسم...',
            hintStyle: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: fontSize),
            prefixIcon: const Icon(Icons.person_outline, size: 18, color: AppTheme.textSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: state.selectedShareholder != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      textEditingController.clear();
                      context.read<ShareholderStatementCubit>().selectShareholder(null);
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
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: optionsList.length,
                itemBuilder: (context, index) {
                  final option = optionsList[index];
                  return ListTile(
                    title: Text('${option.code} - ${option.name}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
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
  }

  Widget _buildDateField({
    required BuildContext context,
    required DateTime? value,
    required String label,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.glassBorder),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withAlpha(5),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: value != null ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? AppUtils.formatDate(value) : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: fontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown(ShareholderStatementState state, double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.glassBorder),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withAlpha(5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.selectedCurrency,
          isExpanded: true,
          dropdownColor: const Color(0xCC05192D),
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: fontSize),
          items: ['EGP', 'USD', 'EUR', 'GBP'].map((c) => DropdownMenuItem(
            value: c,
            child: Text(c, style: TextStyle(fontFamily: 'Cairo', fontSize: fontSize)),
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              context.read<ShareholderStatementCubit>().setCurrency(v);
            }
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ShareholderStatementState state, double w) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (state.selectedShareholder == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: AppTheme.textSecondary.withAlpha(60)),
            const SizedBox(height: 16),
            Text('اختر مساهماً لعرض كشف الحساب',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: _bodyFontSize(w), fontFamily: 'Cairo')),
          ],
        ),
      );
    }
    if (state.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: AppTheme.textSecondary.withAlpha(60)),
            const SizedBox(height: 16),
            Text('لا توجد حركات في الفترة المحددة',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: _bodyFontSize(w), fontFamily: 'Cairo')),
          ],
        ),
      );
    }

    final hPad = w < 400 ? 8.0 : 16.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isScrollable = !constraints.hasBoundedHeight || constraints.maxHeight > 800;
          return Column(
            mainAxisSize: isScrollable ? MainAxisSize.min : MainAxisSize.max,
            children: [
              _buildSummaryCards(state, w),
              SizedBox(height: w < 400 ? 8 : 12),
              if (state.fromDate != null && state.openingBalance != 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Builder(
                    builder: (ctx) {
                      final isNeg = state.openingBalance < 0;
                      final noteColor = isNeg ? AppTheme.danger : AppTheme.info;
                      final absVal = _numberFormat.format(state.openingBalance.abs());
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: noteColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: noteColor.withAlpha(60)),
                        ),
                        child: RichText(
                          textDirection: TextDirection.rtl,
                          text: TextSpan(
                            style: TextStyle(color: noteColor, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo'),
                            children: [
                              const TextSpan(text: 'ملحوظة: الرصيد السابق = '),
                              if (isNeg) const TextSpan(text: '- ', style: TextStyle(fontSize: 18)),
                              TextSpan(text: '$absVal ${state.selectedCurrency}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (isScrollable)
                SizedBox(height: 400, child: _buildStatementTable(state, w))
              else
                Expanded(child: _buildStatementTable(state, w)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(ShareholderStatementState state, double w) {
    final netResult = state.totalCredit - state.totalDebit;
    final grandNet = state.openingBalance + netResult + state.totalProfitShare;
    final currencyLabel = state.selectedCurrency;

    if (w < 700) {
      return SizedBox(
        height: 80,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildSummaryItem('إجمالي الإيداعات', '${_numberFormat.format(state.totalCredit)} $currencyLabel', AppTheme.success, w),
            const SizedBox(width: 10),
            _buildSummaryItem('إجمالي السحوبات', '${_numberFormat.format(state.totalDebit)} $currencyLabel', AppTheme.danger, w),
            const SizedBox(width: 10),
            _buildSummaryItem('صافي الحركات', '${_numberFormat.format(netResult)} $currencyLabel', netResult >= 0 ? AppTheme.success : AppTheme.danger, w),
            const SizedBox(width: 10),
            _buildSummaryItem('إجمالي الأرباح', '${_numberFormat.format(state.totalProfitShare)} $currencyLabel', AppTheme.primary, w),
            const SizedBox(width: 10),
            _buildSummaryItem('الصافي النهائي', '${_numberFormat.format(grandNet)} $currencyLabel', grandNet >= 0 ? AppTheme.success : AppTheme.danger, w),
          ],
        ),
      );
    }

    return Row(
      children: [
        _buildSummaryItem('إجمالي الإيداعات', '${_numberFormat.format(state.totalCredit)} $currencyLabel', AppTheme.success, w),
        const SizedBox(width: 10),
        _buildSummaryItem('إجمالي السحوبات', '${_numberFormat.format(state.totalDebit)} $currencyLabel', AppTheme.danger, w),
        const SizedBox(width: 10),
        _buildSummaryItem('صافي الحركات', '${_numberFormat.format(netResult)} $currencyLabel', netResult >= 0 ? AppTheme.success : AppTheme.danger, w),
        const SizedBox(width: 10),
        _buildSummaryItem('إجمالي الأرباح', '${_numberFormat.format(state.totalProfitShare)} $currencyLabel', AppTheme.primary, w),
        const SizedBox(width: 10),
        _buildSummaryItem('الصافي النهائي', '${_numberFormat.format(grandNet)} $currencyLabel', grandNet >= 0 ? AppTheme.success : AppTheme.danger, w),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color, double w) {
    final labelSize = _summaryLabelFontSize(w);
    final valueSize = _summaryValueFontSize(w);

    if (w < 700) {
      return SizedBox(
        width: 160,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: labelSize, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: TextStyle(color: color, fontSize: valueSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: labelSize, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(color: color, fontSize: valueSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatementTable(ShareholderStatementState state, double w) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: AppTheme.glassCard(),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: max(w - (w < 400 ? 16 : 60), 700),
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                horizontalMargin: 12,
                columnSpacing: 8,
                headingTextStyle: TextStyle(
                    color: AppTheme.textSecondary, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: w < 400 ? 10 : 12),
                dataTextStyle: TextStyle(
                    color: AppTheme.textPrimary, fontFamily: 'Cairo', fontSize: w < 400 ? 10 : 12),
                columns: const [
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('النوع')),
                  DataColumn(label: Text('الوصف')),
                  DataColumn(label: Text('مدين')),
                  DataColumn(label: Text('دائن')),
                  DataColumn(label: Text('الرصيد')),
                  DataColumn(label: Text('ملاحظات')),
                ],
                rows: state.rows.asMap().entries.map((entry) {
                  final row = entry.value;
                  final isNegative = row.balance < 0;
                  final cellFontSize = w < 400 ? 10.0 : 11.0;
                  final noteText = state.rowNotes[row.transactionNumber] ?? '';
                  return DataRow(cells: [
                    DataCell(Text(row.date, style: TextStyle(fontSize: cellFontSize))),
                    DataCell(_buildTypeBadge(row, w)),
                    DataCell(SizedBox(
                      width: w < 400 ? 150 : 250,
                      child: Text(row.description, style: TextStyle(fontSize: cellFontSize), overflow: TextOverflow.ellipsis, maxLines: 1),
                    )),
                    DataCell(row.debit > 0
                        ? Text(_numberFormat.format(row.debit), style: TextStyle(color: AppTheme.danger, fontSize: cellFontSize))
                        : const Text('—')),
                    DataCell(row.credit > 0
                        ? Text(_numberFormat.format(row.credit), style: TextStyle(color: AppTheme.success, fontSize: cellFontSize))
                        : const Text('—')),
                    DataCell(Text(
                      _numberFormat.format(row.balance),
                      style: TextStyle(
                        color: isNegative ? AppTheme.danger : AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: cellFontSize,
                      ),
                    )),
                    DataCell(
                      GestureDetector(
                        onTap: () => _showNoteDialog(context, row.transactionNumber),
                        child: noteText.isNotEmpty
                            ? Text(noteText, style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis, maxLines: 2)
                            : Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.textMuted.withAlpha(120)),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(StatementRow row, double w) {
    Color color;
    String label;
    switch (row.type) {
      case 'treasury':
        color = AppTheme.primary;
        label = 'نقدية';
        break;
      case 'bank':
        color = AppTheme.accent;
        label = 'بنكي';
        break;
      case 'cheque':
        color = AppTheme.warning;
        label = 'شيك';
        break;
      case 'ledger':
        color = AppTheme.textSecondary;
        label = 'قيد';
        break;
      case 'profit':
        color = AppTheme.success;
        label = 'أرباح';
        break;
      default:
        color = AppTheme.textSecondary;
        label = row.type;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w < 400 ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: w < 400 ? 8 : 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
    );
  }

  void _showNoteDialog(BuildContext context, String transactionNumber) {
    final currentNote = context.read<ShareholderStatementCubit>().state.rowNotes[transactionNumber] ?? '';
    final controller = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('ملاحظة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'أضف ملاحظة...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: Colors.white.withAlpha(5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { context.read<ShareholderStatementCubit>().setRowNote(transactionNumber, controller.text.trim()); Navigator.of(ctx).pop(); },
            child: const Text('حفظ', style: TextStyle(color: AppTheme.primary, fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () { context.read<ShareholderStatementCubit>().setRowNote(transactionNumber, ''); Navigator.of(ctx).pop(); },
            child: const Text('حذف', style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  // ── PDF Export ──
  Future<void> _exportPdf(BuildContext context, ShareholderStatementState state) async {
    try {
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final arabicBold = pw.Font.ttf(boldData);
      final arabicFont = pw.Font.ttf(regularData);

      final pdf = pw.Document();
      final shareholder = state.selectedShareholder!;

      final bgData = await rootBundle.load('assets/images/statment.png');
      final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

      pdf.addPage(pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[];

          widgets.add(pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('اسم المساهم: ${shareholder.name}',
                        style: pw.TextStyle(font: arabicBold, fontSize: 14)),
                    pw.Text('كود المساهم: ${shareholder.code}',
                        style: pw.TextStyle(font: arabicFont, fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
                pw.SizedBox(),
              ],
            ),
          ));
          widgets.add(pw.SizedBox(height: 16));

          if (state.fromDate != null &&
              state.openingBalance != 0) {
            final isNeg = state.openingBalance < 0;
            final bgColor = isNeg ? PdfColor.fromHex('#FFEBEE') : PdfColor.fromHex('#E8F4FD');
            final borderColor = isNeg ? PdfColor.fromHex('#EF9A9A') : PdfColor.fromHex('#B3D9F2');
            final textColor = isNeg ? PdfColor.fromHex('#C62828') : PdfColor.fromHex('#1565C0');
            final absVal = _numberFormat.format(state.openingBalance.abs());
            widgets.add(pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: bgColor,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: borderColor),
                ),
                child: isNeg
                    ? pw.RichText(
                        text: pw.TextSpan(children: [
                          pw.TextSpan(text: 'ملحوظة: الرصيد السابق = ', style: pw.TextStyle(font: arabicBold, fontSize: 9, color: textColor)),
                          pw.TextSpan(text: '- $absVal ${state.selectedCurrency}', style: pw.TextStyle(font: arabicBold, fontSize: 14, color: textColor)),
                        ]),
                      )
                    : pw.Text(
                        'ملحوظة: الرصيد السابق = $absVal ${state.selectedCurrency}',
                        style: pw.TextStyle(font: arabicBold, fontSize: 9, color: textColor),
                      ),
              ),
            ));
          }

          widgets.add(pw.SizedBox(height: 16));

          widgets.add(pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: arabicBold, fontSize: 9, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1A5276')),
            headerAlignment: pw.Alignment.center,
            cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
            cellAlignment: pw.Alignment.center,
            cellHeight: 20,
            headerHeight: 24,
            headers: ['التاريخ', 'النوع', 'الوصف', 'مدين', 'دائن', 'الرصيد', 'ملاحظات'],
            data: state.rows.asMap().entries.map((entry) {
              final r = entry.value;
              final note = state.rowNotes[r.transactionNumber] ?? '';
              return [
                r.date,
                r.accountName,
                r.description,
                r.debit > 0 ? _numberFormat.format(r.debit) : '—',
                r.credit > 0 ? _numberFormat.format(r.credit) : '—',
                _numberFormat.format(r.balance),
                note,
              ];
            }).toList(),
          ));

          widgets.add(pw.SizedBox(height: 12));
          widgets.add(pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                pw.Text('إجمالي الإيداعات: ${_numberFormat.format(state.totalCredit)} ج.م',
                    style: pw.TextStyle(font: arabicBold, fontSize: 11, color: PdfColor.fromHex('#27AE60'))),
                pw.SizedBox(width: 20),
                pw.Text('إجمالي السحوبات: ${_numberFormat.format(state.totalDebit)} ج.م',
                    style: pw.TextStyle(font: arabicBold, fontSize: 11, color: PdfColor.fromHex('#E74C3C'))),
                pw.SizedBox(width: 20),
                pw.Text('حصة الأرباح: ${_numberFormat.format(state.totalProfitShare)} ${state.selectedCurrency}',
                    style: pw.TextStyle(font: arabicBold, fontSize: 11, color: PdfColor.fromHex('#2980B9'))),
                pw.SizedBox(width: 20),
                pw.Text('الصافي النهائي: ${_numberFormat.format(state.totalCredit - state.totalDebit + state.totalProfitShare)} ${state.selectedCurrency}',
                    style: pw.TextStyle(font: arabicBold, fontSize: 11)),
              ],
            ),
          ));

          return widgets;
        },
      ));

      final bytes = await pdf.save();
      final dir = await FileHelper.getExportDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/shareholder_statement_${shareholder.code}_$dateStr.pdf');
      await file.writeAsBytes(bytes);

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ PDF في: ${file.path}'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      debugPrint('PDF export error: $e');
    }
  }

  // ── Excel Export ──
  Future<void> _exportExcel(BuildContext context, ShareholderStatementState state) async {
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'كشف حساب المساهم');
      final sheet = excel['كشف حساب المساهم'];

      final shareholder = state.selectedShareholder!;
      final headers = ['التاريخ', 'النوع', 'الوصف', 'مدين', 'دائن', 'الرصيد'];

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      for (int i = 0; i < state.rows.length; i++) {
        final row = state.rows[i];
        final r = i + 1;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(row.date);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(row.accountName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(row.description);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = row.debit > 0 ? DoubleCellValue(row.debit) : TextCellValue('—');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = row.credit > 0 ? DoubleCellValue(row.credit) : TextCellValue('—');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(row.balance);
      }

      final totalsRow = state.rows.length + 2;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRow)).value = TextCellValue('الإجمالي');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalsRow)).value = DoubleCellValue(state.totalDebit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: totalsRow)).value = DoubleCellValue(state.totalCredit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalsRow)).value = DoubleCellValue(state.finalBalance);

      final profitRow = totalsRow + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: profitRow)).value = TextCellValue('حصة الأرباح');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: profitRow)).value = DoubleCellValue(state.totalProfitShare);

      final finalRow = profitRow + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: finalRow)).value = TextCellValue('الصافي النهائي');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: finalRow)).value = DoubleCellValue(state.totalCredit - state.totalDebit + state.totalProfitShare);

      final bytes = excel.save();
      if (bytes == null) return;

      final dir = await FileHelper.getExportDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/shareholder_statement_${shareholder.code}_$dateStr.xlsx');
      await file.writeAsBytes(bytes);

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ Excel في: ${file.path}'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      debugPrint('Excel export error: $e');
    }
  }
}
