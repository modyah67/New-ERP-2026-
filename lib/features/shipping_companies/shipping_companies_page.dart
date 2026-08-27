import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../data/models/shipping_company_model.dart';
import 'shipping_company_cubit.dart';
import 'shipping_company_state.dart';
import 'shipping_company_form_dialog.dart';
import 'shipping_company_pdf_service.dart';

class ShippingCompaniesPage extends StatefulWidget {
  const ShippingCompaniesPage({super.key});

  @override
  State<ShippingCompaniesPage> createState() => _ShippingCompaniesPageState();
}

class _ShippingCompaniesPageState extends State<ShippingCompaniesPage> {
  late final ShippingCompanyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ShippingCompanyCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Container(
          decoration: AppTheme.backgroundGradient,
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isMobile),
                const SizedBox(height: 20),
                _buildSearchBar(isMobile),
                const SizedBox(height: 16),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_shipping_outlined,
                color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('شركات الشحن', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: isMobile ? 22 : 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Cairo')),
                BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
                  buildWhen: (prev, curr) => curr is ShippingCompanyLoaded,
                  builder: (context, state) {
                    final count =
                        state is ShippingCompanyLoaded ? state.companies.length : 0;
                    return Text('$count شركة',
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontFamily: 'Cairo',
                            fontSize: 13));
                  },
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'تحديث',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        const SizedBox(width: 4),
        BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
          buildWhen: (prev, curr) => curr is ShippingCompanyLoaded,
          builder: (context, state) {
            final companies =
                state is ShippingCompanyLoaded ? state.companies : <ShippingCompanyModel>[];
            if (companies.isEmpty) return const SizedBox.shrink();
            return Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.print_outlined, color: Colors.white70),
                  tooltip: 'طباعة كشف مجمع',
                  onPressed: () => _printSummary(companies),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
                  tooltip: 'حفظ PDF',
                  onPressed: () => _savePdf(companies),
                ),
              ],
            );
          },
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة شركة شحن'),
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
        ),
        ],
      );
  }

  Widget _buildSearchBar(bool isMobile) {
    return TextField(
      onChanged: _cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
          buildWhen: (prev, curr) => curr is ShippingCompanyLoaded,
          builder: (context, state) {
            final query =
                state is ShippingCompanyLoaded ? state.searchQuery : '';
            if (query.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _cubit.onSearchChanged(''),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    return BlocBuilder<ShippingCompanyCubit, ShippingCompanyState>(
      builder: (context, state) {
        if (state is ShippingCompanyLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent));
        }
        if (state is ShippingCompanyError) {
          return Center(
            child: Text(state.message,
                style: const TextStyle(color: Colors.white70)),
          );
        }
        if (state is! ShippingCompanyLoaded || state.companies.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_shipping_outlined,
                    color: Colors.white24, size: 64),
                const SizedBox(height: 16),
                const Text('لا توجد شركات شحن',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة شركة شحن'),
                  onPressed: () async {
                    await _cubit.prepareAddForm();
                    _showFormDialog();
                  },
                ),
              ],
            ),
          );
        }

        return _buildTable(state.companies);
      },
    );
  }

  Widget _buildTable(List<ShippingCompanyModel> companies) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth > 800 ? constraints.maxWidth : 800,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF072548),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 30)),
              ),
              child: Column(
                children: [
                  _buildTableHeader(),
                  const Divider(height: 1, color: AppTheme.glassBorder),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification &&
                            notification.metrics.pixels >=
                                notification.metrics.maxScrollExtent - 100) {
                          _cubit.fetchMore();
                        }
                        return false;
                      },
                      child: ListView.separated(
                        itemCount: companies.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: AppTheme.glassBorder),
                        itemBuilder: (ctx, i) =>
                            _buildTableRow(ctx, companies[i], i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const _labelStyle = TextStyle(
      color: AppTheme.textSecondary,
      fontWeight: FontWeight.w600,
      fontFamily: 'Cairo',
      fontSize: 13);

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(width: 36, child: Text('#', style: _labelStyle)),
          SizedBox(width: 100, child: Text('الكود', style: _labelStyle)),
          SizedBox(width: 160, child: Text('الاسم', style: _labelStyle)),
          SizedBox(width: 120, child: Text('الهاتف', style: _labelStyle)),
          SizedBox(width: 160, child: Text('البريد الإلكتروني', style: _labelStyle)),
          SizedBox(width: 100, child: Text('الرصيد', style: _labelStyle)),
          SizedBox(width: 70, child: Text('إجراءات', style: _labelStyle)),
        ],
      ),
    );
  }

  Widget _buildTableRow(
      BuildContext context, ShippingCompanyModel company, int index) {
    return Container(
      height: 55,
      color: index.isEven
          ? Colors.white.withValues(alpha: 0.03)
          : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
              width: 36,
              child: Text('${index + 1}',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'Cairo',
                      fontSize: 12))),
          SizedBox(
              width: 100,
              child: Text(company.code,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          SizedBox(
              width: 160,
              child: Text(company.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 12))),
          SizedBox(
              width: 120,
              child: Text(company.phone,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Cairo',
                      fontSize: 12))),
          SizedBox(
              width: 160,
              child: Text(company.email,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Cairo',
                      fontSize: 12))),
          SizedBox(
              width: 100,
              child: Text('${company.balance < 0 ? '-' : ''}${company.balance.abs().toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold))),
          SizedBox(
            width: 70,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showEditDialog(context, company),
                  child: const Icon(Icons.edit_outlined,
                      size: 18, color: Color.fromARGB(134, 100, 221, 255)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFormDialog({ShippingCompanyModel? company}) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: _cubit,
        child: ShippingCompanyFormDialog(company: company),
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, ShippingCompanyModel company) async {
    await _cubit.prepareEditForm(company);
    _showFormDialog(company: company);
  }

  void _showDeleteConfirm(
      BuildContext context, ShippingCompanyModel company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF0051B2B),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف شركة الشحن',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف "${company.name}"؟',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              await _cubit.deleteCompany(company);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('حذف',
                style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _printSummary(List<ShippingCompanyModel> companies) async {
    await ShippingCompanyPdfService.printSummary(companies);
  }

  Future<void> _savePdf(List<ShippingCompanyModel> companies) async {
    try {
      final path = await ShippingCompanyPdfService.saveToFile(companies);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ في: $path'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
