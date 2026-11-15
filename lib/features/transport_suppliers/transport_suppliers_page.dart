import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/transport_supplier_model.dart';
import 'transport_supplier_cubit.dart';
import 'transport_supplier_state.dart';
import 'transport_supplier_form_dialog.dart';
import 'transport_supplier_payment_dialog.dart';
import 'transport_supplier_invoice_dialog.dart';
import 'transport_suppliers_pdf_service.dart';
import '../../core/widgets/password_verification_dialog.dart';

class TransportSuppliersPage extends StatefulWidget {
  const TransportSuppliersPage({super.key});

  @override
  State<TransportSuppliersPage> createState() => _TransportSuppliersPageState();
}

class _TransportSuppliersPageState extends State<TransportSuppliersPage> {
  late final TransportSupplierCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = TransportSupplierCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _openAddDialog() {
    if (!ReadOnlyGuard.check(context)) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BlocProvider.value(
        value: _cubit,
        child: const TransportSupplierFormDialog(),
      ),
    );
  }

  void _openEditDialog(TransportSupplierModel supplier) async {
    if (!ReadOnlyGuard.check(context)) return;
    final verified = await showPasswordVerificationDialog(context);
    if (!verified) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BlocProvider.value(
        value: _cubit,
        child: TransportSupplierFormDialog(supplier: supplier),
      ),
    );
  }

  void _openPaymentDialog(TransportSupplierModel supplier) {
    if (!ReadOnlyGuard.check(context)) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TransportSupplierPaymentDialog(supplier: supplier),
    );
  }

  void _openInvoiceDialog({
    TransportSupplierModel? supplier,
    List<TransportSupplierModel> suppliers = const [],
  }) {
    if (!ReadOnlyGuard.check(context)) return;
    TransportSupplierInvoiceDialog.show(
      context,
      supplier: supplier,
      suppliers: suppliers,
    );
  }

  void _openStatement(TransportSupplierModel supplier) {
    context.push(
      RoutePaths.transportSupplierStatement,
      extra: supplier.id,
    );
  }

  Future<void> _openConsolidatedPdf(List<TransportSupplierModel> suppliers) async {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات موردين للتصدير',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    try {
      await TransportSuppliersPdfService.generateAndPrint(suppliers: suppliers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء PDF: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _saveConsolidatedPdf(List<TransportSupplierModel> suppliers) async {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات موردين للتصدير',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    try {
      await TransportSuppliersPdfService.saveToFile(context, suppliers: suppliers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ PDF: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
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
                  _buildSummaryCards(isMobile),
                  const SizedBox(height: 16),
                  _buildSearchBar(isMobile),
                  const SizedBox(height: 16),
                  if (isVerySmall)
                    _buildContent(isMobile)
                  else
                    Expanded(child: _buildContent(isMobile)),
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
    final titleSection = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withAlpha(80)),
          ),
          child: const Icon(Icons.local_shipping,
              color: AppTheme.primary, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'موردين النقل ومقاولي الشحن',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  fontFamily: 'Cairo',
                ),
              ),
              const Text(
                'إدارة حسابات سيارات النقل، مقاولي الشحن، كشوفات الحساب وسندات الصرف',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = BlocBuilder<TransportSupplierCubit, TransportSupplierState>(
      builder: (context, state) {
        final suppliers = state is TransportSupplierLoaded
            ? state.suppliers
            : <TransportSupplierModel>[];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
              tooltip: 'تحديث البيانات',
              onPressed: () => _cubit.loadAll(reset: true),
            ),
            ElevatedButton.icon(
              onPressed: () => _openConsolidatedPdf(suppliers),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(isMobile ? 'كشف مجمع' : 'كشف حساب مجمع 📄'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A365D),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: const Color(0xFF38BDF8).withAlpha(80)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, color: Colors.white70),
              tooltip: 'حفظ كشف حساب مجمع كملف PDF',
              onPressed: () => _saveConsolidatedPdf(suppliers),
            ),
            ElevatedButton.icon(
              onPressed: () => _openInvoiceDialog(suppliers: suppliers),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(isMobile ? 'استحقاق' : 'تسجيل استحقاق نقل 🚚'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleSection,
          const SizedBox(height: 12),
          actions,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titleSection),
        const SizedBox(width: 16),
        Flexible(child: actions),
      ],
    );
  }

  Widget _buildSummaryCards(bool isMobile) {
    return BlocBuilder<TransportSupplierCubit, TransportSupplierState>(
      builder: (context, state) {
        int totalCount = 0;
        double totalBalance = 0.0;
        double totalCredit = 0.0;
        double totalDebit = 0.0;
        double totalTruckStock = 0.0;

        if (state is TransportSupplierLoaded) {
          totalCount = state.suppliers.length;
          totalBalance = state.totalBalance;
          totalCredit = state.totalCreditDues;
          totalDebit = state.totalDebitAdvances;
          totalTruckStock =
              state.suppliers.fold<double>(0.0, (sum, s) => sum + s.truckBalance);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = isMobile || constraints.maxWidth < 1120;
            if (isNarrow) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: _buildKpiCard('إجمالي الموردين', '$totalCount',
                          Icons.people_outline, AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 210,
                      child: _buildKpiCard(
                          'مخزون النقلات المتاحة',
                          '${totalTruckStock % 1 == 0 ? totalTruckStock.toInt() : totalTruckStock.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                          Icons.local_shipping_outlined,
                          const Color(0xFF00B4D8)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 210,
                      child: _buildKpiCard(
                          'إجمالي المستحق (دائن)',
                          '${totalCredit.toStringAsFixed(2)} ج.م',
                          Icons.call_made_outlined,
                          AppTheme.warning),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 210,
                      child: _buildKpiCard(
                          'إجمالي المسدد (مدين)',
                          '${totalDebit.toStringAsFixed(2)} ج.م',
                          Icons.call_received_outlined,
                          AppTheme.accent),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 210,
                      child: _buildKpiCard(
                          'صافي المديونية',
                          '${totalBalance.toStringAsFixed(2)} ج.م',
                          Icons.account_balance_wallet_outlined,
                          totalBalance >= 0 ? AppTheme.warning : AppTheme.success),
                    ),
                  ],
                ),
              );
            }

            return Row(
              children: [
                Expanded(
                  child: _buildKpiCard('إجمالي الموردين', '$totalCount',
                      Icons.people_outline, AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                      'مخزون النقلات المتاحة',
                      '${totalTruckStock % 1 == 0 ? totalTruckStock.toInt() : totalTruckStock.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                      Icons.local_shipping_outlined,
                      const Color(0xFF00B4D8)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                      'إجمالي المستحق (دائن)',
                      '${totalCredit.toStringAsFixed(2)} ج.م',
                      Icons.call_made_outlined,
                      AppTheme.warning),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                      'إجمالي المسدد (مدين)',
                      '${totalDebit.toStringAsFixed(2)} ج.م',
                      Icons.call_received_outlined,
                      AppTheme.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                      'صافي المديونية',
                      '${totalBalance.toStringAsFixed(2)} ج.م',
                      Icons.account_balance_wallet_outlined,
                      totalBalance >= 0 ? AppTheme.warning : AppTheme.success),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKpiCard(
      String title, String value, IconData icon, Color color) {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(isDark ? 60 : 40)),
        boxShadow: [
          BoxShadow(
            color: isDark ? color.withAlpha(15) : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: isDark ? color : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isMobile) {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: _cubit.onSearchChanged,
        style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : AppTheme.lightTextPrimary),
        decoration: InputDecoration(
          hintText: 'بحث باسم المورد، الكود، أو رقم الهاتف...',
          hintStyle:
              TextStyle(fontFamily: 'Cairo', color: isDark ? AppTheme.textSecondary : AppTheme.lightTextMuted),
          prefixIcon:
              Icon(Icons.search, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildContent(bool isMobile) {
    return BlocBuilder<TransportSupplierCubit, TransportSupplierState>(
      builder: (context, state) {
        if (state is TransportSupplierLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is TransportSupplierError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.danger, size: 48),
                const SizedBox(height: 12),
                Text(state.message,
                    style: const TextStyle(
                        fontFamily: 'Cairo', color: Colors.white)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _cubit.loadAll(reset: true),
                  child: const Text('إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        }

        if (state is TransportSupplierLoaded) {
          final isDark = ThemeCubit.isCurrentDark;
          if (state.suppliers.isEmpty) {
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
                    child: Icon(Icons.local_shipping_outlined,
                        size: 48, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextMuted),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'لا يوجد موردين نقل مسجلين حتى الآن',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _openAddDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة أول مورد نقل',
                        style: TextStyle(fontFamily: 'Cairo')),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary),
                  ),
                ],
              ),
            );
          }

          if (isMobile) {
            return ListView.separated(
              itemCount: state.suppliers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) =>
                  _buildMobileSupplierCard(state.suppliers[idx]),
            );
          }

          return _buildDesktopTable(state.suppliers);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDesktopTable(List<TransportSupplierModel> suppliers) {
    final isDark = ThemeCubit.isCurrentDark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(isDark ? const Color(0xFF05192D) : const Color(0xFFF1F5F9)),
            dataRowMaxHeight: 60,
            columnSpacing: 24,
            columns: [
              DataColumn(
                  label: Text('الكود',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.accent : AppTheme.lightPrimary))),
              DataColumn(
                  label: Text('اسم مورد النقل',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
              DataColumn(
                  label: Text('رقم الهاتف',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
              const DataColumn(
                  label: Text('مخزون النقلات',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00B4D8)))),
              DataColumn(
                  label: Text('الرصيد الافتتاحي',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
              DataColumn(
                  label: Text('الرصيد المالي الحالي',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
              DataColumn(
                  label: Text('الإجراءات',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary))),
            ],
            rows: suppliers.map((s) {
              final isCredit = s.balance > 0;
              final isDebit = s.balance < 0;

              return DataRow(
                cells: [
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.code.isNotEmpty ? s.code : '—',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.name,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                        ),
                        if (s.notes != null && s.notes!.isNotEmpty)
                          Text(
                            s.notes!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      s.phone.isNotEmpty ? s.phone : '—',
                      style: TextStyle(
                          fontFamily: 'Cairo', color: isDark ? Colors.white70 : AppTheme.lightTextPrimary),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (s.truckBalance > 0
                                ? AppTheme.success
                                : (s.truckBalance < 0
                                    ? AppTheme.danger
                                    : AppTheme.textSecondary))
                            .withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (s.truckBalance > 0
                                  ? AppTheme.success
                                  : (s.truckBalance < 0
                                      ? AppTheme.danger
                                      : AppTheme.textSecondary))
                              .withAlpha(70),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_shipping_outlined,
                              size: 14, color: Color(0xFF00B4D8)),
                          const SizedBox(width: 4),
                          Text(
                            '${s.truckBalance % 1 == 0 ? s.truckBalance.toInt() : s.truckBalance.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: s.truckBalance > 0
                                  ? AppTheme.success
                                  : (s.truckBalance < 0
                                      ? AppTheme.danger
                                      : (isDark ? Colors.white70 : AppTheme.lightTextSecondary)),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${s.initialBalance.toStringAsFixed(2)} ج.م (${s.initialBalanceDirection == 'CREDIT' ? 'له' : 'عليه'})',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: AppTheme.textSecondary,
                          fontSize: 12),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isCredit
                                ? AppTheme.warning
                                : (isDebit
                                    ? AppTheme.accent
                                    : AppTheme.success))
                            .withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${s.balance.abs().toStringAsFixed(2)} ج.م ${isCredit ? '(له)' : (isDebit ? '(عليه)' : '(خالص)')}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isCredit
                              ? AppTheme.warning
                              : (isDebit
                                  ? AppTheme.accent
                                  : AppTheme.success),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _openInvoiceDialog(supplier: s, suppliers: suppliers),
                          icon: const Icon(Icons.receipt_long_rounded, size: 14),
                          label: const Text('استحقاق نقل',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: () => _openPaymentDialog(s),
                          icon: const Icon(Icons.payment_outlined, size: 14),
                          label: const Text('سداد دفعة',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          onPressed: () => _openStatement(s),
                          icon: const Icon(Icons.receipt_long_outlined, size: 14),
                          label: const Text('كشف حساب',
                              style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              color: isDark ? Colors.white70 : AppTheme.lightTextSecondary, size: 18),
                          tooltip: 'تعديل',
                          onPressed: () => _openEditDialog(s),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMobileSupplierCard(TransportSupplierModel s) {
    final isDark = ThemeCubit.isCurrentDark;
    final isCredit = s.balance > 0;
    final isDebit = s.balance < 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2338) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  s.displayName,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4D8).withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF00B4D8).withAlpha(80)),
                    ),
                    child: Text(
                      '${s.truckBalance % 1 == 0 ? s.truckBalance.toInt() : s.truckBalance.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} نقلة',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xFF00B4D8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isCredit
                              ? AppTheme.warning
                              : (isDebit
                                  ? AppTheme.accent
                                  : AppTheme.success))
                          .withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${s.balance.abs().toStringAsFixed(2)} ج.م ${isCredit ? '(له)' : (isDebit ? '(عليه)' : '')}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isCredit
                            ? AppTheme.warning
                            : (isDebit ? AppTheme.accent : AppTheme.success),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (s.phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  s.phone,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
          Divider(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder, height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openInvoiceDialog(supplier: s),
                icon: const Icon(Icons.receipt_long_rounded, size: 14),
                label: const Text('استحقاق',
                    style: TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openPaymentDialog(s),
                icon: const Icon(Icons.payment_outlined, size: 14),
                label: const Text('سداد دفعة',
                    style: TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openStatement(s),
                icon: const Icon(Icons.receipt_long_outlined, size: 14),
                label: const Text('كشف حساب',
                    style: TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary, size: 18),
                onPressed: () => _openEditDialog(s),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
