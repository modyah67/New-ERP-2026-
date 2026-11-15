import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../data/models/transport_supplier_model.dart';
import 'transport_supplier_payment_dialog.dart';
import 'transport_supplier_statement_cubit.dart';
import 'transport_supplier_statement_pdf_service.dart';
import 'transport_supplier_statement_state.dart';

class TransportSupplierStatementPage extends StatefulWidget {
  final int? initialSupplierId;
  const TransportSupplierStatementPage({super.key, this.initialSupplierId});

  @override
  State<TransportSupplierStatementPage> createState() =>
      _TransportSupplierStatementPageState();
}

class _TransportSupplierStatementPageState
    extends State<TransportSupplierStatementPage> {
  late final TransportSupplierStatementCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = TransportSupplierStatementCubit(
        initialSupplierId: widget.initialSupplierId);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _openPaymentDialog(TransportSupplierModel supplier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TransportSupplierPaymentDialog(supplier: supplier),
    );
  }

  Future<void> _printPdf(
      BuildContext context, TransportSupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await TransportSupplierStatementPdfService.generateAndPrint(
        supplier: supplier,
        transactions: state.transactions,
        openingBalance: state.openingBalance,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
      );
    } catch (e) {
      if (context.mounted) {
        UIUtils.showErrorSnackbar(context, 'فشل إنشاء ملف الـ PDF: $e');
      }
    }
  }

  Future<void> _savePdf(
      BuildContext context, TransportSupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await TransportSupplierStatementPdfService.saveToFile(
        context,
        supplier: supplier,
        transactions: state.transactions,
        openingBalance: state.openingBalance,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
      );
    } catch (e) {
      if (context.mounted) {
        UIUtils.showErrorSnackbar(context, 'فشل حفظ ملف الـ PDF: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: AppTheme.getBackgroundGradientFor(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 950;
              final isVerySmall = constraints.maxHeight < 600;

              Widget content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isMobile),
                  const SizedBox(height: 16),
                  _buildFilterBar(isMobile),
                  const SizedBox(height: 16),
                  _buildSummaryKpis(isMobile),
                  const SizedBox(height: 16),
                  if (isVerySmall)
                    _buildStatementTable(isMobile)
                  else
                    Expanded(child: _buildStatementTable(isMobile)),
                ],
              );

              if (isVerySmall) {
                content = SingleChildScrollView(
                  child: content,
                );
              }

              return Padding(
                padding: EdgeInsets.all(isMobile ? 12 : 24),
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final isDark = ThemeCubit.isCurrentDark;
    return BlocBuilder<TransportSupplierStatementCubit,
        TransportSupplierStatementState>(
      builder: (context, state) {
        final hasSelected = state is TransportSupplierStatementLoaded &&
            state.selectedSupplier != null;

        final actionButtons = <Widget>[
          IconButton(
            icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
            tooltip: 'تحديث',
            onPressed: () => _cubit.refreshData(),
          ),
          if (hasSelected) ...[
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: () => _printPdf(context, state),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('طباعة كشف الحساب',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _savePdf(context, state),
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: const Text('حفظ PDF',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00B4D8),
                side: const BorderSide(color: Color(0xFF00B4D8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () =>
                  _openPaymentDialog(state.selectedSupplier!),
              icon: const Icon(Icons.payment_outlined, size: 16),
              label: const Text('سداد دفعة للمقاول',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ];

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4D8).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF00B4D8).withAlpha(80)),
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: Color(0xFF00B4D8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'كشف حساب مقاول النقل والشحن',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const Text(
                          'تقرير تفصيلي بفواتير وسندات النقل',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionButtons,
              ),
            ],
          );
        }

        return Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF00B4D8).withAlpha(30),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFF00B4D8).withAlpha(80)),
              ),
              child: const Icon(Icons.receipt_long_outlined,
                  color: Color(0xFF00B4D8), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'كشف حساب مقاول النقل والشحن',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'تقرير تفصيلي بجميع فواتير النقل المستحقة وسندات الصرف النقدية والبنكية',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actionButtons,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(bool isMobile) {
    final isDark = ThemeCubit.isCurrentDark;
    return BlocBuilder<TransportSupplierStatementCubit,
        TransportSupplierStatementState>(
      builder: (context, state) {
        if (state is! TransportSupplierStatementLoaded) {
          return const SizedBox.shrink();
        }

        final suppliers = state.suppliers;
        final selected = state.selectedSupplier;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F2338) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
            boxShadow: isDark ? null : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 320,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF05192D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TransportSupplierModel>(
                      value: selected,
                      hint: Text('اختر مورد النقل...',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary)),
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                          fontSize: 14),
                      items: suppliers.map((s) {
                        return DropdownMenuItem<TransportSupplierModel>(
                          value: s,
                          child: Text(s.displayName,
                              style: TextStyle(
                                  color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
                        );
                      }).toList(),
                      onChanged: (val) => _cubit.selectSupplier(val),
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => _cubit.pickFromDate(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF05192D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        state.fromDate != null
                            ? 'من: ${state.fromDate!.year}/${state.fromDate!.month.toString().padLeft(2, '0')}/${state.fromDate!.day.toString().padLeft(2, '0')}'
                            : 'من تاريخ',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => _cubit.pickToDate(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF05192D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_outlined,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        state.toDate != null
                            ? 'إلى: ${state.toDate!.year}/${state.toDate!.month.toString().padLeft(2, '0')}/${state.toDate!.day.toString().padLeft(2, '0')}'
                            : 'إلى تاريخ',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryKpis(bool isMobile) {
    return BlocBuilder<TransportSupplierStatementCubit,
        TransportSupplierStatementState>(
      builder: (context, state) {
        if (state is! TransportSupplierStatementLoaded ||
            state.selectedSupplier == null) {
          return const SizedBox.shrink();
        }

        final opening = state.openingBalance;
        final totalCredit = state.totalCredit;
        final totalDebit = state.totalDebit;
        final finalBal = state.finalBalance;
        final truckBal = state.selectedSupplier?.truckBalance ?? 0.0;
        final truckBalFormatted = truckBal % 1 == 0 ? truckBal.toInt().toString() : truckBal.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

        if (isMobile) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatementKpiCard('رصيد افتتاحي / سابق',
                    '${opening.toStringAsFixed(2)} ج.م', AppTheme.primary),
                const SizedBox(width: 10),
                _buildStatementKpiCard('إجمالي النقل المستحق (دائن)',
                    '${totalCredit.toStringAsFixed(2)} ج.م', AppTheme.warning),
                const SizedBox(width: 10),
                _buildStatementKpiCard('إجمالي المسدد (مدين)',
                    '${totalDebit.toStringAsFixed(2)} ج.م', AppTheme.accent),
                const SizedBox(width: 10),
                _buildStatementKpiCard(
                    'الرصيد النهائي المستحق',
                    '${finalBal.toStringAsFixed(2)} ج.م',
                    finalBal >= 0 ? AppTheme.warning : AppTheme.success),
                const SizedBox(width: 10),
                _buildStatementKpiCard(
                    'رصيد النقلات المتاح',
                    '$truckBalFormatted نقلة',
                    const Color(0xFF00B4D8)),
              ],
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildStatementKpiCard('رصيد افتتاحي / سابق',
                  '${opening.toStringAsFixed(2)} ج.م', AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatementKpiCard('إجمالي النقل المستحق (دائن)',
                  '${totalCredit.toStringAsFixed(2)} ج.م', AppTheme.warning),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatementKpiCard('إجمالي المسدد (مدين)',
                  '${totalDebit.toStringAsFixed(2)} ج.م', AppTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatementKpiCard(
                  'الرصيد النهائي المستحق',
                  '${finalBal.toStringAsFixed(2)} ج.م',
                  finalBal >= 0 ? AppTheme.warning : AppTheme.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatementKpiCard(
                  'رصيد النقلات المتاح',
                  '$truckBalFormatted نقلة',
                  const Color(0xFF00B4D8)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatementKpiCard(String title, String value, Color color) {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? color.withAlpha(60) : AppTheme.lightBorder),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark ? color : const Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildStatementTable(bool isMobile) {
    return BlocBuilder<TransportSupplierStatementCubit,
        TransportSupplierStatementState>(
      builder: (context, state) {
        if (state is TransportSupplierStatementLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is! TransportSupplierStatementLoaded) {
          return const SizedBox.shrink();
        }

        final isDark = ThemeCubit.isCurrentDark;

        if (state.selectedSupplier == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_search_outlined,
                      size: 48, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextMuted),
                ),
                const SizedBox(height: 14),
                Text(
                  'يرجى اختيار مقاول النقل لعرض كشف الحساب',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 16, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
                ),
              ],
            ),
          );
        }

        if (state.isLoadingStatement) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.transactions.isEmpty && state.openingBalance == 0.0) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_outlined,
                    size: 48, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextMuted),
                const SizedBox(height: 12),
                Text(
                  'لا توجد حركات مالية مسجلة لهذا المورد في الفترة المحددة',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 15, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () =>
                      _openPaymentDialog(state.selectedSupplier!),
                  icon: const Icon(Icons.payment_outlined),
                  label: const Text('تسجيل أول سند صرف',
                      style: TextStyle(fontFamily: 'Cairo')),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                ),
              ],
            ),
          );
        }

        double runningBalance = state.openingBalance;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F2338) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
            boxShadow: isDark ? null : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(isDark ? const Color(0xFF05192D) : const Color(0xFFF1F5F9)),
                dataRowMinHeight: 52,
                dataRowMaxHeight: 74,
                columnSpacing: 20,
                columns: [
                  DataColumn(
                      label: Text('التاريخ',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.accent : AppTheme.lightPrimary))),
                  DataColumn(
                      label: Text('نوع الحركة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
                  const DataColumn(
                      label: Text('حركة النقلات',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00B4D8)))),
                  DataColumn(
                      label: Text('البيان / الوصف',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
                  DataColumn(
                      label: Text('مسدد (مدين)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.accent : AppTheme.lightPrimary))),
                  const DataColumn(
                      label: Text('مستحق (دائن)',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: AppTheme.warning))),
                  DataColumn(
                      label: Text('الرصيد التراكمي',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
                ],
                rows: [
                  // Opening Balance Row
                  DataRow(
                    color: WidgetStateProperty.all(
                        isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC)),
                    cells: [
                      DataCell(Text('—',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary))),
                      DataCell(Text('رصيد افتتاحي / سابق',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.primary : AppTheme.lightPrimary))),
                      DataCell(Text(
                        state.selectedSupplier?.initialTruckBalance != null &&
                                state.selectedSupplier!.initialTruckBalance > 0
                            ? '${state.selectedSupplier!.initialTruckBalance % 1 == 0 ? state.selectedSupplier!.initialTruckBalance.toInt() : state.selectedSupplier!.initialTruckBalance} نقلة'
                            : '—',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Color(0xFF00B4D8)),
                      )),
                      DataCell(Text('الرصيد المستحق قبل بداية الفترة',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary))),
                      DataCell(Text('—',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary))),
                      DataCell(Text('—',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary))),
                      DataCell(
                        Text(
                          '${state.openingBalance.toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                        ),
                      ),
                    ],
                  ),
                  // Transaction Rows
                  ...state.transactions.map((tx) {
                    runningBalance += (tx.credit - tx.debit);
                    final isConsump = tx.isConsumption;
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(tx.date,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                                  fontSize: 12)),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isConsump
                                  ? const Color(0xFF00B4D8).withAlpha(30)
                                  : (tx.isInvoice
                                      ? AppTheme.warning.withAlpha(30)
                                      : AppTheme.accent.withAlpha(30)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tx.typeLabel,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isConsump
                                    ? const Color(0xFF00B4D8)
                                    : (tx.isInvoice
                                        ? AppTheme.warning
                                        : AppTheme.accent),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          tx.truckCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isConsump
                                            ? AppTheme.warning
                                            : AppTheme.success)
                                        .withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isConsump
                                        ? '-${tx.truckCount % 1 == 0 ? tx.truckCount.toInt() : tx.truckCount} نقلة'
                                        : '+${tx.truckCount % 1 == 0 ? tx.truckCount.toInt() : tx.truckCount} نقلة',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isConsump
                                          ? AppTheme.warning
                                          : AppTheme.success,
                                    ),
                                  ),
                                )
                              : const Text('—',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.textSecondary)),
                        ),
                        DataCell(
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isConsump
                                      ? '${tx.description ?? ''} (استهلاك تشغيلي بدون أثر مالي)'
                                      : (tx.description ?? '—'),
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: isConsump
                                          ? (isDark ? Colors.white70 : AppTheme.lightTextSecondary)
                                          : (isDark ? Colors.white : AppTheme.lightTextPrimary),
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                if (tx.routeDisplay != null) ...[
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00B4D8).withAlpha(25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFF00B4D8).withAlpha(60)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.route_outlined,
                                            size: 11, color: Color(0xFF00B4D8)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'خط السير: ${tx.routeDisplay}',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10.5,
                                            color: Color(0xFF00B4D8),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            tx.debit > 0
                                ? '${tx.debit.toStringAsFixed(2)} ج.م'
                                : '—',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent),
                          ),
                        ),
                        DataCell(
                          Text(
                            tx.credit > 0
                                ? '${tx.credit.toStringAsFixed(2)} ج.م'
                                : '—',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: AppTheme.warning),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${runningBalance.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: runningBalance >= 0
                                  ? AppTheme.warning
                                  : AppTheme.accent,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
);
      },
    );
  }
}
